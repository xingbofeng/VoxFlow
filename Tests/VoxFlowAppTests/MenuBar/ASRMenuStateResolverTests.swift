import XCTest
@testable import VoxFlowApp

final class ASRMenuStateResolverTests: XCTestCase {
    func testUnavailablePersistedFunASRSelectionShowsEffectiveAppleFallbackInMenu() {
        let suiteName = "test.ASRMenuStateResolver.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        addTeardownBlock {
            UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName)
        }
        let manager = ASRManager(defaults: defaults)
        manager.selectedEngineType = .funASR

        let resolver = ASRMenuStateResolver(
            asrManager: manager,
            funASRAvailable: { _ in false }
        )
        let appleOption = ASRMenuModel(engineType: .apple, title: "系统自带")
        let funASROption = ASRMenuModel(
            engineType: .funASR,
            funASRPrecision: .int8,
            title: "FunASR Nano INT8"
        )

        XCTAssertTrue(resolver.isSelected(appleOption))
        XCTAssertFalse(resolver.isSelected(funASROption))
        XCTAssertEqual(manager.selectedEngineType, .funASR)
        XCTAssertEqual(manager.effectiveSelectedEngineType, .apple)
    }

}
