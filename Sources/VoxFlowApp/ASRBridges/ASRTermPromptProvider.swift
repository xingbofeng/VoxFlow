import Foundation
import VoxFlowVoiceCorrection

@MainActor
protocol ASRTermPromptProviding {
    func prompt(for engineType: ASREngineType, bundleIdentifier: String?) -> String?
}

@MainActor
struct CorrectionTargetASRTermPromptProvider: ASRTermPromptProviding {
    private let repository: any CorrectionTargetRepository
    private let isEnabled: () -> Bool

    init(
        repository: any CorrectionTargetRepository,
        isEnabled: @escaping () -> Bool = { true }
    ) {
        self.repository = repository
        self.isEnabled = isEnabled
    }

    func prompt(for engineType: ASREngineType, bundleIdentifier: String?) -> String? {
        guard isEnabled() else {
            return nil
        }

        // Use the capability matrix for all providers, not just whisper/groq.
        // Apple Speech still receives a string at this app boundary; its provider
        // session parses the terms and maps them to contextualStrings.
        let capability = ASRHotwordCapabilityMatrix.capability(for: engineType)
        guard capability.supportMode == .promptContext
            || (
                capability.supportMode == .nativeHotword
                    && (engineType == .apple || engineType == .nvidiaNemotron || engineType == .tencentCloud)
            ) else {
            return nil
        }

        guard let targets = try? repository.listHotwords() else {
            return nil
        }

        let scopedTargets = targets.filter { target in
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

        // Use the capability matrix to prune by the provider's budget
        let payload = ASRHotwordCapabilityMatrix.buildPayload(
            for: engineType,
            candidates: terms
        )
        if engineType == .apple {
            return payload.contextualStrings?.joined(separator: ", ")
        }
        if engineType == .nvidiaNemotron {
            return payload.boostingPhrases?.joined(separator: ", ")
        }
        if engineType == .tencentCloud {
            return payload.hotwordList?.joined(separator: ",")
        }
        return payload.promptString
    }
}
