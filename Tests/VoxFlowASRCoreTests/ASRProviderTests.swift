import XCTest
import VoxFlowASRCore
import VoxFlowAudio

final class ASRProviderTests: XCTestCase {
    func testProviderDescriptorCarriesLanguageAndStreamingCapabilities() {
        let descriptor = ASRProviderDescriptor(
            id: ASRProviderID(rawValue: "qwen3"),
            displayName: "Qwen3-ASR",
            modelInstallationState: .notInstalled,
            supportedLanguages: [
                ASRLanguageCapability(bcp47Tag: "zh-Hans"),
                ASRLanguageCapability(bcp47Tag: "en"),
                ASRLanguageCapability(bcp47Tag: "ja"),
            ],
            streamingSemantics: .chunkedStablePrefix
        )

        XCTAssertEqual(descriptor.id.rawValue, "qwen3")
        XCTAssertEqual(descriptor.modelInstallationState, .notInstalled)
        XCTAssertEqual(descriptor.supportedLanguages.map(\.bcp47Tag), ["zh-Hans", "en", "ja"])
        XCTAssertEqual(descriptor.streamingSemantics, .chunkedStablePrefix)
    }

    func testModelInstallationStateDistinguishesLifecycleUnsupportedAndFailure() {
        XCTAssertTrue(ASRModelInstallationState.ready.isReady)
        XCTAssertFalse(ASRModelInstallationState.corrupt.isReady)
        XCTAssertTrue(ASRModelInstallationState.runtimeUnsupported(reason: "macOS").isUnsupported)
        XCTAssertTrue(ASRModelInstallationState.hardwareUnsupported(reason: "memory").isUnsupported)
        XCTAssertFalse(ASRModelInstallationState.failed(message: "checksum").isUnsupported)
    }

    func testProviderProtocolExposesInstallDeletePrepareHealthAndSessionFactory() async throws {
        let provider = CapturingASRProvider()

        try await provider.install()
        try await provider.delete()
        try await provider.prepare()
        let health = await provider.healthCheck()
        let session = try await provider.makeSession(language: ASRLanguageCapability(bcp47Tag: "en"))

        XCTAssertEqual(health, .healthy)
        let calls = await provider.calls
        XCTAssertEqual(calls, [.install, .delete, .prepare, .healthCheck, .makeSession])
        XCTAssertEqual(session.sessionID.rawValue, "captured-session")
    }
}

private actor CapturingASRProvider: ASRProvider {
    enum Call: Equatable {
        case install
        case delete
        case prepare
        case healthCheck
        case makeSession
    }

    nonisolated let descriptor = ASRProviderDescriptor(
        id: ASRProviderID(rawValue: "capturing"),
        displayName: "Capturing",
        modelInstallationState: .ready,
        supportedLanguages: [ASRLanguageCapability(bcp47Tag: "en")],
        streamingSemantics: .nativeStreaming
    )
    private(set) var calls: [Call] = []

    func install() async throws {
        calls.append(.install)
    }

    func delete() async throws {
        calls.append(.delete)
    }

    func prepare() async throws {
        calls.append(.prepare)
    }

    func healthCheck() async -> ASRProviderHealth {
        calls.append(.healthCheck)
        return .healthy
    }

    func makeSession(language: ASRLanguageCapability) async throws -> any ASRSession {
        calls.append(.makeSession)
        return CapturingProviderSession()
    }
}

private struct CapturingProviderSession: ASRSession {
    let sessionID = ASRSessionID(rawValue: "captured-session")
    let revision: UInt64 = 0
    let events = AsyncStream<ASREvent> { continuation in
        continuation.finish()
    }

    func start() async throws {}
    func accept(_ frame: AudioFrame) async throws {}
    func finish() async throws {}
    func cancel() async {}
}
