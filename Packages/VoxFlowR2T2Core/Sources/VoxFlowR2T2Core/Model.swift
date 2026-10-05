import Foundation
import MLX
import MLXLMCommon
import MLXNN
import Tokenizers

/// Qwen3-ASR: `audio_tower` (AuT) + `model` (Qwen3) with a tied output head.
public final class Qwen3ASRModel: Module {
    public let config: Qwen3ASRConfig
    @ModuleInfo(key: "audio_tower") public var audioTower: Qwen3ASRAudioEncoder
    @ModuleInfo(key: "model") public var model: Qwen3ASRTextModel
    @ModuleInfo(key: "lm_head") var lmHead: Linear?
    public let mel = WhisperLogMel()
    public var tokenizer: (any Tokenizers.Tokenizer)?

    public init(_ cfg: Qwen3ASRConfig) {
        config = cfg
        _audioTower.wrappedValue = Qwen3ASRAudioEncoder(cfg.audioConfig)
        _model.wrappedValue = Qwen3ASRTextModel(cfg.textConfig)
        _lmHead.wrappedValue = cfg.textConfig.tieWordEmbeddings
            ? nil : Linear(cfg.textConfig.hiddenSize, cfg.textConfig.vocabSize, bias: false)
        super.init()
    }

    // MARK: - Prompt

    /// The chat template with ONE `<|audio_pad|>` placeholder — identical to what
    /// `processor.apply_chat_template(..., add_generation_prompt=True)` renders for
    /// `[system: context] [user: audio]`, plus `language X<asr_text>` when the language is forced.
    public static func promptTemplate(context: String, language: String?) -> String {
        var s = "<|im_start|>system\n" + context + "<|im_end|>\n"
            + "<|im_start|>user\n<|audio_start|><|audio_pad|><|audio_end|><|im_end|>\n"
            + "<|im_start|>assistant\n"
        if let language, !language.isEmpty { s += "language \(language)<asr_text>" }
        return s
    }

    /// Canonical language name (`"chinese"` → `"Chinese"`, `"en"` → `"English"`), validated against
    /// `support_languages` when the checkpoint lists them. See `canonicalLanguageName(_:supported:)`.
    public func canonicalLanguage(_ language: String?) -> String? {
        guard let raw = language?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else { return nil }
        return Self.canonicalLanguageName(raw, supported: config.supportLanguages)
    }

    /// The name the prompt's `language X<asr_text>` header needs, from whatever a host holds: a
    /// name (`"English"`), an alias (`"mandarin"`), an ISO 639 code (`"zh"`, `"fil"`) or a BCP-47
    /// locale (`"en-US"`, `"zh-Hans-CN"`, `"yue-HK"` — its primary subtag names the language).
    ///
    /// A language the checkpoint does not list returns **nil**, which means auto-detect. Before
    /// 0.1.1 it came back capitalised (`"en-US"` → `"En-us"`) and went into the prompt as a
    /// language the model has never seen. ⚠️ Forcing a language matters for latency as well as
    /// accuracy. Under auto-detect the stable prefix begins `language None<asr_text>`, and nothing
    /// commits until the header settles. On the 6.7 s Mandarin sample that is 5.9 s, against
    /// 1.9 s with `"Chinese"` forced (goldens `zh_test_auto` vs `zh_test`).
    public static func canonicalLanguageName(_ raw: String, supported: [String]) -> String? {
        let key = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !key.isEmpty else { return nil }
        let primary = key.split(whereSeparator: { $0 == "-" || $0 == "_" }).first.map(String.init) ?? key
        let candidates = [
            qwen3ASRLanguageAliases[key],
            qwen3ASRLanguageAliases[primary],
            Locale(identifier: "en_US").localizedString(forLanguageCode: primary),   // ISO 639 → English name
            key.prefix(1).uppercased() + key.dropFirst(),
        ].compactMap { $0 }
        guard !supported.isEmpty else { return candidates.first }
        for candidate in candidates {
            if let hit = supported.first(where: { $0.lowercased() == candidate.lowercased() }) { return hit }
        }
        return nil
    }

