import AppKit
import Foundation

struct DictationTarget: Equatable, Sendable {
    let bundleID: String?
    let appName: String?
    let pid: Int?
    let windowID: String?
    let windowTitle: String?

    init(
        bundleID: String? = nil,
        appName: String? = nil,
        pid: Int? = nil,
        windowID: String? = nil,
        windowTitle: String? = nil
    ) {
        self.bundleID = bundleID
        self.appName = appName
        self.pid = pid
        self.windowID = windowID
        self.windowTitle = windowTitle
    }
}

@MainActor
protocol DictationTargetProviding {
    func currentTarget() -> DictationTarget?
}

struct WorkspaceDictationTargetProvider: DictationTargetProviding {
    func currentTarget() -> DictationTarget? {
        guard let application = NSWorkspace.shared.frontmostApplication else {
            AppLogger.dictation.warning("WorkspaceDictationTargetProvider no frontmost app")
            return nil
        }
        AppLogger.dictation.debug("WorkspaceDictationTargetProvider app bundle=\(application.bundleIdentifier ?? "nil") name=\(application.localizedName ?? "nil")")
        return DictationTarget(
            bundleID: application.bundleIdentifier,
            appName: application.localizedName,
            pid: Int(application.processIdentifier)
        )
    }
}

struct StaticDictationTargetProvider: DictationTargetProviding {
    let target: DictationTarget?

    func currentTarget() -> DictationTarget? {
        if let target {
            AppLogger.dictation.debug("StaticDictationTargetProvider target bundle=\(target.bundleID ?? "nil")")
        } else {
            AppLogger.dictation.debug("StaticDictationTargetProvider target nil")
        }
        return target
    }
}

enum DictationTargetChangePolicy {
    static func targetChanged(
        original: DictationTarget?,
        current: DictationTarget?
    ) -> Bool {
        guard let original else { return false }
        guard let current else { return true }
        if original.bundleID != current.bundleID { return true }
        if original.windowID != nil && original.windowID != current.windowID { return true }
        return false
    }
}

enum DictationTargetActivation {
    @discardableResult
    static func activate(_ target: DictationTarget?) async -> Bool {
        guard let pid = target?.pid,
              let application = NSRunningApplication(processIdentifier: pid_t(pid)),
              !application.isTerminated else {
            return false
        }

        let activated = application.activate()
        if activated {
            try? await Task.sleep(nanoseconds: 120_000_000)
        }
        return activated
    }
}
