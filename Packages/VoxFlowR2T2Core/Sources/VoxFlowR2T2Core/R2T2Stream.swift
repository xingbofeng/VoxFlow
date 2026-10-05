import Foundation
import MLX
import MLXLMCommon
import Tokenizers

/// Confucius4-R2T2 stable-prefix streaming: a port of `r2t2/r2t2_asr.py`
/// (`streaming_transcribe_no_reset` — the rolling-window path the reference WebSocket server
/// runs) plus the chunk schedule of `ws_server.py` / `example.py`.
///
/// The protocol, per 160 ms chunk (the first carries a 160 ms lookahead): append the chunk to the
/// audio window; once the window exceeds 16 s drop its oldest 8 s AND the text those chunks
/// committed; build `prompt = template + committed text`; greedily decode a few tokens over the
/// whole window; cut the output at the first `|` (the model's own "past here I am guessing"
/// marker); roll back `unfixedTokens` tokens (further if a UTF-8 character would split); the rest is
/// COMMITTED — appended to the prefix and emitted as the delta. Committed text is never revised.
///
/// Two decode strategies produce identical text: `.reencode` re-feeds the window from scratch every
/// chunk (the reference's behaviour on vLLM, where prefix caching hides the cost — and the shape
/// the parity gate runs); `.reuse` caches completed 8 s encoder blocks whose mel did not change and
/// keeps their KV, trimming the cache back to that stable prefix each chunk and re-prefilling only
/// the partial block, the assistant header and the committed text. Blocks never attend to each
/// other and the head/audio KV depends only on what precedes it, so the reuse is exact — except
/// that Whisper's `max − 8` floor is GLOBAL over the window, which is why a block is reused only
/// when its mel frames compare equal, not merely because its audio did not change.
public final class R2T2Stream {
    public enum Strategy: Sendable { case reencode, reuse }
    public enum Schedule: Sendable { case server, example }

    public struct Options: Sendable {
        public var chunkSeconds: Double = 0.16
        public var lookaheadSeconds: Double = 0.16
        public var unfixedTokens: Int = 1
        public var windowSeconds: Double = 16
        public var dropSeconds: Double = 8
        public var rollbackPunctuation: Bool = false
        public var schedule: Schedule = .server
        public var strategy: Strategy = .reuse
        public var hallucinationGuard: Bool = true
        /// 诊断 `steps` 的保留条数。`0`（默认）表示不记录，见 `R2T2StreamPolicy`。
        public var maxRecordedSteps: Int = 0
        public init() {}
    }

    public struct Step: Sendable {
        public let index: Int
        public let audioEndSeconds: Double
        public let generatedIDs: [Int]
        public let generated: String
        public let delta: String
        public let maxNewTokens: Int
        public let wallSeconds: Double
        public let promptTokens: Int
        public let reusedTokens: Int
    }

    public let options: Options
    public private(set) var committedText = ""
    /// 本步被回滚（扣下）、尚未确认的尾部文本，见 `R2T2Text.pendingTail`。
    ///
    /// 它会在下一步带着更多上下文重新解码，因此内容可能改写——只用于实时预览
    /// （`PartialTranscript.unstableSuffix`），永远不能进入最终文本。`finish()` / 幻觉重置后为空。
    public private(set) var pendingText = ""
    public private(set) var language = ""
    public private(set) var steps: [Step] = []
    public private(set) var hallucinationResets = 0
    public private(set) var consumedSamples = 0

    private let model: Qwen3ASRModel
    private let tokenizer: any Tokenizers.Tokenizer
    private let forceLanguage: String?
    private let context: String
    private let sampleRate = 16000
    private let chunkSamples: Int
    private let lookaheadSamples: Int
    private let windowSamples: Int
    private let dropSamples: Int

    // r2t2 state
    private var buffer: [Float] = []
    private var didFinish = false
    private var recordedStepCount = 0
    private var window: [Float] = []
    private var chunkText: [String] = []
    private var rawDecoded = ""
    private var chunkID = 0
    private var isFirstChunk = true
    private var stateText = ""
    // schedule state
    private var maxNewTokens: Double
    private let firstMaxNewTokens: Int
    private let maxNewTokensFloor: Int
    private var lastText = ""
    private var recentTokens: [String] = []
    // reuse state
    private var cache: [KVCache]
    private var headIDs: [Int] = []
    private var stableLen = 0                          // KV positions valid at the start of a step
    private var blockMel: [MLXArray] = []              // mel slice per cached completed block
    private var blockFeats: [MLXArray] = []