    /// Token ids for `template` with the placeholder expanded to `audioTokens` pads.
    public func promptIDs(template: String, audioTokens: Int) -> [Int] {
        guard let tokenizer else { fatalError("tokenizer not loaded") }
        let pad = "<|audio_pad|>"
        precondition(template.components(separatedBy: pad).count == 2, "template must hold exactly one <|audio_pad|>")
        let text = template.replacingOccurrences(of: pad, with: String(repeating: pad, count: audioTokens))
        return tokenizer.encode(text: text, addSpecialTokens: false)
    }

    // MARK: - Features and embeddings

    /// Log-mel `[frames, nMels]` for a 16 kHz mono clip.
    public func melFeatures(_ samples: [Float]) -> MLXArray {
        let (frames, data) = mel.features(samples)
        return MLXArray(data).reshaped(frames, mel.nMels)
    }

    /// Splices `audio` (`[N, hidden]`) over the contiguous run of `<|audio_pad|>` ids in `ids`.
    public func inputEmbeddings(ids: [Int], audio: MLXArray) -> MLXArray {
        let n = audio.dim(0)
        guard let start = ids.firstIndex(of: config.audioTokenId) else { fatalError("prompt has no audio pads") }
        precondition(ids[start ..< start + n].allSatisfy { $0 == config.audioTokenId }, "audio pads are not contiguous / count mismatch")
        let emb = model.embed(MLXArray(ids.map(Int32.init)))          // [L, hidden]
        let parts = [emb[0 ..< start], audio.asType(emb.dtype), emb[(start + n)...]]
        return concatenated(parts, axis: 0).expandedDimensions(axis: 0)   // [1, L, hidden]
    }

    /// Logits `[B, L, vocab]` for embeddings through the decoder and the (tied) head.
    public func logits(embeddings: MLXArray, cache: [KVCache]?) -> MLXArray {
        let h = model(embeddings: embeddings, cache: cache)
        if let lmHead { return lmHead(h) }
        return model.embedTokens.asLinear(h)
    }

    // MARK: - Greedy generation

    /// Prefills `embeddings` into `cache` and greedily decodes up to `maxNewTokens`, stopping on EOS
    /// (which is not returned). The cache is left positioned after the last generated token.
    public func generate(embeddings: MLXArray, cache: [KVCache], maxNewTokens: Int,
                         eos: Set<Int> = Qwen3ASRSpecialIDs.eos) -> [Int] {
        var out: [Int] = []
        guard maxNewTokens > 0 else { return out }
        var logits = self.logits(embeddings: embeddings, cache: cache)
        var next = argMax(logits[0..., -1, 0...], axis: -1)
        asyncEval(next)
        for _ in 0 ..< maxNewTokens {
            let t = next.item(Int.self)
            if eos.contains(t) { break }
            out.append(t)
            if out.count == maxNewTokens { break }
            logits = self.logits(embeddings: model.embed(MLXArray([Int32(t)])).expandedDimensions(axis: 0), cache: cache)
            next = argMax(logits[0..., -1, 0...], axis: -1)
            asyncEval(next)
        }
        return out
    }

    // MARK: - One-shot transcription

    public struct Transcript: Sendable {
        public let text: String
        public let language: String?
        public let tokenIDs: [Int]
        public let promptTokens: Int
    }

