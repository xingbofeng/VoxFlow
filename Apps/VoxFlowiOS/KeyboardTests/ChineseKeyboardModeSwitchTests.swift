import XCTest
import UIKit
import ChineseInput

@MainActor
final class ChineseKeyboardModeSwitchTests: XCTestCase {
    override func tearDown() {
        ChineseAuxiliaryPanelState.shared.dismiss()
        ChineseKeyboardModeStore.active = .chineseQwerty
        super.tearDown()
    }

    func testEnglishSwitchAlternateChangesKeyboardMode() {
        ChineseKeyboardModeStore.active = .chineseQwerty
        let bridge = DictusKeyboardBridge()

        bridge.didTriggerKey(KeyDefinition(type: .input(key: "EN", alternate: "switchEnglish")))

        XCTAssertEqual(ChineseKeyboardModeStore.active, .english)
    }

    func testChineseQwertySwitchAlternateChangesKeyboardMode() {
        ChineseKeyboardModeStore.active = .english
        let bridge = DictusKeyboardBridge()

        bridge.didTriggerKey(KeyDefinition(type: .input(key: "中文", alternate: "switchChineseQwerty")))

        XCTAssertEqual(ChineseKeyboardModeStore.active, .chineseQwerty)
    }

    func testNineGridSymbolAlternateOpensChineseSymbolPanel() {
        ChineseKeyboardModeStore.active = .chineseNineGrid
        ChineseAuxiliaryPanelState.shared.dismiss()
        let definition = KeyboardLayouts.current()
        let keyboardView = GiellaKeyboardView(definition: definition, theme: Theme.current(for: UITraitCollection()))
        let bridge = DictusKeyboardBridge()
        bridge.keyboardView = keyboardView

        bridge.didTriggerKey(KeyDefinition(type: .input(key: "符号", alternate: "openChineseSymbols")))

        XCTAssertEqual(ChineseAuxiliaryPanelState.shared.mode, .symbols)
        XCTAssertEqual(keyboardView.page, .normal)
        ChineseAuxiliaryPanelState.shared.dismiss()
    }

    func testChineseNumberAlternateOpensChineseNumberPanel() {
        ChineseKeyboardModeStore.active = .chineseNineGrid
        ChineseAuxiliaryPanelState.shared.dismiss()
        let definition = KeyboardLayouts.current()
        let keyboardView = GiellaKeyboardView(definition: definition, theme: Theme.current(for: UITraitCollection()))
        let bridge = DictusKeyboardBridge()
        bridge.keyboardView = keyboardView

        bridge.didTriggerKey(KeyDefinition(type: .input(key: "123", alternate: "openChineseNumbers")))

        XCTAssertEqual(ChineseAuxiliaryPanelState.shared.mode, .numbers)
        XCTAssertEqual(keyboardView.page, .normal)
        ChineseAuxiliaryPanelState.shared.dismiss()
    }

    func testToolbarHidesModeToggleWhileChineseCandidatesAreVisible() {
        XCTAssertTrue(ToolbarDisplayPolicy.showsChineseModeToggle(suggestions: [], suggestionMode: .idle, statusMessage: nil))
        XCTAssertFalse(ToolbarDisplayPolicy.showsChineseModeToggle(suggestions: ["wo"], suggestionMode: .chineseCandidates, statusMessage: nil))
        XCTAssertFalse(ToolbarDisplayPolicy.showsChineseModeToggle(suggestions: [], suggestionMode: .idle, statusMessage: "error"))
    }

    func testChinesePreeditShowsInToolbarWhenRimeHasNoCandidatesYet() {
        let state = SuggestionState.shared
        state.clear()

        state.updateChineseComposition(preedit: "w", candidates: [])

        XCTAssertEqual(state.mode, .chineseCandidates)
        XCTAssertEqual(state.suggestions, [])
        XCTAssertEqual(state.toolbarSuggestions, ["w"])

        state.clear()
    }

