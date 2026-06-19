import XCTest
@testable import VoxFlowApp

final class GroqASRManagerTests: XCTestCase {
    func testGroqBecomesSelectableOnlyAfterCredentialIsConfigured() throws {
        let suiteName = "test.GroqASRManager.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let credentials = GroqManagerCredentialStore()
        let manager = ASRManager(defaults: defaults, credentialStore: credentials)

        XCTAssertFalse(manager.canSelectEngine(.groqWhisper))
        XCTAssertFalse(try XCTUnwrap(ASRProviderRegistry(asrManager: manager).descriptor(id: ASRProviderID.groqWhisper)).isAvailable)

        try manager.saveGroqAPIKey("secret")

        XCTAssertTrue(manager.canSelectEngine(.groqWhisper))
        let descriptor = try XCTUnwrap(
            ASRProviderRegistry(asrManager: manager).descriptor(id: ASRProviderID.groqWhisper)
        )
        XCTAssertTrue(descriptor.isAvailable)
        XCTAssertEqual(descriptor.engineType, .groqWhisper)
        XCTAssertTrue(manager.makeEngine(type: .groqWhisper) is BufferedCloudASREngine)
        XCTAssertFalse(defaults.dictionaryRepresentation().values.contains { String(describing: $0).contains("secret") })
    }

    func testClearingGroqCredentialMakesPersistedSelectionFallBackToApple() throws {
        let defaults = UserDefaults(suiteName: "test.GroqFallback.\(UUID().uuidString)")!
        let credentials = GroqManagerCredentialStore()
        let manager = ASRManager(defaults: defaults, credentialStore: credentials)
        try manager.saveGroqAPIKey("secret")
        XCTAssertTrue(manager.selectEngine(.groqWhisper))

        try manager.saveGroqAPIKey("")

        XCTAssertEqual(manager.selectedEngineType, .groqWhisper)
        XCTAssertEqual(manager.effectiveSelectedEngineType, .apple)
        XCTAssertEqual(manager.selectionFallbackNotice?.selectedEngineType, .groqWhisper)
    }
}

private final class GroqManagerCredentialStore: CredentialStore {
    private var values: [String: String] = [:]

    func readCredential(account: String) throws -> String? { values[account] }
    func saveCredential(_ value: String, account: String) throws { values[account] = value }
    func deleteCredential(account: String) throws { values.removeValue(forKey: account) }
}
