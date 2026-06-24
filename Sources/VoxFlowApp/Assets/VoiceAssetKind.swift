import Foundation

enum VoiceAssetKind: String, Equatable {
    case dictation
    case agentCompose
    case agentDispatch
    case selectionTranslation
    case selectionSummary
    case selectionAgent

    init(rawValue: String?) {
        guard let rawValue,
              let kind = VoiceAssetKind(rawValue: rawValue) else {
            self = .dictation
            return
        }
        self = kind
    }
}
