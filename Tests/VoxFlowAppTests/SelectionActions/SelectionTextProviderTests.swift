import AppKit
import XCTest
@testable import VoxFlowApp

final class SelectionTextProviderTests: XCTestCase {
    func testAccessibilitySelectedTextWinsWithoutFallback() async {
        let adapter = CapturingSelectionAcquisitionAdapter(
            responses: [.accessibility: "  hello  "],
            editable: true
        )
        let provider = SelectionTextProvider(adapter: adapter)

        let snapshot = await provider.snapshot()

        XCTAssertEqual(
            snapshot,
            SelectionTextSnapshot(
                text: "hello",
                source: .accessibility,
                isEditable: true
            )
        )
        XCTAssertEqual(adapter.requestedStrategies, [.accessibility])
    }

    func testAccessibilitySelectedTextCarriesSelectionBounds() async {
        let bounds = NSRect(x: 240, y: 520, width: 160, height: 22)
        let adapter = CapturingSelectionAcquisitionAdapter(
            responses: [.accessibility: "hello"],
            selectionBounds: [.accessibility: bounds]
        )
        let provider = SelectionTextProvider(adapter: adapter)

        let snapshot = await provider.snapshot()

        XCTAssertEqual(snapshot?.selectionBounds, bounds)
    }

    func testUserInitiatedConfigurationUsesShortcutCopyFallback() async {
        let adapter = CapturingSelectionAcquisitionAdapter(
            responses: [
                .accessibility: "",
                .shortcutCopy: "shortcut text",
                .menuCopy: "menu text",
            ]
        )
        let provider = SelectionTextProvider(
            adapter: adapter,
            configuration: .userInitiated(frontmostBundleIdentifier: "com.apple.TextEdit")
        )

        let result = await provider.snapshotResult()

        XCTAssertEqual(
            result,
            .success(SelectionTextSnapshot(text: "shortcut text", source: .shortcutCopy, isEditable: false))
        )
        XCTAssertEqual(adapter.requestedStrategies, [.accessibility, .shortcutCopy])
    }

    func testDefaultConfigurationKeepsProgrammaticProviderSideEffectFree() async {
        let adapter = CapturingSelectionAcquisitionAdapter(
            responses: [
                .accessibility: "",
                .shortcutCopy: "shortcut text",
                .menuCopy: "menu text",
            ]
        )
        let provider = SelectionTextProvider(adapter: adapter)

        let result = await provider.snapshotResult()

        XCTAssertEqual(result, .failure(.forceCopyDisabled))
        XCTAssertEqual(adapter.requestedStrategies, [.accessibility])
    }

    func testEditorAppPolicyUsesShortcutCopyBeforeMenuCopy() async {
        for bundleID in [
            "com.microsoft.VSCode",
            "com.apple.dt.Xcode",
            "com.todesktop.230313mzl4w4u92",
            "com.cursor.Cursor",
        ] {
            let configuration = SelectionTextProviderConfiguration.userInitiated(
                frontmostBundleIdentifier: bundleID
            )

            XCTAssertEqual(configuration.forceCopyOrder, .shortcutFirst, bundleID)
            XCTAssertTrue(configuration.forceCopyEnabled, bundleID)
        }
    }

    func testBrowserAppPolicyUsesBrowserScriptBeforeCopyFallback() async {
        let adapter = CapturingSelectionAcquisitionAdapter(
            responses: [
                .accessibility: "",
                .browserScript: "browser selected text",
                .shortcutCopy: "shortcut selected text",
            ]
        )
        let provider = SelectionTextProvider(
            adapter: adapter,
            configuration: .userInitiated(frontmostBundleIdentifier: "com.apple.Safari")
        )

        let snapshot = await provider.snapshot()

        XCTAssertEqual(snapshot?.text, "browser selected text")
        XCTAssertEqual(snapshot?.source, .browserScript)
        XCTAssertEqual(adapter.requestedStrategies, [.accessibility, .browserScript])
    }

