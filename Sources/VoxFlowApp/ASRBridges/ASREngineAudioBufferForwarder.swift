@preconcurrency import AVFoundation
import Foundation
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
        let converter = try currentConverter()
        let samples = try converter.convert(buffer)
        guard !samples.isEmpty else { return nil }

        return (engine, nextFrame(
            samples: samples,
            sampleRate: Int(converter.targetSampleRate)
        ))
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
