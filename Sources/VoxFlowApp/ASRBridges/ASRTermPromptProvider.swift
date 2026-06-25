import Foundation
import VoxFlowVoiceCorrection

@MainActor
protocol ASRTermPromptProviding {
    func prompt(for engineType: ASREngineType, bundleIdentifier: String?) -> String?
}

@MainActor
struct CorrectionTargetASRTermPromptProvider: ASRTermPromptProviding {
    static let defaultBudgets: [ASREngineType: Int] = [
        .whisper: 500,
        .groqWhisper: 600,
    ]

    private let repository: any CorrectionTargetRepository
    private let budgets: [ASREngineType: Int]
    private let isEnabled: () -> Bool

    init(
        repository: any CorrectionTargetRepository,
        budgets: [ASREngineType: Int] = Self.defaultBudgets,
        isEnabled: @escaping () -> Bool = { true }
    ) {
        self.repository = repository
        self.budgets = budgets
        self.isEnabled = isEnabled
    }

    func prompt(for engineType: ASREngineType, bundleIdentifier: String?) -> String? {
        guard isEnabled(),
              let budget = budgets[engineType],
              budget > 0 else {
            return nil
        }
        guard let targets = try? repository.list() else {
            return nil
        }

        let scopedTargets = targets.filter { target in
            guard target.lifecycle == .active else { return false }
            switch target.scope {
            case .global:
                return true
            case .application(let targetBundleIdentifier):
                return targetBundleIdentifier == bundleIdentifier
            }
        }
        let prioritizedTargets = scopedTargets.filter {
            if case .application = $0.scope { return true }
            return false
        } + scopedTargets.filter {
            if case .global = $0.scope { return true }
            return false
        }

        var seen = Set<String>()
        let terms = prioritizedTargets.compactMap { target -> String? in
            let term = target.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !term.isEmpty else { return nil }
            let key = CorrectionTargetTerm.normalize(term)
            guard seen.insert(key).inserted else { return nil }
            return term
        }

        var selected: [String] = []
        var length = 0
        for term in terms {
            let addedLength = term.count + (selected.isEmpty ? 0 : 2)
            guard length + addedLength <= budget else {
                break
            }
            selected.append(term)
            length += addedLength
        }
        return selected.isEmpty ? nil : selected.joined(separator: ", ")
    }
}
