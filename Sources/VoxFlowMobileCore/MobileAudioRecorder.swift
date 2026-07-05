import Foundation
import VoxFlowAudio

/// 移动端音频录制抽象。平台实现（iOS AVAudioSession + AVAudioEngine）注入；
/// 测试用 fake 实现模拟帧流。
public protocol MobileAudioRecording: AnyObject, Sendable {
    /// 请求麦克风权限。返回是否授权。
    func requestPermission() async throws -> Bool

    /// 开始录音，按 16kHz mono PCM 输出 `AudioFrame`。
    /// `onFrame` 在音频线程触发，实现需保证 Sendable。
    func start(onFrame: @escaping @Sendable (AudioFrame) -> Void) throws

    /// 停止录音。幂等：未录音时调用不报错。
    func stop()
}