    func testChineseInputFailureFallsBackToRawHostText() async throws {
        ChineseKeyboardModeStore.active = .chineseQwerty
        let controller = CapturingInputViewController()
        let bridge = DictusKeyboardBridge()
        let session = ChineseInputSession(bridge: ThrowingChineseRimeBridge())

        try await session.start(hasFullAccess: false)
        bridge.controller = controller
        bridge.chineseInputSession = session
        bridge.suggestionState = SuggestionState.shared
        SuggestionState.shared.clear()

        bridge.didTriggerKey(KeyDefinition(type: .input(key: "w", alternate: nil)))

        // Rime input() throws → key is re-buffered, not inserted as raw host text.
        // Host text stays empty.
        await waitUntil { controller.proxy.text.isEmpty }
        XCTAssertEqual(controller.proxy.text, "")
        SuggestionState.shared.clear()
    }

    func testChineseInputEmptyCompositionFallsBackToRawHostText() async throws {
        ChineseKeyboardModeStore.active = .chineseQwerty
        let controller = CapturingInputViewController()
        let bridge = DictusKeyboardBridge()
        let session = ChineseInputSession(bridge: EmptyChineseRimeBridge())

        try await session.start(hasFullAccess: false)
        bridge.controller = controller
        bridge.chineseInputSession = session
        bridge.suggestionState = SuggestionState.shared
        SuggestionState.shared.clear()

        bridge.didTriggerKey(KeyDefinition(type: .input(key: "x", alternate: nil)))

        await waitUntil { controller.proxy.text == "x" }
        XCTAssertEqual(controller.proxy.text, "x")
        SuggestionState.shared.clear()
    }

    func testChineseQwertyCandidateTapCommitsTextToHostProxy() async throws {
        ChineseKeyboardModeStore.active = .chineseQwerty
        let controller = CapturingInputViewController()
        let bridge = DictusKeyboardBridge()
        let session = ChineseInputSession(bridge: ScriptedChineseRimeBridge(
            inputStates: [
                .init(preedit: "n", candidates: [CandidateSuggestion(index: 0, label: "1", text: "你")]),
                .init(preedit: "ni", candidates: [CandidateSuggestion(index: 0, label: "1", text: "你")]),
            ],
            selectedStates: [
                .init(commitText: "你"),
            ]
        ))

        try await session.start(hasFullAccess: false)
        bridge.controller = controller
        bridge.chineseInputSession = session
        bridge.suggestionState = SuggestionState.shared
        SuggestionState.shared.clear()

        bridge.didTriggerKey(KeyDefinition(type: .input(key: "n", alternate: nil)))
        bridge.didTriggerKey(KeyDefinition(type: .input(key: "i", alternate: nil)))
        await waitUntil { SuggestionState.shared.toolbarSuggestions.contains("你") }

        bridge.handleChineseCandidateTap(index: 0)

        await waitUntil { controller.proxy.text == "你" }
        XCTAssertEqual(controller.proxy.text, "你")
        XCTAssertEqual(SuggestionState.shared.mode, .idle)
        SuggestionState.shared.clear()
    }

    func testChineseQwertyBuffersInputUntilNativeSessionStarts() async throws {
        ChineseKeyboardModeStore.active = .chineseQwerty
        let controller = CapturingInputViewController()
        let bridge = DictusKeyboardBridge()
        let session = ChineseInputSession(bridge: ScriptedChineseRimeBridge(
            inputStates: [
                .init(preedit: "g", candidates: [CandidateSuggestion(index: 0, label: "1", text: "哥")]),
            ],
            selectedStates: []
        ))

        bridge.controller = controller
        bridge.prepareChineseInputSession(session)
        bridge.suggestionState = SuggestionState.shared
        SuggestionState.shared.clear()

        bridge.didTriggerKey(KeyDefinition(type: .input(key: "g", alternate: nil)))

        XCTAssertEqual(controller.proxy.text, "")
        XCTAssertEqual(SuggestionState.shared.mode, .chineseCandidates)
        XCTAssertEqual(SuggestionState.shared.toolbarSuggestions, ["g"])

        try await session.start(hasFullAccess: false)
        bridge.handleChineseInputSessionStarted()

        await waitUntil { SuggestionState.shared.toolbarSuggestions.contains("哥") }
        XCTAssertEqual(controller.proxy.text, "")
        SuggestionState.shared.clear()
    }

