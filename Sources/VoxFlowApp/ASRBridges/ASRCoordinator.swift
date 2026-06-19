import Foundation

@MainActor
final class ASRCoordinator: @preconcurrency ASREngineFactory {
    private let manager: ASRManager
    private let menuStateResolver: ASRMenuStateResolver

    init(
        manager: ASRManager = ASRManager(),
        qwenAvailableOnDisk: ASRMenuStateResolver.QwenAvailability? = nil,
        funASRAvailable: @escaping ASRMenuStateResolver.FunASRAvailability = { _ in false },
        whisperAvailable: @escaping ASRMenuStateResolver.WhisperAvailability = { _ in false }
    ) {
        self.manager = manager
        if let qwenAvailableOnDisk {
            self.menuStateResolver = ASRMenuStateResolver(
                asrManager: manager,
                qwenAvailableOnDisk: qwenAvailableOnDisk,
                funASRAvailable: funASRAvailable,
                whisperAvailable: whisperAvailable
            )
        } else {
            self.menuStateResolver = ASRMenuStateResolver(asrManager: manager)
        }
    }

    var effectiveSelectedEngineType: ASREngineType {
        manager.effectiveSelectedEngineType
    }

    var selectionFallbackNotice: ASRManager.SelectionFallbackNotice? {
        manager.selectionFallbackNotice
    }

    func isMenuOptionEnabled(_ option: ASRMenuModel) -> Bool {
        menuStateResolver.isEnabled(option)
    }

    func isMenuOptionSelected(_ option: ASRMenuModel) -> Bool {
        menuStateResolver.isSelected(option)
    }

    @discardableResult
    func selectMenuOption(_ option: ASRMenuModel) -> Bool {
        menuStateResolver.select(option)
    }

    func dictationConfiguration(for language: RecognitionLanguage) -> DictationConfiguration {
        let engineType = effectiveSelectedEngineType
        let modelMetadata = manager.modelMetadata(for: engineType)
        return DictationConfiguration(
            engineType: engineType,
            locale: language.locale,
            languageIdentifier: language.rawValue,
            modelID: modelMetadata.modelID,
            modelVersion: modelMetadata.modelVersion
        )
    }

    func shouldShowWaitingIndicator(activeVoiceAction: VoiceAction?) -> Bool {
        activeVoiceAction != .agentCompose
            && Self.requiresFinalRecognitionIndicator(for: effectiveSelectedEngineType)
    }

    static func requiresFinalRecognitionIndicator(for engineType: ASREngineType) -> Bool {
        switch engineType {
        case .qwen3, .whisper, .senseVoice, .funASR, .paraformer, .nvidiaNemotron,
             .parakeetStreaming, .omnilingualASR, .groqWhisper, .tencentCloud,
             .aliyunDashScope:
            return true
        case .apple:
            return false
        }
    }

    func makeEngine(type: ASREngineType) -> ASREngine {
        manager.makeEngine(type: type)
    }
}