    public init(model: Qwen3ASRModel, language: String? = nil, context: String = "", options: Options = Options()) {
        guard let tok = model.tokenizer else { fatalError("tokenizer not loaded") }
        self.model = model
        self.tokenizer = tok
        self.options = options
        self.forceLanguage = model.canonicalLanguage(language)
        self.context = context
        chunkSamples = Int((options.chunkSeconds * Double(sampleRate)).rounded())
        lookaheadSamples = Int((options.lookaheadSeconds * Double(sampleRate)).rounded())
        windowSamples = Int(options.windowSeconds * Double(sampleRate))
        dropSamples = Int(options.dropSeconds * Double(sampleRate))
        let step = chunkSamples
        firstMaxNewTokens = max(1, (step + lookaheadSamples) / 1280)
        maxNewTokens = Double(firstMaxNewTokens)
        maxNewTokensFloor = min(32, max(4, 2 * (step / 1280)))
        cache = model.model.newCache()
        headIDs = tok.encode(text: Self.head(context: context), addSpecialTokens: false)
    }

    // MARK: - Prompt pieces

    static func head(context: String) -> String {
        "<|im_start|>system\n" + context + "<|im_end|>\n<|im_start|>user\n<|audio_start|>"
    }
    static func tail(language: String?) -> String {
        var s = "<|audio_end|><|im_end|>\n<|im_start|>assistant\n"
        if let language, !language.isEmpty { s += "language \(language)<asr_text>" }
        return s
    }

    // MARK: - Input

    /// Feeds audio; returns the committed deltas produced by every full chunk it completed.
    ///
    /// Each step runs inside its own autorelease pool. A step hands Foundation and Metal
    /// AUTORELEASED objects: the tokenizer's NSRegularExpression pre-tokenizer (match results,
    /// NSValue ranges) and MLX's Metal command buffers, with the completion handlers they hold. A
    /// host's loop may never drain a pool of its own — a Swift-concurrency job, a CLI's `run()` — so
    /// without this a session kept every step's objects: phys grew ~0.07 GB per 10 minutes of audio,
    /// 6.18 → 6.47 GB over 45 min (ML[X] Audio Studio M14-C item 2; `qwen3asr-gates creep`).
    public func push(_ samples: [Float]) -> [String] {
        buffer.append(contentsOf: samples)
        var deltas: [String] = []
        while true {
            let need = isFirstChunk ? chunkSamples + lookaheadSamples : chunkSamples
            guard buffer.count >= need else { break }
            let chunk = Array(buffer[0 ..< need])
            buffer.removeFirst(need)
            isFirstChunk = false
            let d = autoreleasepool { step(chunk: chunk, budget: Int(maxNewTokens), final: false) }
            if let d, !d.isEmpty { deltas.append(d) }
        }
        return deltas
    }

    /// Flushes the tail with the first-chunk budget; returns its delta.
    ///
    /// 本地改动（见 `PROVENANCE.md`）：即使尾部缓冲为空，只要本次会话处理过音频就仍然走一次
    /// final decode。上游在此处直接返回，会丢掉最后一个非 final step 回滚的 token——录音结束在
    /// chunk 边界上时没有"下一次 chunk"去重新生成它们。`didFinish` 保证幂等。
    public func finish() -> String {
        guard !didFinish else { return "" }
        guard R2T2StreamPolicy.shouldIssueFinalDecode(
            hasBufferedTail: !buffer.isEmpty,
            consumedSamples: consumedSamples
        ) else {
            return ""
        }
        didFinish = true
        let tail = buffer
        buffer.removeAll()
        return autoreleasepool { step(chunk: tail, budget: firstMaxNewTokens, final: true) } ?? ""
    }

    // MARK: - One step (streaming_transcribe_no_reset / finish_streaming_transcribe_no_reset)

