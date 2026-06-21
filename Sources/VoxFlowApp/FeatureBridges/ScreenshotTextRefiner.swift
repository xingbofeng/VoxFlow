import Foundation
@preconcurrency import MADLADTranslation
@preconcurrency import Qwen3Chat

protocol ScreenshotTextRefiningCapabilities {
    var isTranslationConfigured: Bool { get }
    var isSummaryConfigured: Bool { get }
}

final class ScreenshotTextRefiner: PromptAwareTextRefining, ScreenshotTextRefiningCapabilities, @unchecked Sendable {
    private let cloudRefiner: (any PromptAwareTextRefining)?
    private let systemTranslator: any PromptAwareTextRefining
    private let localTranslator: any PromptAwareTextRefining
    private let localSummarizer: any PromptAwareTextRefining
    private let defaults: UserDefaults

    init(
        cloudRefiner: (any PromptAwareTextRefining)?,
        systemTranslator: any PromptAwareTextRefining = AppleSystemTranslationRefiner(),
        localTranslator: any PromptAwareTextRefining = SoniqoMADLADTranslationRefiner(),
        localSummarizer: any PromptAwareTextRefining = SoniqoQwen35SummaryRefiner(),
        defaults: UserDefaults = .standard
    ) {
        self.cloudRefiner = cloudRefiner
        self.systemTranslator = systemTranslator
        self.localTranslator = localTranslator
        self.localSummarizer = localSummarizer
        self.defaults = defaults
    }

    var isEnabled: Bool {
        isTranslationConfigured || isSummaryConfigured
    }

    var isConfigured: Bool {
        isTranslationConfigured || isSummaryConfigured
    }

    var isTranslationConfigured: Bool {
        switch selectedTranslationModelID {
        case CapabilityModelID.systemDefaultTranslation:
            return (systemTranslator.isEnabled && systemTranslator.isConfigured) ||
                cloudRefinerIsReady
        case CapabilityModelID.llmTranslation:
            return cloudRefinerIsReady
        case CapabilityModelID.madladTranslation:
            return localTranslator.isConfigured || cloudRefinerIsReady
        default:
            return cloudRefinerIsReady
        }
    }

    var isSummaryConfigured: Bool {
        cloudRefinerIsReady
    }

    func refine(_ text: String) async throws -> String {
        try await refine(
            TextRefinementRequest(
                text: text,
                systemPrompt: ScreenshotOCRService.translationSystemPrompt,
                model: nil,
                temperature: nil
            )
        )
    }

    func refine(_ request: TextRefinementRequest) async throws -> String {
        let isTranslationRequest = Self.isTranslationRequest(request)
        if isTranslationRequest {
            var selectedPathError: Error?
            if selectedTranslationModelID == CapabilityModelID.llmTranslation {
                guard let cloudRefiner,
                      cloudRefiner.isEnabled,
                      cloudRefiner.isConfigured else {
                    throw ScreenshotLocalModelError.translationRequiresLLM
                }
                let output = try await cloudRefiner.refine(request)
                return try Self.validatedOutput(output, isTranslationRequest: true)
            } else if selectedTranslationModelID == CapabilityModelID.systemDefaultTranslation {
                do {
                    let output = try await systemTranslator.refine(request)
                    return try Self.validatedOutput(output, isTranslationRequest: true)
                } catch {
                    selectedPathError = error
                    AppLogger.general.warning("Screenshot Apple translation failed, falling back to cloud model: \(error.localizedDescription)")
                }
            } else if localTranslator.isEnabled, localTranslator.isConfigured {
                do {
                    let output = try await localTranslator.refine(request)
                    return try Self.validatedOutput(output, isTranslationRequest: true)
                } catch {
                    selectedPathError = error
                    AppLogger.general.warning("Screenshot local translation failed, falling back to cloud model: \(error.localizedDescription)")
                }
            }

            if let cloudRefiner,
               cloudRefiner.isEnabled,
               cloudRefiner.isConfigured {
                let output = try await cloudRefiner.refine(request)
                return try Self.validatedOutput(output, isTranslationRequest: true)
            }

            if let selectedPathError {
                throw selectedPathError
            }
            throw ScreenshotLocalModelError.translationModelNotInstalled
        }

        guard let cloudRefiner,
              cloudRefiner.isEnabled,
              cloudRefiner.isConfigured else {
            throw ScreenshotLocalModelError.summaryRequiresLLM
        }

        let output = try await cloudRefiner.refine(request)
        return try Self.validatedOutput(output, isTranslationRequest: false)
    }

