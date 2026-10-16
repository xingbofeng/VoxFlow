import CoreAudio
import XCTest
@testable import VoxFlowApp

final class BluetoothInputDeviceQualityCheckerTests: XCTestCase {
    // MARK: - Quality classification

    func testLowQualityBluetoothIsHFPProfileSampleRate() {
        // HFP hands-free capture: 16 kHz over Bluetooth LE.
        let hfp = BluetoothInputDeviceQuality(transportType: kAudioDeviceTransportTypeBluetoothLE, sampleRate: 16_000)
        XCTAssertTrue(hfp.isLowQualityBluetooth)
        // Classic Bluetooth at 8 kHz (narrowband HFP).
        let narrowband = BluetoothInputDeviceQuality(transportType: kAudioDeviceTransportTypeBluetooth, sampleRate: 8_000)
        XCTAssertTrue(narrowband.isLowQualityBluetooth)
    }

    func testWidebandBluetoothIsNotLowQuality() {
        // 48 kHz capture is the A2DP-grade path — no hint.
        let wideband = BluetoothInputDeviceQuality(transportType: kAudioDeviceTransportTypeBluetoothLE, sampleRate: 48_000)
        XCTAssertFalse(wideband.isLowQualityBluetooth)
    }

    func testBuiltInMicIsNeverLowQuality() {
        // Built-in mic transport ('usb ' style builtin values differ from bluetooth).
        let builtin = BluetoothInputDeviceQuality(transportType: 0x75736220, sampleRate: 48_000)
        XCTAssertFalse(builtin.isLowQualityBluetooth)
        // Even a builtin misreported at 16 kHz stays silent — transport gate first.
        let odd = BluetoothInputDeviceQuality(transportType: 0x75736220, sampleRate: 16_000)
        XCTAssertFalse(odd.isLowQualityBluetooth)
    }

    func testZeroSampleRateIsNeverLowQuality() {
        let unreadable = BluetoothInputDeviceQuality(transportType: kAudioDeviceTransportTypeBluetoothLE, sampleRate: 0)
        XCTAssertFalse(unreadable.isLowQualityBluetooth)
    }

    // MARK: - One-time hint policy

    func testPolicyShowsHintOnce() {
        let first = BluetoothQualityHintPolicy(hasShownHint: false)
        XCTAssertTrue(first.shouldShowHint(for: BluetoothInputDeviceQuality(transportType: kAudioDeviceTransportTypeBluetoothLE, sampleRate: 16_000)))

        let after = BluetoothQualityHintPolicy(hasShownHint: true)
        XCTAssertFalse(after.shouldShowHint(for: BluetoothInputDeviceQuality(transportType: kAudioDeviceTransportTypeBluetoothLE, sampleRate: 16_000)))
    }

    func testPolicyStaysSilentForGoodDevice() {
        let policy = BluetoothQualityHintPolicy(hasShownHint: false)
        XCTAssertFalse(policy.shouldShowHint(for: BluetoothInputDeviceQuality(transportType: kAudioDeviceTransportTypeBluetoothLE, sampleRate: 48_000)))
    }

    // MARK: - Evaluator (recording-start entry point)

    @MainActor
    func testEvaluateFiresOnceAndPersistsShownFlag() {
        let quality = BluetoothInputDeviceQuality(transportType: kAudioDeviceTransportTypeBluetoothLE, sampleRate: 16_000)
        var shown = false
        var persistedShown: [Bool] = []
        let checker = BluetoothInputDeviceQualityChecker(
            provideDeviceQuality: { quality },
            hasShownHint: { shown },
            setHasShownHint: { shown = $0; persistedShown.append($0) }
        )

        XCTAssertTrue(checker.evaluateForRecordingStart(), "First low-quality recording start shows the hint")
        XCTAssertTrue(persistedShown == [true], "Shown flag must be persisted when the hint fires")
        XCTAssertFalse(checker.evaluateForRecordingStart(), "Second start stays silent")
        XCTAssertTrue(persistedShown.count == 1, "No repeated persistence writes")
    }

    @MainActor
    func testEvaluateStaysSilentWhenNoDeviceQualityAvailable() {
        var shown = false
        let checker = BluetoothInputDeviceQualityChecker(
            provideDeviceQuality: { nil },
            hasShownHint: { shown },
            setHasShownHint: { shown = $0 }
        )

        XCTAssertFalse(checker.evaluateForRecordingStart())
        XCTAssertFalse(shown)
    }
}
