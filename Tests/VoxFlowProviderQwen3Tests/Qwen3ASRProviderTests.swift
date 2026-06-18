import VoxFlowASRCore
import VoxFlowAudio
@testable import VoxFlowProviderQwen3
import XCTest

final class Qwen3ASRProviderTests: XCTestCase {
    func testDescriptorKeepsCoreMLNativeStreamingAndMarksMLXAsCompanionPartialFinal() {
        XCTAssertEqual(
            Qwen3ProviderDescriptor.descriptor(
                modelInstallationState: .ready,
                variant: .qwen06CoreMLInt8
            ).streamingSemantics,
            .nativeStreaming
        )
        XCTAssertEqual(
            Qwen3ProviderDescriptor.descriptor(
                modelInstallationState: .ready,
                variant: .qwen17MLX4Bit
            ).streamingSemantics,
            .companionPartialFinal
        )
    }

    func testDescriptorUsesQwen3ASRCoreContract() {
        let descriptor = Qwen3ProviderDescriptor.descriptor(modelInstallationState: .notInstalled)

        XCTAssertEqual(descriptor.id, ASRProviderID(rawValue: "qwen3_asr"))
        XCTAssertEqual(descriptor.displayName, "Qwen3-ASR")
        XCTAssertEqual(descriptor.modelInstallationState, .notInstalled)
        XCTAssertEqual(descriptor.supportedLanguages.map(\.bcp47Tag), ["zh-CN", "zh-TW", "en-US", "ja-JP", "ko-KR"])
        XCTAssertEqual(descriptor.streamingSemantics, .nativeStreaming)
    }

    func testReadyProviderCreatesASRCoreSessionAndPassesLanguage() async throws {
        let factory = CapturingQwen3StreamingSessionFactory(
            session: CapturingQwen3StreamingSession(
                partial: Qwen3StreamingUpdate(transcript: "实时", isFinal: false),
                final: Qwen3StreamingUpdate(transcript: "最终", isFinal: true)
            )
        )
        let modelURL = URL(fileURLWithPath: "/tmp/qwen3-ready", isDirectory: true)
        let provider = Qwen3ASRProvider(
            descriptor: Qwen3ProviderDescriptor.descriptor(modelInstallationState: .ready),
            modelURL: modelURL,
            sessionFactory: factory
        )

        let session = try await provider.makeSession(language: ASRLanguageCapability(bcp47Tag: "en-US"))
        let collector = Task {
            var events: [ASREvent] = []
            for await event in session.events {
                events.append(event)
            }
            return events
        }

        try await session.start()
        try await session.accept(Self.frame(sequenceNumber: 9))
        try await session.finish()

        let events = await collector.value
        XCTAssertEqual(factory.modelURLs, [modelURL])
        XCTAssertEqual(factory.languageHints, ["en"])
        XCTAssertEqual(events[0], .preparing(sessionID: session.sessionID, revision: 0))
        XCTAssertEqual(events[1], .ready(sessionID: session.sessionID, revision: 1))
        XCTAssertEqual(events[2], .speechStarted(sessionID: session.sessionID, revision: 2, sequenceNumber: 9))
        XCTAssertEqual(
            events[3],
            .partial(
                sessionID: session.sessionID,
                transcript: PartialTranscript(
                    stablePrefix: "",
                    unstableSuffix: "实时",
                    revision: 3,
                    audioDuration: .milliseconds(2_000)
                )
            )
        )
        XCTAssertEqual(events[4], .final(sessionID: session.sessionID, revision: 4, text: "最终"))
    }

    func testUnknownLanguageCreatesSessionWithAutoLanguageHint() async throws {
        let factory = CapturingQwen3StreamingSessionFactory(
            session: CapturingQwen3StreamingSession(
                partial: Qwen3StreamingUpdate(transcript: "リアルタイム", isFinal: false),
                final: Qwen3StreamingUpdate(transcript: "最終テキスト", isFinal: true)
            )
        )
        let provider = Qwen3ASRProvider(
            descriptor: Qwen3ProviderDescriptor.descriptor(modelInstallationState: .ready),
            modelURL: URL(fileURLWithPath: "/tmp/qwen3-ready", isDirectory: true),
            sessionFactory: factory
        )

        let session = try await provider.makeSession(language: ASRLanguageCapability(bcp47Tag: "ja-JP"))
        try await session.start()
        await session.cancel()

        XCTAssertEqual(factory.modelURLs, [URL(fileURLWithPath: "/tmp/qwen3-ready", isDirectory: true)])
        XCTAssertEqual(factory.languageHints.count, 1)
        XCTAssertNil(factory.languageHints[0])
    }