    /// Offline transcription of a whole clip (the reference's `transcribe`): one prompt, greedy.
    public func transcribe(samples: [Float], language: String? = nil, context: String = "",
                           maxNewTokens: Int = 4096) -> Transcript {
        guard let tokenizer else { fatalError("tokenizer not loaded") }
        let lang = canonicalLanguage(language)
        let feats = audioTower.encode(melFeatures(samples))
        let ids = promptIDs(template: Self.promptTemplate(context: context, language: lang), audioTokens: feats.dim(0))
        let emb = inputEmbeddings(ids: ids, audio: feats)
        let tokens = generate(embeddings: emb, cache: model.newCache(), maxNewTokens: maxNewTokens)
        let raw = tokenizer.decode(tokens: tokens, skipSpecialTokens: true)
        let (detected, text) = Qwen3ASROutput.parse(raw, forcedLanguage: lang)
        return Transcript(text: text, language: detected.isEmpty ? nil : detected, tokenIDs: tokens, promptTokens: ids.count)
    }
}

/// `parse_asr_output` from `qwen_asr.inference.utils` (with its repetition fixer), verbatim.
public enum Qwen3ASROutput {
    public static let tag = "<asr_text>"

    /// Returns `(language, text)`. With a forced language the whole output is text.
    public static func parse(_ raw: String, forcedLanguage: String?) -> (String, String) {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.isEmpty { return ("", "") }
        s = fixRepetitions(s, threshold: 20)
        if let forcedLanguage, !forcedLanguage.isEmpty { return (forcedLanguage, s) }
        guard let r = s.range(of: tag) else { return ("", s.trimmingCharacters(in: .whitespacesAndNewlines)) }
        let meta = String(s[..<r.lowerBound])
        let text = String(s[r.upperBound...])
        if meta.lowercased().contains("language none") {
            let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
            return ("", t)
        }
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

    /// `detect_and_fix_repetitions(text, threshold)`: collapse a character repeated more than
    /// `threshold` times, then a pattern (≤ 20 chars) repeated `threshold`+ times, to one copy.
    public static func fixRepetitions(_ text: String, threshold: Int) -> String {
        let chars = Array(text)
        // fix_char_repeats
        var res: [Character] = []
        var i = 0
        while i < chars.count {
            var count = 1
            while i + count < chars.count && chars[i + count] == chars[i] { count += 1 }
            if count > threshold { res.append(chars[i]) } else { res.append(contentsOf: chars[i ..< i + count]) }
            i += count
        }
        return fixPatternRepeats(res, threshold: threshold, maxLen: 20)
    }

    private static func fixPatternRepeats(_ s: [Character], threshold: Int, maxLen: Int) -> String {
        let n = s.count
        let minRepeat = threshold * 2
        if n < minRepeat { return String(s) }
        var i = 0
        var result: [Character] = []
        var found = false
        while i <= n - minRepeat {
            found = false
            for k in 1 ... maxLen {
                if i + k * threshold > n { break }
                let pattern = Array(s[i ..< i + k])
                var valid = true
                for rep in 1 ..< threshold {
                    let st = i + rep * k
                    if Array(s[st ..< min(st + k, n)]) != pattern { valid = false; break }
                }
                if valid {
                    var end = i + threshold * k
                    while end + k <= n && Array(s[end ..< end + k]) == pattern { end += k }
                    result.append(contentsOf: pattern)
                    result.append(contentsOf: Array(fixPatternRepeats(Array(s[end...]), threshold: threshold, maxLen: maxLen)))
                    i = n
                    found = true
                    break
                }
            }
            if found { break }
            result.append(s[i])
            i += 1
        }
        if !found { result.append(contentsOf: s[i...]) }
        return String(result)
    }
}

/// Short-code aliases the reference CLI accepts for `language`.
let qwen3ASRLanguageAliases: [String: String] = [
    "zh": "Chinese", "chinese": "Chinese", "mandarin": "Chinese",
    "yue": "Cantonese", "cantonese": "Cantonese",
    "en": "English", "english": "English",
    "de": "German", "german": "German",
    "es": "Spanish", "spanish": "Spanish",
    "fr": "French", "french": "French",
    "it": "Italian", "italian": "Italian",
    "pt": "Portuguese", "portuguese": "Portuguese",
    "ru": "Russian", "russian": "Russian",
    "ko": "Korean", "korean": "Korean",
    "ja": "Japanese", "japanese": "Japanese",
]
