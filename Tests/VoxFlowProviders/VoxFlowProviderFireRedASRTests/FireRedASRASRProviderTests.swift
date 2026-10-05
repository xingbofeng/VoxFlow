import Foundation
import VoxFlowASRCore
import VoxFlowAudio
@testable import VoxFlowProviderFireRedASR
import XCTest

final class FireRedASRASRProviderTests: XCTestCase {
    // MARK: - Descriptor

    func testDescriptorDeclaresRollingWindowSemanticsAndChineseFirstLanguages() {
        let descriptor = FireRedASRProviderDescriptor.descriptor(modelInstallationState: .ready)

        XCTAssertEqual(descriptor.id, ASRProviderID(rawValue: "fireredasr"))
        XCTAssertEqual(descriptor.displayName, "FireRedASR2-AED")
        XCTAssertEqual(descriptor.modelInstallationState, .ready)
        XCTAssertEqual(descriptor.supportedLanguages.map(\.bcp47Tag), ["zh-CN", "zh-TW", "en-US"])
        XCTAssertEqual(descriptor.streamingSemantics, .rollingWindowConfirmedSegments)
        XCTAssertEqual(descriptor.timeoutPolicy, .standard)
    }

    func testLanguageMapperAcceptsChineseAndEnglishAndRejectsJapanese() {
        XCTAssertTrue(FireRedASRLanguageMapper.supports(language: .init(bcp47Tag: "zh-CN")))
        XCTAssertTrue(FireRedASRLanguageMapper.supports(language: .init(bcp47Tag: "zh-TW")))
        XCTAssertTrue(FireRedASRLanguageMapper.supports(language: .init(bcp47Tag: "en-US")))
        XCTAssertFalse(FireRedASRLanguageMapper.supports(language: .init(bcp47Tag: "ja-JP")))
        XCTAssertFalse(FireRedASRLanguageMapper.supports(language: .init(bcp47Tag: "ko-KR")))
    }

    // MARK: - Session lifecycle

    func testSubSecondAudioSchedulesNoPreviewAndDecodesOnce() async throws {
        let transcriber = CapturingFireRedASRTranscriber(result: "昨天是 MONDAY TODAY")
        let session = Self.makeSession(transcriber: transcriber)
        let collector = Self.collectEvents(from: session)

        try await session.start()
        try await session.accept(Self.frame(sequenceNumber: 1))
        try await session.finish()

        let events = await collector.value
        let finals = events.compactMap { event -> String? in
            guard case let .final(_, _, text) = event else { return nil }
            return text
        }
        XCTAssertEqual(finals, ["昨天是 MONDAY TODAY"])
        XCTAssertFalse(
            events.contains(where: \.isPartial),
            "不足 1 秒新音频时不调度预览，避免为一句半句反复重解"
        )
        let invocationCount = await transcriber.invocationCount
        XCTAssertEqual(invocationCount, 1, "短录音只应解码一次")
    }

    // MARK: - Preview scheduling (rollingWindowConfirmedSegments)

    func testAccumulatedAudioSchedulesAPreviewThatCarriesOnlyTheUnstableSuffix() async throws {
        let transcriber = CapturingFireRedASRTranscriber(result: "实时预览文本")
        let session = Self.makeSession(transcriber: transcriber)
        let (recorder, pump) = Self.startEventPump(from: session)

        try await session.start()
        // 两帧各 0.6 秒：第二帧后累积达到 1 秒门槛，调度一次预览。
        try await session.accept(Self.frame(sequenceNumber: 1, sampleCount: 9_600))
        try await session.accept(Self.frame(sequenceNumber: 2, sampleCount: 9_600))
        let landed = await waitUntil(timeout: 5) {
            await recorder.snapshot().contains(where: \.isPartial)
        }
        XCTAssertTrue(landed, "累积满 1 秒音频后应放出预览")

        try await session.finish()
        await pump.value

        let events = await recorder.snapshot()
        let previews = events.compactMap(\.partialTranscript)
        XCTAssertEqual(previews.count, 1, "达到门槛后应恰好调度一次预览")
        XCTAssertEqual(previews.first?.stablePrefix, "", "预览不得提交前缀")
        XCTAssertEqual(previews.first?.unstableSuffix, "实时预览文本")
        XCTAssertEqual(events.compactMap(\.finalText), ["实时预览文本"])
    }

