import VoxFlowASRCore
import VoxFlowModelStore
@testable import VoxFlowProviderR2T2
import XCTest

final class R2T2ModelReadinessTests: XCTestCase {
    private let installationRoot = URL(fileURLWithPath: "/tmp/r2t2-readiness", isDirectory: true)

    private var installation: ModelInstallation {
        ModelInstallation(
            modelID: ModelID(rawValue: "confucius4-r2t2-8bit"),
            version: R2T2ManifestCatalog.pinnedRevision,
            installedRoot: installationRoot
        )
    }

    func testLoadBuildsTheStreamFromTheInstallationRootWithTheRequestedLanguage() async throws {
        let engine = ScriptedR2T2Stream(pushResults: [], finishResult: "")
        let factory = CapturingR2T2StreamFactory(engine: engine)
        let preparer = R2T2ModelRuntimePreparer(streamFactory: factory, languageHint: "zh")

        try await preparer.load(installation: installation)

        XCTAssertEqual(factory.modelURLs, [installationRoot])
        XCTAssertEqual(factory.languageHints, ["zh"])
        XCTAssertNil(factory.contextPrompts.first ?? nil, "预热不带上下文热词")
    }

    func testCompileRefusesToRunBeforeLoad() async {
        let factory = CapturingR2T2StreamFactory(
            engine: ScriptedR2T2Stream(pushResults: [], finishResult: "")
        )
        let preparer = R2T2ModelRuntimePreparer(streamFactory: factory)

        await XCTAssertThrowsErrorAsync {
            try await preparer.compile(installation: self.installation)
        }
    }

    func testTranscribeCanaryFeedsTheAudioAndReportsCommittedText() async throws {
        let engine = ScriptedR2T2Stream(pushResults: [["你", "好"]], finishResult: "。")
        let preparer = R2T2ModelRuntimePreparer(
            streamFactory: CapturingR2T2StreamFactory(engine: engine),
            languageHint: "zh"
        )
        let audio = ModelCanaryAudio(
            samples: [Float](repeating: 0, count: 16_000),
            sampleRate: 16_000,
            expectedTokens: []
        )

        try await preparer.load(installation: installation)
        let transcript = try await preparer.transcribeCanary(
            installation: installation,
            audio: audio
        )

        XCTAssertEqual(transcript, "你好。", "canary 结果必须是已确认全文，而不是尾部增量")
    }

    func testTranscribeCanaryWithoutLoadFailsInsteadOfReturningEmptyText() async {
        let preparer = R2T2ModelRuntimePreparer(
            streamFactory: CapturingR2T2StreamFactory(
                engine: ScriptedR2T2Stream(pushResults: [], finishResult: "")
            )
        )

        await XCTAssertThrowsErrorAsync {
            _ = try await preparer.transcribeCanary(
                installation: self.installation,
                audio: ModelCanaryAudio(samples: [], sampleRate: 16_000, expectedTokens: [])
            )
        }
    }

    func testBlockedPreflightProducesAPreparerThatRefusesEveryStep() async {
        let preparer = R2T2UnsupportedRuntimePreparer(
            blocker: .architectureUnsupported(required: [.arm64], actual: .x86_64)
        )

        await XCTAssertThrowsErrorAsync { try await preparer.load(installation: self.installation) }
        await XCTAssertThrowsErrorAsync { try await preparer.compile(installation: self.installation) }
        await XCTAssertThrowsErrorAsync {
            _ = try await preparer.transcribeCanary(
                installation: self.installation,
                audio: ModelCanaryAudio(samples: [], sampleRate: 16_000, expectedTokens: [])
            )
        }
    }

    func testUnsupportedPreparerReportsTheStructuredBlockerToTheApp() async {
        let preparer = R2T2UnsupportedRuntimePreparer(
            blocker: .insufficientMemory(requiredBytes: 16, actualBytes: 8)
        )

        do {
            try await preparer.load(installation: installation)
            XCTFail("Expected the unsupported preparer to fail")
        } catch let error as R2T2ProviderError {
            XCTAssertEqual(error, .preflightBlocked(.insufficientMemory(requiredBytes: 16, actualBytes: 8)))
            XCTAssertEqual(error.asrError.category, .hardwareUnsupported)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testReadinessRunnerBuildsTheInstallationFromThePinnedManifestMetadata() async throws {
        let runtime = CapturingModelRuntimePreparer(transcript: "你好")
        let runner = R2T2ModelReadinessRunner(runtimeFactory: { _ in runtime })

        let report = try await runner.prepare(modelURL: installationRoot)

        XCTAssertEqual(report.transcript, "你好")
        let recorded = await runtime.recordedInstallations
        XCTAssertEqual(recorded.count, 1)
        XCTAssertEqual(recorded.first?.modelID.rawValue, "confucius4-r2t2-8bit")
        XCTAssertEqual(recorded.first?.version, R2T2ManifestCatalog.pinnedRevision)
        XCTAssertEqual(recorded.first?.installedRoot, installationRoot)
    }

    func testReadinessRunnerLoadsCompilesAndCanariesTheModelInOrder() async throws {
        let runtime = CapturingModelRuntimePreparer(transcript: "你好")
        let runner = R2T2ModelReadinessRunner(runtimeFactory: { _ in runtime })

        _ = try await runner.prepare(modelURL: installationRoot)

        let steps = await runtime.recordedSteps
        XCTAssertEqual(steps, ["load", "compile", "canary"])
    }
}

// MARK: - Fakes

private actor CapturingModelRuntimePreparer: ModelRuntimePreparing {
    private let transcript: String
    private(set) var recordedInstallations: [ModelInstallation] = []
    private(set) var recordedSteps: [String] = []

    init(transcript: String) {
        self.transcript = transcript
    }

    func load(installation: ModelInstallation) async throws {
        recordedInstallations.append(installation)
        recordedSteps.append("load")
    }

    func compile(installation: ModelInstallation) async throws {
        recordedSteps.append("compile")
    }

    func transcribeCanary(
        installation: ModelInstallation,
        audio: ModelCanaryAudio
    ) async throws -> String {
        recordedSteps.append("canary")
        return transcript
    }
}
