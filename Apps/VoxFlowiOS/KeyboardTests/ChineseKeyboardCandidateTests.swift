import XCTest
import UIKit
import ChineseInput

@MainActor
final class ChineseKeyboardCandidateTests: XCTestCase {
    override func tearDown() {
        ChineseAuxiliaryPanelState.shared.dismiss()
        ChineseKeyboardModeStore.active = .chineseQwerty
        SuggestionState.shared.clear()
        super.tearDown()
    }

    // MARK: - Candidate window is not silently capped

    func testBridgeReturnsAllCandidatesNotCappedAtTen() async throws {
        let bridge = ManyCandidateBridge(candidateCount: 25)
        let session = ChineseInputSession(bridge: bridge)
        try await session.start(hasFullAccess: false)

        let action = try await session.input("nihao")
        guard case let .updateComposition(composition) = action else {
            XCTFail("Expected updateComposition")
            return
        }
        XCTAssertEqual(composition.candidates.count, 25, "Native bridge must surface all candidates, not just 10.")
    }

    func testSessionVisibleCandidatesWindowBoundsTheUICount() async throws {
        let bridge = ManyCandidateBridge(candidateCount: 250)
        let session = ChineseInputSession(bridge: bridge)
        try await session.start(hasFullAccess: false)
        _ = try await session.input("nihao")

        XCTAssertLessThanOrEqual(session.visibleCandidates.count, chineseCandidateWindowSize)
        XCTAssertEqual(session.state.composition.candidates.count, 250)
    }

    func testExpandedPanelReceivesFullCandidateList() {
        let state = SuggestionState.shared
        state.clear()

        let candidates = [
            CandidateSuggestion(index: 7, label: "8", text: "你", subtitle: "ni"),
            CandidateSuggestion(index: 23, label: "24", text: "泥", subtitle: "ni"),
        ]
        state.updateChineseComposition(.init(
            preedit: "ni",
            candidates: candidates,
            hasMoreCandidates: true,
            pinyinCandidates: ["ni", "mi"],
            selectedPinyin: "ni"
        ))

        XCTAssertEqual(state.mode, .chineseCandidates)
        XCTAssertEqual(state.chineseCandidates.map(\.index), [7, 23])
        XCTAssertEqual(state.rimeCandidateIndex(atVisibleIndex: 1), 23)
        XCTAssertEqual(state.chineseCandidates[1].subtitle, "ni")
        XCTAssertTrue(state.chineseHasMoreCandidates)
        XCTAssertEqual(state.chinesePinyinCandidates, ["ni", "mi"])
        XCTAssertEqual(state.chineseSelectedPinyin, "ni")
        XCTAssertEqual(state.toolbarSuggestions, ["你", "泥"])
        state.clear()
    }

    func testChineseCompositionClearRemovesPreeditPagingAndPinyinState() {
        let state = SuggestionState.shared
        state.updateChineseComposition(.init(
            preedit: "wo",
            candidates: [CandidateSuggestion(index: 0, label: "1", text: "我")],
            hasMoreCandidates: true,
            pinyinCandidates: ["wo", "yo"],
            selectedPinyin: "wo"
        ))

        state.clear()

        XCTAssertEqual(state.chinesePreedit, "")
        XCTAssertTrue(state.chineseCandidates.isEmpty)
        XCTAssertFalse(state.chineseHasMoreCandidates)
        XCTAssertTrue(state.chinesePinyinCandidates.isEmpty)
        XCTAssertNil(state.chineseSelectedPinyin)
    }

    func testNineGridCandidatePresentationUsesPinyinInsteadOfRawDigitPreedit() {
        let presentation = ChineseCandidatePanelPresentation(
            mode: .chineseNineGrid,
            rawPreedit: "96 4...",
            pinyinCandidates: ["wo", "yo", "9", "w", "x"],
            selectedPinyin: nil
        )

        XCTAssertEqual(presentation.preedit, "wo")
        XCTAssertEqual(presentation.pinyinCandidates, ["wo", "yo", "w", "x"])
        XCTAssertTrue(presentation.showsPinyinSidebar)
    }

    func testNineGridCandidatePresentationIgnoresStaleSelectedPinyin() {
        let presentation = ChineseCandidatePanelPresentation(
            mode: .chineseNineGrid,
            rawPreedit: "6464",
            pinyinCandidates: ["ming", "ning"],
            selectedPinyin: "zhong"
        )

        XCTAssertEqual(presentation.preedit, "ming")
        XCTAssertEqual(presentation.pinyinCandidates, ["ming", "ning"])
    }

    func testNumericChinesePreeditDoesNotBecomeToolbarSuggestion() {
        let state = SuggestionState.shared
        state.clear()

        state.updateChineseComposition(preedit: "222", candidates: [])

        XCTAssertEqual(state.mode, .chineseCandidates)
        XCTAssertTrue(state.toolbarSuggestions.isEmpty)
        state.clear()
    }

