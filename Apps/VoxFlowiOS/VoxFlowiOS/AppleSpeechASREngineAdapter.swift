import Foundation
import AVFoundation
@preconcurrency import Speech
import VoxFlowASRCore
import VoxFlowASRRuntime
import VoxFlowAudio
import VoxFlowProviderApple

/// 将 `AppleSpeechASRProvider`（产出 `ASRSession`，AsyncStream 事件流）适配为共享 `ASREngine` 协议（闭包回调）。
///
/// Apple Speech 是 iOS V1 的 baseline Provider，不是 LiveContainer 主验收路径。
/// 在 LiveContainer 环境下，Speech 权限可能不可用，调用方应通过 `isAvailable` 和 `onError` 处理失败。
///
/// 帧转发通过 actor 串行化，避免在音频线程上直接调用 async `ASRSession.accept(_:)`。
final class AppleSpeechASREngineAdapter: ASREngine, @unchecked Sendable {
    var onTranscription: ((String, Bool) -> Void)?
    var onError: ((Error) -> Void)?

    var isAvailable: Bool {
        SFSpeechRecognizer.authorizationStatus() == .authorized
    }

    private let provider: AppleSpeechASRProvider
    private let sessionActor = AppleSpeechSessionActor()
    private var eventTask: Task<Void, Never>?
    private var locale: Locale

    init(provider: AppleSpeechASRProvider = AppleSpeechASRProvider()) {
        self.provider = provider
        self.locale = Locale(identifier: "zh-CN")
    }

    func configure(locale: Locale) {
        self.locale = locale
    }

    func start() throws {
        guard SFSpeechRecognizer.authorizationStatus() == .authorized else {
            throw AppleSpeechProviderError.authorizationDenied
        }
        eventTask?.cancel()
        eventTask = Task { [weak self] in
            guard let self else { return }
            do {
                let session = try await provider.makeSession(
                    language: ASRLanguageCapability(bcp47Tag: locale.identifier)
                )
                await sessionActor.setSession(session)
                try await session.start()
                for await event in session.events {
                    if Task.isCancelled { break }
                    self.handleEvent(event)
                }
            } catch {
                self.emitError(error)
            }
        }
    }

    func appendAudioFrame(_ frame: AudioFrame) {
        Task { await sessionActor.accept(frame) }
    }

    func endAudio() {
        Task { await sessionActor.finish() }
    }

    func stop() {
        eventTask?.cancel()
        Task { await sessionActor.cancel() }
    }

    func cancel() {
        eventTask?.cancel()
        Task { await sessionActor.cancel() }
    }

    private func handleEvent(_ event: ASREvent) {
        switch event {
        case let .partial(_, transcript):
            let text = transcript.stablePrefix + transcript.unstableSuffix
            emitTranscription(text, isFinal: false)
        case let .final(_, _, text):
            emitTranscription(text, isFinal: true)
        case let .failure(_, _, error):
            emitError(ASRCoreFailureError(error))
        default:
            break
        }
    }

    private func emitTranscription(_ text: String, isFinal: Bool) {
        Task { @MainActor [weak self] in
            self?.onTranscription?(text, isFinal)
        }
    }

    private func emitError(_ error: Error) {
        Task { @MainActor [weak self] in
            self?.onError?(error)
        }
    }
}

private struct ASRCoreFailureError: LocalizedError {
    let category: ASRErrorCategory
    let message: String

    init(_ error: ASRError) {
        self.category = error.category
        self.message = error.message
    }

    var errorDescription: String? {
        "[\(category.rawValue)] \(message)"
    }
}

private actor AppleSpeechSessionActor {
    private var session: (any ASRSession)?

    func setSession(_ session: any ASRSession) {
        self.session = session
    }

    func accept(_ frame: AudioFrame) async {
        try? await session?.accept(frame)
    }

    func finish() async {
        try? await session?.finish()
    }

    func cancel() async {
        await session?.cancel()
        session = nil
    }
}
