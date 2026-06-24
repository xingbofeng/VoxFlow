import AVFoundation
import XCTest
@testable import VoxFlowApp

final class AudioRecorderTests: XCTestCase {
    func testVoiceEnhancementIsDisabledByDefault() {
        let recorder = AudioRecorder()

        XCTAssertFalse(recorder.voiceEnhancementEnabled)
    }

    func testSilenceProducesZeroNormalizedRMS() throws {
        let buffer = try makeBuffer(samples: [0, 0, 0, 0])

        XCTAssertEqual(AudioRecorder.calculateRMS(from: buffer), 0, accuracy: 0.0001)
    }

    func testFullScaleSignalProducesMaximumNormalizedRMS() throws {
        let buffer = try makeBuffer(samples: [1, -1, 1, -1])

        XCTAssertEqual(AudioRecorder.calculateRMS(from: buffer), 1, accuracy: 0.0001)
    }

    func testVoiceEnhancementBoostsQuietSpeechButLeavesSilenceAndLoudAudioStable() {
        XCTAssertEqual(AudioRecorder.voiceEnhancementGain(normalizedRMS: 0), 1)
        XCTAssertGreaterThan(AudioRecorder.voiceEnhancementGain(normalizedRMS: 0.15), 1)
        XCTAssertEqual(AudioRecorder.voiceEnhancementGain(normalizedRMS: 0.6), 1)
        XCTAssertLessThanOrEqual(AudioRecorder.voiceEnhancementGain(normalizedRMS: 0.01), 2.2)
    }

    func testInputFormatUsabilityRejectsMissingMicrophoneFormat() {
        XCTAssertFalse(AudioRecorder.isInputFormatUsable(sampleRate: 0, channelCount: 1))
        XCTAssertFalse(AudioRecorder.isInputFormatUsable(sampleRate: 44_100, channelCount: 0))
        XCTAssertTrue(AudioRecorder.isInputFormatUsable(sampleRate: 44_100, channelCount: 1))
    }

    func testStartWithoutUsableInputDeviceThrowsBeforeStartingRecording() {
        let recorder = AudioRecorder(
            permissionStatus: { .granted },
            inputDeviceAvailability: { false }
        )

        XCTAssertThrowsError(try recorder.start()) { error in
            XCTAssertEqual(
                error as? AudioRecorder.AudioRecorderError,
                .microphoneUnavailable
            )
        }
        XCTAssertFalse(recorder.isRecording)
    }

    func testUnavailableMicrophoneErrorExplainsHowToRecover() {
        XCTAssertEqual(
            AudioRecorder.AudioRecorderError.microphoneUnavailable.errorDescription,
            "未检测到可用麦克风。请连接或启用一个输入设备后重试。"
        )
    }

    func testObjectiveCExceptionDuringTapInstallationIsConvertedToFailure() {
        let succeeded = AudioRecorder.performCatchingObjectiveCException {
            NSException(
                name: .internalInconsistencyException,
                reason: "Simulated AVAudioEngine tap failure"
            ).raise()
        }

        XCTAssertFalse(succeeded)
    }

    func testCopyBufferPreservesSamplesWhenOriginalIsReused() throws {
        let original = try makeBuffer(samples: [0.1, 0.2, 0.3, 0.4])

        let copy = try XCTUnwrap(AudioRecorder.copyBuffer(original))
        let originalSamples = try XCTUnwrap(original.floatChannelData?[0])
        for index in 0..<4 {
            originalSamples[index] = 0
        }

        let copiedSamples = try XCTUnwrap(copy.floatChannelData?[0])
        XCTAssertEqual(copiedSamples[0], 0.1, accuracy: 0.0001)
        XCTAssertEqual(copiedSamples[1], 0.2, accuracy: 0.0001)
        XCTAssertEqual(copiedSamples[2], 0.3, accuracy: 0.0001)
        XCTAssertEqual(copiedSamples[3], 0.4, accuracy: 0.0001)
    }

    func testCapturedAudioIsDeliveredThroughInjectedDispatcherAfterCopying() throws {
        let dispatcher = AudioRecorderDispatchProbe()
        let recorder = AudioRecorder(eventDispatcher: dispatcher.makeDispatcher())
        let delegate = AudioRecorderDelegateProbe()
        recorder.delegate = delegate
        let original = try makeBuffer(samples: [0.1, 0.2, 0.3, 0.4])

        recorder.processCapturedBuffer(original)
        let originalSamples = try XCTUnwrap(original.floatChannelData?[0])
        for index in 0..<4 {
            originalSamples[index] = 0
        }

        XCTAssertEqual(dispatcher.pendingActionCount, 1)
        XCTAssertTrue(delegate.receivedBuffers.isEmpty)
        XCTAssertTrue(delegate.receivedRMSValues.isEmpty)

        dispatcher.runNext()

        XCTAssertEqual(delegate.receivedRMSValues.count, 1)
        let copiedSamples = try XCTUnwrap(delegate.receivedBuffers.first?.floatChannelData?[0])
        XCTAssertEqual(copiedSamples[0], 0.1, accuracy: 0.0001)
        XCTAssertEqual(copiedSamples[1], 0.2, accuracy: 0.0001)
        XCTAssertEqual(copiedSamples[2], 0.3, accuracy: 0.0001)
        XCTAssertEqual(copiedSamples[3], 0.4, accuracy: 0.0001)
    }

    func testDrainFlushesPendingAudioQueueEvents() throws {
        let recorder = AudioRecorder(eventDispatcher: .audioQueue(
            label: "com.voxflow.app.audio-recorder-events.tests.\(UUID().uuidString)"
        ))
        let delegate = AudioRecorderDelegateProbe()
        recorder.delegate = delegate

        recorder.processCapturedBuffer(try makeBuffer(samples: [0.1, 0.2]))
        recorder.drain()

        XCTAssertEqual(delegate.receivedBuffers.count, 1)
        XCTAssertEqual(delegate.receivedRMSValues.count, 1)
    }

    private func makeBuffer(samples: [Float]) throws -> AVAudioPCMBuffer {
        let format = try XCTUnwrap(
            AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)
        )
        let buffer = try XCTUnwrap(
            AVAudioPCMBuffer(
                pcmFormat: format,
                frameCapacity: AVAudioFrameCount(samples.count)
            )
        )
        buffer.frameLength = AVAudioFrameCount(samples.count)
        let channel = try XCTUnwrap(buffer.floatChannelData?[0])
        for (index, sample) in samples.enumerated() {
            channel[index] = sample
        }
        return buffer
    }
}

private final class AudioRecorderDispatchProbe: @unchecked Sendable {
    private var actions: [@Sendable () -> Void] = []

    var pendingActionCount: Int {
        actions.count
    }

    func makeDispatcher() -> AudioRecorder.EventDispatcher {
        AudioRecorder.EventDispatcher { [weak self] action in
            self?.actions.append(action)
        }
    }

    func runNext() {
        guard !actions.isEmpty else { return }
        actions.removeFirst()()
    }
}

private final class AudioRecorderDelegateProbe: AudioRecorder.Delegate {
    private(set) var receivedBuffers: [AVAudioPCMBuffer] = []
    private(set) var receivedRMSValues: [Float] = []

    func audioRecorder(_ recorder: AudioRecorder, didReceiveBuffer buffer: AVAudioPCMBuffer) {
        receivedBuffers.append(buffer)
    }

    func audioRecorder(_ recorder: AudioRecorder, didUpdateRMS rms: Float) {
        receivedRMSValues.append(rms)
    }
}
