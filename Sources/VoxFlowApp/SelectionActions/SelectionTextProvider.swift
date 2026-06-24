import AppKit
import Foundation
import VoxFlowTextInsertion

// Adapted from Easydict SelectionWorkflow.swift
// Upstream: https://github.com/tisfeng/Easydict
// Upstream path: Easydict/Swift/Utility/EventMonitor/Workflow/SelectionWorkflow.swift
// Upstream commit: 1376005e8455783d2db162cb7029f14cde932a9f
// License: GPL-3.0

enum SelectionTextAcquisitionStrategy: Equatable, Hashable, Sendable {
    case accessibility
    case browserScript
    case shortcutCopy
    case menuCopy
}

struct SelectionTextSnapshot: Equatable, Sendable {
    let text: String
    let source: SelectionTextAcquisitionStrategy
    let isEditable: Bool
    let selectionBounds: NSRect?

    init(
        text: String,
        source: SelectionTextAcquisitionStrategy,
        isEditable: Bool,
        selectionBounds: NSRect? = nil
    ) {
        self.text = text
        self.source = source
        self.isEditable = isEditable
        self.selectionBounds = selectionBounds
    }
}

enum SelectionTextProviderFailure: Error, Equatable, Sendable {
    case forceCopyDisabled
    case frontmostAppIsSelf
    case copyFallbackFailed(SelectionTextAcquisitionStrategy)

    var userMessage: String {
        switch self {
        case .forceCopyDisabled:
            return "未检测到选中文本"
        case .frontmostAppIsSelf:
            return "请在其他应用中选择文本"
        case .copyFallbackFailed(.accessibility):
            return "未检测到选中文本"
        case .copyFallbackFailed(.browserScript):
            return "未检测到选中文本，浏览器选区读取未返回内容"
        case .copyFallbackFailed(.shortcutCopy):
            return "未检测到选中文本，复制快捷键未返回内容"
        case .copyFallbackFailed(.menuCopy):
            return "未检测到选中文本，菜单复制未返回内容"
        }
    }
}

protocol SelectionAcquisitionSystemAdapter: Sendable {
    func selectedText(using strategy: SelectionTextAcquisitionStrategy) async throws -> String?
    func selectedTextBounds(using strategy: SelectionTextAcquisitionStrategy) async -> NSRect?
    func isFocusedTextField() async -> Bool
    func hasEnabledCopyMenuItem() async -> Bool
    func isFrontmostAppSelf() async -> Bool
}

@MainActor
protocol SelectionAccessibilityReading: Sendable {
    func selectedText() throws -> String?
    func selectedTextBounds() throws -> NSRect?
    func isFocusedTextField() -> Bool
}

@MainActor
protocol SelectionCopyPerforming: AnyObject {
    func performShortcutCopy() async
    func performMenuCopy() async -> Bool
}

@MainActor
protocol SelectionBrowserSelectionReading: AnyObject, Sendable {
    func selectedText(bundleIdentifier: String?) -> String?
}

@MainActor
protocol SelectionKeyboardEventPosting: AnyObject {
    func postKeyEvent(keyCode: CGKeyCode, flags: CGEventFlags, keyDown: Bool)
}

@MainActor
protocol SelectionMenuActionSending: AnyObject {
    func sendAction(_ action: Selector) -> Bool
    func canSendAction(_ action: Selector) -> Bool
}

@MainActor
protocol SelectionAppContextProviding: Sendable {
    func isFrontmostAppSelf() -> Bool
    func frontmostBundleIdentifier() -> String?
    func hasEnabledCopyMenuItem() -> Bool
}

@MainActor
final class SystemSelectionCopyPerformer: SelectionCopyPerforming {
    private static let cKeyCode = CGKeyCode(0x08)

    private let keyboardEventPoster: any SelectionKeyboardEventPosting
    private let menuActionSender: any SelectionMenuActionSending
    private let settleDelayNanoseconds: UInt64

    init(
        keyboardEventPoster: any SelectionKeyboardEventPosting = CGSelectionKeyboardEventPoster(),
        menuActionSender: any SelectionMenuActionSending = AppKitSelectionMenuActionSender(),
        settleDelayNanoseconds: UInt64 = 80_000_000
    ) {
        self.keyboardEventPoster = keyboardEventPoster
        self.menuActionSender = menuActionSender
        self.settleDelayNanoseconds = settleDelayNanoseconds
    }

