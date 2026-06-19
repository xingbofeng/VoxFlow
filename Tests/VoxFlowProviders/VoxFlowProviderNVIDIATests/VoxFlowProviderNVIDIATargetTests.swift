import XCTest
import VoxFlowASRCore
import VoxFlowAudio
@testable import VoxFlowProviderNVIDIA

final class VoxFlowProviderNVIDIATargetTests: XCTestCase {
    func testTargetIsAvailableForProviderContractTests() {
        XCTAssertNotNil(VoxFlowProviderNVIDIATargetMarker.self)
    }

    func testNemotronMetadataRecordsModelSourceAndRuntimeCandidates() throws {
        let metadata = NVIDIANemotronModelMetadata.current

        XCTAssertEqual(metadata.modelID, "aufklarer/Nemotron-3.5-ASR-Streaming-0.6B-CoreML-INT8")
        XCTAssertEqual(metadata.sourceURL.absoluteString, "https://huggingface.co/aufklarer/Nemotron-3.5-ASR-Streaming-0.6B-CoreML-INT8")
        XCTAssertEqual(metadata.licenseID, "openmdw-1.1")
        XCTAssertEqual(metadata.parameterCount, "600M")
        XCTAssertEqual(metadata.runtimeRoutesUnderEvaluation, [.speechSwiftCoreML])
        XCTAssertTrue(metadata.allowsModelDownload)
        XCTAssertTrue(metadata.canAdvertiseReady)
    }

    func testNemotronMetadataRecordsUpstreamDependenciesAndStreamingAPIShape() {
        let metadata = NVIDIANemotronModelMetadata.current

        XCTAssertEqual(metadata.libraryName, "speech-swift")
        XCTAssertEqual(metadata.runtimeEngine, "NemotronStreamingASR")
        XCTAssertEqual(metadata.modelArtifactFileName, "encoder.mlmodelc + decoder.mlmodelc + joint.mlmodelc")
        XCTAssertEqual(metadata.requiredRuntimeDependencies, ["speech-swift", "CoreML"])
        XCTAssertNil(metadata.streamingInferenceScript)
        XCTAssertEqual(metadata.streamingParameters, ["audio", "sampleRate", "language"])
        XCTAssertEqual(metadata.languagePromptModes, ["language=<bcp47>", "language=auto"])
        XCTAssertTrue(metadata.requiresMonoAudio)
        XCTAssertEqual(metadata.inputSampleRateHertz, 16_000)
    }

    func testNemotronProviderDescriptorSupportsMenuLocalesButStaysUnavailable() {
        let descriptor = NVIDIANemotronProviderDescriptor.current

        XCTAssertEqual(descriptor.id, ASRProviderID(rawValue: "nvidia_nemotron_3_5_asr_streaming_0_6b"))
        XCTAssertEqual(descriptor.supportedLanguages.map(\.bcp47Tag), ["zh-CN", "zh-TW", "en-US", "ja-JP", "ko-KR"])
        XCTAssertEqual(descriptor.streamingSemantics, .nativeStreaming)
        XCTAssertFalse(descriptor.modelInstallationState.isReady)
        XCTAssertEqual(
            descriptor.modelInstallationState,
            .runtimeUnsupported(reason: "NVIDIA Nemotron ASR CoreML streaming runtime requires Apple Silicon.")
        )
    }

    func testReadyProviderCreatesNativeStreamingSessionAndEmitsPartialAndFinal() async throws {
        let transcriber = CapturingNVIDIANemotronTranscriber(finalText: "最终文本")
        let provider = NVIDIANemotronASRProvider.live(
            descriptor: NVIDIANemotronProviderDescriptor.descriptor(modelInstallationState: .ready),
            modelURL: URL(fileURLWithPath: "/tmp/nvidia-ready", isDirectory: true),
            transcriberFactory: CapturingNVIDIANemotronTranscriberFactory(transcriber: transcriber)
        )

        let session = try await provider.makeSession(language: ASRLanguageCapability(bcp47Tag: "zh-CN"))
        let recorder = ASREventRecorder()
        let collector = Task {
            for await event in session.events {
                await recorder.append(event)
            }
        }

        try await session.start()
        try await session.accept(Self.frame(sequenceNumber: 1, sampleCount: 16_000))
        try await session.finish()
        _ = await collector.value

        let partialTexts = await recorder.partialTexts()
        let finalTexts = await recorder.finalTexts()
        let languageCode = await transcriber.languageCode
        XCTAssertTrue(partialTexts.contains("实时文本"))
        XCTAssertTrue(finalTexts.contains("最终文本"))
        XCTAssertEqual(languageCode, "zh-CN")
    }

    func testStartWaitsForTranscriberBeforeEmittingReady() async throws {
        let factory = GatedNVIDIANemotronTranscriberFactory()
        let provider = NVIDIANemotronASRProvider.live(
            descriptor: NVIDIANemotronProviderDescriptor.descriptor(modelInstallationState: .ready),
            modelURL: URL(fileURLWithPath: "/tmp/nvidia-gated", isDirectory: true),
            transcriberFactory: factory
        )
        let session = try await provider.makeSession(language: ASRLanguageCapability(bcp47Tag: "zh-CN"))
        let recorder = ASREventRecorder()
        let collector = Task {
            for await event in session.events {
                await recorder.append(event)
            }
        }

        let startTask = Task {
            try await session.start()
        }
        try await waitUntil("session emits preparing") {
            await recorder.containsPreparing()
        }
        let emittedReadyBeforeTranscriberLoaded = await recorder.containsReady()
        XCTAssertFalse(emittedReadyBeforeTranscriberLoaded)

        await factory.release(with: CapturingNVIDIANemotronTranscriber(finalText: "最终文本"))
        try await startTask.value
        try await waitUntil("session emits ready") {
            await recorder.containsReady()
        }

        await session.cancel()
        _ = await collector.value
    }