    func testFallbackUsesShortcutCopyBeforeMenuCopyWhenExplicitlyEnabled() async {
        let adapter = CapturingSelectionAcquisitionAdapter(
            responses: [
                .accessibility: "",
                .shortcutCopy: "",
                .menuCopy: "menu text",
            ]
        )
        let provider = SelectionTextProvider(
            adapter: adapter,
            configuration: SelectionTextProviderConfiguration(
                forceCopyEnabled: true,
                forceCopyOrder: .shortcutFirst,
                browserScriptFallbackEnabled: false
            )
        )

        let snapshot = await provider.snapshot()

        XCTAssertEqual(snapshot?.text, "menu text")
        XCTAssertEqual(snapshot?.source, .menuCopy)
        XCTAssertEqual(adapter.requestedStrategies, [.accessibility, .shortcutCopy, .menuCopy])
    }

    func testDoesNotForceCopyWhenFrontmostAppIsVoxFlow() async {
        let adapter = CapturingSelectionAcquisitionAdapter(
            responses: [.accessibility: ""],
            frontmostAppIsSelf: true
        )
        let provider = SelectionTextProvider(adapter: adapter)

        let snapshot = await provider.snapshot()

        XCTAssertNil(snapshot)
        XCTAssertEqual(adapter.requestedStrategies, [.accessibility])
    }

    func testMenuCopyFailureReturnsExplicitProviderError() async {
        let adapter = CapturingSelectionAcquisitionAdapter(
            responses: [
                .accessibility: "",
                .menuCopy: "",
            ]
        )
        let provider = SelectionTextProvider(
            adapter: adapter,
            configuration: SelectionTextProviderConfiguration(
                forceCopyEnabled: true,
                forceCopyOrder: .menuFirst,
                browserScriptFallbackEnabled: false
            )
        )

        let result = await provider.snapshotResult()

        XCTAssertEqual(result, .failure(.copyFallbackFailed(.menuCopy)))
        XCTAssertEqual(adapter.requestedStrategies, [.accessibility, .menuCopy])
    }

    @MainActor
    func testShortcutCopyFallbackRestoresOriginalPasteboard() async throws {
        let pasteboard = try XCTUnwrap(NSPasteboard(name: NSPasteboard.Name("SelectionTextProviderTests-\(UUID().uuidString)")))
        pasteboard.clearContents()
        pasteboard.setString("original clipboard", forType: .string)
        let copyPerformer = CapturingSelectionCopyPerformer(
            pasteboard: pasteboard,
            shortcutText: "selected by shortcut"
        )
        let adapter = SystemSelectionAcquisitionAdapter(
            accessibilityReader: EmptySelectionAccessibilityReader(),
            copyPerformer: copyPerformer,
            pasteboard: pasteboard,
            appContext: StubSelectionAppContext()
        )

        let text = try await adapter.selectedText(using: .shortcutCopy)

        XCTAssertEqual(text, "selected by shortcut")
        XCTAssertEqual(copyPerformer.shortcutCopyCount, 1)
        XCTAssertEqual(pasteboard.string(forType: .string), "original clipboard")
    }

    @MainActor
    func testShortcutCopyFallbackReturnsNilWhenCopyDoesNotChangePasteboard() async throws {
        let pasteboard = try XCTUnwrap(NSPasteboard(name: NSPasteboard.Name("SelectionTextProviderTests-\(UUID().uuidString)")))
        pasteboard.clearContents()
        pasteboard.setString("original clipboard", forType: .string)
        let copyPerformer = CapturingSelectionCopyPerformer(
            pasteboard: pasteboard,
            shortcutText: nil
        )
        let adapter = SystemSelectionAcquisitionAdapter(
            accessibilityReader: EmptySelectionAccessibilityReader(),
            copyPerformer: copyPerformer,
            pasteboard: pasteboard,
            appContext: StubSelectionAppContext()
        )

        let text = try await adapter.selectedText(using: .shortcutCopy)

        XCTAssertNil(text)
        XCTAssertEqual(copyPerformer.shortcutCopyCount, 1)
        XCTAssertEqual(pasteboard.string(forType: .string), "original clipboard")
    }

