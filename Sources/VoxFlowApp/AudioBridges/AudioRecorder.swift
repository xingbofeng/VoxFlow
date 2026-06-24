@preconcurrency import AVFoundation
import Foundation

/// Manages audio capture from the default microphone with real-time RMS level metering.
final class AudioRecorder: NSObject, @unchecked Sendable {
    // MARK: - Types

    protocol Delegate: AnyObject {
        func audioRecorder(_ recorder: AudioRecorder, didReceiveBuffer buffer: AVAudioPCMBuffer)
        func audioRecorder(_ recorder: AudioRecorder, didUpdateRMS rms: Float)
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

    enum AudioRecorderError: Error, LocalizedError {
        case microphoneUnavailable

        var errorDescription: String? {
            "麦克风不可用。请检查系统权限设置。"
        }
    }

    // MARK: - Properties

    private let engine = AVAudioEngine()
    private let eventDispatcher: EventDispatcher
    private(set) var isRecording = false
    var voiceEnhancementEnabled = false
    weak var delegate: Delegate?

    init(eventDispatcher: EventDispatcher = .audioQueue()) {
        self.eventDispatcher = eventDispatcher
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
        guard !isRecording else {
            AppLogger.audio.debug("AudioRecorder start skipped: already recording")
            return
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

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: inputFormat) { [weak self] buffer, _ in
            self?.processCapturedBuffer(buffer)
        }

        do {
            engine.prepare()
            try engine.start()
            isRecording = true
        } catch {
            inputNode.removeTap(onBus: 0)
            engine.stop()
            AppLogger.audio.error("AudioRecorder start failed: microphoneUnavailable")
            throw AudioRecorderError.microphoneUnavailable
        }
        AppLogger.audio.info("AudioRecorder started")
    }

    static func isInputFormatUsable(sampleRate: Double, channelCount: AVAudioChannelCount) -> Bool {
        sampleRate.isFinite && sampleRate > 0 && channelCount > 0
    }

    func stop() {
        guard isRecording else { return }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        engine.reset()
        isRecording = false
        AppLogger.audio.debug("AudioRecorder stopped")
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