    func testASRCoreSessionFlushesTailAfterStreamingFinal() async throws {
        let runtime = CapturingQwen3StreamingSession(
            partial: Qwen3StreamingUpdate(transcript: "流式最终文本", isFinal: true),
            final: Qwen3StreamingUpdate(transcript: "尾部刷新后的最终文本", isFinal: true)
        )
        let provider = Qwen3ASRProvider(
            descriptor: Qwen3ProviderDescriptor.descriptor(modelInstallationState: .ready),
            modelURL: URL(fileURLWithPath: "/tmp/qwen3-ready", isDirectory: true),
            sessionFactory: CapturingQwen3StreamingSessionFactory(session: runtime)
        )

        let session = try await provider.makeSession(language: ASRLanguageCapability(bcp47Tag: "zh-CN"))
        let collector = Task {
            var events: [ASREvent] = []
            for await event in session.events {
                events.append(event)
            }
            return events
        }

        try await session.start()
        try await session.accept(Self.frame(sequenceNumber: 11))
        try await session.finish()

        let events = await collector.value
        let finishCount = await runtime.finishCallCount()
        XCTAssertEqual(finishCount, 1)
        XCTAssertTrue(
            events.contains { event in
                guard case let .final(sessionID, _, text) = event else { return false }
                return sessionID == session.sessionID && text == "尾部刷新后的最终文本"
            },
            "ASRCore session must publish the tail-flushed final instead of closing on the streaming-final update."
        )
    }

    func testASRCoreSessionEmitsFinalTimeoutWhenFinishStalls() async throws {
        let runtime = DelayedFinishQwen3StreamingSession(
            partial: nil,
            final: Qwen3StreamingUpdate(transcript: "迟到的最终文本", isFinal: true)
        )
        let provider = Qwen3ASRProvider(
            descriptor: Self.descriptor(timeoutPolicy: ASRTimeoutPolicy(
                preparationTimeout: .seconds(1),
                firstPartialTimeout: .seconds(1),
                streamStallTimeout: .seconds(1),
                finalBaseTimeout: .milliseconds(50),
                finalPerAudioSecondTimeout: .zero,
                workerHeartbeatTimeout: .seconds(1),
                initialModelCompilationTimeout: .seconds(1)
            )),
            modelURL: URL(fileURLWithPath: "/tmp/qwen3-ready", isDirectory: true),
            sessionFactory: CapturingQwen3StreamingSessionFactory(session: runtime)
        )

        let session = try await provider.makeSession(language: ASRLanguageCapability(bcp47Tag: "zh-CN"))
        let recorder = ASREventRecorder()
        let collector = Task {
            for await event in session.events {
                await recorder.append(event)
            }
        }

        try await session.start()
        try await session.accept(Self.frame(sequenceNumber: 12))
        let finishTask = Task {
            try await session.finish()
        }

        let receivedTimeout = await waitUntil(timeout: 1.0) {
            await recorder.firstFailure()?.category == .finalTimeout
        }
        await runtime.releaseDelayedFinish()
        _ = try? await finishTask.value
        collector.cancel()

        XCTAssertTrue(receivedTimeout)
        let failure = await recorder.firstFailure()
        XCTAssertEqual(failure?.category, .finalTimeout)
    }

