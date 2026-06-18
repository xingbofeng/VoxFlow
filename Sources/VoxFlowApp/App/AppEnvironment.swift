import Combine
import Foundation

final class AppEnvironment: ObservableObject, AppServiceProviding, AppEventRouting {
    private let historyDidChangeSubject = PassthroughSubject<Void, Never>()
    private let openHistoryDetailSubject = PassthroughSubject<String, Never>()
    let container: DependencyContainer

    var clock: any AppClock { container.clock }
    var paths: ApplicationSupportPaths? { container.paths }
    var databaseQueue: DatabaseQueue { container.databaseQueue }
    var credentialStore: CredentialStore { container.credentialStore }
    var historyRepository: any HistoryRepository { container.historyRepository }
    var glossaryRepository: any GlossaryRepository { container.glossaryRepository }
    var replacementRuleRepository: any ReplacementRuleRepository { container.replacementRuleRepository }
    var styleRepository: any StyleRepository { container.styleRepository }
    var asrProviderRepository: any ASRProviderRepository { container.asrProviderRepository }
    var llmProviderRepository: any LLMProviderRepository { container.llmProviderRepository }
    var transcriptionJobRepository: any TranscriptionJobRepository { container.transcriptionJobRepository }
    var noteRepository: any NoteRepository { container.noteRepository }
    var settingsRepository: any SettingsRepository { container.settingsRepository }

    var historyDidChangePublisher: AnyPublisher<Void, Never> {
        historyDidChangeSubject.eraseToAnyPublisher()
    }

    var openHistoryDetailPublisher: AnyPublisher<String, Never> {
        openHistoryDetailSubject.eraseToAnyPublisher()
    }

    init(container: DependencyContainer) {
        self.container = container
    }

    func notifyHistoryDidChange() {
        historyDidChangeSubject.send()
    }

    func requestOpenHistoryDetail(_ id: String) {
        openHistoryDetailSubject.send(id)
    }
}
