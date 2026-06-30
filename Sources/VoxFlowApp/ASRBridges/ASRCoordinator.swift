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
        AppLogger.general.debug("ASRCoordinator initialized")
    }

    var effectiveSelectedEngineType: ASREngineType {
        manager.effectiveSelectedEngineType
    }

    var selectionFallbackNotice: ASRManager.SelectionFallbackNotice? {
        manager.selectionFallbackNotice
    }

    func isMenuOptionEnabled(_ option: ASRMenuModel) -> Bool {
        let enabled = menuStateResolver.isEnabled(option)
        if !enabled {
            AppLogger.general.info("ASR menu option disabled: \(option.title)")
        }
        return enabled
    }

    func isMenuOptionSelected(_ option: ASRMenuModel) -> Bool {
        menuStateResolver.isSelected(option)
    }

    @discardableResult
    func selectMenuOption(_ option: ASRMenuModel) -> Bool {
        let selected = menuStateResolver.select(option)
        AppLogger.general.info("ASR menu option selected: \(option.title), success=\(selected)")
        return selected
    }

    func dictationConfiguration(for language: RecognitionLanguage) -> DictationConfiguration {
        let engineType = effectiveSelectedEngineType
        let modelMetadata = manager.modelMetadata(for: engineType)
        AppLogger.general.debug("Build dictation configuration: engine=\(engineType.rawValue), language=\(language.rawValue)")
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
             .aliyunDashScope, .volcengineDoubao:
            return true
        case .apple:
            return false
        }
    }

    func makeEngine(type: ASREngineType) -> ASREngine {
        AppLogger.general.info("ASRCoordinator makeEngine requested: \(type.rawValue)")
        return manager.makeEngine(type: type)
    }
}
