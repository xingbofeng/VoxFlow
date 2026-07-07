// DictusKeyboard/KeyboardViewController.swift
import UIKit
import SwiftUI
import Combine
import Shared
import ChineseInput

class KeyboardViewController: UIInputViewController {
    let controllerID = String(UUID().uuidString.prefix(8))

    private var hostingController: UIHostingController<KeyboardRootView>?
    private var dictationStatusCancellable: AnyCancellable?
    private var colorTraitRegistration: UITraitChangeRegistration?

    /// Process-wide SuggestionState (see SuggestionState.shared). Per-controller
    /// instances leaked via SwiftUI @ObservedObject backing storage that survives
    /// KeyboardViewController.deinit; the singleton makes the leak benign.
    private let suggestionState = SuggestionState.shared

    /// The giellakbd-ios UICollectionView keyboard, added as a direct UIKit subview.
    /// WHY not wrapped in UIViewRepresentable: SwiftUI recreates representable views
    /// on state changes, which would destroy/rebuild the UICollectionView and lose
    /// scroll position, active key state, and long-press overlays. Adding as a direct
    /// sibling subview of kbInputView avoids this entirely.
    private var giellaKeyboard: GiellaKeyboardView?

    /// Bottom-anchored fixed-height stack containing the Dictus toolbar and key grid.
    /// iOS may transiently hand keyboard extensions a full-screen inputView during
    /// switching; keeping the actual content in this container preserves the
    /// Dictus-sized keyboard at the bottom of that system-owned canvas.
    private var contentContainer: UIView?
    private var contentHeightConstraint: NSLayoutConstraint?

    /// Delegate adapter that translates giellakbd-ios key events into Dictus actions.
    private var bridge: DictusKeyboardBridge?

    /// Explicit height constraint on inputView to prevent layout issues after app switch.
    /// WHY: Without this, iOS may not recalculate the keyboard height correctly when the
    /// extension is brought back to foreground after a URL scheme app switch. The system
    /// keyboard row (globe, mic) bleeds through and the recording overlay gets compressed.
    private var heightConstraint: NSLayoutConstraint?

    /// Height constraint for the SwiftUI hosting view (toolbar + recording overlay).
    /// Changes from toolbarHeight (52pt) to full height when recording overlay is active.
    private var hostingHeightConstraint: NSLayoutConstraint?

    /// Idle-state bottom anchor: hosting sits directly above the keyboard.
    /// Active when not recording / emoji. Deactivated when expanding to fill
    /// the full keyboard area, where we instead pin hosting's bottom to
    /// kbInputView's bottom so the overlay fills the entire keyboard.
    private var hostingBottomToKeyboardTop: NSLayoutConstraint?

    /// Expanded-state bottom anchor: hosting's bottom == kbInputView's bottom.
    /// Active during recording overlay or emoji picker (when keyboard is
    /// hidden). With this active + height=276, hosting fills the whole
    /// keyboard area without leaving stripes off-screen.
    private var hostingBottomToInputBottom: NSLayoutConstraint?

    /// Fixed toolbar height matching ToolbarView (52pt: 48pt content + 4pt top padding).
    private let toolbarHeight: CGFloat = 52

    /// Whether viewWillAppear has fired at least once. Guards the Combine handler
    /// from changing hosting height before the controller is registered with KeyboardState.
    /// WHY: During cold start, the Combine subscription fires in viewDidLoad with .recording
    /// status, but SwiftUI's showsOverlay is still false (activeControllerID doesn't match).
    /// Expanding the hosting view at this point shows the toolbar in a full-height area,
    /// displacing it to the middle of the screen.
    private var hasAppeared = false
    private var didStartChineseInputSession = false
    private var isStartingChineseInputSession = false

