import VoxFlowASRCore
import VoxFlowModelStore
import VoxFlowProviderXASR
import XCTest
@testable import VoxFlowApp

final class XASRAppIntegrationTests: XCTestCase {
    func testCatalogExposesStreamingWithoutUnverifiedFileOrHotwordCapabilities() throws {
        let manager = makeManager()
        let descriptor = try XCTUnwrap(ASRProviderRegistry(asrManager: manager).descriptor(id: "xasr"))
        XCTAssertEqual(descriptor.engineType, ASREngineType(rawValue: "X-ASR-zh-en"))
        XCTAssertTrue(descriptor.capabilities.contains([.local, .streaming, .multilingual, .punctuation]))
        XCTAssertFalse(descriptor.capabilities.contains(.fileTranscription))
        XCTAssertTrue(descriptor.supportsLocalModelControls)
        XCTAssertEqual(descriptor.localModelAction, .download)
        XCTAssertFalse(descriptor.isDefault)
        XCTAssertEqual(manager.selectedEngineType, .apple)
        XCTAssertEqual(ASRHotwordCapabilityMatrix.capability(for: .xasr).supportMode, .unsupported)
    }

    func testIntelPreflightOverridesStoredReadyAndLeavesAppleAvailable() throws {
        let repository = FakeXASRInstallationRepository()
        try repository.save(.ready(ModelInstallation(
            modelID: XASRManifestCatalog.modelID,
            version: XASRManifestCatalog.pinnedRevision,
            installedRoot: URL(fileURLWithPath: "/unused-xasr")
        )), for: XASRManifestCatalog.modelInstallKey)
        let manager = makeManager(repository: repository, preflight: {
            .blocked(.architectureUnsupported(required: [.arm64], actual: .x86_64))
        })
        let descriptor = try XCTUnwrap(ASRProviderRegistry(asrManager: manager).descriptor(id: "xasr"))
        XCTAssertEqual(descriptor.healthStatus, .runtimeUnsupported)
        XCTAssertEqual(descriptor.localModelAction, .none)
        XCTAssertFalse(manager.canSelectEngine(.xasr))
        XCTAssertTrue(manager.canSelectEngine(.apple))
    }

    @MainActor
    func testMenuAndPermissionPolicyUseExistingLocalRecordingEntry() throws {
        let options: [ASRMenuModel] = ASRMenuOptions.makeOptions()
        let option = try XCTUnwrap(options.first(where: { $0.engineType == .xasr }))
        XCTAssertEqual(option.title, "X-ASR-zh-en")
        XCTAssertNil(option.modelSize)
        XCTAssertTrue(RecordingPermissionPolicy.hasRequiredPermissions(
            engineType: .xasr, microphonePermission: .granted, speechPermission: .denied
        ))
        XCTAssertFalse(RecordingPermissionPolicy.hasRequiredPermissions(
            engineType: .xasr, microphonePermission: .denied, speechPermission: .granted
        ))
        XCTAssertTrue(ASRCoordinator.requiresFinalRecognitionIndicator(for: .xasr))
    }

    private func makeManager(
        repository: any ModelInstallationStateStoring = FakeXASRInstallationRepository(),
        preflight: @escaping () -> XASRRuntimePreflightOutcome = { .usable }
    ) -> ASRManager {
        let suite = "test.XASRAppIntegration.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        addTeardownBlock { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
        return ASRManager(defaults: defaults, modelInstallationRepository: repository,
            xasrRuntimePreflight: preflight)
    }

    func testExpansionRegistersNativeStreamingXASRWithModelReadiness() throws {
        let entry = try XCTUnwrap(ASRProviderExpansionMatrix.task11Entries.first { $0.providerID == "xasr" })
        XCTAssertEqual(entry.streamingSemantics, .nativeStreaming)
        XCTAssertEqual(entry.providerTargetName, "VoxFlowProviderXASR")
        XCTAssertTrue(entry.requiresModelStoreLifecycle)
        XCTAssertTrue(entry.requiresRuntimePrewarmCanary)
    }
}

private final class FakeXASRInstallationRepository: ModelInstallationStateStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var states: [ModelInstallKey: ModelInstallationState] = [:]
    func state(for key: ModelInstallKey) throws -> ModelInstallationState {
        lock.withLock { states[key] ?? .notInstalled }
    }
    func save(_ state: ModelInstallationState, for key: ModelInstallKey) throws {
        lock.withLock { states[key] = state }
    }
    func removeState(for key: ModelInstallKey) throws {
        _ = lock.withLock { states.removeValue(forKey: key) }
    }
}
