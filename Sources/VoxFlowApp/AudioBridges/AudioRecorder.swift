@preconcurrency import AVFoundation
import CoreAudio
import Foundation
import VoxFlowObjCExceptionSupport

protocol AudioInputNodeControlling: AnyObject {
    func outputFormat(forBus bus: AVAudioNodeBus) -> AVAudioFormat
    func installTap(
        onBus bus: AVAudioNodeBus,
        bufferSize: AVAudioFrameCount,
        format: AVAudioFormat?,
        block: @escaping AVAudioNodeTapBlock
    )
    func removeTap(onBus bus: AVAudioNodeBus)
}

protocol AudioEngineControlling: AnyObject {
    var inputNode: any AudioInputNodeControlling { get }

    func prepare()
    func start() throws
    func stop()
    func reset()
}

private final class LiveAudioInputNodeController: AudioInputNodeControlling {
    private let node: AVAudioInputNode

    init(node: AVAudioInputNode) {
        self.node = node
    }

    func outputFormat(forBus bus: AVAudioNodeBus) -> AVAudioFormat {
        node.outputFormat(forBus: bus)
    }

    func installTap(
        onBus bus: AVAudioNodeBus,
        bufferSize: AVAudioFrameCount,
        format: AVAudioFormat?,
        block: @escaping AVAudioNodeTapBlock
    ) {
        node.installTap(onBus: bus, bufferSize: bufferSize, format: format, block: block)
    }

    func removeTap(onBus bus: AVAudioNodeBus) {
        node.removeTap(onBus: bus)
    }
}

private final class LiveAudioEngineController: AudioEngineControlling {
    private let engine = AVAudioEngine()
    private lazy var liveInputNode = LiveAudioInputNodeController(node: engine.inputNode)

    var inputNode: any AudioInputNodeControlling {
        liveInputNode
    }

    func prepare() {
        engine.prepare()
    }

    func start() throws {
        try engine.start()
    }

    func stop() {
        engine.stop()
    }

    func reset() {
        engine.reset()
    }
}

/// Manages audio capture from the default microphone with real-time RMS level metering.
final class AudioRecorder: NSObject, @unchecked Sendable {
    // MARK: - Types

    protocol Delegate: AnyObject {
        func audioRecorder(_ recorder: AudioRecorder, didReceiveBuffer buffer: AVAudioPCMBuffer)
        func audioRecorder(_ recorder: AudioRecorder, didUpdateRMS rms: Float)
        /// The capture device changed (or vanished) mid-recording and the
        /// recorder could not recover automatically. Optional; the recorder
        /// has already stopped itself cleanly.
        func audioRecorderDidBecomeUnavailable(_ recorder: AudioRecorder)
    }

    struct EventDispatcher: Sendable {
        private let dispatchAction: @Sendable (@escaping @Sendable () -> Void) -> Void
        private let drainAction: @Sendable () -> Void

        init(
            _ dispatchAction: @escaping @Sendable (@escaping @Sendable () -> Void) -> Void,
            drain: @escaping @Sendable () -> Void = {}
        ) {
            self.dispatchAction = dispatchAction
            drainAction = drain
        }

        func dispatch(_ action: @escaping @Sendable () -> Void) {
            dispatchAction(action)
        }

        func drain() {
            drainAction()
        }

        static func audioQueue(
            label: String = "com.voxflow.app.audio-recorder-events"
        ) -> EventDispatcher {
            let queue = DispatchQueue(label: label, qos: .userInitiated)
            return EventDispatcher(
                { action in
                    queue.async(execute: action)
                },
                drain: {
                    queue.sync {}
                }
            )
        }
    }

    struct SendableBuffer: @unchecked Sendable {
        let buffer: AVAudioPCMBuffer
    }

    enum PermissionStatus: String, Equatable {
        case granted
        case denied
        case notDetermined
    }

    enum AudioRecorderError: Error, Equatable, LocalizedError {
        case microphonePermissionDenied
        case microphoneUnavailable

