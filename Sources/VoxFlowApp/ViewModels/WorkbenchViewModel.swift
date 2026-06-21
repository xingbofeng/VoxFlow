import Combine
import Foundation

struct WorkbenchSnapshot: Equatable {
    var historyCount = 0
    var glossaryCount = 0
    var styleCount = 0
    var noteCount = 0
    var asrProviderCount = 0
    var llmProviderCount = 0
    var lastError: String?
}

@MainActor
final class WorkbenchViewModel: ObservableObject {
    @Published private(set) var snapshot = WorkbenchSnapshot()

    private let environment: any AppServiceProviding
    private var hasLoaded = false

    init(environment: any AppServiceProviding) {
        self.environment = environment
    }

    func load() {
        do {
            snapshot = WorkbenchSnapshot(
                historyCount: try environment.historyRepository.listRecent(limit: 1_000).count,
                glossaryCount: 0,
                styleCount: try environment.styleRepository.list(category: nil).count,
                noteCount: try environment.noteRepository.list().count,
                asrProviderCount: try environment.asrProviderRepository.list().count,
                llmProviderCount: try environment.llmProviderRepository.list().count,
                lastError: nil
            )
            hasLoaded = true
        } catch {
            snapshot.lastError = error.localizedDescription
        }
    }

    func loadIfNeeded() {
        guard !hasLoaded else {
            return
        }
        load()
    }
}
