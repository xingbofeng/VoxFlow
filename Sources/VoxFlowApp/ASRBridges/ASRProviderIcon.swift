import AppKit

enum ASRProviderIcon {
    static func systemSymbolName(providerID: String) -> String? {
        nil
    }

    static func textBadge(providerID: String) -> String? {
        switch providerID {
        default:
            return nil
        }
    }

    static func load(providerID: String) -> NSImage? {
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
        guard let url = Bundle.module.url(forResource: resourceName, withExtension: "png"),
              let image = NSImage(contentsOf: url) else {
            return nil
        }
        image.isTemplate = true
        return image
    }
}
