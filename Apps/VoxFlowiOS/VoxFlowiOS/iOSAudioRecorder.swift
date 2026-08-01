import Foundation
import AVFoundation
import VoxFlowAudio
import VoxFlowMobileCore

/// iOS V1 麦克风录制适配：`AVAudioSession` + `AVAudioEngine` 采集 PCM buffer，
/// 通过 `PersistentAudioConverter` 重采样为 16kHz mono Float32，组装为 `AudioFrame`。
///
/// 处理中断、权限拒绝、录音失败、停止与取消（task 3.1 / 3.3）。
///
/// 中断处理：
/// - `.began`：停止录音并通知调用方（通过 `onInterruption` 回调），由上层决定是否进入 failed 状态。
/// - `.ended`：恢复音频会话，不自动重启录音；V1 用户需手动重新点按开始。
///
/// 路由变化处理：
/// - 输入设备被拔出（例如耳机断开）时，停止录音，避免 AVAudioEngine 进入异常状态。
///
/// `setActive(false)` 错误不抛给调用方：会话停用失败通常是系统侧暂时性冲突，
/// 不影响本次录音数据完整性，仅记录到 `lastDeactivationError` 供诊断页展示。
final class iOSAudioRecorder: NSObject, MobileAudioRecording, @unchecked Sendable {
    private let lock = NSLock()
    private let converterLock = NSLock()
    private let engine = AVAudioEngine()
    private let converter: PersistentAudioConverter?
    private var onFrame: (@Sendable (AudioFrame) -> Void)?
    private var sequenceNumber: UInt64 = 0
    private var startSample: UInt64 = 0
    private var isRunning = false
    private var isTapInstalled = false
    private var didFinishConverter = false

    /// 中断回调（主线程）。`.began` 时触发，UI/会话层据此推进到 failed 或 idle。
    var onInterruption: (@Sendable () -> Void)?

    /// 路由变化导致录音终止的回调（主线程）。
    var onRouteChangeEnded: (@Sendable () -> Void)?

    /// 录音能量波形回调。用于 ClipboardBridge 主 App 页面展示真实麦克风音量。
    var onWaveform: (@Sendable ([Float]) -> Void)?

    /// 最近的会话停用错误，用于诊断页展示；nil 表示无错误或停用成功。
    private(set) var lastDeactivationError: String?

    override init() {
        converter = try? PersistentAudioConverter(targetSampleRate: 16_000)
        super.init()
        let center = NotificationCenter.default
        center.addObserver(
            self,
            selector: #selector(handleInterruption(_:)),
            name: AVAudioSession.interruptionNotification,
            object: nil
        )
        center.addObserver(
            self,
            selector: #selector(handleRouteChange(_:)),
            name: AVAudioSession.routeChangeNotification,
            object: nil
        )
    }

    deinit {
        stop()
        NotificationCenter.default.removeObserver(self)
    }

    func requestPermission() async throws -> Bool {
        switch AVAudioApplication.shared.recordPermission {
        case .granted:
            return true
        case .denied:
            return false
        case .undetermined:
            return await withCheckedContinuation { continuation in
                AVAudioApplication.requestRecordPermission { granted in
                    continuation.resume(returning: granted)
                }
            }
        @unknown default:
            return false
        }
    }

