import XCTest
@testable import Shared

/// Phase 1.5 — BridgeResolver 是纯函数，覆盖三种模式 × AppGroup 可用性的矩阵。
final class BridgeResolverTests: XCTestCase {

    // MARK: - Clipboard forced mode

    func testClipboardModeAlwaysSelectsClipboardBridgeRegardlessOfAppGroup() {
        for availability in allAvailabilities {
            let selection = BridgeResolver.resolve(mode: .clipboard, appGroupAvailability: availability)
            XCTAssertEqual(selection.configuredMode, .clipboard)
            XCTAssertEqual(selection.effectiveBridge, .clipboardBridge)
            XCTAssertEqual(selection.fallbackReason, .forcedClipboardMode)
            XCTAssertEqual(selection.appGroupAvailability, availability)
        }
    }

    // MARK: - AppGroup forced mode

    func testAppGroupModeForcesAppGroupBridgeEvenWhenUnavailable() {
        let selection = BridgeResolver.resolve(
            mode: .appGroup,
            appGroupAvailability: .unavailable(reason: .containerLookupFailed)
        )
        XCTAssertEqual(selection.configuredMode, .appGroup)
        XCTAssertEqual(selection.effectiveBridge, .appGroupBridge)
        XCTAssertEqual(selection.fallbackReason, .forcedAppGroupMode)
        // The unavailability must propagate so callers can show diagnostics
        // — we deliberately do NOT silently fall back to Clipboard in this mode.
        XCTAssertEqual(selection.appGroupAvailability, .unavailable(reason: .containerLookupFailed))
    }

    func testAppGroupModeWhenAvailableHasNoFallbackReason() {
        let selection = BridgeResolver.resolve(mode: .appGroup, appGroupAvailability: .available)
        XCTAssertEqual(selection.effectiveBridge, .appGroupBridge)
        XCTAssertEqual(selection.fallbackReason, .forcedAppGroupMode)
    }

    // MARK: - Auto mode

    func testAutoModeSelectsAppGroupBridgeWhenAvailable() {
        let selection = BridgeResolver.resolve(mode: .automatic, appGroupAvailability: .available)
        XCTAssertEqual(selection.configuredMode, .automatic)
        XCTAssertEqual(selection.effectiveBridge, .appGroupBridge)
        XCTAssertNil(selection.fallbackReason)
    }

    func testAutoModeDegradesToClipboardWhenAppGroupSuiteNotConfigurable() {
        let selection = BridgeResolver.resolve(
            mode: .automatic,
            appGroupAvailability: .unavailable(reason: .suiteNotConfigurable)
        )
        XCTAssertEqual(selection.effectiveBridge, .clipboardBridge)
        XCTAssertEqual(selection.fallbackReason, .autoDegradedToClipboard)
    }

    func testAutoModeDegradesToClipboardWhenContainerLookupFailed() {
        let selection = BridgeResolver.resolve(
            mode: .automatic,
            appGroupAvailability: .unavailable(reason: .containerLookupFailed)
        )
        XCTAssertEqual(selection.effectiveBridge, .clipboardBridge)
        XCTAssertEqual(selection.fallbackReason, .autoDegradedToClipboard)
    }

    func testAutoModeDegradesToClipboardWhenEntitlementMissing() {
        let selection = BridgeResolver.resolve(
            mode: .automatic,
            appGroupAvailability: .unavailable(reason: .entitlementMissing)
        )
        XCTAssertEqual(selection.effectiveBridge, .clipboardBridge)
        XCTAssertEqual(selection.fallbackReason, .autoDegradedToClipboard)
    }

    // MARK: - BridgeModeStore persistence (uses standard defaults fallback)

    func testBridgeModeStoreRoundTripsThroughStandardDefaults() {
        // We cannot reliably reset AppGroup.defaults in the test process because
        // it's a process-wide singleton, but standard defaults round-trip is the
        // critical fallback path on free-signed devices.
        let key = BridgeModeStore.key
        let original = UserDefaults.standard.string(forKey: key)
        defer {
            if let original = original {
                UserDefaults.standard.set(original, forKey: key)
            } else {
                UserDefaults.standard.removeObject(forKey: key)
            }
        }

        BridgeModeStore.write(.clipboard)
        XCTAssertEqual(BridgeModeStore.read(), .clipboard)

        BridgeModeStore.write(.appGroup)
        XCTAssertEqual(BridgeModeStore.read(), .appGroup)

        BridgeModeStore.write(.automatic)
        XCTAssertEqual(BridgeModeStore.read(), .automatic)
    }

    func testBridgeModeStoreReadsClipboardWhenUnset() {
        let key = BridgeModeStore.key
        let originalShared = AppGroup.defaultsIfAvailable?.string(forKey: key)
        let originalStandard = UserDefaults.standard.string(forKey: key)
        AppGroup.defaultsIfAvailable?.removeObject(forKey: key)
        UserDefaults.standard.removeObject(forKey: key)
        defer {
            if let originalShared = originalShared {
                AppGroup.defaultsIfAvailable?.set(originalShared, forKey: key)
            }
            if let originalStandard = originalStandard {
                UserDefaults.standard.set(originalStandard, forKey: key)
            }
        }

        XCTAssertEqual(BridgeModeStore.read(), .clipboard)
    }

    func testBridgeModeStoreRecoversFromCorruptValue() {
        let key = BridgeModeStore.key
        let originalShared = AppGroup.defaultsIfAvailable?.string(forKey: key)
        let originalStandard = UserDefaults.standard.string(forKey: key)
        AppGroup.defaultsIfAvailable?.set("not_a_real_mode", forKey: key)
        UserDefaults.standard.set("not_a_real_mode", forKey: key)
        defer {
            if let originalShared {
                AppGroup.defaultsIfAvailable?.set(originalShared, forKey: key)
            } else {
                AppGroup.defaultsIfAvailable?.removeObject(forKey: key)
            }
            if let originalStandard {
                UserDefaults.standard.set(originalStandard, forKey: key)
            } else {
                UserDefaults.standard.removeObject(forKey: key)
            }
        }

        XCTAssertEqual(BridgeModeStore.read(), .clipboard)
    }

    // MARK: - Helpers

    private var allAvailabilities: [AppGroupAvailability] {
        [
            .available,
            .unavailable(reason: .suiteNotConfigurable),
            .unavailable(reason: .containerLookupFailed),
            .unavailable(reason: .entitlementMissing)
        ]
    }
}