    private var selectedTranslationModelID: String {
        CapabilityModelViewModel.selectedModelID(kind: .translation, defaults: defaults)
    }

    private var cloudRefinerIsReady: Bool {
        guard let cloudRefiner else { return false }
        return cloudRefiner.isEnabled && cloudRefiner.isConfigured
    }

    private static func isTranslationRequest(_ request: TextRefinementRequest) -> Bool {
        request.systemPrompt.contains("翻译助手") ||
            request.systemPrompt == ScreenshotOCRService.translationSystemPrompt
    }

    private static func validatedOutput(_ output: String, isTranslationRequest: Bool) throws -> String {
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return trimmed }
        if !isTranslationRequest,
           TranslationOutputValidator.looksPathologicallyRepetitive(trimmed) {
            throw ScreenshotLocalModelError.invalidSummaryRepetition
        }

        guard !isTranslationRequest else { return trimmed }

        if SummaryOutputValidator.looksLikeHTMLOrCode(trimmed) {
            throw ScreenshotLocalModelError.invalidSummaryOutput
        }
        return trimmed
    }
}

private enum ScreenshotLocalModelError: LocalizedError {
    case translationModelNotInstalled
    case translationRequiresLLM
    case summaryModelNotInstalled
    case summaryRequiresLLM
    case invalidSummaryOutput
    case invalidSummaryRepetition

    var errorDescription: String? {
        switch self {
        case .translationModelNotInstalled:
            return "本地翻译模型未安装，MADLAD-400 INT4 约 1.7GB；请先配置 LLM 或安装本地翻译模型"
        case .translationRequiresLLM:
            return "翻译需要先配置 LLM 模型"
        case .summaryModelNotInstalled:
            return "本地总结模型未安装，Qwen3.5-0.8B INT4 约 404MB；请先配置 LLM 或安装本地总结模型"
        case .summaryRequiresLLM:
            return "总结需要先配置 LLM 模型"
        case .invalidSummaryOutput:
            return "总结模型输出了网页/代码内容，请重试或改用已配置的 LLM"
        case .invalidSummaryRepetition:
            return "总结模型输出异常重复内容，请重试或改用已配置的 LLM"
        }
    }
}

private enum TranslationOutputValidator {
    static func looksPathologicallyRepetitive(_ text: String) -> Bool {
        let tokens = normalizedTokens(in: text)
        guard tokens.count >= 12 else { return false }

        let counts = Dictionary(grouping: tokens, by: { $0 }).mapValues(\.count)
        if let mostRepeated = counts.values.max(),
           mostRepeated >= 8,
           Double(mostRepeated) / Double(tokens.count) >= 0.35 {
            return true
        }

        return (2...min(5, tokens.count / 2)).contains { width in
            repeatedNGram(tokens, width: width)
        }
    }

    private static func normalizedTokens(in text: String) -> [String] {
        let pattern = #"[A-Za-z_][A-Za-z0-9_]*(?:\.[A-Za-z_][A-Za-z0-9_]*)?|\p{Han}+|\d+"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.matches(in: text, range: range).compactMap { match in
            guard let tokenRange = Range(match.range, in: text) else { return nil }
            return String(text[tokenRange]).lowercased()
        }
    }

    private static func repeatedNGram(_ tokens: [String], width: Int) -> Bool {
        var counts: [String: Int] = [:]
        for index in 0...(tokens.count - width) {
            let phrase = tokens[index..<(index + width)].joined(separator: " ")
            counts[phrase, default: 0] += 1
        }
        guard let mostRepeated = counts.values.max(), mostRepeated >= 4 else {
            return false
        }
        return Double(mostRepeated * width) / Double(tokens.count) >= 0.5
    }
}

private enum SummaryOutputValidator {
    static func looksLikeHTMLOrCode(_ text: String) -> Bool {
        let lowered = text.lowercased()
        if lowered.hasPrefix("```") {
            return true
        }
        let htmlMarkers = [
            "<!doctype html",
            "<html",
            "<head",
            "<body",
            "<style",
            "<script",
            "</html>",
        ]
        return htmlMarkers.contains { lowered.contains($0) }
    }
}

struct SoniqoLocalModelCache {
    let modelId: String
    let variant: String
    var fileManager: FileManager = .default

