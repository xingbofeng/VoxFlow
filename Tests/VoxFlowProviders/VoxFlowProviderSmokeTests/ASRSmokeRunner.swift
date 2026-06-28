import Foundation
import VoxFlowASRCore
import VoxFlowAudio

struct ASRSmokeRunner {
    func run(
        sample: ASRSmokeSample,
        provider: any ASRProvider,
        audioFrames: [AudioFrame]? = nil,
        prompt: String? = nil
    ) async throws -> ASRSmokeResult {
        guard provider.descriptor.modelInstallationState.isReady else {
            return ASRSmokeResult(
                sampleID: sample.id,
                providerID: provider.descriptor.id.rawValue,
                outcome: .skipped,
                sawPartial: false,
                sawFinal: false,
                finalText: "",
                finalLatencyMilliseconds: nil,
                issues: [.providerNotReady]
            )
        }

        let language = ASRLanguageCapability(bcp47Tag: sample.language)
        guard provider.descriptor.supportedLanguages.contains(language) else {
            return ASRSmokeResult(
                sampleID: sample.id,
                providerID: provider.descriptor.id.rawValue,
                outcome: .skipped,
                sawPartial: false,
                sawFinal: false,
                finalText: "",
                finalLatencyMilliseconds: nil,
                issues: [.unsupportedLanguage]
            )
        }

        let frames = try audioFrames ?? ASRSmokeAudio.loadFrames(for: sample)
        let previousCurrentDirectory = FileManager.default.currentDirectoryPath
        if let metallibDirectory = try Self.prepareMLXMetallibIfNeeded(providerID: provider.descriptor.id) {
            FileManager.default.changeCurrentDirectoryPath(metallibDirectory.path)
        }
        defer {
            FileManager.default.changeCurrentDirectoryPath(previousCurrentDirectory)
        }
        let session = try await provider.makeSession(language: language)
        try await session.configurePrompt(prompt)
        let collector = Task { () -> [ASREvent] in
            var events: [ASREvent] = []
            for await event in session.events {
                events.append(event)
            }
            return events
        }

        let start = ContinuousClock.now
        do {
            try await session.start()
            for frame in frames {
                try await session.accept(frame)
            }
        } catch {
            await session.cancel()
            throw error
        }

        do {
            try await session.finish()
        } catch {
            // Provider sessions often report ASR-domain failures by yielding a
            // failure event and throwing. The smoke runner should preserve that
            // structured result instead of aborting the whole corpus.
        }

        let events = try await withTimeout(milliseconds: sample.maxFinalLatencyMilliseconds) {
            await collector.value
        }
        let latency = start.duration(to: ContinuousClock.now)
        return analyze(
            events: events,
            sample: sample,
            provider: provider,
            finalLatencyMilliseconds: latency.milliseconds
        )
    }