    func testPreviewNeverLeaksIntoTheAuthoritativeFinalText() async throws {
        // 预览解出「预览稿」，final 整段重解出「权威稿」。
        let transcriber = SequencedFireRedASRTranscriber(texts: ["预览稿", "权威稿"])
        let session = Self.makeSession(transcriber: transcriber)
        let (recorder, pump) = Self.startEventPump(from: session)

        try await session.start()
        try await session.accept(Self.frame(sequenceNumber: 1, sampleCount: 9_600))
        try await session.accept(Self.frame(sequenceNumber: 2, sampleCount: 9_600))
        let landed = await waitUntil(timeout: 5) {
            await recorder.snapshot().contains(where: \.isPartial)
        }
        XCTAssertTrue(landed, "预览应先落地，才能验证它不污染 final")

        try await session.finish()
        await pump.value

        let events = await recorder.snapshot()
        XCTAssertEqual(events.compactMap(\.partialTranscript).map(\.unstableSuffix), ["预览稿"])
        XCTAssertEqual(
            events.compactMap(\.finalText),
            ["权威稿"],
            "final 必须来自 finish() 的整段重解，而不是预览结果"
        )
    }

    func testPreviewIsNotScheduledForSilentAudio() async throws {
        let transcriber = CapturingFireRedASRTranscriber(result: "不该出现在预览里")
        let session = Self.makeSession(transcriber: transcriber)
        let collector = Self.collectEvents(from: session)

        try await session.start()
        try await session.accept(Self.frame(sequenceNumber: 1, sampleCount: 9_600, amplitude: 0))
        try await session.accept(Self.frame(sequenceNumber: 2, sampleCount: 9_600, amplitude: 0))
        await XCTAssertThrowsErrorAsync(try await session.finish())

        let events = await collector.value
        XCTAssertFalse(events.contains(where: \.isPartial), "静音不应触发预览解码")
    }

    func testSilenceTokenPreviewIsStrippedInsteadOfBeingShownToTheUser() async throws {
        let transcriber = CapturingFireRedASRTranscriber(result: "<sil>")
        let session = Self.makeSession(transcriber: transcriber)
        let collector = Self.collectEvents(from: session)

        try await session.start()
        try await session.accept(Self.frame(sequenceNumber: 1, sampleCount: 9_600))
        try await session.accept(Self.frame(sequenceNumber: 2, sampleCount: 9_600))
        // 整段只解出 `<sil>`：剥掉功能性 token 后为空，finish() 因此报 emptyTranscript。
        await XCTAssertThrowsErrorAsync(try await session.finish())

        let events = await collector.value
        XCTAssertFalse(
            events.contains(where: \.isPartial),
            "整段解出 <sil> 时不得把它当作预览文本显示"
        )
    }

    func testPreviewDecodeFailureDoesNotBreakTheSession() async throws {
        let transcriber = FailFirstFireRedASRTranscriber(result: "最终文本")
        let session = Self.makeSession(transcriber: transcriber)
        let collector = Self.collectEvents(from: session)

        try await session.start()
        try await session.accept(Self.frame(sequenceNumber: 1, sampleCount: 9_600))
        try await session.accept(Self.frame(sequenceNumber: 2, sampleCount: 9_600))
        // 预览是尽力而为的：若松手太快，在飞的预览会在起飞前就被取消。
        // 这里必须先确认预览真的失败过一次，才能验证它没有毁掉会话。
        let previewRan = await waitUntil(timeout: 5) { await transcriber.invocationCount >= 1 }
        XCTAssertTrue(previewRan, "预览解码应先跑过一次")

        try await session.finish()

        let events = await collector.value
        XCTAssertFalse(events.contains(where: \.isPartial), "失败的预览不得发出 partial")
        XCTAssertEqual(
            events.compactMap(\.finalText),
            ["最终文本"],
            "预览解码失败只能丢预览，不能影响 final"
        )
    }

