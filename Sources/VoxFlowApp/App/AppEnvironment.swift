import Combine
import Foundation

final class AppEnvironment: ObservableObject, AppServiceProviding, AppEventRouting {
    private let logger = AppLogger.general

    private let historyDidChangeSubject = PassthroughSubject<Void, Never>()
    private let openHistoryDetailSubject = PassthroughSubject<String, Never>()
    let container: DependencyContainer

    var clock: any AppClock { container.clock }
    var paths: ApplicationSupportPaths? { container.paths }
    var storageHealth: StorageHealthState { container.storageHealth }
    var databaseQueue: DatabaseQueue { container.databaseQueue }
    var credentialStore: CredentialStore { container.credentialStore }
    var historyRepository: any HistoryRepository { container.historyRepository }
    var styleRepository: any StyleRepository { container.styleRepository }
    var asrProviderRepository: any ASRProviderRepository { container.asrProviderRepository }
    var llmProviderRepository: any LLMProviderRepository { container.llmProviderRepository }
    var transcriptionJobRepository: any TranscriptionJobRepository { container.transcriptionJobRepository }
    var noteRepository: any NoteRepository { container.noteRepository }
    var screenshotRecordRepository: any ScreenshotRecordRepository { container.screenshotRecordRepository }
    var settingsRepository: any SettingsRepository { container.settingsRepository }
    var correctionTargetRepository: any CorrectionTargetRepository { container.correctionTargetRepository }
    var correctionRuleRepository: any CorrectionRuleRepository { container.correctionRuleRepository }
    var correctionSnapshotProvider: CorrectionRuleSnapshotProvider { container.correctionSnapshotProvider }
    var voiceCorrectionProcessor: any VoiceCorrectionTextProcessing { container.voiceCorrectionProcessor }

    var historyDidChangePublisher: AnyPublisher<Void, Never> {
        historyDidChangeSubject.eraseToAnyPublisher()
    }

    var openHistoryDetailPublisher: AnyPublisher<String, Never> {
        openHistoryDetailSubject.eraseToAnyPublisher()
    }

    init(container: DependencyContainer) {
        AppLogger.general.debug("AppEnvironment init")
        self.container = container
    }

    func notifyHistoryDidChange() {
        logger.debug("AppEnvironment notifyHistoryDidChange")
        historyDidChangeSubject.send()
    }

    func requestOpenHistoryDetail(_ id: String) {
        logger.debug("AppEnvironment requestOpenHistoryDetail id=\(id)")
        openHistoryDetailSubject.send(id)
    }
}
