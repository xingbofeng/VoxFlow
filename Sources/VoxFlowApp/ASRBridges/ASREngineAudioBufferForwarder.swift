@preconcurrency import AVFoundation
import Foundation
import VoxFlowASRRuntime
import VoxFlowAudio

protocol ASREngineAudioFrameForwarding: AnyObject, Sendable {
    func attach(_ engine: ASREngine)
    func detach()
    func appendAudioFrame(_ frame: AudioFrame)
    func appendAudioBuffer(_ buffer: AVAudioPCMBuffer)
    func finish()
}

final class ASREngineAudioFrameForwarder: ASREngineAudioFrameForwarding, @unchecked Sendable {
    private let lock = NSLock()
    private let makeConverter: @Sendable () throws -> any AudioPCMConverting
    private let currentInstant: @Sendable () -> ContinuousClock.Instant
    private var engine: ASREngine?
    private var converter: (any AudioPCMConverting)?
    private var nextSequenceNumber: UInt64 = 0
    private var nextStartSample: UInt64 = 0
    private var isFinished = false

    init(
        makeConverter: @escaping @Sendable () throws -> any AudioPCMConverting = {
            try PersistentAudioConverter()
        },
        currentInstant: @escaping @Sendable () -> ContinuousClock.Instant = {
            ContinuousClock.now
        }
    ) {
        self.makeConverter = makeConverter
        self.currentInstant = currentInstant
    }

    func attach(_ engine: ASREngine) {
        lock.withLock {
            self.engine = engine
            resetCaptureState()
        }
    }

    func detach() {
        lock.withLock {
            engine = nil
            resetCaptureState()
        }
    }

    func appendAudioFrame(_ frame: AudioFrame) {
        let currentEngine = lock.withLock {
            isFinished ? nil : engine
        }
        currentEngine?.appendAudioFrame(frame)
    }

    func appendAudioBuffer(_ buffer: AVAudioPCMBuffer) {
        do {
            guard let pendingFrame = try makeFrame(from: buffer) else { return }
            pendingFrame.engine.appendAudioFrame(pendingFrame.frame)
        } catch {
            AppLogger.audio.error("ASR audio frame conversion failed: \(error.localizedDescription)")
        }
    }

    func finish() {
        do {
            guard let pendingFrame = try makeTailFrame() else { return }
            pendingFrame.engine.appendAudioFrame(pendingFrame.frame)
        } catch {
            AppLogger.audio.error("ASR audio frame flush failed: \(error.localizedDescription)")
        }
    }

    private func makeFrame(from buffer: AVAudioPCMBuffer) throws -> (engine: ASREngine, frame: AudioFrame)? {
        lock.lock()
        defer { lock.unlock() }

        guard !isFinished,
              let engine else { return nil }
        let samples = try convertSamples(from: buffer)
        guard !samples.isEmpty,
              let converter else { return nil }

        return (engine, nextFrame(
            samples: samples,
            sampleRate: Int(converter.targetSampleRate)
        ))
    }

    /// `PersistentAudioConverter` 锁定会话首个 buffer 的源格式，之后遇到不同格式（录音中切换
    /// 输入设备，采样率/声道数变了）会拒绝转换。这里重建转换器重试一次——重建只会丢掉旧转换器
    /// 滤波器尾巴里几毫秒的样本，而放着不管会把切换设备之后的整段录音全部丢掉。
    private func convertSamples(from buffer: AVAudioPCMBuffer) throws -> ContiguousArray<Float> {
        do {
            return try currentConverter().convert(buffer)
        } catch PersistentAudioConverterError.sourceFormatChanged {
            let format = buffer.format
            converter = nil
            AppLogger.audio.warning(
                "ASR source format changed mid-session; rebuilding converter sampleRate=\(format.sampleRate) channels=\(format.channelCount)"
            )
            return try currentConverter().convert(buffer)
        }
    }

    private func makeTailFrame() throws -> (engine: ASREngine, frame: AudioFrame)? {
        lock.lock()
        defer { lock.unlock() }

        guard !isFinished,
              let engine,
              let converter else {
            isFinished = true
            return nil
        }
        isFinished = true
        let samples = try converter.finish()
        guard !samples.isEmpty else { return nil }

        return (engine, nextFrame(
            samples: samples,
            sampleRate: Int(converter.targetSampleRate)
        ))
    }

    private func currentConverter() throws -> any AudioPCMConverting {
        if let converter {
            return converter
        }
        let converter = try makeConverter()
        self.converter = converter
        return converter
    }

    private func nextFrame(
        samples: ContiguousArray<Float>,
        sampleRate: Int
    ) -> AudioFrame {
        let frame = AudioFrame(
            sequenceNumber: nextSequenceNumber,
            startSample: nextStartSample,
            samples: samples,
            sampleRate: sampleRate,
            capturedAt: currentInstant()
        )
        nextSequenceNumber += 1
        nextStartSample += UInt64(samples.count)
        return frame
    }

    private func resetCaptureState() {
        converter = nil
        nextSequenceNumber = 0
        nextStartSample = 0
        isFinished = false
    }
}