    var isInstalled: Bool {
        candidateModelFiles.contains { fileManager.fileExists(atPath: $0.path) }
    }

    private var candidateModelFiles: [URL] {
        guard let cachesDirectory = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first else {
            return []
        }

        let components = modelId.split(separator: "/", maxSplits: 1).map(String.init)
        guard components.count == 2 else { return [] }

        let hubStyle = cachesDirectory
            .appendingPathComponent("qwen3-speech", isDirectory: true)
            .appendingPathComponent("models", isDirectory: true)
            .appendingPathComponent(components[0], isDirectory: true)
            .appendingPathComponent(components[1], isDirectory: true)
            .appendingPathComponent(variant, isDirectory: true)
            .appendingPathComponent("model.safetensors")

        let flatStyle = cachesDirectory
            .appendingPathComponent("qwen3-speech", isDirectory: true)
            .appendingPathComponent(modelId.replacingOccurrences(of: "/", with: "_"), isDirectory: true)
            .appendingPathComponent(variant, isDirectory: true)
            .appendingPathComponent("model.safetensors")

        return [hubStyle, flatStyle]
    }
}

protocol SoniqoMADLADTranslating: Sendable {
    func translate(_ text: String, to targetLanguage: String) async throws -> String
}

final class SoniqoMADLADTranslationRefiner: PromptAwareTextRefining, @unchecked Sendable {
    private let engine: any SoniqoMADLADTranslating
    private let cache: SoniqoLocalModelCache
    private let capabilityDownloader: any CapabilityModelDownloading
    private let isModelInstalled: (() -> Bool)?

    init(
        engine: any SoniqoMADLADTranslating = SoniqoMADLADTranslationEngine(),
        cache: SoniqoLocalModelCache = SoniqoLocalModelCache(
            modelId: MADLADTranslator.defaultModelId,
            variant: MADLADTranslator.Quantization.int4.rawValue
        ),
        capabilityDownloader: any CapabilityModelDownloading = SoniqoCapabilityModelDownloader(),
        isModelInstalled: (() -> Bool)? = nil
    ) {
        self.engine = engine
        self.cache = cache
        self.capabilityDownloader = capabilityDownloader
        self.isModelInstalled = isModelInstalled
    }

    var isEnabled: Bool { true }
    var isConfigured: Bool {
        if let isModelInstalled {
            return isModelInstalled()
        }
        return capabilityDownloader.isInstalled(modelID: CapabilityModelID.madladTranslation) || cache.isInstalled
    }

    func refine(_ text: String) async throws -> String {
        guard isConfigured else {
            throw ScreenshotLocalModelError.translationModelNotInstalled
        }
        let normalizedText = MADLADTranslationInputNormalizer.normalized(text)
        let chunks = MADLADTranslationInputChunker.chunks(for: normalizedText)
        var translatedChunks: [String] = []
        translatedChunks.reserveCapacity(chunks.count)
        for chunk in chunks {
            translatedChunks.append(try await engine.translate(chunk, to: "zh"))
        }
        return translatedChunks.joined(separator: "\n\n")
    }

    func refine(_ request: TextRefinementRequest) async throws -> String {
        try await refine(request.text)
    }

}

enum MADLADTranslationInputNormalizer {
    static func normalized(_ text: String) -> String {
        let lines = text.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline)
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
        let nonEmptyLines = lines.filter { !$0.isEmpty }
        guard nonEmptyLines.count >= 2 else {
            return text
        }

        if looksLikeWrappedProse(nonEmptyLines) {
            return unwrapProseLines(lines)
        }

        let shortFragmentCount = nonEmptyLines.filter { line in
            line.count <= 80 && !endsWithPhrasePunctuation(line)
        }.count
        guard Double(shortFragmentCount) / Double(nonEmptyLines.count) >= 0.6 else {
            return text
        }

