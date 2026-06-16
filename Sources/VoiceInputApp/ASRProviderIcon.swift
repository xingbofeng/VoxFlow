import AppKit

enum ASRProviderIcon {
    static func systemSymbolName(providerID: String) -> String? {
        switch providerID {
        case ASRProviderID.appleSpeech:
            return "apple.logo"
        default:
            return nil
        }
    }

    static func textBadge(providerID: String) -> String? {
        switch providerID {
        case ASRProviderID.funASR:
            return "FA"
        case ASRProviderID.qwen3:
            return "QW"
        case ASRProviderID.senseVoice:
            return "SV"
        default:
            return nil
        }
    }

    static func load(providerID: String) -> NSImage? {
        let resourceName: String
        switch providerID {
        case ASRProviderID.funASR:
            resourceName = "ASRFunASR"
        case ASRProviderID.whisper:
            resourceName = "ASRWhisper"
        case ASRProviderID.qwen3:
            resourceName = "ASRQwen"
        case ASRProviderID.paraformer:
            resourceName = "ASRParaformer"
        case ASRProviderID.senseVoice:
            resourceName = "ASRSenseVoice"
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
