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

    init(
        engine: VoiceCorrectionEngine = VoiceCorrectionEngine(),
        snapshotProvider: CorrectionRuleSnapshotProvider,
        settingsRepository: (any SettingsRepository)? = nil
    ) {
        self.engine = engine
        self.snapshotProvider = snapshotProvider
        self.settingsRepository = settingsRepository
    }

    func process(
        _ text: String,
        context: CorrectionContext
    ) -> CorrectionResult {
        guard isEnabled else {
            return CorrectionResult(rawText: text, correctedText: text)
        }

        let result = engine.correct(
            rawText: text,
            context: context,
            snapshot: snapshotProvider.refresh()
        )
        guard !shadowMode else {
            return CorrectionResult(
                rawText: text,
                correctedText: text,
                events: result.events,
                warnings: result.warnings
            )
        }
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
