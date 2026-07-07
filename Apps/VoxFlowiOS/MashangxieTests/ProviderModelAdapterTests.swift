import XCTest
import Shared
@testable import Mashangxie

final class ProviderModelAdapterTests: XCTestCase {
    private var previousProvider: String?
    private var previousStandardProvider: String?
    private var tempCredentialsURL: URL!

    override func setUp() {
        super.setUp()
        previousProvider = AppGroup.defaults.string(forKey: SharedKeys.provider)
        previousStandardProvider = UserDefaults.standard.string(forKey: "VoxFlowiOS.selectedProvider")
        tempCredentialsURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("json")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempCredentialsURL)
        if let previousProvider {
            AppGroup.defaults.set(previousProvider, forKey: SharedKeys.provider)
        } else {
            AppGroup.defaults.removeObject(forKey: SharedKeys.provider)
        }
        if let previousStandardProvider {
            UserDefaults.standard.set(previousStandardProvider, forKey: "VoxFlowiOS.selectedProvider")
        } else {
            UserDefaults.standard.removeObject(forKey: "VoxFlowiOS.selectedProvider")
        }
        AppGroup.defaults.synchronize()
        super.tearDown()
    }

    @MainActor
    func testActiveCloudProviderRemainsDisplayableWhenCredentialsAreMissing() {
        let manager = ModelManager(credentialStore: isolatedCredentialStore())

        manager.selectModel(SelectedProvider.tencent.rawValue)

        let status = manager.activeModelStatus
        XCTAssertEqual(status?.info.provider, .tencent)
        XCTAssertEqual(status?.state, .unavailable(L10n.t("diagnostics.availability.missing_credentials")))
        XCTAssertFalse(status?.isReady ?? true)
    }

    @MainActor
    func testCloudProvidersWithoutCredentialsAreUnavailableBeforeSelection() {
        let manager = ModelManager(credentialStore: isolatedCredentialStore())

        XCTAssertEqual(
            manager.modelStates[SelectedProvider.aliyun.rawValue],
            .unavailable(L10n.t("diagnostics.availability.missing_credentials"))
        )
        XCTAssertEqual(
            manager.modelStates[SelectedProvider.volcengine.rawValue],
            .unavailable(L10n.t("diagnostics.availability.missing_credentials"))
        )
    }

    @MainActor
    func testCloudProviderBecomesReadyAfterCredentialsAreSaved() throws {
        let store = isolatedCredentialStore()
        let manager = ModelManager(credentialStore: store)

        manager.selectModel(SelectedProvider.tencent.rawValue)
        XCTAssertFalse(manager.activeModelStatus?.isReady ?? true)

        try store.save(provider: .tencent, values: [
            "appID": "app-id",
            "secretID": "secret-id",
            "secretKey": "secret-key",
        ])
        manager.loadState()

        let status = manager.activeModelStatus
        XCTAssertEqual(status?.info.provider, .tencent)
        XCTAssertEqual(status?.state, .ready)
        XCTAssertTrue(status?.isReady ?? false)
    }

    func testDevCloudCredentialsDecodeBundledProviderValues() {
        let root: [String: Any] = [
            "TencentAppIDB64": b64("app-id"),
            "TencentSecretIDB64": b64("secret-id"),
            "TencentSecretKeyB64": b64("secret-key"),
            "AliyunAPIKeyB64": b64("aliyun-key"),
            "VolcengineAppIDB64": b64("volc-app"),
            "VolcengineAccessTokenB64": b64("volc-token"),
            "VolcengineSecretKeyB64": b64("volc-secret"),
        ]

        XCTAssertEqual(DevCloudCredentials.values(for: .tencent, root: root), [
            "appID": "app-id",
            "secretID": "secret-id",
            "secretKey": "secret-key",
        ])
        XCTAssertEqual(DevCloudCredentials.values(for: .aliyun, root: root), [
            "apiKey": "aliyun-key",
        ])
        XCTAssertEqual(DevCloudCredentials.values(for: .volcengine, root: root), [
            "appID": "volc-app",
            "accessToken": "volc-token",
            "secretKey": "volc-secret",
        ])
    }

    func testDevCloudCredentialsIgnorePlaceholdersAndInvalidValues() {
        let root: [String: Any] = [
            "TencentAppIDB64": "$(MASHANGXIE_DEV_TENCENT_APP_ID)",
            "TencentSecretIDB64": "not-base64",
            "TencentSecretKeyB64": b64(""),
            "AliyunAPIKeyB64": b64("  "),
        ]

        XCTAssertEqual(DevCloudCredentials.values(for: .tencent, root: root), [:])
        XCTAssertEqual(DevCloudCredentials.values(for: .aliyun, root: root), [:])
    }

    func testDevCloudCredentialsIgnoreSimulatorPlaceholderValues() {
        let root: [String: Any] = [
            "TencentAppIDB64": b64("sim-app-id"),
            "TencentSecretIDB64": b64("sim-secret-id"),
            "TencentSecretKeyB64": b64("sim-secret-key"),
            "AliyunAPIKeyB64": b64("sim-api-key"),
            "VolcengineAppIDB64": b64("sim-volc-app"),
            "VolcengineAccessTokenB64": b64("sim-volc-token"),
            "VolcengineSecretKeyB64": b64("sim-volc-secret"),
        ]

        XCTAssertEqual(DevCloudCredentials.values(for: .tencent, root: root), [:])
        XCTAssertEqual(DevCloudCredentials.values(for: .aliyun, root: root), [:])
        XCTAssertEqual(DevCloudCredentials.values(for: .volcengine, root: root), [:])
    }

    func testCredentialStoreMigratesLegacySandboxFileIntoSharedStore() throws {
        let legacyURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("legacy.json")
        defer { try? FileManager.default.removeItem(at: legacyURL) }

        let legacyStore = LocalCredentialStore(fileURL: legacyURL)
        try legacyStore.save(provider: .tencent, values: [
            "appID": "legacy-app",
            "secretID": "legacy-secret-id",
            "secretKey": "legacy-secret-key",
        ])

        let sharedStore = LocalCredentialStore(fileURL: tempCredentialsURL, legacyFileURL: legacyURL)

        XCTAssertEqual(sharedStore.values(for: .tencent), [
            "appID": "legacy-app",
            "secretID": "legacy-secret-id",
            "secretKey": "legacy-secret-key",
        ])
    }

    func testCredentialStoreDoesNotOverwriteExistingSharedCredentialsDuringMigration() throws {
        let legacyURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("legacy.json")
        defer { try? FileManager.default.removeItem(at: legacyURL) }

        let legacyStore = LocalCredentialStore(fileURL: legacyURL)
        try legacyStore.save(provider: .tencent, values: [
            "appID": "legacy-app",
            "secretID": "legacy-secret-id",
            "secretKey": "legacy-secret-key",
        ])

        let existingStore = LocalCredentialStore(fileURL: tempCredentialsURL)
        try existingStore.save(provider: .tencent, values: [
            "appID": "shared-app",
            "secretID": "shared-secret-id",
            "secretKey": "shared-secret-key",
        ])

        let sharedStore = LocalCredentialStore(fileURL: tempCredentialsURL, legacyFileURL: legacyURL)

        XCTAssertEqual(sharedStore.values(for: .tencent), [
            "appID": "shared-app",
            "secretID": "shared-secret-id",
            "secretKey": "shared-secret-key",
        ])
    }

    func testCredentialStoreTrimsCopiedCredentialValuesOnSave() throws {
        let store = LocalCredentialStore(fileURL: tempCredentialsURL)

        try store.save(provider: .tencent, values: [
            "appID": "  app-id\n",
            "secretID": "\tsecret-id ",
            "secretKey": "\nsecret-key\t",
        ])

        XCTAssertEqual(store.values(for: .tencent), [
            "appID": "app-id",
            "secretID": "secret-id",
            "secretKey": "secret-key",
        ])
    }

    func testCredentialStoreTreatsSimulatorPlaceholderValuesAsIncomplete() throws {
        let store = LocalCredentialStore(fileURL: tempCredentialsURL)

        try store.save(provider: .tencent, values: [
            "appID": "sim-app-id",
            "secretID": "sim-secret-id",
            "secretKey": "sim-secret-key",
        ])

        XCTAssertFalse(store.isComplete(.tencent))
        XCTAssertEqual(store.values(for: .tencent), [:])
    }

    func testCredentialStoreTreatsPersistedSimulatorPlaceholderValuesAsIncomplete() throws {
        let data = try JSONEncoder().encode([
            "tencent": [
                "appID": "sim-app-id",
                "secretID": "sim-secret-id",
                "secretKey": "sim-secret-key",
            ],
        ])
        try data.write(to: tempCredentialsURL, options: .atomic)
        let store = LocalCredentialStore(fileURL: tempCredentialsURL)

        XCTAssertFalse(store.isComplete(.tencent))
        XCTAssertEqual(store.values(for: .tencent), [:])
    }

    @MainActor
    func testAppStatePrefersAppGroupProviderOnLaunch() {
        AppGroup.defaults.set(SelectedProvider.tencent.rawValue, forKey: SharedKeys.provider)
        UserDefaults.standard.set(SelectedProvider.aliyun.rawValue, forKey: "VoxFlowiOS.selectedProvider")

        let appState = AppState()

        XCTAssertEqual(appState.selectedProvider, .tencent)
    }

    private func b64(_ value: String) -> String {
        Data(value.utf8).base64EncodedString()
    }

    private func isolatedCredentialStore() -> LocalCredentialStore {
        LocalCredentialStore(fileURL: tempCredentialsURL, usesDevCloudCredentials: false)
    }
}