    func start(onFrame: @escaping @Sendable (AudioFrame) -> Void) throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .measurement, options: [.defaultToSpeaker, .allowBluetooth])
        try session.setActive(true, options: [])

        let inputFormat = engine.inputNode.outputFormat(forBus: 0)
        lock.withLock {
            self.onFrame = onFrame
            sequenceNumber = 0
            startSample = 0
            isRunning = true
            didFinishConverter = false
        }

        engine.inputNode.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { [weak self] buffer, _ in
            self?.process(buffer: buffer)
        }
        lock.withLock {
            isTapInstalled = true
        }
        try engine.start()
    }

    func stop() {
        let shouldDeactivateSession = lock.withLock { () -> Bool in
            let wasRunning = isRunning
            isRunning = false
            return wasRunning
        }
        if engine.isRunning {
            engine.stop()
        }
        let shouldRemoveTap = lock.withLock { isTapInstalled }
        if shouldRemoveTap {
            engine.inputNode.removeTap(onBus: 0)
            lock.withLock {
                isTapInstalled = false
            }
        }
        finishConverterIfNeeded()
        if shouldDeactivateSession {
            do {
                try AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
                lock.withLock { lastDeactivationError = nil }
            } catch {
                // 会话停用失败通常是系统侧暂时性冲突（例如其他 App 正在占用音频），
                // 不影响本次已采集数据。记录错误供诊断页展示。
                lock.withLock { lastDeactivationError = error.localizedDescription }
            }
        }
        lock.withLock {
            onFrame = nil
            onWaveform = nil
        }
    }

    // MARK: - Private

    private func process(buffer: AVAudioPCMBuffer) {
        guard buffer.floatChannelData?[0] != nil,
              let converter
        else { return }

        // 将原始 buffer 喂给 converter，由共享音频层统一转成 16kHz mono Float32。
        let converted: ContiguousArray<Float>
        do {
            converterLock.lock()
            defer { converterLock.unlock() }
            converted = try converter.convert(buffer)
        } catch {
            return
        }
        guard !converted.isEmpty else { return }

        let frame = AudioFrame(
            sequenceNumber: lock.withLock { sequenceNumber },
            startSample: lock.withLock { startSample },
            samples: converted,
            sampleRate: 16_000,
            capturedAt: ContinuousClock().now
        )
        lock.withLock {
            sequenceNumber &+= 1
            startSample &+= UInt64(converted.count)
        }
        let callback = lock.withLock { onFrame }
        callback?(frame)
        let waveformCallback = lock.withLock { onWaveform }
        waveformCallback?(Self.makeWaveform(from: Array(converted), targetCount: 30))
    }

    private func finishConverterIfNeeded() {
        let shouldFinish = lock.withLock { () -> Bool in
            guard !didFinishConverter else { return false }
            didFinishConverter = true
            return true
        }
        guard shouldFinish else { return }
        converterLock.lock()
        defer { converterLock.unlock() }
        _ = try? converter?.finish()
    }

    private static func makeWaveform(from samples: [Float], targetCount: Int) -> [Float] {
        guard targetCount > 0, !samples.isEmpty else { return [] }

        let bucketSize = max(1, samples.count / targetCount)
        return (0..<targetCount).map { index in
            let start = index * bucketSize
            let end = min(samples.count, start + bucketSize)
            guard start < end else { return 0 }

            var sumSquares: Float = 0
            for sample in samples[start..<end] {
                sumSquares += sample * sample
            }
            let rms = sqrt(sumSquares / Float(end - start))
            return min(1, max(0, rms * 18))
        }
    }

    @objc private func handleInterruption(_ notification: Notification) {
        guard let info = notification.userInfo,
              let typeValue = info[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue) else {
            return
        }
        switch type {
        case .began:
            // 系统中断（电话、Siri、闹钟等）：停止录音并通知上层。
            // V1 不在中断结束后自动恢复录音，避免在没有用户意图的情况下重启音频会话。
            stop()
            onInterruption?()
        case .ended:
            // 中断结束：恢复音频会话激活状态，但不自动重启 engine；
            // 用户需重新点按开始按钮。V1 不做 .shouldResume 自动续录。
            do {
                try AVAudioSession.sharedInstance().setActive(true, options: [])
            } catch {
                lock.withLock { lastDeactivationError = error.localizedDescription }
            }
        @unknown default:
            break
        }
    }

    @objc private func handleRouteChange(_ notification: Notification) {
        guard let info = notification.userInfo,
              let reasonValue = info[AVAudioSessionRouteChangeReasonKey] as? UInt,
              let reason = AVAudioSession.RouteChangeReason(rawValue: reasonValue) else {
            return
        }
        switch reason {
        case .oldDeviceUnavailable:
            // 输入设备被拔出（耳机断开、蓝牙音箱关机等）：停止录音，避免 engine 进入异常。
            // 不主动调用 onRouteChangeEnded 之外的清理逻辑，stop() 已完成 engine/会话清理。
            stop()
            onRouteChangeEnded?()
        default:
            break
        }
    }
}