    func performShortcutCopy() async {
        keyboardEventPoster.postKeyEvent(
            keyCode: Self.cKeyCode,
            flags: .maskCommand,
            keyDown: true
        )
        keyboardEventPoster.postKeyEvent(
            keyCode: Self.cKeyCode,
            flags: .maskCommand,
            keyDown: false
        )
        await settle()
    }

    func performMenuCopy() async -> Bool {
        let sent = menuActionSender.sendAction(#selector(NSText.copy(_:)))
        await settle()
        return sent
    }

    private func settle() async {
        guard settleDelayNanoseconds > 0 else { return }
        try? await Task.sleep(nanoseconds: settleDelayNanoseconds)
    }
}

@MainActor
final class CGSelectionKeyboardEventPoster: SelectionKeyboardEventPosting {
    func postKeyEvent(keyCode: CGKeyCode, flags: CGEventFlags, keyDown: Bool) {
        guard let event = CGEvent(
            keyboardEventSource: CGEventSource(stateID: .combinedSessionState),
            virtualKey: keyCode,
            keyDown: keyDown
        ) else {
            return
        }
        event.flags = flags
        event.post(tap: .cghidEventTap)
    }
}

@MainActor
final class AppKitSelectionMenuActionSender: SelectionMenuActionSending {
    func sendAction(_ action: Selector) -> Bool {
        NSApplication.shared.sendAction(action, to: nil, from: nil)
    }

    func canSendAction(_ action: Selector) -> Bool {
        NSApplication.shared.target(forAction: action, to: nil, from: nil) != nil
    }
}

@MainActor
final class SystemSelectionAppContextProvider: SelectionAppContextProviding {
    private let frontmostBundleIDProvider: () -> String?
    private let menuActionSender: any SelectionMenuActionSending

    init(
        frontmostBundleIDProvider: @escaping () -> String? = {
            NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        },
        menuActionSender: any SelectionMenuActionSending = AppKitSelectionMenuActionSender()
    ) {
        self.frontmostBundleIDProvider = frontmostBundleIDProvider
        self.menuActionSender = menuActionSender
    }

    func isFrontmostAppSelf() -> Bool {
        frontmostBundleIDProvider() == Bundle.main.bundleIdentifier
    }

    func frontmostBundleIdentifier() -> String? {
        frontmostBundleIDProvider()
    }

    func hasEnabledCopyMenuItem() -> Bool {
        menuActionSender.canSendAction(#selector(NSText.copy(_:)))
    }
}

@MainActor
final class AppleScriptBrowserSelectionReader: SelectionBrowserSelectionReading {
    private enum BrowserKind {
        case safari
        case chromium
    }

    func selectedText(bundleIdentifier: String?) -> String? {
        guard let bundleIdentifier,
              let kind = Self.browserKind(for: bundleIdentifier),
              let source = Self.appleScriptSource(bundleIdentifier: bundleIdentifier, kind: kind) else {
            return nil
        }

        var error: NSDictionary?
        let descriptor = NSAppleScript(source: source)?.executeAndReturnError(&error)
        guard error == nil else {
            return nil
        }
        return descriptor?.stringValue
    }

    private static func browserKind(for bundleIdentifier: String) -> BrowserKind? {
        switch bundleIdentifier {
        case "com.apple.Safari":
            return .safari
        case "com.google.Chrome",
             "com.microsoft.edgemac",
             "com.brave.Browser",
             "company.thebrowser.Browser":
            return .chromium
        default:
            return nil
        }
    }

    private static func appleScriptSource(bundleIdentifier: String, kind: BrowserKind) -> String? {
        let escapedBundleIdentifier = bundleIdentifier.replacingOccurrences(of: "\"", with: "\\\"")
        let javascript = "window.getSelection().toString()"
        switch kind {
        case .safari:
            return """
            tell application id "\(escapedBundleIdentifier)"
                if not (exists front window) then return ""
                return do JavaScript "\(javascript)" in current tab of front window
            end tell
            """
        case .chromium:
            return """
            tell application id "\(escapedBundleIdentifier)"
                if not (exists front window) then return ""
                return execute active tab of front window javascript "\(javascript)"
            end tell
            """
        }
    }
}

final class SystemSelectionAccessibilityReader: SelectionAccessibilityReading, @unchecked Sendable {
    private let targetProvider: any DictationTargetProviding
    private let accessibilityProvider: any AccessibilityProviding