    @MainActor
    func testMenuCopyFallbackReturnsNilWhenMenuActionFailsWithoutTouchingClipboard() async throws {
        let pasteboard = try XCTUnwrap(NSPasteboard(name: NSPasteboard.Name("SelectionTextProviderTests-\(UUID().uuidString)")))
        pasteboard.clearContents()
        pasteboard.setString("original clipboard", forType: .string)
        let copyPerformer = CapturingSelectionCopyPerformer(
            pasteboard: pasteboard,
            menuText: nil,
            menuCopySucceeded: false
        )
        let adapter = SystemSelectionAcquisitionAdapter(
            accessibilityReader: EmptySelectionAccessibilityReader(),
            copyPerformer: copyPerformer,
            pasteboard: pasteboard,
            appContext: StubSelectionAppContext()
        )

        let text = try await adapter.selectedText(using: .menuCopy)

        XCTAssertNil(text)
        XCTAssertEqual(copyPerformer.menuCopyCount, 1)
        XCTAssertEqual(pasteboard.string(forType: .string), "original clipboard")
    }

    @MainActor
    func testSystemAccessibilityReaderUsesCurrentTargetPidForSelectedText() throws {
        let accessibilityProvider = CapturingAccessibilityProvider(
            selectedText: "selected from ax",
            inputAreaText: "editable value"
        )
        let reader = SystemSelectionAccessibilityReader(
            targetProvider: StaticDictationTargetProvider(target: DictationTarget(pid: 42)),
            accessibilityProvider: accessibilityProvider
        )

        let selectedText = try reader.selectedText()

        XCTAssertEqual(selectedText, "selected from ax")
        XCTAssertEqual(accessibilityProvider.selectedTextPIDs, [42])
        XCTAssertTrue(reader.isFocusedTextField())
    }

    @MainActor
    func testSystemCopyPerformerPostsCommandCForShortcutCopy() async {
        let keyboard = CapturingSelectionKeyboardEventPoster()
        let performer = SystemSelectionCopyPerformer(
            keyboardEventPoster: keyboard,
            menuActionSender: StubSelectionMenuActionSender(result: false),
            settleDelayNanoseconds: 0
        )

        await performer.performShortcutCopy()

        XCTAssertEqual(
            keyboard.events,
            [
                CapturingSelectionKeyboardEventPoster.Event(keyCode: 0x08, flags: .maskCommand, keyDown: true),
                CapturingSelectionKeyboardEventPoster.Event(keyCode: 0x08, flags: .maskCommand, keyDown: false),
            ]
        )
    }