    private func step(chunk: [Float], budget: Int, final: Bool) -> String? {
        let t0 = Date()
        window.append(contentsOf: chunk)
        consumedSamples += chunk.count
        applyWindow()
        let prefixText = chunkText.joined()
        var prefix = prefixText
        if forceLanguage == nil && !language.isEmpty { prefix = "language \(language)<asr_text>" + prefixText }
        prefix = String(prefix.split(separator: "|", maxSplits: 1, omittingEmptySubsequences: false).first ?? "")
        let (ids, generated, promptTokens, reused) = decode(prefix: prefix, budget: budget)
        var gen = R2T2Text.normalizePunctByContext(generated).replacingOccurrences(of: "\u{FFFD}", with: "")
        if final {
            // finish_streaming_transcribe_no_reset
            // final 把尾部一次性确认掉，不再有待定内容。
            pendingText = ""
            rawDecoded = R2T2Text.beforePipe(prefix + gen)
            let (lang, txt0) = Qwen3ASROutput.parse(rawDecoded, forcedLanguage: forceLanguage)
            let txt = R2T2Text.beforePipe(txt0)
            language = lang
            stateText = txt
            chunkID += 1
            let ps = prefixText.trimmingCharacters(in: .whitespacesAndNewlines)
            let fs = txt.trimmingCharacters(in: .whitespacesAndNewlines)
            let newText = String(fs.dropFirst(min(ps.count, fs.count)))
            chunkText.append(newText)
            let emitted = R2T2Text.joining(newText, after: committedText, restarted: ps.isEmpty)
            committedText += emitted
            record(t0: t0, ids: ids, gen: gen, delta: newText, budget: budget, promptTokens: promptTokens, reused: reused)
            return emitted
        }
        rawDecoded = prefix + gen
        var lang: String? = nil
        if forceLanguage == nil { lang = R2T2Text.parseLanguageOutput(rawDecoded, userLanguage: nil).0 }
        if forceLanguage == "Chinese" || lang == "Chinese" { rawDecoded = R2T2Text.stripChineseSpaces(rawDecoded) }
        let (lang2, txt) = Qwen3ASROutput.parse(rawDecoded, forcedLanguage: forceLanguage)
        if let r = rawDecoded.range(of: Qwen3ASROutput.tag) {
            rawDecoded = String(rawDecoded[..<r.lowerBound]) + Qwen3ASROutput.tag + txt
        } else {
            rawDecoded = txt
        }
        rawDecoded = R2T2Text.beforePipe(rawDecoded)
        var k = kFor(punct: R2T2Text.punctRollbackB)
        let hasTag = rawDecoded.contains(Qwen3ASROutput.tag)
        if hasTag, let r = rawDecoded.range(of: Qwen3ASROutput.tag), rawDecoded[r.upperBound...].isEmpty { k = 0 }
        let rolledBack = rollback(rawDecoded, k: k)
        var fixed = rolledBack
        if let r = fixed.range(of: Qwen3ASROutput.tag) { fixed = String(fixed[r.upperBound...]) }
        if !hasTag && forceLanguage == nil {
            stateText = ""
            gen = ""
            // 本步没有可提交的文本，也就没有可预览的尾巴。
            pendingText = ""
            record(t0: t0, ids: ids, gen: generated, delta: "", budget: budget, promptTokens: promptTokens, reused: reused)
            schedule(grew: false, delta: "")
            return nil
        }
        // 回滚掉的那段就是本步尚未确认的尾巴：它不进 `committedText`，只作为实时预览交给 HUD。
        pendingText = R2T2Text.pendingTail(rawDecoded: rawDecoded, committed: rolledBack)
        language = lang2
        stateText = R2T2Text.beforePipe(txt)
        chunkID += 1
        let ps = prefixText.trimmingCharacters(in: .whitespacesAndNewlines)
        let fs = fixed.trimmingCharacters(in: .whitespacesAndNewlines)
        var newText = fs.hasPrefix(ps) ? String(fs.dropFirst(ps.count)) : ""
        newText = R2T2Text.beforePipe(newText)
        // The prompt keeps the model's own text exactly as upstream; only what is EMITTED gains a
        // separator when the loop restarted from an empty prefix (see `R2T2Text.joining`).
        chunkText.append(newText)
        let emitted = R2T2Text.joining(newText, after: committedText, restarted: ps.isEmpty)
        committedText += emitted
        record(t0: t0, ids: ids, gen: generated, delta: newText, budget: budget, promptTokens: promptTokens, reused: reused)
        schedule(grew: !newText.isEmpty, delta: newText)
        if options.hallucinationGuard, R2T2Text.detectHallucination(committedText).0 {
            hallucinationResets += 1
            resetContext()
        }
        return emitted
    }

