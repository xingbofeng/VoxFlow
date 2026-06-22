import Foundation
import VoxFlowVoiceCorrection

protocol VoiceCorrectionTextProcessing {
    func process(
        _ text: String,
        context: CorrectionContext
    ) throws -> CorrectionResult
}

struct VoiceCorrectionTextProcessor: VoiceCorrectionTextProcessing {
    let engine: VoiceCorrectionEngine
    let snapshotProvider: CorrectionRuleSnapshotProvider
    let settingsRepository: (any SettingsRepository)?
    let usageRecorder: (any CorrectionRuleRepository)?

    init(
        engine: VoiceCorrectionEngine = VoiceCorrectionEngine(),
        snapshotProvider: CorrectionRuleSnapshotProvider,
        settingsRepository: (any SettingsRepository)? = nil,
        usageRecorder: (any CorrectionRuleRepository)? = nil
    ) {
        self.engine = engine
        self.snapshotProvider = snapshotProvider
        self.settingsRepository = settingsRepository
        self.usageRecorder = usageRecorder
    }

    func process(
        _ text: String,
        context: CorrectionContext
    ) -> CorrectionResult {
        guard isEnabled else {
            AppLogger.dictation.debug("纠错未启用，返回原文：textLen=\(text.count)")
            return CorrectionResult(rawText: text, correctedText: text)
        }

        let result = engine.correct(
            rawText: text,
            context: context,
            snapshot: snapshotProvider.refresh()
        )
        guard !shadowMode else {
            AppLogger.dictation.debug("纠错影子模式开启，结果未落库：rules=\(result.events.count), warnings=\(result.warnings.count)")
            return CorrectionResult(
                rawText: text,
                correctedText: text,
                events: result.events,
                warnings: result.warnings
            )
        }
        AppLogger.dictation.info("完成纠错：textLen=\(text.count), events=\(result.events.count)")
        try? usageRecorder?.recordApplications(
            ruleIDs: result.events.map(\.ruleID),
            at: Date()
        )
        return result
    }

    private var isEnabled: Bool {
        guard let settingsRepository else {
            return VoiceCorrectionSettingsKey.enabled.defaultValue
        }
        return (try? VoiceCorrectionSettingsStore.bool(.enabled, repository: settingsRepository)) ??
            VoiceCorrectionSettingsKey.enabled.defaultValue
    }

    private var shadowMode: Bool {
        guard let settingsRepository else {
            return VoiceCorrectionSettingsKey.shadowMode.defaultValue
        }
        return (try? VoiceCorrectionSettingsStore.bool(.shadowMode, repository: settingsRepository)) ??
            VoiceCorrectionSettingsKey.shadowMode.defaultValue
    }
}