    @MainActor
    func testSystemCopyPerformerReturnsMenuCopyActionResult() async {
        let menuActionSender = StubSelectionMenuActionSender(result: true)
        let performer = SystemSelectionCopyPerformer(
            keyboardEventPoster: CapturingSelectionKeyboardEventPoster(),
            menuActionSender: menuActionSender,
            settleDelayNanoseconds: 0
        )

        let result = await performer.performMenuCopy()

        XCTAssertTrue(result)
        XCTAssertEqual(menuActionSender.sentActions, [#selector(NSText.copy(_:))])
    }

    @MainActor
    func testSystemAppContextProviderChecksSelfAndCopyMenuAvailability() {
        let menuActionSender = StubSelectionMenuActionSender(result: false, canSendResult: true)
        let provider = SystemSelectionAppContextProvider(
            frontmostBundleIDProvider: { Bundle.main.bundleIdentifier },
            menuActionSender: menuActionSender
        )

        XCTAssertTrue(provider.isFrontmostAppSelf())
        XCTAssertTrue(provider.hasEnabledCopyMenuItem())
        XCTAssertEqual(menuActionSender.checkedActions, [#selector(NSText.copy(_:))])
    }
}

private final class CapturingSelectionAcquisitionAdapter: SelectionAcquisitionSystemAdapter, @unchecked Sendable {
    private let responses: [SelectionTextAcquisitionStrategy: String]
    private let selectionBounds: [SelectionTextAcquisitionStrategy: NSRect]
    private let editable: Bool
    private let frontmostAppIsSelf: Bool
    private(set) var requestedStrategies: [SelectionTextAcquisitionStrategy] = []

    init(
        responses: [SelectionTextAcquisitionStrategy: String],
        selectionBounds: [SelectionTextAcquisitionStrategy: NSRect] = [:],
        editable: Bool = false,
        frontmostAppIsSelf: Bool = false
    ) {
        self.responses = responses
        self.selectionBounds = selectionBounds
        self.editable = editable
        self.frontmostAppIsSelf = frontmostAppIsSelf
    }

    func selectedText(using strategy: SelectionTextAcquisitionStrategy) async throws -> String? {
        requestedStrategies.append(strategy)
        return responses[strategy]
    }

    func selectedTextBounds(using strategy: SelectionTextAcquisitionStrategy) async -> NSRect? {
        selectionBounds[strategy]
    }

    func isFocusedTextField() async -> Bool {
        editable
    }

    func hasEnabledCopyMenuItem() async -> Bool {
        true
    }

    func isFrontmostAppSelf() async -> Bool {
        frontmostAppIsSelf
    }
}

@MainActor
private final class CapturingSelectionCopyPerformer: SelectionCopyPerforming {
    private let pasteboard: NSPasteboard
    private let shortcutText: String?
    private let menuText: String?
    private let menuCopySucceeded: Bool
    private(set) var shortcutCopyCount = 0
    private(set) var menuCopyCount = 0

    init(
        pasteboard: NSPasteboard,
        shortcutText: String? = nil,
        menuText: String? = nil,
        menuCopySucceeded: Bool = false
    ) {
        self.pasteboard = pasteboard
        self.shortcutText = shortcutText
        self.menuText = menuText
        self.menuCopySucceeded = menuCopySucceeded
    }

    func performShortcutCopy() async {
        shortcutCopyCount += 1
        if let shortcutText {
            pasteboard.clearContents()
            pasteboard.setString(shortcutText, forType: .string)
        }
    }

    func performMenuCopy() async -> Bool {
        menuCopyCount += 1
        if let menuText {
            pasteboard.clearContents()
            pasteboard.setString(menuText, forType: .string)
        }
        return menuCopySucceeded
    }
}

private struct EmptySelectionAccessibilityReader: SelectionAccessibilityReading {
    func selectedText() throws -> String? { nil }
    func selectedTextBounds() throws -> NSRect? { nil }
    func isFocusedTextField() -> Bool { false }
}

private struct StubSelectionAppContext: SelectionAppContextProviding {
    @MainActor
    func isFrontmostAppSelf() -> Bool { false }
    @MainActor
    func frontmostBundleIdentifier() -> String? { nil }
    @MainActor
    func hasEnabledCopyMenuItem() -> Bool { true }
}

private final class CapturingAccessibilityProvider: AccessibilityProviding, @unchecked Sendable {
    private let selectedTextValue: String?
    private let inputAreaTextValue: String?
    private(set) var selectedTextPIDs: [Int?] = []

    init(selectedText: String?, inputAreaText: String?) {
        self.selectedTextValue = selectedText
        self.inputAreaTextValue = inputAreaText
    }

    func visibleText(pid: Int?) -> String? { nil }

    func selectedText(pid: Int?) -> String? {
        selectedTextPIDs.append(pid)
        return selectedTextValue
    }

    func selectedTextBounds(pid: Int?) -> NSRect? {
        nil
    }

    func inputAreaText(pid: Int?) -> String? {
        inputAreaTextValue
    }

    func isSecureTextField(pid: Int?) -> Bool { false }
}

@MainActor
private final class CapturingSelectionKeyboardEventPoster: SelectionKeyboardEventPosting {
    struct Event: Equatable {
        let keyCode: CGKeyCode
        let flags: CGEventFlags
        let keyDown: Bool
    }

    private(set) var events: [Event] = []

    func postKeyEvent(keyCode: CGKeyCode, flags: CGEventFlags, keyDown: Bool) {
        events.append(Event(keyCode: keyCode, flags: flags, keyDown: keyDown))
    }
}

@MainActor
private final class StubSelectionMenuActionSender: SelectionMenuActionSending {
    private let result: Bool
    private let canSendResult: Bool
    private(set) var sentActions: [Selector] = []
    private(set) var checkedActions: [Selector] = []

    init(result: Bool, canSendResult: Bool = false) {
        self.result = result
        self.canSendResult = canSendResult
    }

    func sendAction(_ action: Selector) -> Bool {
        sentActions.append(action)
        return result
    }

    func canSendAction(_ action: Selector) -> Bool {
        checkedActions.append(action)
        return canSendResult
    }
}
