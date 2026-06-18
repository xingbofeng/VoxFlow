import Combine
import Foundation

protocol AppServiceProviding {
    var clock: any AppClock { get }
    var paths: ApplicationSupportPaths? { get }
    var databaseQueue: DatabaseQueue { get }
    var credentialStore: CredentialStore { get }
    var historyRepository: any HistoryRepository { get }
    var glossaryRepository: any GlossaryRepository { get }
    var replacementRuleRepository: any ReplacementRuleRepository { get }
    var styleRepository: any StyleRepository { get }
    var asrProviderRepository: any ASRProviderRepository { get }
    var llmProviderRepository: any LLMProviderRepository { get }
    var transcriptionJobRepository: any TranscriptionJobRepository { get }
    var noteRepository: any NoteRepository { get }
    var settingsRepository: any SettingsRepository { get }
}

protocol AppEventRouting {
    var historyDidChangePublisher: AnyPublisher<Void, Never> { get }
    var openHistoryDetailPublisher: AnyPublisher<String, Never> { get }

    func notifyHistoryDidChange()
    func requestOpenHistoryDetail(_ id: String)
}