    func testASRCoreSessionKeepsStablePrefixAcrossWholeReplacementPartials() async throws {
        let runtime = SequencedQwen3StreamingSession(
            partials: [
                Qwen3StreamingUpdate(transcript: "今天我想打开", isFinal: false),
                Qwen3StreamingUpdate(transcript: "明天你需要关闭", isFinal: false),
            ],
            final: Qwen3StreamingUpdate(transcript: "今天我想打开设置", isFinal: true)
        )
        let provider = Qwen3ASRProvider(
            descriptor: Qwen3ProviderDescriptor.descriptor(modelInstallationState: .ready),
            modelURL: URL(fileURLWithPath: "/tmp/qwen3-ready", isDirectory: true),
            sessionFactory: CapturingQwen3StreamingSessionFactory(session: runtime)
        )

        let session = try await provider.makeSession(language: ASRLanguageCapability(bcp47Tag: "zh-CN"))
        let collector = Task {
            var events: [ASREvent] = []
            for await event in session.events {
                events.append(event)
            }
            return events
        }

        try await session.start()
        try await session.accept(Self.frame(sequenceNumber: 21))
        try await session.accept(Self.frame(sequenceNumber: 22))
        try await session.finish()

        let events = await collector.value
        let partials = events.compactMap { event -> PartialTranscript? in
            guard case let .partial(_, transcript) = event else { return nil }
            return transcript
        }
        XCTAssertGreaterThanOrEqual(partials.count, 2)
        XCTAssertEqual(partials[0].stablePrefix, "")
        XCTAssertEqual(partials[0].unstableSuffix, "今天我想打开")
        XCTAssertEqual(partials[1].stablePrefix, "今天我想打开")
        XCTAssertEqual(partials[1].unstableSuffix, "明天你需要关闭")
        XCTAssertTrue(
            (partials[1].stablePrefix + partials[1].unstableSuffix)
                .hasPrefix(partials[0].stablePrefix + partials[0].unstableSuffix),
            "A later Qwen partial must not rewrite text that has already been emitted as the stable prefix."
        )
    }

    func testASRCoreSessionAllowsPunctuationPausePartialRevisionWithoutRepeatingText() async throws {
        let runtime = SequencedQwen3StreamingSession(
            partials: [
                Qwen3StreamingUpdate(transcript: "我不知道你这个问题是。", isFinal: false),
                Qwen3StreamingUpdate(transcript: "我不知道你这个问题是什么。", isFinal: false),
            ],
            final: Qwen3StreamingUpdate(transcript: "我不知道你这个问题是什么。", isFinal: true)
        )
        let provider = Qwen3ASRProvider(
            descriptor: Qwen3ProviderDescriptor.descriptor(modelInstallationState: .ready),
            modelURL: URL(fileURLWithPath: "/tmp/qwen3-ready", isDirectory: true),
            sessionFactory: CapturingQwen3StreamingSessionFactory(session: runtime)
        )

        let session = try await provider.makeSession(language: ASRLanguageCapability(bcp47Tag: "zh-CN"))
        let collector = Task {
            var events: [ASREvent] = []
            for await event in session.events {
                events.append(event)
            }
            return events
        }

        try await session.start()
        try await session.accept(Self.frame(sequenceNumber: 24))
        try await session.accept(Self.frame(sequenceNumber: 25))
        try await session.finish()

        let events = await collector.value
        let partialTexts = events.compactMap { event -> String? in
            guard case let .partial(_, transcript) = event else { return nil }
            return transcript.stablePrefix + transcript.unstableSuffix
        }
        XCTAssertEqual(partialTexts, [
            "我不知道你这个问题是。",
            "我不知道你这个问题是什么。",
        ])
        let finalText = events.compactMap { event -> String? in
            guard case let .final(_, _, text) = event else { return nil }
            return text
        }.last
        XCTAssertEqual(finalText, "我不知道你这个问题是什么。")
    }