    @MainActor
    init(
        targetProvider: any DictationTargetProviding = WorkspaceDictationTargetProvider(),
        accessibilityProvider: any AccessibilityProviding = SystemAccessibilityProvider()
    ) {
        self.targetProvider = targetProvider
        self.accessibilityProvider = accessibilityProvider
    }

    @MainActor
    func selectedText() throws -> String? {
        accessibilityProvider.selectedText(pid: targetProvider.currentTarget()?.pid)
    }

    @MainActor
    func selectedTextBounds() throws -> NSRect? {
        accessibilityProvider.selectedTextBounds(pid: targetProvider.currentTarget()?.pid)
    }

    @MainActor
    func isFocusedTextField() -> Bool {
        accessibilityProvider.inputAreaText(pid: targetProvider.currentTarget()?.pid) != nil
    }
}

final class SystemSelectionAcquisitionAdapter: SelectionAcquisitionSystemAdapter, @unchecked Sendable {
    private let accessibilityReader: any SelectionAccessibilityReading
    private let copyPerformer: any SelectionCopyPerforming
    private let browserSelectionReader: any SelectionBrowserSelectionReading
    private let pasteboard: NSPasteboard
    private let appContext: any SelectionAppContextProviding

    init(
        accessibilityReader: any SelectionAccessibilityReading,
        copyPerformer: any SelectionCopyPerforming,
        browserSelectionReader: any SelectionBrowserSelectionReading = AppleScriptBrowserSelectionReader(),
        pasteboard: NSPasteboard = .general,
        appContext: any SelectionAppContextProviding
    ) {
        self.accessibilityReader = accessibilityReader
        self.copyPerformer = copyPerformer
        self.browserSelectionReader = browserSelectionReader
        self.pasteboard = pasteboard
        self.appContext = appContext
    }

    func selectedText(using strategy: SelectionTextAcquisitionStrategy) async throws -> String? {
        switch strategy {
        case .accessibility:
            return try await accessibilityReader.selectedText()
        case .browserScript:
            return await browserSelectionReader.selectedText(
                bundleIdentifier: appContext.frontmostBundleIdentifier()
            )
        case .shortcutCopy:
            return await copySelectedText {
                await copyPerformer.performShortcutCopy()
                return true
            }
        case .menuCopy:
            return await copySelectedText {
                await copyPerformer.performMenuCopy()
            }
        }
    }

    func selectedTextBounds(using strategy: SelectionTextAcquisitionStrategy) async -> NSRect? {
        guard strategy == .accessibility else { return nil }
        return try? await accessibilityReader.selectedTextBounds()
    }

    func isFocusedTextField() async -> Bool {
        await accessibilityReader.isFocusedTextField()
    }

    func hasEnabledCopyMenuItem() async -> Bool {
        await appContext.hasEnabledCopyMenuItem()
    }

    func isFrontmostAppSelf() async -> Bool {
        await appContext.isFrontmostAppSelf()
    }

    private func copySelectedText(
        performCopy: @MainActor @Sendable () async -> Bool
    ) async -> String? {
        let originalSnapshot = PasteboardSnapshot(items: pasteboard.pasteboardItems ?? [])
        let originalChangeCount = pasteboard.changeCount
        let performedCopy = await performCopy()
        guard performedCopy, pasteboard.changeCount != originalChangeCount else {
            return nil
        }
        let copiedText = pasteboard.string(forType: .string)
        let copiedChangeCount = pasteboard.changeCount
        restoreOriginalSnapshotIfPasteboardIsUnchangedSinceCopy(
            originalSnapshot,
            copiedChangeCount: copiedChangeCount
        )
        return copiedText
    }

    private func restoreOriginalSnapshotIfPasteboardIsUnchangedSinceCopy(
        _ snapshot: PasteboardSnapshot,
        copiedChangeCount: Int
    ) {
        guard pasteboard.changeCount == copiedChangeCount else {
            return
        }
        pasteboard.clearContents()
        let items = snapshot.makePasteboardItems()
        if !items.isEmpty {
            pasteboard.writeObjects(items)
        }
    }
}

struct SelectionTextProviderConfiguration: Equatable, Sendable {
    enum ForceCopyOrder: Equatable, Sendable {
        case shortcutFirst
        case menuFirst
    }