    private func record(t0: Date, ids: [Int], gen: String, delta: String, budget: Int, promptTokens: Int, reused: Int) {
        let index = recordedStepCount
        recordedStepCount += 1
        guard options.maxRecordedSteps > 0 else { return }
        let drop = R2T2StreamPolicy.stepHistoryDropCount(count: steps.count, limit: options.maxRecordedSteps)
        if drop > 0 { steps.removeFirst(drop) }
        steps.append(Step(index: index, audioEndSeconds: Double(consumedSamples) / Double(sampleRate),
                          generatedIDs: ids, generated: gen, delta: delta, maxNewTokens: budget,
                          wallSeconds: Date().timeIntervalSince(t0), promptTokens: promptTokens, reusedTokens: reused))
    }

    /// ws_server.py: after a hallucination the state is re-initialised (audio + text context dropped).
    private func resetContext() {
        window.removeAll()
        chunkText.removeAll()
        rawDecoded = ""
        chunkID = 0
        stateText = ""
        // 上下文被丢弃后，上一步的待定尾巴不再有任何依据。
        pendingText = ""
        language = forceLanguage == nil ? "" : language
        recentTokens.removeAll()
        maxNewTokens = Double(firstMaxNewTokens)
        invalidateReuse()
    }

    // MARK: - Rolling window

    /// Drops the oldest `dropSamples` of audio AND the committed text of the chunks that spanned it.
    ///
    /// The two must stay in step. Upstream master hard-codes 2560/5120 samples here — it assumes the
    /// 160 ms production schedule and trims 49-50 entries whatever the chunk size is. At 320 ms only
    /// 25 chunks span the dropped 8 s, so it discards about twice the committed text; the prompt
    /// prefix then no longer covers what was already emitted, the model re-transcribes that audio and
    /// the delta computation appends it a second time. Measured on the Python rung before the fix:
    /// **84.4 % WER at 320 ms (vs 2.6 % at 160 ms) with a transcript 1.9x the reference length.**
    /// Upstream's own PR #3 generalises it exactly this way. `chunkSeconds` is a public knob
    /// documented as 80 ms-2 s, so the hard-coded form was a live defect, not a latent one.
    private func applyWindow() {
        guard window.count > windowSamples else { return }
        let keep = window.count - dropSamples
        let discardChunks = dropSamples / chunkSamples
        window = Array(window.suffix(keep))
        chunkText = Array(chunkText.dropFirst(min(discardChunks, chunkText.count)))
    }

    // MARK: - Schedule (ws_server v1 / example.py)

    private func schedule(grew: Bool, delta: String) {
        let base = max(1, chunkSamples / 1280)
        switch options.schedule {
        case .server:
            if grew {
                for w in R2T2Text.splitTextToTokens(delta) {
                    recentTokens.append(w)
                    if recentTokens.count > 10 { recentTokens.removeFirst() }
                }
                maxNewTokens = Double(base)
            } else if !R2T2Text.isLastTokenChinese(recentTokens) {
                maxNewTokens += 0.5
            } else {
                maxNewTokens = Double(base)
            }
        case .example:
            if grew { maxNewTokens = Double(base) }
            else if !R2T2Text.isLastTokenChinese(recentTokens) { maxNewTokens += 1 }
            else { maxNewTokens = Double(base) }
        }
        if R2T2Text.isLastTokenChinese(recentTokens) { maxNewTokens *= 2 }
        maxNewTokens = min(Double(maxNewTokensFloor), maxNewTokens)
    }

    private func kFor(punct: String) -> Int {
        if options.rollbackPunctuation {
            let s = rawDecoded.trimmingCharacters(in: .whitespacesAndNewlines)
            if let last = s.last, punct.contains(last) { return 0 }
        }
        return options.unfixedTokens
    }

    private func rollback(_ raw: String, k kIn: Int) -> String {
        let ids = tokenizer.encode(text: raw, addSpecialTokens: false)
        var k = kIn
        while true {
            let end = max(0, ids.count - k)
            let out = end > 0 ? tokenizer.decode(tokens: Array(ids[0 ..< end]), skipSpecialTokens: false) : ""
            if !out.contains("\u{FFFD}") { return out }
            if end == 0 { return "" }
            k += 1
        }
    }