        var errorDescription: String? {
            switch self {
            case .microphonePermissionDenied:
                return String(
                    L10n.localize("audio_recorder.error.microphone_permission_denied", comment: "Microphone permission denied")
                )
            case .microphoneUnavailable:
                return String(
                    L10n.localize("audio.recorder.error.microphone_unavailable", comment: "No available microphone error message")
                )
            }
        }
    }

    // MARK: - Properties

    private let engine: any AudioEngineControlling
    private let eventDispatcher: EventDispatcher
    private let permissionStatus: @Sendable () -> PermissionStatus
    private let inputDeviceAvailability: @Sendable () -> Bool
    private let lifecycleLock = NSLock()
    private(set) var isRecording = false
    var voiceEnhancementEnabled = false
    weak var delegate: Delegate?

    init(
        engine: any AudioEngineControlling = LiveAudioEngineController(),
        eventDispatcher: EventDispatcher = .audioQueue(),
        permissionStatus: @escaping @Sendable () -> PermissionStatus = AudioRecorder.checkPermission,
        inputDeviceAvailability: @escaping @Sendable () -> Bool = AudioRecorder.hasUsableSystemInputDevice
    ) {
        self.engine = engine
        self.eventDispatcher = eventDispatcher
        self.permissionStatus = permissionStatus
        self.inputDeviceAvailability = inputDeviceAvailability
        super.init()
    }

    // MARK: - Permission