    func testAPreviewInFlightNeverLandsAfterFinish() async throws {
        let transcriber = GatedFireRedASRTranscriber(result: "迟到的预览")
        let session = Self.makeSession(transcriber: transcriber)
        let collector = Self.collectEvents(from: session)

        try await session.start()
        try await session.accept(Self.frame(sequenceNumber: 1, sampleCount: 9_600))
        try await session.accept(Self.frame(sequenceNumber: 2, sampleCount: 9_600))
        let previewStarted = await waitUntil(timeout: 5) { await transcriber.invocationCount >= 1 }
        XCTAssertTrue(previewStarted, "预览解码应已开始，才能制造 finish 与预览的竞态")

        // 放行必须与 finish 并发：若预览根本没起飞（实现缺失的失败态），
        // finish() 自己就会撞上 gate，串行放行会永久死锁。
        let releaser = Task {
            try? await Task.sleep(nanoseconds: 300_000_000)
            await transcriber.release()
        }
        try await session.finish()
        await releaser.value
        await transcriber.release()
        let events = await collector.value

        XCTAssertEqual(events.compactMap(\.finalText), ["迟到的预览"])
        XCTAssertFalse(
            events.contains(where: \.isPartial),
            "已经整段重解出 final 之后，在飞的预览不得再落地"
        )
    }

    func testAPreviewInFlightNeverLandsAfterCancel() async throws {
        let transcriber = GatedFireRedASRTranscriber(result: "迟到的预览")
        let session = Self.makeSession(transcriber: transcriber)
        let collector = Self.collectEvents(from: session)

        try await session.start()
        try await session.accept(Self.frame(sequenceNumber: 1, sampleCount: 9_600))
        try await session.accept(Self.frame(sequenceNumber: 2, sampleCount: 9_600))
        let previewStarted = await waitUntil(timeout: 5) { await transcriber.invocationCount >= 1 }
        XCTAssertTrue(previewStarted, "预览解码应已开始，才能制造 cancel 与预览的竞态")

        await session.cancel()
        await transcriber.release()
        let events = await collector.value

        XCTAssertFalse(
            events.contains(where: \.isPartial),
            "取消之后在飞的预览不得再落地"
        )
        XCTAssertTrue(events.contains(where: \.isFailure))
    }

    func testFinishThenCancelDoesNotEmitASecondOutcome() async throws {
        let session = Self.makeSession(
            transcriber: CapturingFireRedASRTranscriber(result: "文本")
        )
        let collector = Self.collectEvents(from: session)

        try await session.start()
        try await session.accept(Self.frame(sequenceNumber: 1))
        try await session.finish()
        await session.cancel()

        let events = await collector.value
        XCTAssertEqual(events.filter { $0.isFailure }.count, 0, "已 final 的会话不应再报 cancelled")
        XCTAssertEqual(events.filter { $0.isFinal }.count, 1)
    }

    func testCancelDuringStartupNeverEmitsReadyOrFinal() async throws {
        let factory = DelayedFireRedASRTranscriberFactory(
            transcriber: CapturingFireRedASRTranscriber(result: "不该出现")
        )
        let session = Self.makeSession(factory: factory)
        let recorder = FireRedASREventRecorder()
        let collector = Task {
            for await event in session.events {
                await recorder.append(event)
            }
        }

        let startTask = Task { try await session.start() }
        let started = await waitUntil(timeout: 1.0) { factory.hasStarted }
        XCTAssertTrue(started)

        await session.cancel()
        // 让卡住的加载结束：`start()` 恢复后必须发现会话已关闭，从而既不安装识别器也不发 ready。
        factory.release()
        _ = try? await startTask.value
        _ = await collector.value

        let events = await recorder.snapshot()
        XCTAssertEqual(events.filter { $0.isReady }.count, 0)
        XCTAssertEqual(events.filter { $0.isFinal }.count, 0)
        XCTAssertEqual(events.filter { $0.isFailure }.count, 1)
        XCTAssertEqual(events.compactMap { $0.failureCategory }.first, .cancelled)
    }

    func testCancelWithoutSpeechEmitsCancelledAndNoText() async throws {
        let session = Self.makeSession(
            transcriber: CapturingFireRedASRTranscriber(result: "不该出现")
        )
        let collector = Self.collectEvents(from: session)

        try await session.start()
        await session.cancel()

        let events = await collector.value
        XCTAssertEqual(events.filter { $0.isFinal }.count, 0)
        XCTAssertEqual(events.filter { $0.isFailure }.count, 1)
        XCTAssertEqual(events.compactMap { $0.failureCategory }.first, .cancelled)
    }