    func testASRCoreSessionReplacesSimilarWholeUtterancePartialsInsteadOfAppendingDuplicates() async throws {
        let runtime = SequencedQwen3StreamingSession(
            partials: [
                Qwen3StreamingUpdate(transcript: "啸哭的声音。", isFinal: false),
                Qwen3StreamingUpdate(transcript: "海枯的声音。", isFinal: false),
                Qwen3StreamingUpdate(transcript: "海枯的声音。", isFinal: false),
            ],
            final: Qwen3StreamingUpdate(transcript: "海枯的声音。", isFinal: true)
        )
        let provider = Qwen3ASRProvider(
            descriptor: Qwen3ProviderDescriptor.descriptor(modelInstallationState: .ready),
            modelURL: URL(fileURLWithPath: "/tmp/qwen3-ready", isDirectory: true),
            sessionFactory: CapturingQwen3StreamingSessionFactory(session: runtime)
        )

        let session = try await provider.makeSession(language: ASRLanguageCapability(bcp47Tag: "zh-CN"))
        let collector = Task {
            var events: [ASREvent] = []
            for await event in session.events {
                events.append(event)
            }
            return events
        }

        try await session.start()
        try await session.accept(Self.frame(sequenceNumber: 26))
        try await session.accept(Self.frame(sequenceNumber: 27))
        try await session.accept(Self.frame(sequenceNumber: 28))
        try await session.finish()

        let events = await collector.value
        let partialTexts = events.compactMap { event -> String? in
            guard case let .partial(_, transcript) = event else { return nil }
            return transcript.stablePrefix + transcript.unstableSuffix
        }
        XCTAssertEqual(partialTexts, [
            "啸哭的声音。",
            "海枯的声音。",
            "海枯的声音。",
        ])
    }

    func testASRCoreSessionFailsEmptyFinalInsteadOfPublishingEmptyFinalText() async throws {
        let runtime = CapturingQwen3StreamingSession(
            partial: nil,
            final: Qwen3StreamingUpdate(transcript: " \n ", isFinal: true)
        )
        let provider = Qwen3ASRProvider(
            descriptor: Qwen3ProviderDescriptor.descriptor(modelInstallationState: .ready),
            modelURL: URL(fileURLWithPath: "/tmp/qwen3-ready", isDirectory: true),
            sessionFactory: CapturingQwen3StreamingSessionFactory(session: runtime)
        )

        let session = try await provider.makeSession(language: ASRLanguageCapability(bcp47Tag: "zh-CN"))
        let collector = Task {
            var events: [ASREvent] = []
            for await event in session.events {
                events.append(event)
            }
            return events
        }

        try await session.start()
        try await session.accept(Self.frame(sequenceNumber: 23))
        do {
            try await session.finish()
        } catch {
        }

        let events = await collector.value
        XCTAssertFalse(
            events.contains { event in
                guard case let .final(_, _, text) = event else { return false }
                return text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            },
            "Qwen ASRCore session must not publish a successful final event for empty transcript text."
        )
        let failure = events.compactMap { event -> ASRError? in
            guard case let .failure(_, _, error) = event else { return nil }
            return error
        }.first
        XCTAssertEqual(failure?.category, .emptyTranscript)
    }

    func testASRCoreSessionPublishesRuntimeFinalWithoutStitchingCommittedPartialPrefix() async throws {
        let runtime = SequencedQwen3StreamingSession(
            partials: [
                Qwen3StreamingUpdate(transcript: "第一段已经确认", isFinal: false),
                Qwen3StreamingUpdate(transcript: "第二段正在继续", isFinal: false),
                Qwen3StreamingUpdate(transcript: "第三段接近结束", isFinal: false),
            ],
            final: Qwen3StreamingUpdate(transcript: "第三段接近结束", isFinal: true)
        )
        let provider = Qwen3ASRProvider(
            descriptor: Qwen3ProviderDescriptor.descriptor(modelInstallationState: .ready),
            modelURL: URL(fileURLWithPath: "/tmp/qwen3-ready", isDirectory: true),
            sessionFactory: CapturingQwen3StreamingSessionFactory(session: runtime)
        )

        let session = try await provider.makeSession(language: ASRLanguageCapability(bcp47Tag: "zh-CN"))
        let collector = Task {
            var events: [ASREvent] = []
            for await event in session.events {
                events.append(event)
            }
            return events
        }

        try await session.start()
        try await session.accept(Self.frame(sequenceNumber: 31))
        try await session.accept(Self.frame(sequenceNumber: 32))
        try await session.accept(Self.frame(sequenceNumber: 33))
        try await session.finish()

        let events = await collector.value
        let finalText = events.compactMap { event -> String? in
            guard case let .final(_, _, text) = event else { return nil }
            return text
        }.last
        XCTAssertEqual(finalText, "第三段接近结束")
    }

