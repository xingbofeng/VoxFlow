import AppKit

enum ASRProviderIcon {
    static func systemSymbolName(providerID: String) -> String? {
        switch providerID {
        // 尚无品牌图：用系统符号占位，避免卡片出现空白图标块。
        // 补上 ASRConfucius.png 后应删掉这条，改为 load() 的 bundle 图。
        case ASRProviderID.confucius4R2T2, ASRProviderID.fireRedASR:
            return "waveform.circle"
        default:
            return nil
        }
    }

    static func textBadge(providerID: String) -> String? {
        switch providerID {
        default:
            return nil
        }
    }

    static func load(providerID: String) -> NSImage? {
        AppLogger.general.debug("ASRProviderIcon load providerID=\(providerID)")
        let resourceName: String
        switch providerID {
        case ASRProviderID.appleSpeech:
            resourceName = "ASRAppleSpeech"
        case ASRProviderID.funASR:
            resourceName = "ASRFunASR"
        case ASRProviderID.whisper:
            resourceName = "ASRWhisper"
        case ASRProviderID.qwen3:
            resourceName = "ASRQwen"
        case ASRProviderID.senseVoice:
            resourceName = "ASRSenseVoice"
        case ASRProviderID.paraformer:
            resourceName = "ASRProviderParaformer"
        case ASRProviderID.nvidiaNemotron:
            resourceName = "ASRNVIDIANemotron"
        case ASRProviderID.parakeetStreaming:
            resourceName = "ASRParakeetStreaming"
        case ASRProviderID.omnilingualASR:
            resourceName = "ASROmnilingual"
        case ASRProviderID.groqWhisper:
            resourceName = "ASRGroqWhisper"
        case ASRProviderID.qwenCloudASR:
            resourceName = "ASRQwenCloud"
        case ASRProviderID.tencentCloudASR:
            resourceName = "ASRTencentCloud"
        case ASRProviderID.mistralVoxtral:
            resourceName = "ASRMistralVoxtral"
        case ASRProviderID.assemblyAI:
            resourceName = "ASRAssemblyAI"
        case ASRProviderID.volcengineDoubao:
            resourceName = "ASRDoubao"
        case ASRProviderID.elevenLabsScribe:
            resourceName = "ASRElevenLabs"
        default:
            return nil
        }
        guard let url = VoxFlowAppResourceBundle.url(forResource: resourceName, withExtension: "png"),
              let image = NSImage(contentsOf: url) else {
            AppLogger.general.warning("ASRProviderIcon load failed providerID=\(providerID) resource=\(resourceName)")
            return nil
        }
        image.isTemplate = true
        return image
    }
}
