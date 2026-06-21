import Foundation
import VoxFlowVoiceCorrection

struct CorrectionRuleRecord {
    let rule: CorrectionRule

    var scopeType: String {
        switch rule.scope {
        case .global: "global"
        case .application: "application"
        }
    }

    var scopeValue: String? {
        switch rule.scope {
        case .global: nil
        case .application(let bundleIdentifier): bundleIdentifier
        }
    }

    var allowedModesJSON: String {
        let values = rule.allowedModes.map(\.rawValue).sorted()
        let data = try? JSONEncoder().encode(values)
        return data.flatMap { String(data: $0, encoding: .utf8) } ?? "[]"
    }
}