    // MARK: - Decode over the window (the generate_fn)

    private func invalidateReuse() {
        blockMel.removeAll()
        blockFeats.removeAll()
        stableLen = 0
        cache = model.model.newCache()
    }

    /// Returns (generated ids, decoded text, prompt length, KV positions reused).
    private func decode(prefix: String, budget: Int) -> ([Int], String, Int, Int) {
        var samples = window
        if samples.count < 1280 { samples.append(contentsOf: repeatElement(0, count: 1280 - samples.count)) }
        let mel = model.melFeatures(samples)
        let frames = mel.dim(0)
        let blockFrames = model.config.audioConfig.blockFrames
        let complete = frames / blockFrames                    // fully filled blocks
        let reuse = options.strategy == .reuse
        // Encoder: reuse a completed block only when its mel frames are identical.
        var feats: [MLXArray] = []
        var stableBlocks = 0
        var stableRun = true
        for b in 0 ..< complete {
            let slice = mel[b * blockFrames ..< (b + 1) * blockFrames]
            if reuse, stableRun, b < blockMel.count, blockMel[b].shape == slice.shape,
               MLX.all(blockMel[b] .== slice).item(Bool.self) {
                feats.append(blockFeats[b]); stableBlocks += 1
            } else {
                stableRun = false
                let f = model.audioTower.encodeBlock(slice); eval(f)
                if reuse {
                    if b < blockMel.count { blockMel[b] = slice; blockFeats[b] = f } else { blockMel.append(slice); blockFeats.append(f) }
                }
                feats.append(f)
            }
        }
        if reuse, blockMel.count > complete { blockMel.removeLast(blockMel.count - complete); blockFeats.removeLast(blockFeats.count - complete) }
        if complete * blockFrames < frames {
            let f = model.audioTower.encodeBlock(mel[(complete * blockFrames)...]); eval(f)
            feats.append(f)
        }
        let audio = feats.count == 1 ? feats[0] : concatenated(feats, axis: 0)
        // Prompt
        let tailIDs = tokenizer.encode(text: Self.tail(language: forceLanguage) + prefix, addSpecialTokens: false)
        let nAudio = audio.dim(0)
        let promptLen = headIDs.count + nAudio + tailIDs.count
        // How much KV survives: head + the stable completed blocks' audio positions.
        let stableAudio = stableBlocks > 0 ? feats[0 ..< stableBlocks].reduce(0) { $0 + $1.dim(0) } : 0
        var keep = reuse ? min(stableLen, headIDs.count + stableAudio) : 0
        if !reuse || stableBlocks == 0 { keep = reuse ? min(stableLen, headIDs.count) : 0 }
        let offset = cache.first?.offset ?? 0
        if keep > 0 && offset >= keep {
            trimPromptCache(cache, numTokens: offset - keep)
        } else {
            keep = 0
            cache = model.model.newCache()
        }
        // Embeddings for positions keep..<promptLen
        let headEmb = model.model.embed(MLXArray(headIDs.map(Int32.init)))
        let tailEmb = model.model.embed(MLXArray(tailIDs.map(Int32.init)))
        let full = concatenated([headEmb, audio.asType(headEmb.dtype), tailEmb], axis: 0)
        let emb = full[keep...].expandedDimensions(axis: 0)
        let ids = model.generate(embeddings: emb, cache: cache, maxNewTokens: budget)
        // The stable prefix for the NEXT step: head + all completed blocks (their KV is in the cache now).
        stableLen = reuse ? headIDs.count + feats.prefix(complete).reduce(0) { $0 + $1.dim(0) } : 0
        let text = tokenizer.decode(tokens: ids, skipSpecialTokens: true)
        return (ids, text, promptLen, keep)
    }
}

/// Text helpers ported verbatim from `r2t2_asr.py`, `example.py` and `ws_server.py`.
public enum R2T2Text {
    static let en2zh: [Character: Character] = [",": "，", ".": "。", "!": "！", "?": "？", ";": "；", ":": "：", "(": "（", ")": "）"]
    static let zh2en: [Character: Character] = Dictionary(uniqueKeysWithValues: en2zh.map { ($1, $0) })
    static let allPunct: Set<Character> = Set(",.!?;:()，。！？；：（）")
    static let punctRollbackA = "，。！？、；：.!?;:"
    static let punctRollbackB = "，。！？、；：,.!?;:"