    func testASRCoreSessionDoesNotPrependRepeatedPartialWhenRuntimeFinalRevisesTheUtterance() async throws {
        let runtime = SequencedQwen3StreamingSession(
            partials: [
                Qwen3StreamingUpdate(transcript: "输入设备和识别仪。", isFinal: false),
                Qwen3StreamingUpdate(transcript: "输入设备和识别仪。", isFinal: false),
            ],
            final: Qwen3StreamingUpdate(transcript: "输入设备和识别语言要挨着。", isFinal: true)
        )
        let provider = Qwen3ASRProvider(
            descriptor: Qwen3ProviderDescriptor.descriptor(modelInstallationState: .ready),
            modelURL: URL(fileURLWithPath: "/tmp/qwen3-ready", isDirectory: true),
            sessionFactory: CapturingQwen3StreamingSessionFactory(session: runtime)
        )

        let session = try await provider.makeSession(language: ASRLanguageCapability(bcp47Tag: "zh-CN"))
        let collector = Task {
            var events: [ASREvent] = []
            for await event in session.events {
                events.append(event)
            }
            return events
        }

        try await session.start()
        try await session.accept(Self.frame(sequenceNumber: 41))
        try await session.accept(Self.frame(sequenceNumber: 42))
        try await session.finish()

        let events = await collector.value
        let finalText = events.compactMap { event -> String? in
            guard case let .final(_, _, text) = event else { return nil }
            return text
        }.last
        XCTAssertEqual(finalText, "输入设备和识别语言要挨着。")
    }

    func testLifecycleNotReadyRejectsSessionWithoutCreatingRuntime() async {
        let factory = CapturingQwen3StreamingSessionFactory(session: CapturingQwen3StreamingSession())
        let provider = Qwen3ASRProvider(
            descriptor: Qwen3ProviderDescriptor.descriptor(modelInstallationState: .notInstalled),
            modelURL: URL(fileURLWithPath: "/tmp/qwen3-missing", isDirectory: true),
            sessionFactory: factory
        )

        await XCTAssertThrowsErrorAsync(
            try await provider.makeSession(language: ASRLanguageCapability(bcp47Tag: "zh-CN"))
        ) { error in
            XCTAssertEqual(error as? Qwen3ProviderError, .modelNotInstalled)
        }
        XCTAssertTrue(factory.modelURLs.isEmpty)
    }

    func testRuntimeUnsupportedRejectsQwen17Session() async {
        let factory = CapturingQwen3StreamingSessionFactory(session: CapturingQwen3StreamingSession())
        let reason = "Qwen3-ASR 1.7B 需要 MLX 本地 worker：voxflow-qwen3-mlx-worker。"
        let provider = Qwen3ASRProvider(
            descriptor: Qwen3ProviderDescriptor.descriptor(
                modelInstallationState: .runtimeUnsupported(reason: reason)
            ),
            modelURL: URL(fileURLWithPath: "/tmp/qwen3-17", isDirectory: true),
            sessionFactory: factory
        )

        await XCTAssertThrowsErrorAsync(
            try await provider.makeSession(language: ASRLanguageCapability(bcp47Tag: "zh-CN"))
        ) { error in
            XCTAssertEqual(error as? Qwen3ProviderError, .runtimeUnsupported(reason))
        }
        XCTAssertTrue(factory.modelURLs.isEmpty)
    }

    private static func descriptor(
        timeoutPolicy: ASRTimeoutPolicy = .standard
    ) -> ASRProviderDescriptor {
        ASRProviderDescriptor(
            id: ASRProviderID(rawValue: "qwen3_asr"),
            displayName: "Qwen3-ASR",
            modelInstallationState: .ready,
            supportedLanguages: [
                ASRLanguageCapability(bcp47Tag: "zh-CN"),
                ASRLanguageCapability(bcp47Tag: "en-US"),
            ],
            streamingSemantics: .nativeStreaming,
            timeoutPolicy: timeoutPolicy
        )
    }

