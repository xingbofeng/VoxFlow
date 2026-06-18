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

        XCTAssertEqual(metadata.modelID, "nvidia/nemotron-3.5-asr-streaming-0.6b")
        XCTAssertEqual(metadata.sourceURL.absoluteString, "https://huggingface.co/nvidia/nemotron-3.5-asr-streaming-0.6b")
        XCTAssertEqual(metadata.licenseID, "openmdw-1.1")
        XCTAssertEqual(metadata.parameterCount, "600M")
        XCTAssertEqual(metadata.runtimeRoutesUnderEvaluation, [.macOSLocal, .externalWorker, .remoteService])
        XCTAssertFalse(metadata.allowsModelDownload)
        XCTAssertFalse(metadata.canAdvertiseReady)
    }

    func testNemotronMetadataRecordsUpstreamDependenciesAndStreamingAPIShape() {
        let metadata = NVIDIANemotronModelMetadata.current

        XCTAssertEqual(metadata.modelArtifactFileName, "nemotron-3.5-asr-streaming-0.6b.nemo")
        XCTAssertEqual(metadata.approximateRepositoryStorageBytes, 4_740_254_495)
        XCTAssertEqual(metadata.requiredRuntimeDependencies, ["Python >= 3.11", "Cython", "PyTorch", "NVIDIA NeMo"])
        XCTAssertEqual(
            metadata.streamingInferenceScript,
            "examples/asr/asr_cache_aware_streaming/speech_to_text_cache_aware_streaming_infer.py"
        )
        XCTAssertEqual(metadata.streamingParameters, ["model_path", "dataset_manifest", "batch_size", "target_lang", "att_context_size", "strip_lang_tags", "output_path"])
        XCTAssertEqual(metadata.languagePromptModes, ["target_lang=<lang_id>", "target_lang=auto"])
        XCTAssertTrue(metadata.requiresMonoAudio)
        XCTAssertNil(metadata.inputSampleRateHertz)
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

    func testRuntimeAssessmentKeepsRoutesExplicitlyEvaluatedButNotReady() {
        let assessment = NVIDIANemotronRuntimeAssessment.current

        XCTAssertNil(assessment.readyRoute)
        XCTAssertEqual(assessment.routes.map(\.route), [.macOSLocal, .externalWorker, .remoteService])
        XCTAssertEqual(
            assessment.routes.map(\.status),
            [
                .blocked,
                .candidate,
                .candidate,
            ]
        )
        XCTAssertTrue(
            assessment.routes[0].rationale.contains("NeMo") &&
            assessment.routes[0].rationale.contains("PyTorch") &&
            assessment.routes[0].rationale.contains("CUDA")
        )
        XCTAssertTrue(assessment.routes[1].rationale.contains("cache-aware streaming"))
        XCTAssertTrue(assessment.routes[2].rationale.contains("privacy"))
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