    func testQwertyCandidatePresentationKeepsLetterPreeditWithoutPinyinSidebar() {
        let presentation = ChineseCandidatePanelPresentation(
            mode: .chineseQwerty,
            rawPreedit: "wo",
            pinyinCandidates: ["wo", "yo"],
            selectedPinyin: nil
        )

        XCTAssertEqual(presentation.preedit, "wo")
        XCTAssertTrue(presentation.pinyinCandidates.isEmpty)
        XCTAssertFalse(presentation.showsPinyinSidebar)
    }

    func testKeyboardChromeStaysExpandedWhileChineseCandidatePanelIsVisible() {
        let layout = KeyboardChromeLayoutPolicy(
            dictationStatus: .idle,
            isShowingEmoji: false,
            isShowingAuxiliaryPanel: false,
            isShowingChineseCandidatePanel: true
        )

        XCTAssertTrue(layout.hidesKeyGrid)
        XCTAssertTrue(layout.expandsHostingView)
    }

    // MARK: - Consistent 9-key preview (no inert live-candidate trap)

    func testNineKeyPreviewBeforeSessionStartShowsPreeditOnly() async throws {
        ChineseKeyboardModeStore.active = .chineseNineGrid
        let bridge = DictusKeyboardBridge()
        let controller = CapturingInputViewController()
        bridge.controller = controller
        bridge.suggestionState = SuggestionState.shared
        SuggestionState.shared.clear()

        // Session not started: digits should buffer as preedit, not as live candidates.
        bridge.didTriggerKey(KeyDefinition(type: .input(key: "6", alternate: "chineseNineGridDigit:6")))

        let state = SuggestionState.shared
        XCTAssertEqual(state.mode, .chineseCandidates, "9-key preview must render as Chinese composition preview.")
        XCTAssertEqual(state.chinesePreedit, "6")
        // Buffered preview is not a committed composition — the host text stays empty.
        XCTAssertEqual(controller.proxy.text, "")
        SuggestionState.shared.clear()
    }

    // MARK: - Commit-on-space single path

    func testHandleSpaceCommitsCandidatesPresentViaSinglePath() async throws {
        let bridge = ScriptedChineseRimeBridge(
            inputStates: [ChineseCompositionState(preedit: "ni", candidates: [CandidateSuggestion(index: 0, label: "1", text: "你")])],
            selectedStates: []
        )
        let session = ChineseInputSession(bridge: bridge)
        try await session.start(hasFullAccess: false)

        let keyBridge = DictusKeyboardBridge()
        let controller = CapturingInputViewController()
        keyBridge.controller = controller
        keyBridge.chineseInputSession = session
        keyBridge.suggestionState = SuggestionState.shared
        SuggestionState.shared.clear()

        // Drive composition then space.
        _ = try await session.input("ni")
        keyBridge.didTriggerKey(KeyDefinition(type: .spacebar(name: "空格")))

        await waitUntil { controller.proxy.text == "你" }
        XCTAssertEqual(controller.proxy.text, "你")
        XCTAssertFalse(session.state.hasActiveComposition, "Composition must clear after space commit.")
        SuggestionState.shared.clear()
    }

    func testHandleSpaceCommitsPreeditOnlyViaSinglePath() async throws {
        // No candidates, only preedit: commitBestCandidateOrPreedit should insert preedit.
        let bridge = ScriptedChineseRimeBridge(
            inputStates: [ChineseCompositionState(preedit: "abc", candidates: [])],
            selectedStates: []
        )
        let session = ChineseInputSession(bridge: bridge)
        try await session.start(hasFullAccess: false)

        let keyBridge = DictusKeyboardBridge()
        let controller = CapturingInputViewController()
        keyBridge.controller = controller
        keyBridge.chineseInputSession = session
        keyBridge.suggestionState = SuggestionState.shared
        SuggestionState.shared.clear()

        _ = try await session.input("abc")
        keyBridge.didTriggerKey(KeyDefinition(type: .spacebar(name: "空格")))

        await waitUntil { controller.proxy.text == "abc" }
        XCTAssertEqual(controller.proxy.text, "abc")
        SuggestionState.shared.clear()
    }

    // MARK: - Rime failure does not degrade to raw input