    private static func frame(sequenceNumber: UInt64) -> AudioFrame {
        AudioFrame(
            sequenceNumber: sequenceNumber,
            startSample: 0,
            samples: ContiguousArray(repeating: 0.1, count: 32_000),
            sampleRate: 16_000,
            capturedAt: ContinuousClock.now
        )
    }
}

private final class CapturingQwen3StreamingSessionFactory: Qwen3StreamingSessionMaking, @unchecked Sendable {
    let session: any Qwen3StreamingSession
    private(set) var modelURLs: [URL] = []
    private(set) var languageHints: [String?] = []

    init(session: any Qwen3StreamingSession) {
        self.session = session
    }

    func makeSession(modelURL: URL, languageHint: String?) async throws -> any Qwen3StreamingSession {
        modelURLs.append(modelURL)
        languageHints.append(languageHint)
        return session
    }
}

private actor ASREventRecorder {
    private var events: [ASREvent] = []

    func append(_ event: ASREvent) {
        events.append(event)
    }

    func firstFailure() -> ASRError? {
        for event in events {
            if case let .failure(_, _, error) = event {
                return error
            }
        }
        return nil
    }
}

private actor CapturingQwen3StreamingSession: Qwen3StreamingSession {
    let partial: Qwen3StreamingUpdate?
    let final: Qwen3StreamingUpdate
    private(set) var acceptedSamples: [[Float]] = []
    private(set) var finishCount = 0

    init(
        partial: Qwen3StreamingUpdate? = nil,
        final: Qwen3StreamingUpdate = Qwen3StreamingUpdate(transcript: "", isFinal: true)
    ) {
        self.partial = partial
        self.final = final
    }

    func addAudio(_ samples: [Float]) async throws -> Qwen3StreamingUpdate? {
        acceptedSamples.append(samples)
        return partial
    }

    func finish() async throws -> Qwen3StreamingUpdate {
        finishCount += 1
        return final
    }

    func finishCallCount() -> Int {
        finishCount
    }

    func cancel() async {}
}

private actor SequencedQwen3StreamingSession: Qwen3StreamingSession {
    private var partials: [Qwen3StreamingUpdate]
    let final: Qwen3StreamingUpdate

    init(partials: [Qwen3StreamingUpdate], final: Qwen3StreamingUpdate) {
        self.partials = partials
        self.final = final
    }

    func addAudio(_ samples: [Float]) async throws -> Qwen3StreamingUpdate? {
        guard !partials.isEmpty else { return nil }
        return partials.removeFirst()
    }

    func finish() async throws -> Qwen3StreamingUpdate {
        final
    }

    func cancel() async {}
}

private actor DelayedFinishQwen3StreamingSession: Qwen3StreamingSession {
    let partial: Qwen3StreamingUpdate?
    let final: Qwen3StreamingUpdate
    private var isReleased = false
    private var continuations: [CheckedContinuation<Void, Never>] = []

    init(partial: Qwen3StreamingUpdate?, final: Qwen3StreamingUpdate) {
        self.partial = partial
        self.final = final
    }

    func addAudio(_ samples: [Float]) async throws -> Qwen3StreamingUpdate? {
        partial
    }

    func finish() async throws -> Qwen3StreamingUpdate {
        if !isReleased {
            await withCheckedContinuation { continuation in
                continuations.append(continuation)
            }
        }
        return final
    }

    func cancel() async {}

    func releaseDelayedFinish() {
        isReleased = true
        let pending = continuations
        continuations.removeAll()
        pending.forEach { $0.resume() }
    }
}

private func waitUntil(
    timeout: TimeInterval,
    condition: @escaping () async -> Bool
) async -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
        if await condition() {
            return true
        }
        try? await Task.sleep(nanoseconds: 10_000_000)
    }
    return false
}

private func XCTAssertThrowsErrorAsync<T>(
    _ expression: @autoclosure () async throws -> T,
    _ verify: (Error) -> Void,
    file: StaticString = #filePath,
    line: UInt = #line
) async {
    do {
        _ = try await expression()
        XCTFail("Expected error", file: file, line: line)
    } catch {
        verify(error)
    }
}
