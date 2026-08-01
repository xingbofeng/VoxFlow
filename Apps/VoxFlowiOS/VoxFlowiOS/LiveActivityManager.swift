// DictusApp/LiveActivityManager.swift adapter.
// Phase 1 keeps the Settings toggle and future entry point, but does not require
// ActivityKit entitlements for simulator/provider validation.
@MainActor
final class LiveActivityManager {
    static let shared = LiveActivityManager()

    private init() {}

    func stopStandbyActivity() {}
}