    func testChineseSessionInputErrorDoesNotInsertRawHostText() async throws {
        ChineseKeyboardModeStore.active = .chineseQwerty
        let bridge = DictusKeyboardBridge()
        let controller = CapturingInputViewController()
        bridge.controller = controller
        bridge.suggestionState = SuggestionState.shared
        SuggestionState.shared.clear()

        // A throwing bridge that has already started.
        let failingBridge = ThrowingInputChineseRimeBridge()
        let session = ChineseInputSession(bridge: failingBridge)
        try await session.start(hasFullAccess: false)
        bridge.prepareChineseInputSession(session)

        // Key typed into the session that throws on input().
        bridge.didTriggerKey(KeyDefinition(type: .input(key: "w", alternate: nil)))

        // After a short delay, host text must remain empty — no raw fallback.
        try? await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertEqual(controller.proxy.text, "", "Rime input() error must NOT insert raw host text.")
        SuggestionState.shared.clear()
    }

    func testChineseSessionFailedStatusClearsBufferWithoutInserting() async throws {
        ChineseKeyboardModeStore.active = .chineseQwerty
        let bridge = DictusKeyboardBridge()
        let controller = CapturingInputViewController()
        bridge.controller = controller
        bridge.suggestionState = SuggestionState.shared
        SuggestionState.shared.clear()

        // Buffer a key, then simulate terminal failure.
        bridge.didTriggerKey(KeyDefinition(type: .input(key: "w", alternate: nil)))
        bridge.setChineseInputStatus(.failed, message: "engine failed")

        await waitUntil { controller.proxy.text == "" }
        XCTAssertEqual(controller.proxy.text, "", "Terminal failure must clear buffer without inserting raw text.")
        SuggestionState.shared.clear()
    }

    func testSessionStartFailureSetsFailedStatus() async {
        let bridge = FailingStartChineseRimeBridge()
        let session = ChineseInputSession(bridge: bridge)

        do {
            try await session.start(hasFullAccess: false)
            XCTFail("start should throw")
        } catch {
            XCTAssertEqual(session.status, .failed)
            XCTAssertFalse(session.isStarted)
        }
    }

    // MARK: - Helpers

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

@MainActor
private final class ManyCandidateBridge: ChineseRimeBridge {
    var state = ChineseCompositionState()
    var status: ChineseInputStatus = .idle
    private let candidateCount: Int

    init(candidateCount: Int) {
        self.candidateCount = candidateCount
    }

    func start(hasFullAccess: Bool) async throws {}

    func switchMode(_ mode: ChineseInputMode) async throws -> ChineseCompositionState { state }

    func input(_ text: String) async throws -> ChineseCompositionState {
        let candidates = (0..<candidateCount).map {
            CandidateSuggestion(index: $0, label: "\($0 + 1)", text: "字\($0)")
        }
        state = ChineseCompositionState(preedit: text, candidates: candidates)
        return state
    }

    func selectCandidate(at index: Int) async throws -> ChineseCompositionState { state }
    func deleteBackward() async throws -> ChineseCompositionState { state }
    func pageCandidates(from offset: Int, count: Int) async throws -> [CandidateSuggestion] { [] }
    func replacePreeditInput(_ replacement: String) async throws -> ChineseCompositionState { state }
    func reset() async { state = ChineseCompositionState() }
}

@MainActor
private final class FailingStartChineseRimeBridge: ChineseRimeBridge {
    var state = ChineseCompositionState()
    var status: ChineseInputStatus = .idle

    func start(hasFullAccess: Bool) async throws {
        throw NSError(domain: "test", code: 1)
    }

    func switchMode(_ mode: ChineseInputMode) async throws -> ChineseCompositionState { state }
    func input(_ text: String) async throws -> ChineseCompositionState { state }
    func selectCandidate(at index: Int) async throws -> ChineseCompositionState { state }
    func deleteBackward() async throws -> ChineseCompositionState { state }
    func pageCandidates(from offset: Int, count: Int) async throws -> [CandidateSuggestion] { [] }
    func replacePreeditInput(_ replacement: String) async throws -> ChineseCompositionState { state }
    func reset() async { state = ChineseCompositionState() }
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

@MainActor
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

@MainActor
private final class ThrowingInputChineseRimeBridge: ChineseRimeBridge {
    var state = ChineseCompositionState()
    var status: ChineseInputStatus = .idle

    func start(hasFullAccess: Bool) async throws { status = .ready }

    func switchMode(_ mode: ChineseInputMode) async throws -> ChineseCompositionState { state }

    func input(_ text: String) async throws -> ChineseCompositionState {
        throw NSError(domain: "test", code: 1, userInfo: [NSLocalizedDescriptionKey: "Rime input rejected"])
    }

    func selectCandidate(at index: Int) async throws -> ChineseCompositionState { state }
    func deleteBackward() async throws -> ChineseCompositionState { state }
    func pageCandidates(from offset: Int, count: Int) async throws -> [CandidateSuggestion] { [] }
    func replacePreeditInput(_ replacement: String) async throws -> ChineseCompositionState { state }
    func reset() async { state = ChineseCompositionState() }
}