    func testChineseQwertyRequestsNativeSessionOnlyWhenChineseInputStarts() {
        ChineseKeyboardModeStore.active = .chineseQwerty
        let controller = CapturingInputViewController()
        let bridge = DictusKeyboardBridge()
        var requestCount = 0

        bridge.controller = controller
        bridge.suggestionState = SuggestionState.shared
        bridge.onChineseInputNeeded = {
            requestCount += 1
        }
        SuggestionState.shared.clear()

        bridge.didTriggerKey(KeyDefinition(type: .input(key: "g", alternate: nil)))

        XCTAssertEqual(requestCount, 1)
        XCTAssertEqual(controller.proxy.text, "")
        XCTAssertEqual(SuggestionState.shared.toolbarSuggestions, ["g"])
        SuggestionState.shared.clear()
    }

    func testChineseQwertyFlushesBufferedInputAsRawWhenNativeSessionFails() {
        ChineseKeyboardModeStore.active = .chineseQwerty
        let controller = CapturingInputViewController()
        let bridge = DictusKeyboardBridge()

        bridge.controller = controller
        bridge.suggestionState = SuggestionState.shared
        SuggestionState.shared.clear()

        bridge.didTriggerKey(KeyDefinition(type: .input(key: "g", alternate: nil)))
        bridge.handleChineseInputSessionFailed()

        // Session failure clears the buffer without inserting raw host text.
        XCTAssertEqual(controller.proxy.text, "")
        SuggestionState.shared.clear()
    }

    func testChineseNineGridDigitDoesNotInsertRawDigitBeforeNativeSessionStarts() {
        ChineseKeyboardModeStore.active = .chineseNineGrid
        let controller = CapturingInputViewController()
        let bridge = DictusKeyboardBridge()
        var requestCount = 0

        bridge.controller = controller
        bridge.suggestionState = SuggestionState.shared
        bridge.onChineseInputNeeded = {
            requestCount += 1
        }
        SuggestionState.shared.clear()

        bridge.didTriggerKey(KeyDefinition(type: .input(key: "MNO", alternate: "chineseNineGridDigit:6")))

        XCTAssertEqual(requestCount, 1)
        XCTAssertEqual(controller.proxy.text, "")
        XCTAssertFalse(SuggestionState.shared.toolbarSuggestions.isEmpty)
        SuggestionState.shared.clear()
    }

    func testChineseNineGridCandidateTapCommitsTextToHostProxy() async throws {
        ChineseKeyboardModeStore.active = .chineseNineGrid
        let controller = CapturingInputViewController()
        let bridge = DictusKeyboardBridge()
        let session = ChineseInputSession(
            mode: .chineseNineGrid,
            bridge: ScriptedChineseRimeBridge(
                inputStates: [
                    .init(preedit: "6", candidates: [CandidateSuggestion(index: 0, label: "1", text: "你")]),
                    .init(preedit: "64", candidates: [CandidateSuggestion(index: 0, label: "1", text: "你")]),
                ],
                selectedStates: [
                    .init(commitText: "你"),
                ]
            )
        )

        try await session.start(hasFullAccess: false)
        bridge.controller = controller
        bridge.chineseInputSession = session
        bridge.suggestionState = SuggestionState.shared
        SuggestionState.shared.clear()

        bridge.didTriggerKey(KeyDefinition(type: .input(key: "MNO", alternate: "chineseNineGridDigit:6")))
        bridge.didTriggerKey(KeyDefinition(type: .input(key: "GHI", alternate: "chineseNineGridDigit:4")))
        await waitUntil { SuggestionState.shared.toolbarSuggestions.contains("你") }

        bridge.handleChineseCandidateTap(index: 0)

        await waitUntil { controller.proxy.text == "你" }
        XCTAssertEqual(controller.proxy.text, "你")
        XCTAssertEqual(SuggestionState.shared.mode, .idle)
        SuggestionState.shared.clear()
    }

    private func waitUntil(
        timeout: TimeInterval = 1,
        _ condition: @escaping @MainActor () -> Bool
    ) async {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTFail("Condition was not satisfied within \(timeout)s")
    }
}