    static func isCJK(_ c: Character) -> Bool {
        guard let u = c.unicodeScalars.first?.value else { return false }
        return u >= 0x4E00 && u <= 0x9FFF
    }

    /// `_normalize_punct_by_context`: a mark after a Chinese character becomes full-width, after an
    /// ASCII letter/digit half-width, otherwise unchanged.
    public static func normalizePunctByContext(_ text: String) -> String {
        let chars = Array(text)
        var out = chars
        for (i, c) in chars.enumerated() where allPunct.contains(c) {
            var prev: Character? = nil
            var j = i - 1
            while j >= 0 { if !chars[j].isWhitespace { prev = chars[j]; break }; j -= 1 }
            guard let p = prev else { continue }
            if isCJK(p) { out[i] = en2zh[c] ?? c }
            else if p.isASCII && (p.isLetter || p.isNumber) { out[i] = zh2en[c] ?? c }
        }
        return String(out)
    }

    /// The committed piece to EMIT, given what was emitted before it.
    ///
    /// When the loop restarts from an empty prefix, the model begins a fresh transcript whose first
    /// token carries no leading space. That happens after a pause longer than the rolling window,
    /// whose drop leaves no committed text in the prompt, and after a hallucination reset. Upstream
    /// concatenates anyway, so English after a 20 s pause reads "the lakesOn August" (the Python
    /// rung does the same). A separator goes in only on a restart, only between space-delimited
    /// scripts, and never before closing punctuation. Mid-stream deltas are subword continuations
    /// ("glean" + "er") and are never touched. Found by ML[X] Audio Studio M14-C item 6 (0.1.2).
    public static func joining(_ piece: String, after emitted: String, restarted: Bool) -> String {
        guard restarted, let left = emitted.last, let right = piece.first,
              !left.isWhitespace, !right.isWhitespace,
              !",.!?;:)]}\u{3001}\u{3002}".contains(right),
              !isUnspacedScript(left), !isUnspacedScript(right) else { return piece }
        return " " + piece
    }

    /// 本步被回滚（扣下）的尾部文本：`rawDecoded` 中 `committed` 之后的部分。
    ///
    /// 这些 token 会在下一步带着更多上下文重新解码，内容因此可能改写——只能用于实时预览
    /// （`PartialTranscript.unstableSuffix`），永远不能进最终文本。
    ///
    /// `committed` 必须是 `rawDecoded` 的前缀。BPE 编解码往返并非恒等，一旦不是前缀就返回空串：
    /// 宁可什么都不暴露，也不要把错位的文本交给 HUD。
    public static func pendingTail(rawDecoded: String, committed: String) -> String {
        guard rawDecoded.hasPrefix(committed) else { return "" }
        return String(rawDecoded.dropFirst(committed.count))
    }

    /// Scripts written without spaces between words: Han, kana, Thai, and CJK punctuation or
    /// full-width forms. Korean (Hangul) is space-delimited, so it is not in the list.
    public static func isUnspacedScript(_ c: Character) -> Bool {
        guard let v = c.unicodeScalars.first?.value else { return false }
        switch v {
        case 0x3400...0x4DBF, 0x4E00...0x9FFF, 0xF900...0xFAFF, 0x20000...0x2FA1F: return true   // Han
        case 0x3040...0x30FF, 0x31F0...0x31FF: return true                                    // kana
        case 0x0E00...0x0E7F: return true                                                     // Thai
        case 0x3000...0x303F, 0xFF00...0xFFEF: return true                                    // CJK punctuation, full-width
        default: return false
        }
    }

    public static func beforePipe(_ s: String) -> String {
        if let r = s.firstIndex(of: "|") { return String(s[..<r]) }
        return s
    }

    /// `re.sub(r'(?<=[一-鿿])\s+(?=[一-鿿])', '', s)`
    public static func stripChineseSpaces(_ s: String) -> String {
        let chars = Array(s)
        var out: [Character] = []
        var i = 0
        while i < chars.count {
            if chars[i].isWhitespace, let prev = out.last, isCJK(prev) {
                var j = i
                while j < chars.count && chars[j].isWhitespace { j += 1 }
                if j < chars.count && isCJK(chars[j]) { i = j; continue }
            }
            out.append(chars[i]); i += 1
        }
        return String(out)
    }