    static func checkPermission() -> PermissionStatus {
        if #available(macOS 14.0, *) {
            switch AVAudioApplication.shared.recordPermission {
            case .granted: return .granted
            case .denied: return .denied
            case .undetermined: return .notDetermined
            @unknown default: return .notDetermined
            }
        }
        return .granted
    }

    static func requestPermission() async -> Bool {
        await withCheckedContinuation { continuation in
            #if os(macOS)
            if #available(macOS 14.0, *) {
                AVAudioApplication.requestRecordPermission { granted in
                    continuation.resume(returning: granted)
                }
            } else {
                continuation.resume(returning: true)
            }
            #endif
        }
    }

    // MARK: - Lifecycle

    func start() throws {
        lifecycleLock.lock()
        defer { lifecycleLock.unlock() }

        guard !isRecording else {
            AppLogger.audio.debug("AudioRecorder start skipped: already recording")
            return
        }
        guard permissionStatus() == .granted else {
            AppLogger.audio.error("AudioRecorder start failed: microphone permission denied")
            throw AudioRecorderError.microphonePermissionDenied
        }
        guard inputDeviceAvailability() else {
            AppLogger.audio.error("AudioRecorder start failed: no usable input device")
            throw AudioRecorderError.microphoneUnavailable
        }

        let inputNode = engine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)
        AppLogger.audio.debug("AudioRecorder start sampleRate=\(inputFormat.sampleRate) channels=\(inputFormat.channelCount)")
        guard Self.isInputFormatUsable(
            sampleRate: inputFormat.sampleRate,
            channelCount: inputFormat.channelCount
        ) else {
            AppLogger.audio.error("AudioRecorder start failed: invalid input format")
            throw AudioRecorderError.microphoneUnavailable
        }

        let tapInstalled = Self.performCatchingObjectiveCException {
            inputNode.installTap(onBus: 0, bufferSize: 1024, format: inputFormat) { [weak self] buffer, _ in
                self?.processCapturedBuffer(buffer)
            }
        }
        guard tapInstalled else {
            AppLogger.audio.error("AudioRecorder start failed: input tap installation raised an exception")
            throw AudioRecorderError.microphoneUnavailable
        }

        do {
            engine.prepare()
            try engine.start()
            isRecording = true
        } catch {
            engine.stop()
            inputNode.removeTap(onBus: 0)
            engine.reset()
            if permissionStatus() != .granted {
                AppLogger.audio.error("AudioRecorder start failed: microphone permission denied")
                throw AudioRecorderError.microphonePermissionDenied
            }
            AppLogger.audio.error("AudioRecorder start failed: microphone unavailable")
            throw AudioRecorderError.microphoneUnavailable
        }
        AppLogger.audio.notice(
            "AudioRecorder started sampleRate=\(inputFormat.sampleRate) channels=\(inputFormat.channelCount)"
        )
    }

    static func performCatchingObjectiveCException(_ action: () -> Void) -> Bool {
        VoxFlowPerformCatchingException(action)
    }

    static func hasUsableSystemInputDevice() -> Bool {
        var defaultInputAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var device = AudioObjectID(kAudioObjectUnknown)
        var deviceSize = UInt32(MemoryLayout<AudioObjectID>.size)
        let deviceStatus = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &defaultInputAddress,
            0,
            nil,
            &deviceSize,
            &device
        )
        guard deviceStatus == noErr, device != kAudioObjectUnknown else {
            return false
        }

        var aliveAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceIsAlive,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var isAlive: UInt32 = 0
        var aliveSize = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(
            device,
            &aliveAddress,
            0,
            nil,
            &aliveSize,
            &isAlive
        ) == noErr, isAlive != 0 else {
            return false
        }

        var streamsAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreams,
            mScope: kAudioDevicePropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )
        var streamsSize: UInt32 = 0
        let streamsStatus = AudioObjectGetPropertyDataSize(
            device,
            &streamsAddress,
            0,
            nil,
            &streamsSize
        )
        return streamsStatus == noErr
            && streamsSize >= UInt32(MemoryLayout<AudioStreamID>.size)
    }

    static func isInputFormatUsable(sampleRate: Double, channelCount: AVAudioChannelCount) -> Bool {
        sampleRate.isFinite && sampleRate > 0 && channelCount > 0
    }

    func stop() {
        lifecycleLock.lock()
        defer { lifecycleLock.unlock() }

        guard isRecording else { return }
        isRecording = false
        engine.stop()
        engine.inputNode.removeTap(onBus: 0)
        engine.reset()
        AppLogger.audio.debug("AudioRecorder stopped")
    }

    /// Observes `AVAudioEngineConfigurationChange` so capture follows the new
    /// default input device. The returned token stays registered until the
    /// caller removes it.
    ///
    /// AVAudioEngine posts this notification on its own internal queue, so the
    /// observer has to hop through `queue: .main`: the restart below touches
    /// engine lifecycle state and must not run on the posting thread.
    func observeConfigurationChanges(in center: NotificationCenter = .default) -> NSObjectProtocol {
        center.addObserver(
            forName: .AVAudioEngineConfigurationChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.handleAudioEngineConfigurationChange()
        }
    }

    /// Reacts to an AVAudioEngineConfigurationChange notification: the input
    /// device changed (or vanished) while recording. Restarting the engine
    /// re-attaches to the system's new default input device, so an in-flight
    /// dictation keeps capturing instead of silently dying. The pre-change
    /// audio stays in the ASR pipeline; the restart only affects future
    /// frames.
    func handleAudioEngineConfigurationChange() {
        lifecycleLock.lock()
        guard isRecording else {
            lifecycleLock.unlock()
            return
        }
        let previousFormat = engine.inputNode.outputFormat(forBus: 0)
        lifecycleLock.unlock()

        AppLogger.audio.notice(
            "AudioRecorder input configuration changed; restarting capture fromRate=\(previousFormat.sampleRate) fromChannels=\(previousFormat.channelCount)"
        )
        stop()

        do {
            try start()
        } catch {
            AppLogger.audio.error("AudioRecorder restart after device change failed: \(error.localizedDescription)")
            eventDispatcher.dispatch { [weak self] in
                guard let self else { return }
                self.delegate?.audioRecorderDidBecomeUnavailable(self)
            }
        }
    }

    func drain() {
        AppLogger.audio.debug("AudioRecorder drain")
        eventDispatcher.drain()
    }

    // MARK: - RMS Calculation

    static func calculateRMS(from buffer: AVAudioPCMBuffer) -> Float {
        guard let channelData = buffer.floatChannelData else { return 0.0 }

        let frameLength = Int(buffer.frameLength)
        guard frameLength > 0 else { return 0.0 }

        let samples = channelData[0]
        var sum: Float = 0.0

        // Process in chunks for better cache utilization
        let strideCount = frameLength / 4
        for i in 0..<strideCount {
            let idx = i * 4
            sum += samples[idx] * samples[idx]
            sum += samples[idx + 1] * samples[idx + 1]
            sum += samples[idx + 2] * samples[idx + 2]
            sum += samples[idx + 3] * samples[idx + 3]
        }

        // Handle remainder
        let remainder = frameLength - (strideCount * 4)
        for i in 0..<remainder {
            let sample = samples[strideCount * 4 + i]
            sum += sample * sample
        }

        let mean = sum / Float(frameLength)
        let rms = sqrt(mean)

        // Convert to dB and normalize to 0...1 range
        // RMS floor is around -60 dB for silence
        let db = 20.0 * log10(max(rms, 1e-6))
        let normalized = max(0.0, min(1.0, (db + 50.0) / 50.0))
        return normalized
    }

    static func voiceEnhancementGain(normalizedRMS: Float) -> Float {
        guard normalizedRMS > 0, normalizedRMS < 0.45 else { return 1 }
        return min(2.2, max(1, 0.35 / max(normalizedRMS, 0.05)))
    }

    static func copyBuffer(_ buffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        guard let copy = AVAudioPCMBuffer(
            pcmFormat: buffer.format,
            frameCapacity: buffer.frameLength
        ) else {
            return nil
        }
        copy.frameLength = buffer.frameLength

        guard let sourceChannels = buffer.floatChannelData,
              let destinationChannels = copy.floatChannelData else {
            return nil
        }

        let frameCount = Int(buffer.frameLength)
        let channelCount = Int(buffer.format.channelCount)
        for channelIndex in 0..<channelCount {
            destinationChannels[channelIndex].update(
                from: sourceChannels[channelIndex],
                count: frameCount
            )
        }

        return copy
    }

    func processCapturedBuffer(_ buffer: AVAudioPCMBuffer) {
        let rms = Self.calculateRMS(from: buffer)
        if voiceEnhancementEnabled {
            Self.applyVoiceEnhancement(to: buffer, normalizedRMS: rms)
        }
        let copiedBuffer = Self.copyBuffer(buffer).map(SendableBuffer.init(buffer:))
        if copiedBuffer == nil {
            AppLogger.audio.error("AudioRecorder: failed to copy input buffer before dispatch")
        }

        eventDispatcher.dispatch { [weak self, copiedBuffer, rms] in
            guard let self else { return }
            if let copiedBuffer {
                self.delegate?.audioRecorder(self, didReceiveBuffer: copiedBuffer.buffer)
            }
            self.delegate?.audioRecorder(self, didUpdateRMS: rms)
        }
    }

    private static func applyVoiceEnhancement(
        to buffer: AVAudioPCMBuffer,
        normalizedRMS: Float
    ) {
        let gain = voiceEnhancementGain(normalizedRMS: normalizedRMS)
        guard gain > 1, let channels = buffer.floatChannelData else { return }

        let frameCount = Int(buffer.frameLength)
        let channelCount = Int(buffer.format.channelCount)
        for channelIndex in 0..<channelCount {
            let channel = channels[channelIndex]
            for sampleIndex in 0..<frameCount {
                channel[sampleIndex] = tanh(channel[sampleIndex] * gain)
            }
        }
    }
}

extension AudioRecorder.Delegate {
    func audioRecorderDidBecomeUnavailable(_ recorder: AudioRecorder) {}
}
