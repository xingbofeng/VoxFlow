// DictusKeyboard/KeyboardRootView.swift
import SwiftUI
import Combine
import Shared
import ChineseInput

/// Root SwiftUI view for the keyboard extension chrome (toolbar + recording overlay).
///
/// Phase 18 architecture change: The keyboard grid is now a UIKit GiellaKeyboardView
/// added as a direct subview in KeyboardViewController. This SwiftUI view only renders:
/// - ToolbarView (always visible when not recording)
/// - RecordingOverlay (replaces keyboard area during recording)
///
/// WHY SwiftUI for toolbar/overlay but UIKit for keys:
/// The toolbar and recording overlay are simple SwiftUI layouts that don't need
/// zero-latency touch handling. The key grid needs UICollectionView's proven touch
/// pipeline for zero dead zones. Mixing UIKit keys + SwiftUI chrome gives us both.
struct KeyboardRootView: View {
    let controllerID: String
    @ObservedObject private var state = KeyboardState.shared
    @ObservedObject private var auxiliaryPanelState = ChineseAuxiliaryPanelState.shared
    @ObservedObject private var waveformDriver = KeyboardWaveformDriver.shared
    @State private var instanceID = String(UUID().uuidString.prefix(8))
    @State private var chineseInputMode = ChineseKeyboardModeStore.active
    /// Whether the emoji picker is currently visible.
    /// Toggled via NotificationCenter from KeyboardViewController.toggleEmojiPicker().
    @State private var showingEmoji = false
    /// Whether the expanded Chinese candidate picker is visible.
    @State private var showingChineseCandidates = false
    /// Observable state for the suggestion bar, owned by KeyboardViewController.
    /// WHY @ObservedObject (not @StateObject): The controller creates and owns SuggestionState,
    /// injecting the same instance into both this view (for display) and the bridge (for updates).
    /// Using @ObservedObject here means we observe without owning -- the controller is the source of truth.
    @ObservedObject var suggestionState: SuggestionState

    /// Reference to the keyboard bridge for prediction tap handling.
    /// WHY needed: When the user taps a prediction, we need to call
    /// bridge.handlePredictionTap() which inserts the word + space and chains
    /// new predictions. The bridge owns textDocumentProxy access and state management.
    var bridge: DictusKeyboardBridge?

    /// Callback when the user cycles language via the toolbar switcher.
    /// The controller uses this to reload the GiellaKeyboardView with the new layout.
    var onLanguageChanged: ((SupportedLanguage) -> Void)?

    /// Invoked when the user taps the emoji picker's dismiss button.
    /// Supplied by KeyboardViewController with [weak self] capture so we don't
    /// retain the controller through the hosting view (issue #134).
    var onEmojiDismiss: (() -> Void)?

    /// Invoked when a Chinese auxiliary panel expands/collapses so the UIKit key
    /// grid can be hidden by KeyboardViewController.
    var onAuxiliaryPanelVisibilityChanged: ((Bool) -> Void)?

    /// WHY @Environment here: openURL is the SwiftUI way to open URLs.
    /// Keyboard extensions cannot access UIApplication.shared, but SwiftUI's
    /// openURL environment action works because it goes through the responder
    /// chain. We capture it here and inject it into KeyboardState via .onAppear.
    @Environment(\.openURL) private var openURL

    /// Whether the recording overlay should be visible.
    /// Extracted as a computed property for clear animation binding.
    private var showsOverlay: Bool {
        let isActiveStatus = state.dictationStatus == .requested
            || state.dictationStatus == .recording
            || state.dictationStatus == .transcribing
        guard isActiveStatus else { return false }

        // Only the registered active controller shows the overlay.
        // The legacy `activeControllerID == nil` fallback existed to mask the
        // controller leak from #128: stale KeyboardRootView instances rendered
        // RecordingOverlay in parallel with the visible one, producing the
        // duplicate grey overlay observed in issue #116. With #128 fixed,
        // stale controllers are dormant and this fallback is unnecessary.
        return state.activeControllerID == controllerID && state.isKeyboardVisible
    }