private final class CapturingInputViewController: UIInputViewController {
    let proxy = CapturingTextDocumentProxy()

    override var textDocumentProxy: UITextDocumentProxy {
        proxy
    }
}

private final class CapturingTextDocumentProxy: NSObject, UITextDocumentProxy {
    var text = ""

    var documentContextBeforeInput: String? { text }
    var documentContextAfterInput: String? { nil }
    var selectedText: String? { nil }
    var documentInputMode: UITextInputMode? { nil }
    var documentIdentifier: UUID { UUID() }
    var hasText: Bool { !text.isEmpty }

    func insertText(_ text: String) {
        self.text += text
    }

    func deleteBackward() {
        if !text.isEmpty {
            text.removeLast()
        }
    }

    func adjustTextPosition(byCharacterOffset offset: Int) {}
    func setMarkedText(_ markedText: String, selectedRange: NSRange) {}
    func unmarkText() {}
}

private struct SampleChineseInputError: Error {}

@MainActor
private final class ThrowingChineseRimeBridge: ChineseRimeBridge {
    var state = ChineseCompositionState()
    var status: ChineseInputStatus = .idle

    func start(hasFullAccess: Bool) async throws {}

    func switchMode(_ mode: ChineseInputMode) async throws -> ChineseCompositionState {
        state
    }

    func input(_ text: String) async throws -> ChineseCompositionState {
        throw SampleChineseInputError()
    }

    func selectCandidate(at index: Int) async throws -> ChineseCompositionState {
        state
    }

    func deleteBackward() async throws -> ChineseCompositionState {
        state
    }

    func pageCandidates(from offset: Int, count: Int) async throws -> [CandidateSuggestion] { [] }
    func replacePreeditInput(_ replacement: String) async throws -> ChineseCompositionState { state }
    func reset() async {
        state = ChineseCompositionState()
    }
}

@MainActor
private final class EmptyChineseRimeBridge: ChineseRimeBridge {
    var state = ChineseCompositionState()
    var status: ChineseInputStatus = .idle

    func start(hasFullAccess: Bool) async throws {}

    func switchMode(_ mode: ChineseInputMode) async throws -> ChineseCompositionState {
        state
    }

    func input(_ text: String) async throws -> ChineseCompositionState {
        state
    }

    func selectCandidate(at index: Int) async throws -> ChineseCompositionState {
        state
    }

    func deleteBackward() async throws -> ChineseCompositionState {
        state
    }

    func pageCandidates(from offset: Int, count: Int) async throws -> [CandidateSuggestion] { [] }
    func replacePreeditInput(_ replacement: String) async throws -> ChineseCompositionState { state }
    func reset() async {
        state = ChineseCompositionState()
    }
}

@MainActor
private final class ScriptedChineseRimeBridge: ChineseRimeBridge {
    private(set) var state = ChineseCompositionState()
    var status: ChineseInputStatus = .idle
    private var inputStates: [ChineseCompositionState]
    private var selectedStates: [ChineseCompositionState]

    init(
        inputStates: [ChineseCompositionState],
        selectedStates: [ChineseCompositionState]
    ) {
        self.inputStates = inputStates
        self.selectedStates = selectedStates
    }

    func start(hasFullAccess: Bool) async throws {}

    func switchMode(_ mode: ChineseInputMode) async throws -> ChineseCompositionState {
        state = .init()
        return state
    }

    func input(_ text: String) async throws -> ChineseCompositionState {
        if !inputStates.isEmpty {
            state = inputStates.removeFirst()
        }
        return state
    }

    func selectCandidate(at index: Int) async throws -> ChineseCompositionState {
        if !selectedStates.isEmpty {
            state = selectedStates.removeFirst()
        }
        return state
    }

    func deleteBackward() async throws -> ChineseCompositionState {
        state = .init()
        return state
    }

    func pageCandidates(from offset: Int, count: Int) async throws -> [CandidateSuggestion] { [] }
    func replacePreeditInput(_ replacement: String) async throws -> ChineseCompositionState { state }
    func reset() async {
        state = .init()
    }
}
