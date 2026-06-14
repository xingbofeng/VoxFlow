import Combine
import Foundation

final class AppEnvironment: ObservableObject {
    let historyDidChange = PassthroughSubject<Void, Never>()
    let openHistoryDetail = PassthroughSubject<String, Never>()
    let container: DependencyContainer

    var clock: any AppClock { container.clock }
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

    init(container: DependencyContainer) {
        self.container = container
    }
}
