import Foundation

// MARK: - SmartConfigInvitationState

enum SmartConfigInvitationState: String, Codable, Equatable, Sendable {
    case pending
    case shown
    case started
    case dismissed
}

// MARK: - SmartConfigInvitationManaging

protocol SmartConfigInvitationManaging: Sendable {
    var state: SmartConfigInvitationState { get }
    func notifyLLMSuccess()
    func markShown()
    func markStarted()
    func markDismissed()
}

// MARK: - SmartConfigInvitationManager

final class SmartConfigInvitationManager: SmartConfigInvitationManaging, @unchecked Sendable {
    private static let logger = AppLogger.general

    static let defaultsKey = "smartConfigInvitationState"

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var state: SmartConfigInvitationState {
        guard let raw = defaults.string(forKey: Self.defaultsKey) else {
            return .pending
        }
        return SmartConfigInvitationState(rawValue: raw) ?? .pending
    }

    func notifyLLMSuccess() {
        guard state == .pending else { return }
        set(.shown)
    }

    func markShown() {
        guard state == .pending else { return }
        set(.shown)
    }

    func markStarted() {
        guard state == .shown || state == .pending else { return }
        set(.started)
    }

    func markDismissed() {
        guard state == .shown || state == .pending else { return }
        set(.dismissed)
    }

    private func set(_ newState: SmartConfigInvitationState) {
        let current = state
        guard current != newState else {
            Self.logger.debug("SmartConfigInvitation state set skipped: already \(current.rawValue)")
            return
        }
        Self.logger.info("SmartConfigInvitation state \(current.rawValue) -> \(newState.rawValue)")
        defaults.set(newState.rawValue, forKey: Self.defaultsKey)
    }
}