    // MARK: - Failure paths

    func testEmptyFinalFailsInsteadOfPublishingSuccessfulFinal() async throws {
        let session = Self.makeSession(
            transcriber: CapturingFireRedASRTranscriber(result: " \n ")
        )
        let collector = Self.collectEvents(from: session)

        try await session.start()
        try await session.accept(Self.frame(sequenceNumber: 1))
        await XCTAssertThrowsErrorAsync(try await session.finish())

        let events = await collector.value
        XCTAssertEqual(events.filter { $0.isFinal }.count, 0)
        XCTAssertEqual(events.compactMap { $0.failureCategory }.first, .emptyTranscript)
    }

    func testSilenceFailsEmptyWithoutInvokingTheDecoder() async throws {
        let transcriber = CapturingFireRedASRTranscriber(result: "嗯。")
        let session = Self.makeSession(transcriber: transcriber)
        let collector = Self.collectEvents(from: session)

        try await session.start()
        try await session.accept(Self.frame(sequenceNumber: 1, amplitude: 0))
        await XCTAssertThrowsErrorAsync(try await session.finish())

        let events = await collector.value
        XCTAssertEqual(events.filter { $0.isFinal }.count, 0)
        XCTAssertEqual(events.compactMap { $0.failureCategory }.first, .emptyTranscript)
        let invocationCount = await transcriber.invocationCount
        XCTAssertEqual(invocationCount, 0, "纯静音不应该跑 1.24 GB 模型")
    }

    // MARK: - 功能性 token（`<sil>` / `<unk>`）

    /// 线上回归：整段没有可识别语音时，AED 返回 `<sil>`——一个**非空**字符串。
    /// 早期只判 `!text.isEmpty`，于是 `<sil>` 被当成正文注入到了用户光标处。
    func testSilenceTokenResultIsReportedAsEmptyInsteadOfBeingEmittedAsTranscript() async throws {
        let transcriber = CapturingFireRedASRTranscriber(result: "<sil>")
        let session = Self.makeSession(transcriber: transcriber)
        let collector = Self.collectEvents(from: session)

        try await session.start()
        // 有声帧：必须真的跑到解码，才验证得到「解码结果只有 `<sil>`」这条路径。
        try await session.accept(Self.frame(sequenceNumber: 1, amplitude: 0.1))
        await XCTAssertThrowsErrorAsync(try await session.finish())

        let events = await collector.value
        XCTAssertEqual(events.compactMap { $0.finalText }, [], "`<sil>` 绝不能成为 final 文本")
        XCTAssertEqual(events.compactMap { $0.failureCategory }.first, .emptyTranscript)
        let invocationCount = await transcriber.invocationCount
        XCTAssertEqual(invocationCount, 1, "有声帧仍应走解码，只是结果被判为无语音")
    }

    /// 130 s 里有一段是静音：该段的 `<sil>` 要被丢掉，其余正文必须原样保序保留。
    func testSilentSegmentIsDroppedFromLongAudioWithoutLosingSurroundingSpeech() async throws {
        let transcriber = SequencedFireRedASRTranscriber(texts: ["段一", "<sil>", "段三"])
        let session = Self.makeSession(transcriber: transcriber)
        let collector = Self.collectEvents(from: session)

        try await session.start()
        try await session.accept(Self.frame(sequenceNumber: 1, sampleCount: 130 * 16_000))
        try await session.finish()

        let events = await collector.value
        XCTAssertEqual(events.compactMap { $0.finalText }, ["段一段三"])
    }

    /// 整段长音频都没有语音：拼接结果为空，必须走空结果失败，而不是拼出一串 token。
    func testAllSilenceLongAudioFailsEmptyInsteadOfEmittingTokens() async throws {
        let transcriber = SequencedFireRedASRTranscriber(texts: ["<sil>", "<sil>", "<sil>"])
        let session = Self.makeSession(transcriber: transcriber)
        let collector = Self.collectEvents(from: session)

        try await session.start()
        try await session.accept(Self.frame(sequenceNumber: 1, sampleCount: 130 * 16_000))
        await XCTAssertThrowsErrorAsync(try await session.finish())

        let events = await collector.value
        XCTAssertEqual(events.compactMap { $0.finalText }, [])
        XCTAssertEqual(events.compactMap { $0.failureCategory }.first, .emptyTranscript)
    }