    private func analyze(
        events: [ASREvent],
        sample: ASRSmokeSample,
        provider: any ASRProvider,
        finalLatencyMilliseconds: Int
    ) -> ASRSmokeResult {
        let partials = events.compactMap { event -> String? in
            guard case let .partial(_, transcript) = event else {
                return nil
            }
            return transcript.stablePrefix + transcript.unstableSuffix
        }
        let finalText = events.compactMap { event -> String? in
            guard case let .final(_, _, text) = event else {
                return nil
            }
            return text
        }.last ?? ""
        let failureCategories = events.compactMap { event -> ASRErrorCategory? in
            guard case let .failure(_, _, error) = event else {
                return nil
            }
            return error.category
        }

        var issues: [ASRSmokeIssue] = []
        if sample.requiresPartialWhenStreaming,
           requiresPartial(provider.descriptor.streamingSemantics),
           partials.isEmpty,
           sample.expectsSpeech {
            issues.append(.missingPartial)
        }
        if sample.expectsSpeech, finalText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            issues.append(.emptyFinal)
        }
        if !sample.expectsSpeech, !sample.allowsEmptyFinal, finalText.isEmpty {
            issues.append(.emptyFinal)
        }
        if !sample.expectsSpeech,
           !finalText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            issues.append(.unexpectedSpeechOnSilence)
        }
        if hasObviousDuplication(finalText) {
            issues.append(.obviousDuplication)
        }
        if finalLatencyMilliseconds > sample.maxFinalLatencyMilliseconds {
            issues.append(.finalTimedOut)
        }

        if sample.allowsEmptyFinal,
           finalText.isEmpty,
           failureCategories.allSatisfy({ $0 == .emptyTranscript || $0 == .finalTimeout }) {
            issues.removeAll { $0 == .emptyFinal }
        }

        return ASRSmokeResult(
            sampleID: sample.id,
            providerID: provider.descriptor.id.rawValue,
            outcome: issues.isEmpty ? .passed : .failed,
            sawPartial: !partials.isEmpty,
            sawFinal: !finalText.isEmpty,
            finalText: finalText,
            finalLatencyMilliseconds: finalLatencyMilliseconds,
            issues: issues
        )
    }

    private func requiresPartial(_ semantics: ASRStreamingSemantics) -> Bool {
        switch semantics {
        case .systemStreaming, .nativeStreaming, .chunkedStablePrefix, .companionPartialFinal:
            return true
        case .rollingWindowConfirmedSegments, .offlineFinalOnly:
            return false
        }
    }

    private func hasObviousDuplication(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 8 else {
            return false
        }
        let characters = Array(trimmed)
        let window = min(6, characters.count / 2)
        guard window >= 2 else {
            return false
        }
        for index in 0...(characters.count - window * 2) {
            let first = characters[index..<(index + window)]
            let second = characters[(index + window)..<(index + window * 2)]
            if Array(first) == Array(second) {
                return true
            }
        }
        return false
    }

    private func withTimeout<T: Sendable>(
        milliseconds: Int,
        operation: @escaping @Sendable () async -> T
    ) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask {
                await operation()
            }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(milliseconds) * 1_000_000)
                throw ASRSmokeTimeoutError()
            }
            let value = try await group.next()!
            group.cancelAll()
            return value
        }
    }

    @discardableResult
    static func prepareMLXMetallibIfNeeded(
        providerID: ASRProviderID,
        binaryDirectory: URL = Self.currentBinaryDirectory(),
        fileManager: FileManager = .default
    ) throws -> URL? {
        guard providerNeedsMLXMetallib(providerID) else {
            return nil
        }
        let colocatedMLX = binaryDirectory.appendingPathComponent("mlx.metallib")
        let colocatedDefault = binaryDirectory.appendingPathComponent("default.metallib")
        if fileManager.fileExists(atPath: colocatedMLX.path),
           fileManager.fileExists(atPath: colocatedDefault.path) {
            return binaryDirectory
        }
        guard let source = nearestMetallibSource(from: binaryDirectory, fileManager: fileManager) else {
            return nil
        }
        try fileManager.copyReplacingItem(at: source, to: colocatedMLX)
        try fileManager.copyReplacingItem(at: source, to: colocatedDefault)
        return binaryDirectory
    }

    private static func providerNeedsMLXMetallib(_ providerID: ASRProviderID) -> Bool {
        let rawValue = providerID.rawValue.lowercased()
        return rawValue.contains("qwen3") || rawValue.contains("nvidia")
    }

    private static func currentBinaryDirectory() -> URL {
        if let testBundle = Bundle.allBundles.first(where: { $0.bundleURL.pathExtension == "xctest" }),
           let executableURL = testBundle.executableURL {
            return executableURL.deletingLastPathComponent()
        }
        return (Bundle.main.executableURL ?? URL(fileURLWithPath: CommandLine.arguments[0]))
            .deletingLastPathComponent()
    }

    private static func nearestMetallibSource(
        from binaryDirectory: URL,
        fileManager: FileManager
    ) -> URL? {
        var directory = binaryDirectory
        for _ in 0..<8 {
            for name in ["mlx.metallib", "default.metallib"] {
                let candidate = directory.appendingPathComponent(name)
                if fileManager.fileExists(atPath: candidate.path) {
                    return candidate
                }
            }
            let parent = directory.deletingLastPathComponent()
            guard parent.path != directory.path else {
                return nil
            }
            directory = parent
        }
        return findBuildMetallib(fileManager: fileManager)
    }

    private static func findBuildMetallib(fileManager: FileManager) -> URL? {
        let buildDirectory = URL(fileURLWithPath: fileManager.currentDirectoryPath)
            .appendingPathComponent(".build", isDirectory: true)
        guard let enumerator = fileManager.enumerator(
            at: buildDirectory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return nil
        }
        for case let url as URL in enumerator {
            guard url.lastPathComponent == "mlx.metallib" else {
                continue
            }
            if url.path.contains("/debug/") {
                return url
            }
        }
        return nil
    }
}

private extension FileManager {
    func copyReplacingItem(at source: URL, to destination: URL) throws {
        if fileExists(atPath: destination.path) {
            try removeItem(at: destination)
        }
        try copyItem(at: source, to: destination)
    }
}

struct ASRSmokeResult: Equatable, Sendable {
    let sampleID: String
    let providerID: String
    let outcome: ASRSmokeOutcome
    let sawPartial: Bool
    let sawFinal: Bool
    let finalText: String
    let finalLatencyMilliseconds: Int?
    let issues: [ASRSmokeIssue]
}

enum ASRSmokeOutcome: String, Equatable, Sendable {
    case passed = "PASS"
    case failed = "FAIL"
    case skipped = "SKIPPED"
}

enum ASRSmokeIssue: String, Equatable, Sendable {
    case providerNotReady = "provider_not_ready"
    case unsupportedLanguage = "unsupported_language"
    case missingPartial = "missing_partial"
    case emptyFinal = "empty_final"
    case unexpectedSpeechOnSilence = "unexpected_speech_on_silence"
    case obviousDuplication = "obvious_duplication"
    case finalTimedOut = "final_timed_out"
}

private struct ASRSmokeTimeoutError: Error {}

private extension Duration {
    var milliseconds: Int {
        let components = components
        let seconds = components.seconds * 1_000
        let attoseconds = components.attoseconds / 1_000_000_000_000_000
        return Int(seconds + attoseconds)
    }
}