    override func viewDidLoad() {
        super.viewDidLoad()
        colorTraitRegistration = registerForTraitChanges([UITraitUserInterfaceStyle.self]) {
            (controller: KeyboardViewController, previousTraitCollection: UITraitCollection) in
            controller.handleColorTraitChange(previousTraitCollection)
        }
        PersistentLog.source = "KBD"
        let memEntry = MemoryFootprint.residentMB()
        PersistentLog.log(.diagnosticProbe(
            component: "KeyboardViewController",
            instanceID: controllerID,
            action: "viewDidLoad",
            details: "controllerClass=\(String(describing: type(of: self))) memMB=\(memEntry)"
        ))

        #if DEBUG
        let result = AppGroupDiagnostic.runSafe()
        if #available(iOS 14.0, *) {
            AppLogger.keyboard.debug(
                "Diagnostic: canWrite=\(result.canWrite, privacy: .public) canRead=\(result.canRead, privacy: .public)"
            )
        }
        #endif

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleKeyboardLayoutReloadNotification),
            name: .mashangxieReloadKeyboardLayout,
            object: nil
        )

        // Create a KeyboardInputView (UIInputView + UIInputViewAudioFeedback)
        // and assign it as the controller's inputView. This is the critical step
        // that makes playInputClick() work: iOS checks that the UIInputViewController's
        // inputView conforms to UIInputViewAudioFeedback and returns true from
        // enableInputClicksWhenVisible. Without this assignment, click sounds are silent.
        let kbInputView = KeyboardInputView(frame: .zero, inputViewStyle: .keyboard)
        // Do NOT set translatesAutoresizingMaskIntoConstraints = false on the inputView.
        // iOS manages the inputView's frame via autoresizing masks -- disabling them
        // causes the view to collapse to zero width.

        // #92 fix: kbInputView is opaque by default (UIInputView base) and with
        // backgroundColor=nil it paints a default grey in any region not covered
        // by a subview. During iOS's keyboard entry animation, iOS forces the
        // inputView to ~504pt at constraint priority 1000 (we cannot win against
        // it). Our content fills only 276pt — without these two lines, the
        // remaining 228pt rendered as a visible grey rectangle. Forcing the view
        // truly transparent + non-opaque makes that uncovered area composite
        // with whatever sits behind the keyboard window (the host app),
        // matching what Apple's own keyboards do.
        kbInputView.backgroundColor = .clear
        kbInputView.isOpaque = false

        // --- 1. Create the giellakbd-ios UIKit keyboard ---
        let definition = KeyboardLayouts.current()
        let theme = Theme.current(for: traitCollection)
        let keyboard = GiellaKeyboardView(definition: definition, theme: theme)
        keyboard.translatesAutoresizingMaskIntoConstraints = false

        // --- 2. Create and wire the delegate bridge ---
        let keyBridge = DictusKeyboardBridge()
        keyBridge.controller = self
        keyBridge.keyboardView = keyboard
        keyboard.delegate = keyBridge
        keyBridge.suggestionState = suggestionState
        keyBridge.onEmojiToggle = { [weak self] in
            self?.toggleEmojiPicker()
        }
        keyBridge.onChineseInputNeeded = { [weak self, weak keyBridge] in
            guard let self, let keyBridge else { return }
            self.installChineseInputSession(on: keyBridge)
        }
        self.bridge = keyBridge
        self.giellaKeyboard = keyboard

        // --- 3. Create SwiftUI hosting for toolbar + recording overlay ONLY ---
        // NOTE: do NOT pass `self` into KeyboardRootView. Storing the controller on
        // the View struct creates a strong ref cycle through UIHostingController that
        // prevents stale controllers from deiniting across app-switches (#134).
        // The view accesses the controller through KeyboardState.shared.controller
        // (weak), which is set in viewWillAppear below.
        let rootView = KeyboardRootView(
            controllerID: controllerID,
            suggestionState: suggestionState,
            bridge: keyBridge,
            onLanguageChanged: { [weak self] newLang in
                self?.handleLanguageChange(newLang)
            },
            onEmojiDismiss: { [weak self] in
                self?.toggleEmojiPicker()
            },
            onAuxiliaryPanelVisibilityChanged: { [weak self] isVisible in
                self?.setChineseAuxiliaryPanelVisible(isVisible)
            }
        )
        let hosting = UIHostingController(rootView: rootView)
        PersistentLog.log(.diagnosticProbe(
            component: "KeyboardViewController",
            instanceID: controllerID,
            action: "hostingCreated",
            details: "hosting=\(ObjectIdentifier(hosting).debugDescription)"
        ))

        // Critical: retain the hosting controller or it gets deallocated
        self.hostingController = hosting

        // Disable safe area regions so SwiftUI content uses the full hosting bounds.
        // WHY: Keyboard extensions can have unexpected safe area insets from the system.
        // Note: Do NOT set layoutMargins/directionalLayoutMargins to zero — this
        // triggers layout recalculation that causes the keyboard height to shrink
        // when top-row key popups extend above bounds.
        if #available(iOS 16.4, *) {
            hosting.safeAreaRegions = []
        }

        addChild(hosting)
        hosting.view.translatesAutoresizingMaskIntoConstraints = false
        hosting.view.backgroundColor = .clear
        // Hide hosting view until viewWillAppear has applied the correct state.
        // During cold start, there's a gap between viewDidLoad (hosting created with
        // toolbar content) and viewWillAppear (constraint + SwiftUI state synchronized).
        // Without this, the toolbar briefly renders in an expanded hosting view,
        // displacing FR/mic to the middle of the screen.
        hosting.view.isHidden = true

        // --- 4. Add both views to a bottom-anchored content container ---
        // Order matters: hosting (toolbar) at top, keyboard below.
        let contentView = UIView(frame: .zero)
        contentView.translatesAutoresizingMaskIntoConstraints = false
        contentView.backgroundColor = .clear
        contentView.isOpaque = false
        self.contentContainer = contentView
        kbInputView.addSubview(contentView)
        contentView.addSubview(hosting.view)
        contentView.addSubview(keyboard)
        hosting.didMove(toParent: self)

        // --- 5. Set up Auto Layout constraints ---
        // Hosting view (toolbar): pinned to top, leading, trailing. Height = toolbarHeight.
        let hostingHeight = hosting.view.heightAnchor.constraint(equalToConstant: toolbarHeight)
        // Priority 999 (just below .required): ensures our explicit height always wins over
        // UIHostingController's intrinsic content size (compression resistance = 750).
        // At .defaultHigh (750), the constraint was ambiguous with SwiftUI's own sizing,
        // causing the hosting view to get stuck at wrong heights after recording overlay dismiss.
        hostingHeight.priority = UILayoutPriority(999)
        self.hostingHeightConstraint = hostingHeight

        // Prevent SwiftUI content from fighting the height constraint.
        // WHY: UIHostingController sets compression resistance at .defaultHigh (750).
        // When content switches from RecordingOverlay (full height) to ToolbarView (52pt),
        // the stale intrinsic size can compete with our constraint at equal priority.
        // NOTE: Only lower compression resistance, NOT content hugging — the hosting view
        // must be able to EXPAND to full height during recording overlay.
        hosting.view.setContentCompressionResistancePriority(.defaultLow, for: .vertical)

        // Pin keyboard grid to a fixed height (key grid only) so it never stretches
        // beyond its natural 224pt — even when iOS forces the inputView to 504pt
        // during the entry animation. With a bottom-anchor pin the giellaKeyboard
        // would stretch to ~452pt → "double-size keys" flash (#116 / ba12a69).
        let keyGridHeight = computeKeyboardHeight() - toolbarHeight
        let keyboardHeight = keyboard.heightAnchor.constraint(equalToConstant: keyGridHeight)
        keyboardHeight.priority = UILayoutPriority(999)

        // #92 fix: bottom-anchor the content stack inside kbInputView (matches
        // upstream giellakbd-ios). Combined with kbInputView.backgroundColor =
        // .clear, this makes the 228pt empty zone appear at the TOP of the
        // expanded inputView during the entry animation transient — i.e. in
        // the host-app-content region right above the toolbar — instead of at
        // the bottom (between keys and screen edge), which was extremely
        // visible. With the inputView transparent the host app shows through,
        // matching what Apple's own keyboards render in that area.
        let hostingBottomIdle = hosting.view.bottomAnchor.constraint(equalTo: keyboard.topAnchor)
        let hostingBottomExpanded = hosting.view.bottomAnchor.constraint(equalTo: contentView.bottomAnchor)
        hostingBottomIdle.isActive = true
        hostingBottomExpanded.isActive = false
        self.hostingBottomToKeyboardTop = hostingBottomIdle
        self.hostingBottomToInputBottom = hostingBottomExpanded

        let contentHeight = contentView.heightAnchor.constraint(equalToConstant: computeKeyboardHeight())
        contentHeight.priority = UILayoutPriority(999)
        self.contentHeightConstraint = contentHeight

        NSLayoutConstraint.activate([
            contentView.leadingAnchor.constraint(equalTo: kbInputView.leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: kbInputView.trailingAnchor),
            contentView.bottomAnchor.constraint(equalTo: kbInputView.bottomAnchor),
            contentHeight,

            // UIKit keyboard pinned to the bottom of the content container
            keyboard.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            keyboard.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            keyboard.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            keyboardHeight,

            // Toolbar (SwiftUI hosting) — bottom anchor swapped at runtime
            // (see hostingBottomToKeyboardTop / hostingBottomToInputBottom)
            hosting.view.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            hosting.view.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            hostingHeight,
        ])

        // --- 6. Defer the height constraint to viewDidLayoutSubviews first run ---
        // #92: installing this constraint in viewDidLoad fights iOS's
        // priority-1000 UIView-Encapsulated-Layout-Height during the entry
        // animation, producing a visible "keyboard grows then shrinks"
        // transient (956 → 504 → 276 over ~150ms).
        //
        // Upstream giellakbd-ios installs its height constraint in
        // viewDidLayoutSubviews first run, dispatched async to the main queue,
        // with the comment: "If this is removed, iPhone 5s glitches before
        // finding the correct height." Adding the constraint AFTER iOS has
        // completed its initial layout pass lets our 999-priority constraint
        // win without fighting the encapsulated-layout-height directly.
        //
        // Constraint creation moved to installInputViewHeightConstraint().

        // Attempt to prevent top-row key popup clipping. iOS may re-enforce
        // clipsToBounds -- if so, this is a known limitation of third-party keyboard extensions.
        kbInputView.clipsToBounds = false
        hosting.view.clipsToBounds = false

        // Assign as the controller's inputView -- this activates audio feedback
        self.inputView = kbInputView

        // --- 7. Wire post-transcription suggestion refresh ---
        // After dictation inserts text, update the suggestion bar with completions
        // for the last word of the transcription.
        KeyboardState.shared.onTranscriptionInserted = { [weak self] in
            guard let self = self else { return }
            let context = self.textDocumentProxy.documentContextBeforeInput
            self.suggestionState.updateAsync(context: context)
            self.bridge?.updateCapitalization()
        }

        // Memory after all viewDidLoad allocations — delta vs entry tells us
        // per-controller allocation cost (UIHostingController + GiellaKeyboardView
        // + SuggestionState + DictusKeyboardBridge + constraints).
        let memExit = MemoryFootprint.residentMB()
        PersistentLog.log(.diagnosticProbe(
            component: "KeyboardViewController",
            instanceID: controllerID,
            action: "viewDidLoad_exit",
            details: "memMB=\(memExit) delta=\(memExit - memEntry)"
        ))
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        // CRITICAL: Disable touch delay on system gesture recognizers.
        // iOS attaches gesture recognizers to the keyboard's UIWindow that have
        // delaysTouchesBegan=true (for system gesture disambiguation at screen edges).
        // This causes edge key touches to be delayed ~100ms, making haptic/popup fire
        // on touchUp instead of touchDown, and long-press accent to fail on outer edges.
        // The original giellakbd-ios uses this exact same technique.
        disableWindowGestureDelay()

        // Issue #116 diagnostic: snapshot state at entry BEFORE any mutation.
        // Use defaultsIfAvailable to avoid crashing free-signed keyboards.
        let entryDefaults = AppGroup.defaultsIfAvailable ?? UserDefaults.standard
        let entryStatus = KeyboardState.shared.dictationStatus.rawValue
        let entryStoredStatus = entryDefaults.string(forKey: SharedKeys.dictationStatus) ?? "nil"
        let entryColdStart = entryDefaults.bool(forKey: SharedKeys.coldStartActive)
        let entryBounds = inputView?.bounds.size ?? .zero
        PersistentLog.log(.diagnosticProbe(
            component: "KeyboardViewController",
            instanceID: controllerID,
            action: "viewWillAppear_entry",
            details: "animated=\(animated) status=\(entryStatus) storedStatus=\(entryStoredStatus) coldStart=\(entryColdStart) inputBounds=\(Int(entryBounds.width))x\(Int(entryBounds.height)) hostingConst=\(hostingHeightConstraint?.constant ?? -1) heightConst=\(heightConstraint?.constant ?? -1) memMB=\(MemoryFootprint.residentMB())"
        ))
        // Point KeyboardState's weak controller ref at the currently-visible controller
        // so call sites in KeyboardRootView and KeyboardState can access textDocumentProxy.
        // Previously set from KeyboardRootView.onAppear, which held a strong ref → #134.
        KeyboardState.shared.controller = self
        PersistentLog.log(.keyboardDidAppear)
        KeyboardState.shared.registerControllerAppearance(controllerID: controllerID)
        hasAppeared = true

        // (Re)subscribe to dictation status here, not in viewDidLoad.
        // WHY: iOS caches UIInputViewController instances across app-switches and
        // rarely deallocates them, so stale controllers would keep mutating
        // hostingHeightConstraint on every status change (issue #128). By subscribing
        // in viewWillAppear and cancelling in viewDidDisappear, only the currently
        // visible controller is reactive. Assignment is idempotent — the previous
        // AnyCancellable is released on reassignment, which cancels its subscription.
        observeRecordingState()

        // Force height recalculation when keyboard reappears (e.g., after app switch).
        // Without this, the inputView may retain a stale height from before the switch.
        let oldHeight = heightConstraint?.constant ?? -1
        let newHeight = computeKeyboardHeight()
        heightConstraint?.constant = newHeight
        contentHeightConstraint?.constant = newHeight
        PersistentLog.log(.diagnosticProbe(
            component: "KeyboardViewController",
            instanceID: controllerID,
            action: "heightRecalc_viewWillAppear",
            details: "old=\(oldHeight) new=\(newHeight) contentHeight=\(contentHeightConstraint?.constant ?? -1) hSizeClass=\(traitCollection.horizontalSizeClass.rawValue) vSizeClass=\(traitCollection.verticalSizeClass.rawValue)"
        ))

        // Apply current dictation state to hosting height now that we're registered.
        // During cold start, handleDictationStatusChange was skipped (hasAppeared was false).
        // Now that activeControllerID matches, SwiftUI's showsOverlay will be correct,
        // so the constraint and SwiftUI content change happen together — no displaced toolbar.
        let statusBeforeHandle = KeyboardState.shared.dictationStatus.rawValue
        handleDictationStatusChange(KeyboardState.shared.dictationStatus)
        PersistentLog.log(.diagnosticProbe(
            component: "KeyboardViewController",
            instanceID: controllerID,
            action: "viewWillAppear_afterHandle",
            details: "statusBefore=\(statusBeforeHandle) statusAfter=\(KeyboardState.shared.dictationStatus.rawValue) hostingConst=\(hostingHeightConstraint?.constant ?? -1) contentHeight=\(contentHeightConstraint?.constant ?? -1)"
        ))

        inputView?.setNeedsLayout()

        // Show hosting view now that constraints and SwiftUI state are synchronized.
        // Was hidden in viewDidLoad to prevent cold start flash (toolbar in full-height hosting).
        hostingController?.view.isHidden = false

        // Force synchronous layout AFTER unhiding (#99). During cold start, the status
        // can transition .recording → .idle between handleDictationStatusChange and this
        // unhide. The constraint is updated but the visual frame is stale without this.
        DispatchQueue.main.async { [weak self] in
            self?.inputView?.layoutIfNeeded()
        }

        // Update theme when keyboard reappears (dark/light mode may have changed)
        if let keyboard = giellaKeyboard {
            keyboard.updateTheme(theme: Theme.current(for: traitCollection))
        }

        // Set initial shift state based on the text field's autocapitalization setting.
        // WHY here and not viewDidLoad: The textDocumentProxy is not fully connected
        // until the view is about to appear. Calling in viewDidLoad would read stale data.
        bridge?.updateCapitalization()

        // Set default opening layer from user preference.
        // WHY here not viewDidLoad: viewWillAppear fires each time the keyboard appears,
        // allowing the user to change settings in the app and see the effect immediately.
        let defaultLayer = DefaultKeyboardLayer.active
        if defaultLayer == .numbers {
            giellaKeyboard?.page = .symbols1
        }

        // Refresh prediction language from App Group on every keyboard appearance.
        // WHY here not viewDidLoad: The user can change language in the app between
        // keyboard appearances. viewWillAppear fires each time, picking up the change.
        suggestionState.setLanguage("en")

        PersistentLog.log(.diagnosticProbe(
            component: "KeyboardViewController",
            instanceID: controllerID,
            action: "registeredAppearance",
            details: ""
        ))

        // Cold start return detection: log for diagnostics.
        // DON'T clear coldStartActive here -- KeyboardState.refreshFromDefaults() reads it
        // to activate the watchdog grace period (15s instead of 5s). The app's .background
        // handler clears it when the transition is complete.
        // Use defaultsIfAvailable so free-signed keyboards don't crash here.
        if (AppGroup.defaultsIfAvailable ?? UserDefaults.standard).bool(forKey: SharedKeys.coldStartActive) {
            AppLogger.keyboard.info("Keyboard returned from cold start, recording should be active")
        }

        #if DEBUG
        if #available(iOS 14.0, *) {
            AppLogger.keyboard.debug("viewWillAppear -- refreshing mode")
        }
        #endif
    }

    private func installChineseInputSession(on keyBridge: DictusKeyboardBridge) {
        guard !didStartChineseInputSession, !isStartingChineseInputSession else { return }
        isStartingChineseInputSession = true

        let mode = ChineseKeyboardModeStore.active
        let rimeBridge = NativeChineseRimeBridge(mode: mode)
        let session = ChineseInputSession(mode: mode, bridge: rimeBridge)
        keyBridge.prepareChineseInputSession(session)

        Task { [weak self, weak keyBridge] in
            do {
                try await session.start(hasFullAccess: self?.hasFullAccess ?? false)
                self?.isStartingChineseInputSession = false
                self?.didStartChineseInputSession = true
                keyBridge?.handleChineseInputSessionStarted()
                PersistentLog.log(.diagnosticProbe(
                    component: "KeyboardViewController",
                    instanceID: self?.controllerID ?? "unknown",
                    action: "chineseInputStarted",
                    details: "mode=\(mode.rawValue) hasFullAccess=\(self?.hasFullAccess ?? false)"
                ))
            } catch {
                self?.isStartingChineseInputSession = false
                self?.didStartChineseInputSession = false
                keyBridge?.handleChineseInputSessionFailed()
                keyBridge?.chineseInputSession = nil
                PersistentLog.log(.diagnosticProbe(
                    component: "KeyboardViewController",
                    instanceID: self?.controllerID ?? "unknown",
                    action: "chineseInputStartFailed",
                    details: "\(error)"
                ))
            }
        }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        KeyboardState.shared.readPasteboardOnceIfPending()

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 350_000_000)
            KeyboardState.shared.readPasteboardOnceIfPending()
        }

        // Issue #116 diagnostic: snapshot final frames after layout settles.
        // We log both sizes and constraint constants so we can detect priority mismatches
        // where iOS imposed a different height than we asked for.
        logLayoutSnapshot(action: "viewDidAppear_settled")

        // Issue #129 investigation: viewDidAppear fires BEFORE iOS finishes the
        // keyboard entry animation, so bounds captured here may still be
        // transient. Schedule deferred snapshots to confirm whether 504pt is
        // actually the final, user-visible size — or just a mid-animation value
        // that iOS later resolves to our requested 276pt constraint.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.logLayoutSnapshot(action: "layoutSnapshot_500ms")
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            self?.logLayoutSnapshot(action: "layoutSnapshot_1000ms")
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
            self?.logLayoutSnapshot(action: "layoutSnapshot_2000ms")
        }
    }

    /// First-run flag for viewDidLayoutSubviews. Used by upstream
    /// giellakbd-ios pattern (#92): install the input view height constraint
    /// after iOS finishes its initial layout pass, not in viewDidLoad.
    private var isFirstLayoutPass = true

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        if isFirstLayoutPass {
            isFirstLayoutPass = false
            // Defer constraint installation to the next runloop turn so we
            // don't mutate constraints inside iOS's own layout pass. Upstream
            // comment: "If this is removed, iPhone 5s glitches before finding
            // the correct height."
            DispatchQueue.main.async { [weak self] in
                self?.installInputViewHeightConstraint()
            }
        }
    }

    /// Installs the 999-priority height constraint on kbInputView. Called once
    /// (lazy) from the first viewDidLayoutSubviews via async dispatch. Adding
    /// the constraint here, AFTER iOS has completed its initial layout pass,
    /// lets us win against the encapsulated-layout-height (priority 1000)
    /// without the entry animation flashing at 504pt.
    private func installInputViewHeightConstraint() {
        guard heightConstraint == nil, let kbInputView = inputView else { return }
        let height = computeKeyboardHeight()
        let constraint = kbInputView.heightAnchor.constraint(equalToConstant: height)
        constraint.priority = UILayoutPriority(999)
        constraint.isActive = true
        self.heightConstraint = constraint
    }

    /// Swap hosting view's bottom anchor between idle and expanded positions.
    /// - Idle: hosting.bottom = keyboard.top (sits above the keys at 52pt).
    /// - Expanded: hosting.bottom = contentContainer.bottom (fills the full
    ///   keyboard area, used when the recording overlay or emoji picker is
    ///   shown and the keyboard view is hidden).
    ///
    /// Without this swap, expanding the hosting height alone (with the idle
    /// bottom anchor still active) pushes hosting.top above kbInputView,
    /// leaving the overlay stuck off-screen — the bug in #92 follow-up.
    private func setHostingExpanded(_ expanded: Bool) {
        if expanded {
            hostingBottomToKeyboardTop?.isActive = false
            hostingBottomToInputBottom?.isActive = true
        } else {
            hostingBottomToInputBottom?.isActive = false
            hostingBottomToKeyboardTop?.isActive = true
        }
    }

    private func setChineseAuxiliaryPanelVisible(_ visible: Bool) {
        guard hasAppeared else { return }

        let status = KeyboardState.shared.dictationStatus
        let isActiveSession = status == .requested
            || status == .recording
            || status == .transcribing
        guard !isActiveSession else { return }

        if visible, isShowingEmoji {
            isShowingEmoji = false
            NotificationCenter.default.post(name: .mashangxieSetEmojiVisible, object: false)
        }

        giellaKeyboard?.isHidden = visible || isShowingEmoji
        if visible {
            hostingHeightConstraint?.constant = computeKeyboardHeight()
            setHostingExpanded(true)
        } else if !isShowingEmoji {
            hostingHeightConstraint?.constant = toolbarHeight
            setHostingExpanded(false)
        }

        inputView?.layoutIfNeeded()
    }

    /// Emits the same layout snapshot we log in `viewDidAppear_settled`,
    /// reusable from deferred blocks to compare mid- vs post-animation sizes.
    private func logLayoutSnapshot(action: String) {
        let inputBounds = inputView?.bounds.size ?? .zero
        let contentFrame = contentContainer?.frame.size ?? .zero
        let keyboardFrame = giellaKeyboard?.frame.size ?? .zero
        let hostingFrame = hostingController?.view.frame.size ?? .zero
        let viewBounds = view.bounds.size
        PersistentLog.log(.diagnosticProbe(
            component: "KeyboardViewController",
            instanceID: controllerID,
            action: action,
            details: "inputBounds=\(Int(inputBounds.width))x\(Int(inputBounds.height)) viewBounds=\(Int(viewBounds.width))x\(Int(viewBounds.height)) contentFrame=\(Int(contentFrame.width))x\(Int(contentFrame.height)) keyboardFrame=\(Int(keyboardFrame.width))x\(Int(keyboardFrame.height)) hostingFrame=\(Int(hostingFrame.width))x\(Int(hostingFrame.height)) contentConst=\(contentHeightConstraint?.constant ?? -1) hostingConst=\(hostingHeightConstraint?.constant ?? -1) heightConst=\(heightConstraint?.constant ?? -1) status=\(KeyboardState.shared.dictationStatus.rawValue) memMB=\(MemoryFootprint.residentMB())"
        ))
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)

        // Restore system gesture recognizer delay (be a good citizen)
        restoreWindowGestureDelay()

        PersistentLog.log(.diagnosticProbe(
            component: "KeyboardViewController",
            instanceID: controllerID,
            action: "viewDidDisappear",
            details: "animated=\(animated) memMB=\(MemoryFootprint.residentMB())"
        ))
        PersistentLog.log(.keyboardDidDisappear)

        // Tear down the dictation status subscription so this (now-detached)
        // controller no longer reacts when KeyboardState publishes. iOS caches
        // UIInputViewController and rarely releases it, so without this cleanup
        // 10+ stale controllers race on hostingHeightConstraint (issue #128).
        // viewWillAppear re-subscribes on reattach.
        dictationStatusCancellable?.cancel()
        dictationStatusCancellable = nil

        // Issue #142: skip registerControllerDisappearance during an active
        // dictation session. iOS calls viewDidDisappear on the keyboard right
        // before bringing DictusApp foreground for cold-start; an immediate
        // unregister would flip activeControllerID→nil and isKeyboardVisible
        // →false, making KeyboardRootView.showsOverlay recompute to false and
        // SwiftUI swap RecordingOverlay→ToolbarView while hostingConst is still
        // 276pt. iOS's keyboard-down animation snapshot then captures that
        // inconsistent layout (toolbar centred in expanded hosting), freezing
        // it on screen for the duration of the transition.
        //
        // The successor controller's registerControllerAppearance overwrites
        // activeControllerID, so a clean handoff happens automatically. If
        // the keyboard is truly dismissed during recording (no successor), the
        // synchronous deinit safety net below catches it.
        let status = KeyboardState.shared.dictationStatus
        let isActiveSession = status == .requested
            || status == .recording
            || status == .transcribing
        if isActiveSession {
            PersistentLog.log(.diagnosticProbe(
                component: "KeyboardViewController",
                instanceID: controllerID,
                action: "skippedUnregister_activeSession",
                details: "status=\(status.rawValue) activeID=\(KeyboardState.shared.activeControllerID ?? "none")"
            ))
        } else {
            KeyboardState.shared.registerControllerDisappearance(controllerID: controllerID)
            PersistentLog.log(.diagnosticProbe(
                component: "KeyboardViewController",
                instanceID: controllerID,
                action: "registeredDisappearance",
                details: ""
            ))
        }

        // Darwin observers cleaned up by KeyboardState deinit
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // iOS sends this shortly before it's willing to jetsam the extension.
        // Logging it proves whether the grey-overlay freeze correlates with
        // a memory-pressure signal iOS actually gave us vs an out-of-the-blue kill.
        PersistentLog.log(.diagnosticProbe(
            component: "KeyboardViewController",
            instanceID: controllerID,
            action: "didReceiveMemoryWarning",
            details: "memMB=\(MemoryFootprint.residentMB())"
        ))
    }

    private func handleColorTraitChange(_ previousTraitCollection: UITraitCollection) {
        let hadColorChange = traitCollection.hasDifferentColorAppearance(comparedTo: previousTraitCollection)
        PersistentLog.log(.diagnosticProbe(
            component: "KeyboardViewController",
            instanceID: controllerID,
            action: "traitCollectionDidChange",
            details: "prevStyle=\(previousTraitCollection.userInterfaceStyle.rawValue) newStyle=\(traitCollection.userInterfaceStyle.rawValue) hadColorChange=\(hadColorChange)"
        ))
        // Update keyboard theme when dark/light mode changes while keyboard is visible.
        if hadColorChange {
            let newTheme = Theme.current(for: traitCollection)
            giellaKeyboard?.updateTheme(theme: newTheme)
        }
    }

    deinit {
        // Symmetric tear-down for the addChild()/didMove(toParent:) we did in viewDidLoad.
        // Without this, UIKit holds the hosting controller in `children` and SwiftUI may
        // keep its observation graph alive past our own deinit, perpetuating the
        // KeyboardRootView zombies seen receiving activeControllerChanged broadcasts in
        // logs (#134). Same reasoning applies to giellaKeyboard's superview membership.
        hostingController?.willMove(toParent: nil)
        hostingController?.view.removeFromSuperview()
        hostingController?.removeFromParent()
        hostingController = nil

        giellaKeyboard?.removeFromSuperview()
        giellaKeyboard = nil

        contentContainer?.removeFromSuperview()
        contentContainer = nil
        contentHeightConstraint = nil

        bridge = nil

        PersistentLog.log(.diagnosticProbe(
            component: "KeyboardViewController",
            instanceID: controllerID,
            action: "deinit",
            details: "memMB=\(MemoryFootprint.residentMB())"
        ))
    }

    // MARK: - Keyboard Height

    /// Calculate the total keyboard height using giellakbd-ios KeyboardHeightProvider
    /// for the key grid height, plus toolbar and padding.
    private func computeKeyboardHeight() -> CGFloat {
        let deviceContext = DeviceContext.current
        let keyGridHeight = KeyboardHeightProvider.height(
            for: deviceContext,
            traitCollection: traitCollection
        )
        // bottomPadding was previously 8pt but had no real effect — keyboard view's
        // bottomAnchor is pinned to kbInputView.bottomAnchor, so the extra height got
        // divided across 4 row cells (+2pt per row), making each visible key 2.3pt
        // taller than Apple's. Setting to 0 restores Apple-matched cell height (#117).
        let bottomPadding: CGFloat = 0
        let total = keyGridHeight + toolbarHeight + bottomPadding
        let screen = UIScreen.main.bounds.size
        PersistentLog.log(.diagnosticProbe(
            component: "KeyboardViewController",
            instanceID: controllerID,
            action: "computeKbHeight",
            details: "grid=\(keyGridHeight) total=\(total) screen=\(Int(screen.width))x\(Int(screen.height)) landscape=\(deviceContext.isLandscape)"
        ))
        return total
    }

    // MARK: - Recording State Observation

    /// Observe KeyboardState.dictationStatus to hide/show the UIKit keyboard
    /// when the recording overlay is active. The SwiftUI hosting view handles
    /// showing the overlay itself -- we just need to hide the UIKit keyboard.
    ///
    /// WHY Combine instead of NotificationCenter: KeyboardState uses @Published
    /// for dictationStatus. Subscribing via Combine's $dictationStatus publisher
    /// gives us direct observation without adding manual notification posts.
    private func observeRecordingState() {
        dictationStatusCancellable = KeyboardState.shared.$dictationStatus
            // No .receive(on: .main) — dictationStatus is always set on the main thread
            // (Darwin observer dispatches to main, mic button is UI action).
            // Removing the async dispatch ensures the constraint change happens SYNCHRONOUSLY
            // with the @Published change, BEFORE SwiftUI re-evaluates its body.
            // Without this, there's a 1-frame delay where the overlay renders at 52pt (toolbar
            // height) before the hosting view expands to full height — causing the waveform
            // to flash at the top then drop to center.
            .sink { [weak self] status in
                self?.handleDictationStatusChange(status)
            }
    }

    private func handleDictationStatusChange(_ status: DictationStatus) {
        // Issue #116 diagnostic: entry log (fires even when guard trips).
        let oldHosting = hostingHeightConstraint?.constant ?? -1
        let activeID = KeyboardState.shared.activeControllerID ?? "none"
        PersistentLog.log(.diagnosticProbe(
            component: "KeyboardViewController",
            instanceID: controllerID,
            action: "dictStatusChange_enter",
            details: "status=\(status.rawValue) hasAppeared=\(hasAppeared) oldHosting=\(oldHosting) isShowingEmoji=\(isShowingEmoji) activeID=\(activeID)"
        ))

        // Don't change hosting height until the controller is registered with KeyboardState.
        // During cold start, this fires in viewDidLoad before viewWillAppear — SwiftUI's
        // showsOverlay is still false, so expanding now would show the toolbar displaced
        // in a full-height hosting view. viewWillAppear calls this manually after registering.
        guard hasAppeared else { return }

        // Defense-in-depth for #128: iOS caches UIInputViewController and does not
        // reliably fire viewDidDisappear on stale instances (observed: controllers
        // responding to Darwin status changes for minutes after losing window
        // attachment, no viewDidDisappear event logged). The subscription-cancel
        // path in viewDidDisappear covers the well-behaved case; this guard
        // short-circuits stale controllers that iOS forgot to notify. Only the
        // controller currently owning the keyboard window mutates layout.
        guard KeyboardState.shared.activeControllerID == controllerID else {
            PersistentLog.log(.diagnosticProbe(
                component: "KeyboardViewController",
                instanceID: controllerID,
                action: "dictStatusChange_skippedInactive",
                details: "status=\(status.rawValue) activeID=\(activeID)"
            ))
            return
        }

        let isRecording = status == .requested || status == .recording || status == .transcribing

        // Dismiss auxiliary panels if recording starts.
        if isRecording && isShowingEmoji {
            isShowingEmoji = false
        }
        if isRecording {
            ChineseAuxiliaryPanelState.shared.dismiss()
        }

        let isShowingAuxiliaryPanel = ChineseAuxiliaryPanelState.shared.mode != nil
        giellaKeyboard?.isHidden = isRecording || isShowingEmoji || isShowingAuxiliaryPanel

        if isRecording {
            // Expand hosting view to fill the full keyboard area for the recording overlay
            let fullHeight = computeKeyboardHeight()
            hostingHeightConstraint?.constant = fullHeight
            setHostingExpanded(true)
            PersistentLog.log(.diagnosticProbe(
                component: "KeyboardViewController",
                instanceID: controllerID,
                action: "hostingSet_recording",
                details: "old=\(oldHosting) new=\(fullHeight) status=\(status.rawValue)"
            ))
        } else if isShowingAuxiliaryPanel {
            let fullHeight = computeKeyboardHeight()
            hostingHeightConstraint?.constant = fullHeight
            setHostingExpanded(true)
        } else if !isShowingEmoji {
            // Restore toolbar-only height (unless emoji picker is open)
            hostingHeightConstraint?.constant = toolbarHeight
            setHostingExpanded(false)
            PersistentLog.log(.diagnosticProbe(
                component: "KeyboardViewController",
                instanceID: controllerID,
                action: "hostingSet_idle",
                details: "old=\(oldHosting) new=\(toolbarHeight) status=\(status.rawValue)"
            ))
        }

        inputView?.setNeedsLayout()
        // Some hosts temporarily hand the keyboard extension a full-screen
        // inputView during activation. Forcing synchronous layout from inside
        // the dictation-status sink can stall that activation before
        // viewWillAppear finishes, leaving the system grey keyboard shell.
        DispatchQueue.main.async { [weak self] in
            self?.inputView?.layoutIfNeeded()
        }
    }

    // MARK: - Text Change

    override func textDidChange(_ textInput: UITextInput?) {
        super.textDidChange(textInput)
        // Invalidate autocorrect undo on external text changes (paste, cursor tap, host autocorrect).
        bridge?.suggestionState?.pendingUndo = nil
        // When text changes externally (paste, cursor move, autocorrect by host app),
        // recheck autocapitalization. This ensures shift state stays correct even when
        // the user moves the cursor to a different position in the text.
        bridge?.updateCapitalization()
    }

    // MARK: - Window Gesture Delay

    /// Hashes of gesture recognizers we disabled, so we can restore them on disappear.
    private var disabledGestureHashes = Set<Int>()

    /// Disable `delaysTouchesBegan` on all UIWindow gesture recognizers.
    ///
    /// WHY: iOS attaches system gesture recognizers to the keyboard's UIWindow with
    /// `delaysTouchesBegan = true`. These recognizers check for system gestures (swipe-back,
    /// Control Center) before delivering touches to the keyboard. This adds ~100ms delay
    /// on edge key touches, causing haptic/popup to fire on touchUp instead of touchDown
    /// and long-press accent popup to fail on outer edge of edge keys.
    ///
    /// This is the same technique used by the original giellakbd-ios keyboard.
    private func disableWindowGestureDelay() {
        guard let window = view.window,
              let recognizers = window.gestureRecognizers else { return }
        for recognizer in recognizers {
            let className = String(describing: type(of: recognizer))
            guard !className.localizedCaseInsensitiveContains("Gate") else {
                continue
            }
            if recognizer.delaysTouchesBegan {
                recognizer.delaysTouchesBegan = false
                disabledGestureHashes.insert(recognizer.hash)
            }
        }
    }

    /// Restore `delaysTouchesBegan` on gesture recognizers we previously disabled.
    private func restoreWindowGestureDelay() {
        guard let window = view.window,
              let recognizers = window.gestureRecognizers else { return }
        for recognizer in recognizers where disabledGestureHashes.contains(recognizer.hash) {
            recognizer.delaysTouchesBegan = true
        }
        disabledGestureHashes.removeAll()
    }

    // MARK: - Language Change

    /// Handles a language cycle from the toolbar's LanguageSwitcherView.
    ///
    /// WHY full rebuild: GiellaKeyboardView (UICollectionView) does not support
    /// hot-swapping its KeyboardDefinition. The cleanest approach is to remove the
    /// old view and create a new one with the updated definition. The ~200ms rebuild
    /// is masked by the language code animation in the toolbar.
    private func handleLanguageChange(_ newLang: SupportedLanguage) {
        // 1. Reload suggestion/autocorrect dictionaries for the new language
        suggestionState.setLanguage(newLang.rawValue)

        // 2. Rebuild the keyboard grid with the new layout
        reloadKeyboardLayout()

        PersistentLog.log(.diagnosticProbe(
            component: "KeyboardViewController",
            instanceID: controllerID,
            action: "languageChanged",
            details: "lang=\(newLang.rawValue) layout=\(LayoutType.active.rawValue)"
        ))
    }

    /// Destroys the current GiellaKeyboardView and creates a new one
    /// with the current language and layout preferences from App Group.
    private func reloadKeyboardLayout() {
        guard let kbInputView = inputView, let contentView = contentContainer else { return }

        PersistentLog.log(.diagnosticProbe(
            component: "KeyboardViewController",
            instanceID: controllerID,
            action: "reloadLayout_begin",
            details: "status=\(KeyboardState.shared.dictationStatus.rawValue) oldHosting=\(hostingHeightConstraint?.constant ?? -1) oldHeight=\(heightConstraint?.constant ?? -1) inputBounds=\(Int(kbInputView.bounds.width))x\(Int(kbInputView.bounds.height))"
        ))

        // Remove old keyboard
        giellaKeyboard?.removeFromSuperview()

        // Create new keyboard with updated definition
        let definition = KeyboardLayouts.current()
        let theme = Theme.current(for: traitCollection)
        let keyboard = GiellaKeyboardView(definition: definition, theme: theme)
        keyboard.translatesAutoresizingMaskIntoConstraints = false

        // Re-wire the bridge
        bridge?.keyboardView = keyboard
        keyboard.delegate = bridge

        // Add to view hierarchy below the hosting view
        contentView.addSubview(keyboard)

        // Re-create constraints. Mirrors the bottom-anchor layout from viewDidLoad
        // (#92 fix): keyboard pinned to contentView.bottomAnchor with a fixed
        // height, hosting view sits directly above it.
        //
        // Note: the old hostingBottomToKeyboardTop pointed at the previous
        // keyboard view (about to be deallocated) — we deactivate it and
        // create a new one referencing the new keyboard.
        hostingBottomToKeyboardTop?.isActive = false
        if let hostingView = hostingController?.view {
            let keyGridHeight = computeKeyboardHeight() - toolbarHeight
            let keyboardHeight = keyboard.heightAnchor.constraint(equalToConstant: keyGridHeight)
            keyboardHeight.priority = UILayoutPriority(999)
            let newHostingBottomIdle = hostingView.bottomAnchor.constraint(equalTo: keyboard.topAnchor)
            NSLayoutConstraint.activate([
                keyboard.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
                keyboard.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
                keyboard.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
                keyboardHeight,
                newHostingBottomIdle,
            ])
            self.hostingBottomToKeyboardTop = newHostingBottomIdle
        }
        // reloadKeyboardLayout always returns the layout to idle (the height
        // is reset to toolbarHeight just below). Make sure the expanded bottom
        // anchor isn't lingering active from a previous recording/emoji state.
        hostingBottomToInputBottom?.isActive = false

        self.giellaKeyboard = keyboard

        // Ensure hosting view is at toolbar-only height. If a previous recording
        // left it at full height, the keyboard grid would be squashed below a large
        // empty hosting area — causing the key shrinking bug on language switch.
        let oldHostingRL = hostingHeightConstraint?.constant ?? -1
        hostingHeightConstraint?.constant = toolbarHeight
        PersistentLog.log(.diagnosticProbe(
            component: "KeyboardViewController",
            instanceID: controllerID,
            action: "reloadLayout_hostingReset",
            details: "old=\(oldHostingRL) new=\(toolbarHeight)"
        ))

        // Force height recalculation — the new GiellaKeyboardView may have different
        // intrinsic content size during initial layout. Without this, iOS keeps the
        // stale height constraint from before the rebuild, causing a visible gap
        // between the toolbar and the key grid.
        let oldHeightRL = heightConstraint?.constant ?? -1
        let newHeightRL = computeKeyboardHeight()
        heightConstraint?.constant = newHeightRL
        contentHeightConstraint?.constant = newHeightRL
        PersistentLog.log(.diagnosticProbe(
            component: "KeyboardViewController",
            instanceID: controllerID,
            action: "reloadLayout_heightRecalc",
            details: "old=\(oldHeightRL) new=\(newHeightRL) contentHeight=\(contentHeightConstraint?.constant ?? -1)"
        ))
        kbInputView.setNeedsLayout()
        kbInputView.layoutIfNeeded()
        PersistentLog.log(.diagnosticProbe(
            component: "KeyboardViewController",
            instanceID: controllerID,
            action: "reloadLayout_end",
            details: "inputBounds=\(Int(kbInputView.bounds.width))x\(Int(kbInputView.bounds.height)) contentFrame=\(Int(contentView.frame.width))x\(Int(contentView.frame.height)) keyboardFrame=\(Int(keyboard.frame.width))x\(Int(keyboard.frame.height)) hostingFrame=\(Int(hostingController?.view.frame.width ?? 0))x\(Int(hostingController?.view.frame.height ?? 0))"
        ))

        // Apply current shift state
        bridge?.updateCapitalization()
    }

    @objc private func handleKeyboardLayoutReloadNotification() {
        reloadKeyboardLayout()
    }

    // MARK: - Emoji Picker

    /// Whether the emoji picker is currently visible.
    private(set) var isShowingEmoji = false

    /// Toggle emoji picker visibility. The emoji picker UI itself is wired in Plan 02.
    ///
    /// WHY toggle here (not in bridge): The bridge handles key events but doesn't
    /// own the view hierarchy. Showing/hiding views is the controller's responsibility.
    /// The bridge calls this via the onEmojiToggle closure.
    func toggleEmojiPicker() {
        ChineseAuxiliaryPanelState.shared.dismiss()
        isShowingEmoji.toggle()
        giellaKeyboard?.isHidden = isShowingEmoji

        let oldHostingEmoji = hostingHeightConstraint?.constant ?? -1
        if isShowingEmoji {
            // Expand hosting to cover keyboard area for emoji picker
            let fullHeight = computeKeyboardHeight()
            hostingHeightConstraint?.constant = fullHeight
            setHostingExpanded(true)
            PersistentLog.log(.diagnosticProbe(
                component: "KeyboardViewController",
                instanceID: controllerID,
                action: "hostingSet_emojiOpen",
                details: "old=\(oldHostingEmoji) new=\(fullHeight)"
            ))
        } else {
            hostingHeightConstraint?.constant = toolbarHeight
            setHostingExpanded(false)
            PersistentLog.log(.diagnosticProbe(
                component: "KeyboardViewController",
                instanceID: controllerID,
                action: "hostingSet_emojiClose",
                details: "old=\(oldHostingEmoji) new=\(toolbarHeight)"
            ))
        }
        inputView?.setNeedsLayout()

        // Notify SwiftUI to show/hide emoji picker with an explicit target state.
        // A plain toggle can desync when UIKit and SwiftUI miss one edge during
        // keyboard replacement, leaving a hidden UIKit keyboard and blank hosting view.
        NotificationCenter.default.post(name: .mashangxieSetEmojiVisible, object: isShowingEmoji)
    }
}

// MARK: - Notification names for keyboard internal communication

extension Notification.Name {
    /// Posted by KeyboardViewController when text changes externally (paste, cursor move).
    /// KeyboardView listens for this to recheck autocapitalisation.
    static let dictusTextDidChange = Notification.Name("dictusTextDidChange")

    /// Posted when the emoji picker should toggle visibility.
    static let dictusToggleEmoji = Notification.Name("dictusToggleEmoji")

    /// Posted with a Bool object when the emoji picker should become visible/hidden.
    static let mashangxieSetEmojiVisible = Notification.Name("mashangxieSetEmojiVisible")
}
