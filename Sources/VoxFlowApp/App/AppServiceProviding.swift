import Combine
import Foundation

protocol AppServiceProviding {
    var clock: any AppClock { get }
    var paths: ApplicationSupportPaths? { get }
    var storageHealth: StorageHealthState { get }
    var databaseQueue: DatabaseQueue { get }
    var credentialStore: CredentialStore { get }
    var historyRepository: any HistoryRepository { get }
    var styleRepository: any StyleRepository { get }
    var asrProviderRepository: any ASRProviderRepository { get }
    var llmProviderRepository: any LLMProviderRepository { get }
    var transcriptionJobRepository: any TranscriptionJobRepository { get }
    var noteRepository: any NoteRepository { get }
    var settingsRepository: any SettingsRepository { get }
    var correctionRuleRepository: any CorrectionRuleRepository { get }
    var correctionSnapshotProvider: CorrectionRuleSnapshotProvider { get }
    var voiceCorrectionProcessor: any VoiceCorrectionTextProcessing { get }
}

protocol AppEventRouting {
    var historyDidChangePublisher: AnyPublisher<Void, Never> { get }
    var openHistoryDetailPublisher: AnyPublisher<String, Never> { get }

    func notifyHistoryDidChange()
    func requestOpenHistoryDetail(_ id: String)
}
