import CoreAudio
import Foundation

/// Detects a low-quality Bluetooth input device so the app can warn once
/// that recognition accuracy may suffer. Modeled on Chatterfly's
/// `keyVoiceBluetoothQualityAlertShown`: one persistent "already shown"
/// flag, so the alert fires at most once per device until reset.
///
/// A Bluetooth input running the HFP (hands-free) profile captures at
/// 8/16 kHz, which degrades ASR accuracy noticeably versus the 48 kHz A2DP
/// capture path. The sample-rate threshold separates the two.
struct BluetoothInputDeviceQuality: Sendable, Equatable {
    let transportType: UInt32
    let sampleRate: Double

    /// `kAudioDeviceTransportTypeBluetoothLE` (hands-free capture) or
    /// `kAudioDeviceTransportTypeBluetooth` (classic BR/EDR capture).
    static let bluetoothTransports: Set<UInt32> = [
        kAudioDeviceTransportTypeBluetooth,
        kAudioDeviceTransportTypeBluetoothLE,
    ]

    /// Sample rates at or below this value indicate HFP microphone capture
    /// rather than wideband capture.
    static let lowQualitySampleRateThreshold: Double = 24_000

    var isLowQualityBluetooth: Bool {
        Self.bluetoothTransports.contains(transportType)
            && sampleRate > 0
            && sampleRate <= Self.lowQualitySampleRateThreshold
    }
}

/// Pure decision core over `BluetoothInputDeviceQuality`: should the app
/// show the quality hint now, and should it stay silent afterwards.
struct BluetoothQualityHintPolicy: Sendable {
    /// Whether the one-time hint has already been shown (persisted).
    let hasShownHint: Bool

    func shouldShowHint(for quality: BluetoothInputDeviceQuality) -> Bool {
        quality.isLowQualityBluetooth && !hasShownHint
    }
}

/// Observes the default input device and reports low-quality Bluetooth
/// capture. All CoreAudio access is injectable for testing.
@MainActor
final class BluetoothInputDeviceQualityChecker {
    private static let logger = AppLogger.audio

    typealias DeviceQualityProvider = @Sendable () -> BluetoothInputDeviceQuality?

    private let provideDeviceQuality: DeviceQualityProvider
    private let hasShownHint: () -> Bool
    private let setHasShownHint: (Bool) -> Void

    init(
        provideDeviceQuality: @escaping DeviceQualityProvider,
        hasShownHint: @escaping () -> Bool,
        setHasShownHint: @escaping (Bool) -> Void
    ) {
        self.provideDeviceQuality = provideDeviceQuality
        self.hasShownHint = hasShownHint
        self.setHasShownHint = setHasShownHint
    }

    /// Evaluates the current input device and returns whether the one-time
    /// low-quality hint should be surfaced. Marks the hint as shown when it
    /// fires so it never repeats.
    func evaluateForRecordingStart() -> Bool {
        guard let quality = provideDeviceQuality() else {
            Self.logger.debug("Bluetooth quality check skipped: no input device quality available")
            return false
        }
        let policy = BluetoothQualityHintPolicy(hasShownHint: hasShownHint())
        guard policy.shouldShowHint(for: quality) else {
            return false
        }
        setHasShownHint(true)
        Self.logger.info("Bluetooth input device is low quality (sampleRate=\(quality.sampleRate)), showing one-time hint")
        return true
    }

    // MARK: - Live CoreAudio probe

    /// Reads the default input device's transport type and nominal sample
    /// rate through CoreAudio. Returns nil when no device is present or the
    /// properties cannot be read.
    nonisolated static func liveDeviceQuality() -> BluetoothInputDeviceQuality? {
        var defaultInputAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var device = AudioObjectID(kAudioObjectUnknown)
        var deviceSize = UInt32(MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &defaultInputAddress,
            0,
            nil,
            &deviceSize,
            &device
        ) == noErr, device != kAudioObjectUnknown else {
            return nil
        }

        var transportAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyTransportType,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var transportType: UInt32 = 0
        var transportSize = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(
            device,
            &transportAddress,
            0,
            nil,
            &transportSize,
            &transportType
        ) == noErr else {
            return nil
        }

        var rateAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyNominalSampleRate,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var sampleRate: Float64 = 0
        var rateSize = UInt32(MemoryLayout<Float64>.size)
        guard AudioObjectGetPropertyData(
            device,
            &rateAddress,
            0,
            nil,
            &rateSize,
            &sampleRate
        ) == noErr else {
            return nil
        }

        return BluetoothInputDeviceQuality(transportType: transportType, sampleRate: sampleRate)
    }
}