        return nonEmptyLines
            .map { line in
                endsWithPhrasePunctuation(line) ? line : "\(line)."
            }
            .joined(separator: " ")
    }

    private static func looksLikeWrappedProse(_ lines: [String]) -> Bool {
        let linesWithSentencePunctuation = lines.filter { containsSentencePunctuation($0) }.count
        let longLineCount = lines.filter { $0.count >= 40 }.count
        let continuationLineCount = lines.filter { line in
            guard let last = line.last else { return false }
            return ",，:：".contains(last)
        }.count
        return linesWithSentencePunctuation > 0 ||
            longLineCount >= max(2, lines.count / 3) ||
            continuationLineCount >= 2
    }

    private static func unwrapProseLines(_ lines: [String]) -> String {
        var units: [String] = []
        var current = ""

        for index in lines.indices {
            let line = lines[index]
            guard !line.isEmpty else {
                appendCurrent(&current, to: &units)
                continue
            }

            if current.isEmpty,
               isStandaloneHeading(line, nextLine: nextNonEmptyLine(after: index, in: lines)) {
                units.append(ensureSentenceTerminal(line))
                continue
            }

            current = current.isEmpty ? line : "\(current) \(line)"
            if endsWithSentencePunctuation(line) {
                appendCurrent(&current, to: &units)
            }
        }

        appendCurrent(&current, to: &units)
        return units.joined(separator: " ")
    }

    private static func appendCurrent(_ current: inout String, to units: inout [String]) {
        let trimmed = current.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            units.append(trimmed)
        }
        current = ""
    }

    private static func nextNonEmptyLine(after index: Int, in lines: [String]) -> String? {
        guard index + 1 < lines.count else { return nil }
        return lines[(index + 1)...].first { !$0.isEmpty }
    }

    private static func isStandaloneHeading(_ line: String, nextLine: String?) -> Bool {
        guard let nextLine,
              line.count <= 48,
              nextLine.count >= 24,
              !containsSentencePunctuation(line),
              !endsWithPhrasePunctuation(line) else {
            return false
        }
        return line.split(whereSeparator: \.isWhitespace).count <= 8
    }

    private static func ensureSentenceTerminal(_ line: String) -> String {
        endsWithSentencePunctuation(line) ? line : "\(line)."
    }

    private static func containsSentencePunctuation(_ line: String) -> Bool {
        line.contains { ".!?。！？".contains($0) }
    }

    private static func endsWithSentencePunctuation(_ line: String) -> Bool {
        guard let last = line.last else { return false }
        return ".!?。！？".contains(last)
    }

    private static func endsWithPhrasePunctuation(_ line: String) -> Bool {
        guard let last = line.last else { return false }
        return ".!?。！？;；:：,，".contains(last)
    }
}

enum MADLADTranslationTokenBudget {
    static let minimum = 64
    static let maximum = 512

    static func maxTokens(for text: String) -> Int {
        let estimatedSourceTokens = max(1, estimatedSourceTokenCount(in: text))
        let budget = 32 + Int((Double(estimatedSourceTokens) * 2.5).rounded(.up))
        return min(maximum, max(minimum, budget))
    }

    static func estimatedSourceTokenCount(in text: String) -> Int {
        var count = 0
        var isInsideASCIIWord = false

        for scalar in text.unicodeScalars {
            if CharacterSet.alphanumerics.contains(scalar) || scalar == "_" {
                if !isInsideASCIIWord {
                    count += 1
                    isInsideASCIIWord = true
                }
            } else {
                isInsideASCIIWord = false
                if scalar.properties.isIdeographic {
                    count += 1
                }
            }
        }

        return count
    }
}

enum MADLADTranslationInputChunker {
    static let maxEstimatedSourceTokensPerChunk = 60

    static func chunks(for text: String) -> [String] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [trimmed] }

        let units = splitIntoUnits(trimmed)
        var chunks: [String] = []
        var current = ""

        for unit in units {
            let candidate = current.isEmpty ? unit : "\(current) \(unit)"
            if !current.isEmpty,
               MADLADTranslationTokenBudget.estimatedSourceTokenCount(in: candidate) > maxEstimatedSourceTokensPerChunk {
                chunks.append(current)
                current = unit
            } else if MADLADTranslationTokenBudget.estimatedSourceTokenCount(in: unit) > maxEstimatedSourceTokensPerChunk {
                if !current.isEmpty {
                    chunks.append(current)
                    current = ""
                }
                chunks.append(contentsOf: splitOversizedUnit(unit))
            } else {
                current = candidate
            }
        }

        if !current.isEmpty {
            chunks.append(current)
        }
        return chunks.isEmpty ? [trimmed] : chunks
    }

    private static func splitIntoUnits(_ text: String) -> [String] {
        let pattern = #"(?<=[.!?。！？])\s+"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [text] }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        var units: [String] = []
        var lowerBound = text.startIndex

        for match in regex.matches(in: text, range: range) {
            guard let separatorRange = Range(match.range, in: text) else { continue }
            let unit = text[lowerBound..<separatorRange.lowerBound]
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !unit.isEmpty {
                units.append(unit)
            }
            lowerBound = separatorRange.upperBound
        }

        let tail = text[lowerBound..<text.endIndex]
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if !tail.isEmpty {
            units.append(tail)
        }
        return units.isEmpty ? [text] : units
    }

    private static func splitOversizedUnit(_ unit: String) -> [String] {
        let words = unit.split(separator: " ").map(String.init)
        guard words.count > 1 else { return [unit] }

        var chunks: [String] = []
        var current = ""
        for word in words {
            let candidate = current.isEmpty ? word : "\(current) \(word)"
            if !current.isEmpty,
               MADLADTranslationTokenBudget.estimatedSourceTokenCount(in: candidate) > maxEstimatedSourceTokensPerChunk {
                chunks.append(current)
                current = word
            } else {
                current = candidate
            }
        }
        if !current.isEmpty {
            chunks.append(current)
        }
        return chunks
    }
}

