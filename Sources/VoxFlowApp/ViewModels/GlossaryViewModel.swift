import Combine
import Foundation

@MainActor
final class GlossaryViewModel: ObservableObject {
    @Published private(set) var lastError: String?
    @Published private(set) var lastActionMessage: String?

    private let environment: any AppServiceProviding

    init(environment: any AppServiceProviding) {
        self.environment = environment
        load()
    }

    func load() {
        lastError = nil
    }

    func report(error: Error) {
        lastError = error.localizedDescription
        lastActionMessage = nil
    }

    func clearFeedback() {
        lastError = nil
        lastActionMessage = nil
    }
}