    var forceCopyEnabled: Bool
    var forceCopyOrder: ForceCopyOrder
    var browserScriptFallbackEnabled: Bool

    static let `default` = SelectionTextProviderConfiguration(
        forceCopyEnabled: false,
        forceCopyOrder: .shortcutFirst,
        browserScriptFallbackEnabled: false
    )

    static func userInitiated(frontmostBundleIdentifier: String?) -> SelectionTextProviderConfiguration {
        SelectionTextProviderConfiguration(
            forceCopyEnabled: true,
            forceCopyOrder: forceCopyOrder(for: frontmostBundleIdentifier),
            browserScriptFallbackEnabled: browserBundleIdentifiers.contains(frontmostBundleIdentifier ?? "")
        )
    }

    private static func forceCopyOrder(for bundleIdentifier: String?) -> ForceCopyOrder {
        guard let bundleIdentifier else {
            return .shortcutFirst
        }

        if editorBundleIdentifiers.contains(bundleIdentifier) {
            return .shortcutFirst
        }

        return .shortcutFirst
    }

    private static let editorBundleIdentifiers: Set<String> = [
        "com.apple.dt.Xcode",
        "com.cursor.Cursor",
        "com.microsoft.VSCode",
        "com.todesktop.230313mzl4w4u92",
    ]

    private static let browserBundleIdentifiers: Set<String> = [
        "com.apple.Safari",
        "com.brave.Browser",
        "com.google.Chrome",
        "com.microsoft.edgemac",
        "company.thebrowser.Browser",
    ]
}

final class SelectionTextProvider: @unchecked Sendable {
    private let adapter: any SelectionAcquisitionSystemAdapter
    private let configuration: SelectionTextProviderConfiguration

    init(
        adapter: any SelectionAcquisitionSystemAdapter,
        configuration: SelectionTextProviderConfiguration = .default
    ) {
        self.adapter = adapter
        self.configuration = configuration
    }

    func snapshot() async -> SelectionTextSnapshot? {
        try? await snapshotResult().get()
    }

    func snapshotResult() async -> Result<SelectionTextSnapshot, SelectionTextProviderFailure> {
        if let accessibilitySnapshot = await snapshot(using: .accessibility) {
            return .success(accessibilitySnapshot)
        }

        guard configuration.forceCopyEnabled,
              !(await adapter.isFrontmostAppSelf()) else {
            if configuration.forceCopyEnabled {
                return .failure(.frontmostAppIsSelf)
            }
            return .failure(.forceCopyDisabled)
        }

        if configuration.browserScriptFallbackEnabled,
           let browserSnapshot = await snapshot(using: .browserScript) {
            return .success(browserSnapshot)
        }

        switch configuration.forceCopyOrder {
        case .shortcutFirst:
            if let shortcutSnapshot = await snapshot(using: .shortcutCopy) {
                return .success(shortcutSnapshot)
            }
            if let menuSnapshot = await snapshot(using: .menuCopy) {
                return .success(menuSnapshot)
            }
            return .failure(.copyFallbackFailed(.menuCopy))
        case .menuFirst:
            if let menuSnapshot = await snapshot(using: .menuCopy) {
                return .success(menuSnapshot)
            }
            guard !(await adapter.hasEnabledCopyMenuItem()) else {
                return .failure(.copyFallbackFailed(.menuCopy))
            }
            if let shortcutSnapshot = await snapshot(using: .shortcutCopy) {
                return .success(shortcutSnapshot)
            }
            return .failure(.copyFallbackFailed(.shortcutCopy))
        }
    }

    private func snapshot(
        using strategy: SelectionTextAcquisitionStrategy
    ) async -> SelectionTextSnapshot? {
        do {
            let text = try await adapter.selectedText(using: strategy)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !text.isEmpty else { return nil }
            return SelectionTextSnapshot(
                text: text,
                source: strategy,
                isEditable: await adapter.isFocusedTextField(),
                selectionBounds: await adapter.selectedTextBounds(using: strategy)
            )
        } catch {
            return nil
        }
    }
}