    func testUnavailableProviderNeverAdvertisesHealthyRuntime() async {
        let provider = NVIDIANemotronUnavailableProvider()
        let health = await provider.healthCheck()

        XCTAssertEqual(provider.descriptor, NVIDIANemotronProviderDescriptor.current)
        XCTAssertEqual(
            health,
            .unhealthy(
                ASRError(
                    category: .runtimeUnsupported,
                    message: NVIDIANemotronProviderDescriptor.runtimeUnsupportedReason
                )
            )
        )
    }

    func testUnavailableProviderRefusesInstallPrepareAndSessionCreation() async {
        let provider = NVIDIANemotronUnavailableProvider()

        await assertRuntimeUnsupported {
            try await provider.install()
        }
        await assertRuntimeUnsupported {
            try await provider.prepare()
        }
        await assertRuntimeUnsupported {
            _ = try await provider.makeSession(language: ASRLanguageCapability(bcp47Tag: "zh-CN"))
        }
    }

    func testRuntimeAssessmentUsesSpeechSwiftCoreMLRoute() {
        let assessment = NVIDIANemotronRuntimeAssessment.current

        XCTAssertEqual(assessment.readyRoute, .speechSwiftCoreML)
        XCTAssertEqual(assessment.routes.map(\.route), [.speechSwiftCoreML])
        XCTAssertEqual(assessment.routes.map(\.status), [.ready])
        XCTAssertTrue(assessment.routes[0].rationale.contains("speech-swift"))
        XCTAssertFalse(assessment.routes[0].rationale.contains("NeMo"))
        XCTAssertFalse(assessment.routes[0].rationale.contains("Python"))
    }

    private func assertRuntimeUnsupported(
        file: StaticString = #filePath,
        line: UInt = #line,
        _ operation: () async throws -> Void
    ) async {
        do {
            try await operation()
            XCTFail("Expected NVIDIA runtime unsupported failure", file: file, line: line)
        } catch let error as NVIDIANemotronProviderError {
            XCTAssertEqual(
                error,
                .runtimeUnsupported(reason: NVIDIANemotronProviderDescriptor.runtimeUnsupportedReason),
                file: file,
                line: line
            )
        } catch {
            XCTFail("Expected NVIDIANemotronProviderError, got \(error)", file: file, line: line)
        }
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

private actor ASREventRecorder {
    private var events: [ASREvent] = []

    func append(_ event: ASREvent) {
        events.append(event)
    }

    func partialTexts() -> [String] {
        events.compactMap { event -> String? in
            guard case let .partial(_, transcript) = event else { return nil }
            return transcript.stablePrefix + transcript.unstableSuffix
        }
    }

    func finalTexts() -> [String] {
        events.compactMap { event -> String? in
            guard case let .final(_, _, text) = event else { return nil }
            return text
        }
    }

    func containsPreparing() -> Bool {
        events.contains { event in
            if case .preparing = event {
                return true
            }
            return false
        }
    }

    func containsReady() -> Bool {
        events.contains { event in
            if case .ready = event {
                return true
            }
            return false
        }
    }
}

private actor CapturingNVIDIANemotronTranscriber: NVIDIANemotronTranscribing {
    let finalText: String
    private var partialHandler: (@Sendable (String) -> Void)?
    private(set) var languageCode: String?

    init(finalText: String) {
        self.finalText = finalText
    }

    func setPartialHandler(_ handler: @escaping @Sendable (String) -> Void) async {
        partialHandler = handler
    }

    func setLanguage(_ languageCode: String?) async {
        self.languageCode = languageCode
    }

    func accept(audio: [Float]) async throws -> String {
        partialHandler?("实时文本")
        return ""
    }

    func finish() async throws -> String {
        finalText
    }

    func cancel() async {}
}

private struct CapturingNVIDIANemotronTranscriberFactory: NVIDIANemotronTranscriberMaking {
    let transcriber: CapturingNVIDIANemotronTranscriber

    func makeTranscriber(directoryURL: URL) async throws -> any NVIDIANemotronTranscribing {
        transcriber
    }
}

private actor GatedNVIDIANemotronTranscriberFactory: NVIDIANemotronTranscriberMaking {
    private var continuation: CheckedContinuation<any NVIDIANemotronTranscribing, Error>?

    func makeTranscriber(directoryURL: URL) async throws -> any NVIDIANemotronTranscribing {
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
        }
    }

    func release(with transcriber: any NVIDIANemotronTranscribing) {
        continuation?.resume(returning: transcriber)
        continuation = nil
    }
}

private func waitUntil(
    _ description: String,
    timeout: Duration = .seconds(1),
    pollInterval: Duration = .milliseconds(10),
    condition: () async -> Bool,
    file: StaticString = #filePath,
    line: UInt = #line
) async throws {
    let clock = ContinuousClock()
    let deadline = clock.now + timeout
    while clock.now < deadline {
        if await condition() {
            return
        }
        try await Task.sleep(for: pollInterval)
    }
    XCTFail("Timed out waiting for \(description)", file: file, line: line)
}
