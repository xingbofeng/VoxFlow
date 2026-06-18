import Foundation
import VoxFlowASRCore
import VoxFlowAudio

struct ASRSmokeRunner {
    func run(
        sample: ASRSmokeSample,
        provider: any ASRProvider,
        audioFrames: [AudioFrame]? = nil
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

        let session = try await provider.makeSession(language: language)
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
            let frames = try audioFrames ?? ASRSmokeAudio.loadFrames(for: sample)
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
