import Foundation
import VoxFlowVoiceCorrection

struct CorrectionTargetRecord {
    let target: CorrectionTargetTerm

    var scopeType: String {
        switch target.scope {
        case .global: "global"
        case .application: "application"
        }
    }

    var scopeValue: String? {
        switch target.scope {
        case .global: nil
        case .application(let bundleIdentifier): bundleIdentifier
        }
    }
}