final class AppleSystemTranslationRefiner: PromptAwareTextRefining, @unchecked Sendable {
    var isEnabled: Bool { isConfigured }

    var isConfigured: Bool {
        return false
    }

    func refine(_ text: String) async throws -> String {
        throw AppleSystemTranslationError.unavailableOnCurrentSystem
    }

    func refine(_ request: TextRefinementRequest) async throws -> String {
        try await refine(request.text)
    }
}

private enum AppleSystemTranslationError: LocalizedError {
    case unavailableOnCurrentSystem

    var errorDescription: String? {
        switch self {
        case .unavailableOnCurrentSystem:
            return "Apple 系统翻译在当前系统版本不可用，请使用已配置的 LLM 或安装本地翻译模型"
        }
    }
}

actor SoniqoMADLADTranslationEngine: SoniqoMADLADTranslating {
    private var translator: MADLADTranslator?

    func translate(_ text: String, to targetLanguage: String) async throws -> String {
        let model = try await loadTranslator()
        return try model.translate(
            text,
            to: targetLanguage,
            sampling: TranslationSamplingConfig(maxTokens: MADLADTranslationTokenBudget.maxTokens(for: text))
        )
    }

    private func loadTranslator() async throws -> MADLADTranslator {
        if let translator {
            return translator
        }
        let loaded = try await MADLADTranslator.fromPretrained(quantization: .int4, offlineMode: true)
        translator = loaded
        return loaded
    }
}

final class SoniqoQwen35SummaryRefiner: PromptAwareTextRefining, @unchecked Sendable {
    private let engine: SoniqoQwen35SummaryEngine
    private let cache: SoniqoLocalModelCache

    init(
        engine: SoniqoQwen35SummaryEngine = SoniqoQwen35SummaryEngine(),
        cache: SoniqoLocalModelCache = SoniqoLocalModelCache(
            modelId: Qwen35MLXChat.defaultModelId,
            variant: Qwen35MLXChat.Quantization.int4.rawValue
        )
    ) {
        self.engine = engine
        self.cache = cache
    }

    var isEnabled: Bool { true }
    var isConfigured: Bool { cache.isInstalled }

    func refine(_ text: String) async throws -> String {
        try await refine(
            TextRefinementRequest(
                text: text,
                systemPrompt: ScreenshotOCRService.summarySystemPrompt,
                model: nil,
                temperature: nil
            )
        )
    }

    func refine(_ request: TextRefinementRequest) async throws -> String {
        guard isConfigured else {
            throw ScreenshotLocalModelError.summaryModelNotInstalled
        }
        return try await engine.summarize(text: request.text, systemPrompt: request.systemPrompt)
    }
}

actor SoniqoQwen35SummaryEngine {
    private var chat: Qwen35MLXChat?

    func summarize(text: String, systemPrompt: String) async throws -> String {
        let model = try await loadChat()
        return try model.generate(
            messages: [
                ChatMessage(role: .system, content: systemPrompt),
                ChatMessage(role: .user, content: text),
            ],
            sampling: ChatSamplingConfig(
                temperature: 0.2,
                topK: 20,
                topP: 0.8,
                maxTokens: 180,
                repetitionPenalty: 1.1
            )
        )
    }

    private func loadChat() async throws -> Qwen35MLXChat {
        if let chat {
            return chat
        }
        let loaded = try await Qwen35MLXChat.fromPretrained(quantization: .int4, offlineMode: true)
        chat = loaded
        return loaded
    }
}