    /// 功能性 token 夹在正常文本里时也要清掉，它们不是用户可见内容。
    func testFunctionalTokensAreStrippedFromRecognizedText() async throws {
        let transcriber = CapturingFireRedASRTranscriber(result: "<sil>你好<unk>")
        let session = Self.makeSession(transcriber: transcriber)
        let collector = Self.collectEvents(from: session)

        try await session.start()
        try await session.accept(Self.frame(sequenceNumber: 1, amplitude: 0.1))
        try await session.finish()

        let events = await collector.value
        XCTAssertEqual(events.compactMap { $0.finalText }, ["你好"])
    }

    func testNotInstalledProviderRejectsSessionBeforeCreatingRuntime() async {
        let transcriber = CapturingFireRedASRTranscriber(result: "unused")
        let provider = FireRedASRASRProvider(
            descriptor: FireRedASRProviderDescriptor.descriptor(modelInstallationState: .notInstalled),
            modelURL: nil,
            transcriberFactory: CapturingFireRedASRTranscriberFactory(transcriber: transcriber)
        )

        await XCTAssertThrowsErrorAsync(
            try await provider.makeSession(language: ASRLanguageCapability(bcp47Tag: "zh-CN"))
        ) { error in
            XCTAssertEqual(error as? FireRedASRProviderError, .modelNotInstalled)
        }
        let makeCount = await transcriber.makeCount
        XCTAssertEqual(makeCount, 0)
    }

    func testUnsupportedLanguageIsRejectedWithItsOwnCategory() async {
        let provider = FireRedASRASRProvider(
            descriptor: FireRedASRProviderDescriptor.descriptor(modelInstallationState: .ready),
            modelURL: URL(fileURLWithPath: "/tmp/fireredasr-ready", isDirectory: true),
            transcriberFactory: CapturingFireRedASRTranscriberFactory(
                transcriber: CapturingFireRedASRTranscriber(result: "unused")
            )
        )

        await XCTAssertThrowsErrorAsync(
            try await provider.makeSession(language: ASRLanguageCapability(bcp47Tag: "ja-JP"))
        ) { error in
            XCTAssertEqual(error as? FireRedASRProviderError, .unsupportedLanguage("ja-JP"))
        }
    }

    func testFailedInstallationStateIsSurfacedAsPreparationFailure() async {
        let provider = FireRedASRASRProvider(
            descriptor: FireRedASRProviderDescriptor.descriptor(
                modelInstallationState: .failed(message: "checksum mismatch")
            ),
            modelURL: URL(fileURLWithPath: "/tmp/fireredasr-ready", isDirectory: true)
        )

        let health = await provider.healthCheck()
        guard case let .unhealthy(error) = health else {
            return XCTFail("expected unhealthy provider")
        }
        XCTAssertEqual(error.category, .preparationFailed)
    }

    // MARK: - Long audio

    func testLongAudioIsDecodedPerSegmentAndJoinedInOrder() async throws {
        let transcriber = SequencedFireRedASRTranscriber(texts: ["段一", "段二", "段三"])
        let observer = FireRedASRSegmentationObserver()
        let session = Self.makeSession(
            transcriber: transcriber,
            segmentationObserver: { observer.record($0) }
        )
        let collector = Self.collectEvents(from: session)

        try await session.start()
        // 130 s 恒幅音频：没有静音切点，前两段会退化为硬切。
        try await session.accept(Self.frame(sequenceNumber: 1, sampleCount: 130 * 16_000))
        try await session.finish()

        let events = await collector.value
        XCTAssertEqual(events.compactMap { $0.finalText }, ["段一段二段三"])
        let invocationCount = await transcriber.invocationCount
        XCTAssertEqual(invocationCount, 3)

        let report = try XCTUnwrap(observer.report)
        XCTAssertEqual(report.segmentCount, 3)
        XCTAssertEqual(report.hardCutSegmentCount, 2)
        XCTAssertEqual(report.sampleCount, 130 * 16_000)
    }

