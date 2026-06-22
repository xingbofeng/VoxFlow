import Combine
import Foundation

struct WorkbenchSnapshot: Equatable {
    var historyCount = 0
    var styleCount = 0
    var noteCount = 0
    var asrProviderCount = 0
    var llmProviderCount = 0
    var lastError: String?
}

@MainActor
final class WorkbenchViewModel: ObservableObject {
    private static let logger = AppLogger.general

    @Published private(set) var snapshot = WorkbenchSnapshot()

    private let environment: any AppServiceProviding
    private var hasLoaded = false

    init(environment: any AppServiceProviding) {
        self.environment = environment
    }

    func load() {
        Self.logger.debug("workbench_vm_load_start")
        do {
            snapshot = WorkbenchSnapshot(
                historyCount: try environment.historyRepository.listRecent(limit: 1_000).count,
                styleCount: try environment.styleRepository.list(category: nil).count,
                noteCount: try environment.noteRepository.list().count,
                asrProviderCount: try environment.asrProviderRepository.list().count,
                llmProviderCount: try environment.llmProviderRepository.list().count,
                lastError: nil
            )
            hasLoaded = true
            Self.logger.info(
                "workbench_vm_load_success history=\(snapshot.historyCount) styles=\(snapshot.styleCount) notes=\(snapshot.noteCount) asrProviders=\(snapshot.asrProviderCount) llmProviders=\(snapshot.llmProviderCount)"
            )
        } catch {
            snapshot.lastError = error.localizedDescription
            Self.logger.error("workbench_vm_load_failed error=\(error.localizedDescription)")
        }
    }

    func loadIfNeeded() {
        guard !hasLoaded else {
            Self.logger.debug("workbench_vm_load_if_needed_skip")
            return
        }
        Self.logger.debug("workbench_vm_load_if_needed_execute")
        load()
    }
}
