import Foundation
import VoxFlowAudio
import VoxFlowASRRuntime

/// 移动端听写会话，串联 `MobileAudioRecording` 与跨平台 `ASREngine`，
/// 推进 `MobileDictationState` 并统一 partial / final / failure / cancel 事件。
///
/// 回调（`onChange`、`onFinalText`）在 ASR engine 派发的主线程上触发；
/// 录音帧在音频线程上调用 `engine.appendAudioFrame`，由 engine 内部缓冲。
public final class MobileDictationSession: @unchecked Sendable {
    private let lock = NSLock()
    private let engine: ASREngine
    private let recorder: MobileAudioRecording
    private var state: MobileDictationState = .idle
    private var lastLiveText: String = ""

    /// 状态变化回调（主线程）。
    public var onChange: ((MobileDictationState) -> Void)?

    /// 麦克风权限被拒绝时的回调，用于 UI 引导用户去系统设置。
    public var onPermissionDenied: (() -> Void)?

    public init(engine: ASREngine, recorder: MobileAudioRecording) {
        self.engine = engine
        self.recorder = recorder
        engine.onTranscription = { [weak self] text, isFinal in
            self?.handleTranscription(text: text, isFinal: isFinal)
        }
        engine.onError = { [weak self] error in
            self?.handleError(error)
        }
    }

    public func currentState() -> MobileDictationState {
        lock.withLock { state }
    }

    /// 开始：请求权限 → 启动 engine → 启动录音 → recording。
    public func start() async {
        guard case .idle = currentState() else { return }
        updateState(.requestingPermission)
        do {
            let granted = try await recorder.requestPermission()
            guard granted else {
                onPermissionDenied?()
                updateState(.failed(message: Self.permissionDeniedMessage))
                return
            }
        } catch {
            updateState(.failed(message: error.localizedDescription))
            return
        }
        guard engine.isAvailable else {
            updateState(.failed(message: Self.providerNotConfiguredMessage))
            return
        }
        do {
            try engine.start()
            try recorder.start { [weak self] frame in
                self?.engine.appendAudioFrame(frame)
            }
            updateState(.recording(liveText: ""))
        } catch {
            updateState(.failed(message: error.localizedDescription))
        }
    }

    /// 停止：停止录音、结束音频流，进入 transcribing 等待 final。
    public func stop() {
        let snapshot = currentState()
        guard snapshot.isStoppable else { return }
        recorder.stop()
        engine.endAudio()
        switch snapshot {
        case let .recording(liveText):
            updateState(.transcribing(liveText: liveText))
        case let .transcribing(liveText):
            updateState(.transcribing(liveText: liveText))
        default:
            break
        }
    }

    /// 取消：停止录音、取消 engine、回到 idle。
    public func cancel() {
        recorder.stop()
        engine.cancel()
        lastLiveText = ""
        updateState(.idle)
    }

    /// 清空当前结果，回到 idle（用于 UI"清空"按钮）。
    public func reset() {
        cancel()
    }

    // MARK: - Engine callbacks

    private func handleTranscription(text: String, isFinal: Bool) {
        if isFinal {
            updateState(.finished(text: text))
            return
        }
        let next: MobileDictationState
        switch currentState() {
        case .transcribing:
            next = .transcribing(liveText: text)
        default:
            next = .recording(liveText: text)
        }
        updateState(next)
    }

    private func handleError(_ error: Error) {
        updateState(.failed(message: error.localizedDescription))
    }

    // MARK: - Private

    private func updateState(_ next: MobileDictationState) {
        let previous = lock.withLock { () -> MobileDictationState in
            let old = state
            state = next
            return old
        }
        if previous != next {
            onChange?(next)
        }
    }

    private static let permissionDeniedMessage = "麦克风权限被拒绝，请在系统设置中授权。"
    private static let providerNotConfiguredMessage = "所选 ASR Provider 未配置凭证。"
}