    func testShortAudioReportsASingleNonHardCutSegmentToTheObserver() async throws {
        let observer = FireRedASRSegmentationObserver()
        let session = Self.makeSession(
            transcriber: CapturingFireRedASRTranscriber(result: "短句"),
            segmentationObserver: { observer.record($0) }
        )
        let collector = Self.collectEvents(from: session)

        try await session.start()
        try await session.accept(Self.frame(sequenceNumber: 1, sampleCount: 16_000))
        try await session.finish()
        _ = await collector.value

        let report = try XCTUnwrap(observer.report)
        XCTAssertEqual(report.segmentCount, 1)
        XCTAssertEqual(report.hardCutSegmentCount, 0)
    }

    func testProviderThreadsTheSegmentationObserverIntoTheSession() async throws {
        let observer = FireRedASRSegmentationObserver()
        let provider = FireRedASRASRProvider(
            descriptor: FireRedASRProviderDescriptor.descriptor(modelInstallationState: .ready),
            modelURL: URL(fileURLWithPath: "/tmp/fireredasr-ready", isDirectory: true),
            transcriberFactory: StaticFireRedASRTranscriberFactory(
                transcriber: CapturingFireRedASRTranscriber(result: "文本")
            ),
            segmentationObserver: { observer.record($0) }
        )
        let session = try await provider.makeSession(language: ASRLanguageCapability(bcp47Tag: "zh-CN"))
        let collector = Self.collectEvents(from: session)

        try await session.start()
        try await session.accept(Self.frame(sequenceNumber: 1, sampleCount: 16_000))
        try await session.finish()
        _ = await collector.value

        // observer 必须由 provider 透传到 session；漏接的话分段降级在线上就没有任何痕迹。
        let report = try XCTUnwrap(observer.report)
        XCTAssertEqual(report.segmentCount, 1)
        XCTAssertEqual(report.hardCutSegmentCount, 0)
    }

    // MARK: - Helpers

    private static func makeSession(
        transcriber: any FireRedASRTranscribing,
        segmentationObserver: (@Sendable (FireRedASRSegmentationReport) -> Void)? = nil
    ) -> any VoxFlowASRCore.ASRSession {
        makeSession(
            factory: StaticFireRedASRTranscriberFactory(transcriber: transcriber),
            segmentationObserver: segmentationObserver
        )
    }

    private static func makeSession(
        factory: any FireRedASRTranscriberMaking,
        segmentationObserver: (@Sendable (FireRedASRSegmentationReport) -> Void)? = nil
    ) -> any VoxFlowASRCore.ASRSession {
        FireRedASRASRSession(
            sessionID: ASRSessionID(rawValue: "fireredasr-test"),
            modelURL: URL(fileURLWithPath: "/tmp/fireredasr-ready", isDirectory: true),
            transcriberFactory: factory,
            segmentationObserver: segmentationObserver
        )
    }

    private static func collectEvents(
        from session: any VoxFlowASRCore.ASRSession
    ) -> Task<[ASREvent], Never> {
        Task {
            var events: [ASREvent] = []
            for await event in session.events {
                events.append(event)
            }
            return events
        }
    }

    /// 边录边收事件：预览是异步的，只有在 `finish()` 之前就能观察到事件，
    /// 才能断言「预览先落地、且不污染 final」。
    private static func startEventPump(
        from session: any VoxFlowASRCore.ASRSession
    ) -> (recorder: FireRedASREventRecorder, pump: Task<Void, Never>) {
        let recorder = FireRedASREventRecorder()
        let pump = Task {
            for await event in session.events {
                await recorder.append(event)
            }
        }
        return (recorder, pump)
    }

    private static func frame(
        sequenceNumber: UInt64,
        sampleCount: Int = 1_600,
        amplitude: Float = 0.1
    ) -> AudioFrame {
        AudioFrame(
            sequenceNumber: sequenceNumber,
            startSample: 0,
            samples: ContiguousArray(repeating: amplitude, count: sampleCount),
            sampleRate: 16_000,
            capturedAt: ContinuousClock.now
        )
    }
}