    /// `r2t2_asr.parse_language_output` — no repetition fixer; English keeps leading whitespace.
    public static func parseLanguageOutput(_ raw: String, userLanguage: String?) -> (String, String) {
        var s = raw
        if userLanguage == "English" {
            while let l = s.last, l.isWhitespace { s.removeLast() }
        } else {
            s = s.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if s.isEmpty { return ("", "") }
        if let userLanguage { return (userLanguage, s) }
        guard let r = s.range(of: Qwen3ASROutput.tag) else { return ("", s.trimmingCharacters(in: .whitespacesAndNewlines)) }
        let meta = String(s[..<r.lowerBound]), text = String(s[r.upperBound...])
        if meta.lowercased().contains("language none") { return ("", text.trimmingCharacters(in: .whitespacesAndNewlines)) }
        var lang = ""
        for line in meta.split(separator: "\n", omittingEmptySubsequences: true) {
            let l = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if l.isEmpty { continue }
            if l.lowercased().hasPrefix("language ") {
                let v = l.dropFirst("language ".count).trimmingCharacters(in: .whitespacesAndNewlines)
                if !v.isEmpty { lang = v.prefix(1).uppercased() + v.dropFirst().lowercased() }
            }
            break
        }
        return (lang, text.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    /// `split_text_to_tokens`: strip punctuation, then runs of ASCII letters as words, every other character alone.
    public static func splitTextToTokens(_ text: String) -> [String] {
        let cn = "？！＂＃＄％＆＇（）＊＋，－／：；＜＝＞＠［＼］＾＿｀｛｜｝～、。〃〄々〆〇〈〉《》「」『』【】〔〕〖〗〘〙〚〛〜〝〞〟〰〾〿–—‘’‛“”„‟…‧﹏"
        let ascii = "!\"#$%&'()*+,-./:;<=>?@[\\]^_`{|}~"
        let drop = Set(cn + ascii)
        var out: [String] = []
        var word = ""
        for c in text where !drop.contains(c) {
            if c.isASCII && c.isLetter { word.append(c); continue }
            if !word.isEmpty { out.append(word); word = "" }
            if !c.isWhitespace { out.append(String(c)) }
        }
        if !word.isEmpty { out.append(word) }
        return out
    }

    public static func isLastTokenChinese(_ tokens: [String]) -> Bool {
        guard let last = tokens.last else { return false }
        return last.contains { isCJK($0) }
    }

    /// ws_server.py `detect_hallucination`: a tail pattern (≤ 50 chars) repeated ≥ 5×.
    public static func detectHallucination(_ text: String, threshold: Int = 5, maxPattern: Int = 50, tail: Int = 256) -> (Bool, String) {
        if text.isEmpty { return (false, "") }
        let punctChars = "，。！？、；：,.!?;:~…·\"'()（）《》—-"
        let t = Array(text.suffix(tail))
        let n = t.count
        for k in 1 ... maxPattern {
            if n < k * threshold { continue }
            let pattern = Array(t[(n - k)...])
            if pattern.allSatisfy({ punctChars.contains($0) || $0 == " " || $0 == "\t" }) { continue }
            var ok = true
            for r in 1 ..< threshold where Array(t[(n - (r + 1) * k) ..< (n - r * k)]) != pattern { ok = false; break }
            if ok { return (true, "tail_pattern:'\(String(pattern))'x\(threshold)+") }
        }
        let norm = Array(t.filter { !punctChars.contains($0) && !$0.isWhitespace })
        let n2 = norm.count
        if maxPattern >= 3 {
            for k in 3 ... maxPattern {
                if n2 < k * threshold { continue }
                let pattern = Array(norm[(n2 - k)...])
                var ok = true
                for r in 1 ..< threshold where Array(norm[(n2 - (r + 1) * k) ..< (n2 - r * k)]) != pattern { ok = false; break }
                if ok { return (true, "tail_pattern_norm:'\(String(pattern))'x\(threshold)+") }
            }
        }
        return (false, "")
    }
}