    var body: some View {
        VStack(spacing: 0) {
            if showsOverlay {
                // Recording overlay fills the full area (toolbar + keyboard space).
                // The UIKit keyboard is hidden by KeyboardViewController when recording.
                RecordingOverlay(
                    dictationStatus: state.dictationStatus,
                    liveTranscription: state.liveTranscription,
                    waveformEnergy: state.waveformEnergy,
                    elapsedSeconds: state.recordingElapsed,
                    waveformDriver: waveformDriver,
                    onCancel: { state.requestCancel() },
                    onStop: { state.requestStop() }
                )
            } else if showingChineseCandidates,
                      suggestionState.mode == .chineseCandidates,
                      !suggestionState.toolbarSuggestions.isEmpty {
                VStack(spacing: 0) {
                    ToolbarView(
                        hasFullAccess: state.controller?.hasFullAccess ?? false,
                        dictationStatus: state.dictationStatus,
                        onMicTap: {
                            dismissChineseCandidatePanel()
                            startVoiceDictation()
                        },
                        statusMessage: state.statusMessage,
                        suggestions: suggestionState.toolbarSuggestions,
                        suggestionMode: suggestionState.mode,
                        onSuggestionTap: { index in
                            handleSuggestionTap(index: index)
                            dismissChineseCandidatePanel()
                        },
                        suggestionsExpanded: true,
                        onSuggestionExpand: {
                            dismissChineseCandidatePanel()
                        },
                        onLanguageChanged: onLanguageChanged,
                        chineseInputMode: chineseInputMode,
                        onChineseModeToggle: { mode in switchChineseInputMode(mode) },
                        pendingClipboard: state.pendingClipboard,
                        onPendingInsert: { state.insertPendingTextAndClear() },
                        onPendingDismiss: { state.dismissPendingAndClear() },
                        onPendingRetry: { state.retryPendingClipboardRead() }
                    )
                    .frame(height: 52)

                    ExpandedChineseCandidatePanel(
                        suggestions: suggestionState.toolbarSuggestions,
                        onTap: { index in
                            handleSuggestionTap(index: index)
                            dismissChineseCandidatePanel()
                        }
                    )
                }
            } else if let auxiliaryMode = auxiliaryPanelState.mode {
                VStack(spacing: 0) {
                    ToolbarView(
                        hasFullAccess: state.controller?.hasFullAccess ?? false,
                        dictationStatus: state.dictationStatus,
                        onMicTap: {
                            auxiliaryPanelState.dismiss()
                            startVoiceDictation()
                        },
                        statusMessage: state.statusMessage,
                        suggestions: [],
                        suggestionMode: .idle,
                        onSuggestionTap: { _ in },
                        onLanguageChanged: onLanguageChanged,
                        chineseInputMode: chineseInputMode,
                        onChineseModeToggle: { mode in switchChineseInputMode(mode) },
                        pendingClipboard: state.pendingClipboard,
                        onPendingInsert: { state.insertPendingTextAndClear() },
                        onPendingDismiss: { state.dismissPendingAndClear() },
                        onPendingRetry: { state.retryPendingClipboardRead() }
                    )
                    .frame(height: 52)
                    ChineseAuxiliaryKeyboardView(
                        mode: auxiliaryMode,
                        returnTitle: "返回",
                        onInsert: { text in
                            insertAuxiliaryText(text, dismissAfterInsert: auxiliaryMode == .symbols)
                        },
                        onDelete: { deleteAuxiliaryText() },
                        onSpace: { insertAuxiliaryText(" ", dismissAfterInsert: false) },
                        onSend: { sendAuxiliaryReturn() },
                        onReturn: { dismissAuxiliaryPanel() }
                    )
                }
            } else if showingEmoji {
                // GeometryReader measures the actual space available to SwiftUI.
                // WHY: In keyboard extensions, the hosting controller may not give the
                // full screen width/height to SwiftUI due to safe area or system insets.
                // Passing measured dimensions to EmojiPickerView guarantees it fits.
                GeometryReader { geo in
                    VStack(spacing: 0) {
                        // Toolbar stays visible during emoji browsing
                        ToolbarView(
                            hasFullAccess: state.controller?.hasFullAccess ?? false,
                            dictationStatus: state.dictationStatus,
                            onMicTap: {
                                showingEmoji = false
                                startVoiceDictation()
                            },
                            statusMessage: state.statusMessage,
                            suggestions: [],
                            suggestionMode: .idle,
                            onSuggestionTap: { _ in },
                            onLanguageChanged: onLanguageChanged,
                            chineseInputMode: chineseInputMode,
                            onChineseModeToggle: { mode in switchChineseInputMode(mode) },
                            leadingActionTitle: "返回",
                            onLeadingAction: {
                                onEmojiDismiss?()
                            },
                            pendingClipboard: state.pendingClipboard,
                            onPendingInsert: { state.insertPendingTextAndClear() },
                            onPendingDismiss: { state.dismissPendingAndClear() },
                            onPendingRetry: { state.retryPendingClipboardRead() }
                        )
                        .frame(height: 52)
                        // Emoji picker uses exact measured dimensions
                        EmojiPickerView(
                            onEmojiInsert: { emoji in
                                state.controller?.textDocumentProxy.insertText(emoji)
                                HapticFeedback.keyTapped()
                            },
                            onDelete: {
                                state.controller?.textDocumentProxy.deleteBackward()
                                HapticFeedback.keyTapped()
                            },
                            onDismiss: {
                                // Invokes KeyboardViewController.toggleEmojiPicker() via
                                // [weak self] closure injected at viewDidLoad time.
                                // Avoids the (controller as? KeyboardViewController) cast
                                // that used to require a strong controller ref (#134).
                                onEmojiDismiss?()
                            },
                            availableWidth: geo.size.width,
                            availableHeight: geo.size.height - 52
                        )
                    }
                }
            } else {
                // Toolbar only -- the keyboard grid is UIKit, managed by KeyboardViewController
                ToolbarView(
                    hasFullAccess: state.controller?.hasFullAccess ?? false,
                    dictationStatus: state.dictationStatus,
                    onMicTap: { startVoiceDictation() },
                    statusMessage: state.statusMessage,
                    suggestions: suggestionState.toolbarSuggestions,
                    suggestionMode: suggestionState.mode,
                    onSuggestionTap: { index in
                        handleSuggestionTap(index: index)
                    },
                    suggestionsExpanded: false,
                    onSuggestionExpand: {
                        showChineseCandidatePanel()
                    },
                    onLanguageChanged: onLanguageChanged,
                    chineseInputMode: chineseInputMode,
                    onChineseModeToggle: { mode in switchChineseInputMode(mode) },
                    pendingClipboard: state.pendingClipboard,
                    onPendingInsert: { state.insertPendingTextAndClear() },
                    onPendingDismiss: { state.dismissPendingAndClear() },
                    onPendingRetry: { state.retryPendingClipboardRead() }
                )
                // No KeyboardView here -- it's UIKit, added directly by KeyboardViewController
                // No bottom spacer -- the UIKit keyboard handles its own height
            }
        }
        // Issue #142: force the body to fill its hosting frame top-aligned.
        // Without this, when the hosting view expands from 52→276pt on mic
        // tap but SwiftUI hasn't yet re-rendered ToolbarView→RecordingOverlay
        // (1-frame async lag), UIHostingController centres the 52pt toolbar
        // intrinsic content inside its 276pt frame — and iOS's keyboard-down
        // animation snapshot freezes that centred-toolbar layout on screen.
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color.clear)
        .onChange(of: showsOverlay) { _, isShowing in
            let usedFallback = isShowing && state.activeControllerID == nil
            PersistentLog.log(.diagnosticProbe(
                component: "KeyboardRootView",
                instanceID: instanceID,
                action: "showsOverlayChanged",
                details: "isShowing=\(isShowing) status=\(state.dictationStatus.rawValue) visible=\(state.isKeyboardVisible) owner=\(state.activeControllerID ?? "none") controllerID=\(controllerID) usedFallback=\(usedFallback)"
            ))
            // Dismiss emoji picker when recording starts
            if isShowing {
                showingEmoji = false
                auxiliaryPanelState.dismiss()
                dismissChineseCandidatePanel()
            }
            syncWaveformDriver()
        }
        .onChange(of: state.dictationStatus) { _, newStatus in
            let showsOverlay = newStatus == .requested || newStatus == .recording || newStatus == .transcribing
            if showsOverlay {
                PersistentLog.log(.overlayShown(status: newStatus.rawValue))
            } else {
                PersistentLog.log(.overlayHidden(status: newStatus.rawValue))
            }
            syncWaveformDriver()
        }
        .onChange(of: state.waveformEnergy) { _, _ in
            syncWaveformDriver()
        }
        .onChange(of: state.activeControllerID) { _, newOwner in
            PersistentLog.log(.diagnosticProbe(
                component: "KeyboardRootView",
                instanceID: instanceID,
                action: "activeControllerChanged",
                details: "newOwner=\(newOwner ?? "none") controllerID=\(controllerID)"
            ))
            syncWaveformDriver()
        }
        .onChange(of: state.isKeyboardVisible) { _, _ in
            syncWaveformDriver()
        }
        .onAppear {
            PersistentLog.log(.diagnosticProbe(
                component: "KeyboardRootView",
                instanceID: instanceID,
                action: "onAppear",
                details: "status=\(state.dictationStatus.rawValue) visible=\(state.isKeyboardVisible) owner=\(state.activeControllerID ?? "none") controllerID=\(controllerID)"
            ))
            // state.controller is set by KeyboardViewController.viewWillAppear to avoid
            // a strong ref cycle through the hosting view (#134). openURL must stay
            // here — it's a SwiftUI @Environment value, only capturable from a View.
            state.openURL = { url in openURL(url) }

            // Pre-allocate haptic generators so the first key tap has zero latency.
            HapticFeedback.warmUp()

            // Refresh cached haptic enabled state from UserDefaults.
            HapticFeedback.refreshEnabledState()

            // Language is set in KeyboardViewController.viewWillAppear, which fires
            // on every keyboard appearance and picks up any App Group preference changes.
            chineseInputMode = ChineseKeyboardModeStore.active

            syncWaveformDriver()
        }
        .onReceive(NotificationCenter.default.publisher(for: .mashangxieReloadKeyboardLayout)) { _ in
            chineseInputMode = ChineseKeyboardModeStore.active
        }
        .onDisappear {
            PersistentLog.log(.diagnosticProbe(
                component: "KeyboardRootView",
                instanceID: instanceID,
                action: "onDisappear",
                details: "status=\(state.dictationStatus.rawValue) controllerID=\(controllerID)"
            ))
            syncWaveformDriver(forceHidden: true)
        }
        .onReceive(NotificationCenter.default.publisher(for: .dictusToggleEmoji)) { _ in
            auxiliaryPanelState.dismiss()
            dismissChineseCandidatePanel()
            showingEmoji.toggle()
        }
        .onReceive(NotificationCenter.default.publisher(for: .mashangxieSetEmojiVisible)) { notification in
            let visible = (notification.object as? Bool) ?? false
            if visible {
                auxiliaryPanelState.dismiss()
                dismissChineseCandidatePanel()
            }
            showingEmoji = visible
        }
        .onChange(of: auxiliaryPanelState.mode != nil) { _, isVisible in
            if isVisible {
                showingEmoji = false
                showingChineseCandidates = false
            }
            onAuxiliaryPanelVisibilityChanged?(isVisible)
        }
        .onChange(of: showingChineseCandidates) { _, isVisible in
            if isVisible {
                showingEmoji = false
                auxiliaryPanelState.dismiss()
            }
            onAuxiliaryPanelVisibilityChanged?(isVisible)
        }
        .onChange(of: suggestionState.mode) { _, mode in
            if mode != .chineseCandidates {
                dismissChineseCandidatePanel()
            }
        }
    }

    private func syncWaveformDriver(forceHidden: Bool = false) {
        waveformDriver.sync(
            presenterID: controllerID,
            status: state.dictationStatus,
            energyLevels: state.waveformEnergy,
            isVisible: !forceHidden && showsOverlay
        )
    }

    // MARK: - Suggestion Handling

    /// Handles a tap on one of the suggestion bar slots.
    ///
    /// Three modes:
    /// - Completion mode: replace partial word with full completion + space.
    /// - Correction mode: standard mobile behavior:
    ///   - Tap index 0 (original word): keep as-is + space, reject future autocorrect
    ///   - Tap index 1 (bold correction): apply correction + space
    ///   - Tap index 2 (alternative): apply alternative + space
    /// - Accent mode: replace just the vowel without adding a space.
    private func handleSuggestionTap(index: Int) {
        let visibleSuggestions = suggestionState.toolbarSuggestions
        guard index < visibleSuggestions.count else { return }
        let suggestion = visibleSuggestions[index]
        guard let proxy = state.controller?.textDocumentProxy else { return }

        if suggestionState.mode == .chineseCandidates {
            if suggestionState.suggestions.isEmpty {
                bridge?.commitChinesePreeditFallback()
            } else {
                bridge?.handleChineseCandidateTap(index: index)
            }
            HapticFeedback.keyTapped()
            return
        }

        // Prediction mode: insert word + trailing space, bypass autocorrect, chain predictions.
        if suggestionState.mode == .predictions {
            bridge?.handlePredictionTap(word: suggestion)
            HapticFeedback.keyTapped()
            return
        }

        // Undo mode: tap index 0 = revert autocorrect, tap 1-2 = accept completion/prediction
        if suggestionState.mode == .undoAvailable {
            if index == 0, let undo = suggestionState.pendingUndo {
                performUndo(undo: undo, proxy: proxy)
                suggestionState.pendingUndo = nil
                suggestionState.clear()
            } else {
                suggestionState.pendingUndo = nil
                bridge?.handlePredictionTap(word: suggestion)
            }
            HapticFeedback.keyTapped()
            return
        }

        if suggestionState.mode == .corrections {
            if index == 0 {
                suggestionState.rejectedWords.insert(suggestion.lowercased())
                proxy.insertText(" ")
            } else {
                replaceCurrentWord(
                    proxy: proxy,
                    currentWord: suggestionState.currentWord,
                    replacement: suggestion,
                    addSpace: true
                )
            }
            suggestionState.pendingUndo = nil
            suggestionState.clear()
            HapticFeedback.keyTapped()
            return
        }

        let addSpace = suggestionState.mode == .completions
        replaceCurrentWord(
            proxy: proxy,
            currentWord: suggestionState.currentWord,
            replacement: suggestion,
            addSpace: addSpace
        )

        suggestionState.pendingUndo = nil
        suggestionState.clear()
        HapticFeedback.keyTapped()
    }

    private func showChineseCandidatePanel() {
        guard suggestionState.mode == .chineseCandidates,
              !suggestionState.toolbarSuggestions.isEmpty else {
            return
        }
        showingEmoji = false
        auxiliaryPanelState.dismiss()
        showingChineseCandidates = true
        onAuxiliaryPanelVisibilityChanged?(true)
    }

    private func dismissChineseCandidatePanel() {
        guard showingChineseCandidates else { return }
        showingChineseCandidates = false
        onAuxiliaryPanelVisibilityChanged?(false)
    }

    /// Reverts an autocorrection, preserving any characters typed after the correction.
    private func performUndo(undo: AutocorrectState, proxy: UITextDocumentProxy) {
        guard let context = proxy.documentContextBeforeInput else { return }

        // Try to find the corrected word with trailing space first, then without
        // (user may have deleted the space but the word is still intact).
        let correctedWithSpace = undo.correctedWord + " "
        let range: Range<String.Index>
        let matchedWithSpace: Bool

        if undo.insertedSpace, let r = context.range(of: correctedWithSpace, options: .backwards) {
            range = r
            matchedWithSpace = true
        } else if let r = context.range(of: undo.correctedWord, options: .backwards) {
            range = r
            matchedWithSpace = false
        } else {
            return
        }

        let afterCorrection = String(context[range.upperBound...])
        let matchLength = matchedWithSpace ? correctedWithSpace.count : undo.correctedWord.count
        let deleteCount = matchLength + afterCorrection.count

        for _ in 0..<deleteCount {
            proxy.deleteBackward()
        }

        proxy.insertText(undo.originalWord)
        if matchedWithSpace {
            proxy.insertText(" ")
        }
        proxy.insertText(afterCorrection)

        #if DEBUG
        AutocorrectDebugLog.autocorrectUndone(
            original: undo.originalWord, rejected: undo.correctedWord
        )
        #endif

        suggestionState.rejectedWords.insert(undo.originalWord.lowercased())

        if UserDictionary.shared.recordUsage(undo.originalWord) {
            suggestionState.learnWord(undo.originalWord)
        }
    }

    /// Replaces the word currently being typed with a replacement string.
    private func replaceCurrentWord(
        proxy: UITextDocumentProxy,
        currentWord: String,
        replacement: String,
        addSpace: Bool
    ) {
        for _ in 0..<currentWord.count {
            proxy.deleteBackward()
        }
        proxy.insertText(replacement)
        if addSpace {
            proxy.insertText(" ")
        }
    }

    private func startVoiceDictation() {
        auxiliaryPanelState.dismiss()
        Task { @MainActor in
            await KeyboardVoiceEntryCoordinator.prepareChineseCompositionAndStartRecording(
                prepareChineseComposition: {
                    await bridge?.prepareChineseCompositionForVoice()
                },
                startRecording: {
                    state.startRecording()
                }
            )
        }
    }

    private func switchChineseInputMode(_ mode: ChineseInputMode) {
        chineseInputMode = mode
        dismissAuxiliaryPanel()
        bridge?.switchChineseInputMode(mode)
    }

    private func dismissAuxiliaryPanel() {
        auxiliaryPanelState.dismiss()
        onAuxiliaryPanelVisibilityChanged?(false)
    }

    private func insertAuxiliaryText(_ text: String, dismissAfterInsert: Bool) {
        state.controller?.textDocumentProxy.insertText(text)
        HapticFeedback.keyTapped()
        if dismissAfterInsert {
            dismissAuxiliaryPanel()
        }
    }

    private func deleteAuxiliaryText() {
        state.controller?.textDocumentProxy.deleteBackward()
        HapticFeedback.keyTapped()
    }

    private func sendAuxiliaryReturn() {
        state.controller?.textDocumentProxy.insertText("\n")
        HapticFeedback.keyTapped()
        dismissAuxiliaryPanel()
    }
}

private struct ExpandedChineseCandidatePanel: View {
    let suggestions: [String]
    let onTap: (Int) -> Void

    private let columns = [
        GridItem(.adaptive(minimum: 70), spacing: 8, alignment: .leading)
    ]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, alignment: .leading, spacing: 8) {
                ForEach(Array(suggestions.enumerated()), id: \.offset) { index, suggestion in
                    Button {
                        onTap(index)
                    } label: {
                        Text(suggestion)
                            .font(.system(size: 20, weight: index == 0 ? .semibold : .regular))
                            .foregroundStyle(Color(.label))
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)
                            .padding(.horizontal, 14)
                            .frame(minWidth: 70, minHeight: 44)
                            .background(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(index == 0 ? Color(.systemBackground).opacity(0.96) : Color(.systemGray6))
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 10)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color(.systemGray5))
    }
}
