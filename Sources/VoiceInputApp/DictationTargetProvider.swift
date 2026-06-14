import AppKit
import Foundation

struct DictationTarget: Equatable {
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
            return nil
        }
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
        target
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
