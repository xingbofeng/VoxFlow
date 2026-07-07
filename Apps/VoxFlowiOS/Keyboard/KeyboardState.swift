// DictusKeyboard/KeyboardState.swift
import Foundation
import UIKit
import Combine
import Shared

/// Observes cross-process state changes from DictusApp via Darwin notifications.
/// Reads actual data from App Group UserDefaults after each notification.
///
/// Phase 3 additions:
/// - waveformEnergy/recordingElapsed for recording overlay visualization
/// - requestStop()/requestCancel() to send commands back to DictusApp
/// - Auto-insert transcription into active text field via textDocumentProxy
/// - Haptic feedback on recording lifecycle events
@MainActor
class KeyboardState: ObservableObject {
    static let shared = KeyboardState()
    private let instanceID = String(UUID().uuidString.prefix(8))
    private(set) var activeSessionID: String?

    @Published var dictationStatus: DictationStatus = .idle
    @Published var lastTranscription: String?
    @Published var liveTranscription: String?
    @Published var statusMessage: String?
    @Published var waveformEnergy: [Float] = []
    @Published var recordingElapsed: Double = 0

    /// ClipboardBridge pending state.
    ///
    /// Set when the user taps the mic in Clipboard mode and the keyboard has
    /// launched the main-app handoff page. Cleared when the user taps the
    /// preview (insert) or the X (dismiss). Empty pasteboard reads do not clear
    /// this state immediately because app-switch return can race clipboard
    /// propagation / paste permission.
    ///
    /// WHY @Published: ToolbarView observes this to swap the left mode pill
    /// for the preview pill and the right mic for an X.
    @Published private(set) var pendingClipboard: PendingClipboardDictation = .none

    /// Tracks whether the keyboard extension is currently visible on screen.
    @Published private(set) var isKeyboardVisible: Bool = false
    @Published private(set) var activeControllerID: String?

    /// Reference to the keyboard controller for text insertion.
    /// WHY weak: KeyboardState is owned by KeyboardRootView (via @StateObject),
    /// and the controller owns the hosting view. A strong reference would create
    /// a retain cycle: controller -> view -> state -> controller.
    weak var controller: UIInputViewController?

    /// Closure to open a URL from the keyboard extension.
    /// WHY a closure: KeyboardState is not a SwiftUI View, so it cannot use
    /// @Environment(\.openURL). KeyboardRootView captures its own openURL
    /// environment action and injects it here via .onAppear — same pattern
    /// as the controller reference above.
    var openURL: ((URL) -> Void)?

    /// Called after transcription text is inserted into the text field.
    /// KeyboardViewController sets this to trigger a SuggestionState update
    /// so the suggestion bar shows completions for the last dictated word.
    var onTranscriptionInserted: (() -> Void)?

    /// Opens a URL from the keyboard extension using NSExtensionContext.
    /// WHY extensionContext: This is the Apple-documented API for app extensions
    /// to open URLs. Neither SwiftUI's openURL nor the responder chain work
    /// reliably in keyboard extensions.
    func openURLFromExtension(_ url: URL) {
        controller?.extensionContext?.open(url)
    }

    /// Local fallback for App Group shared defaults.
    ///
    /// WHY optional fallback: on free Apple ID / AltStore / SideStore paths the
    /// App Group entitlement may be missing, and `AppGroup.defaults` would
    /// `fatalError`. The keyboard must keep rendering even in that case so plain
    /// typing still works. We fall back to standard `UserDefaults` — writes
    /// won't be cross-process shared, but ClipboardBridge does not rely on
    /// shared defaults, and AppGroupBridge is only selected when AppGroup is
    /// available (see `BridgeResolver`).
    private let defaults = AppGroup.defaultsIfAvailable ?? UserDefaults.standard

    var pasteboardStringProvider: () -> String? = {
        UIPasteboard.general.string
    }

    private var clipboardReadRetryTask: Task<Void, Never>?
    private var clipboardReadAttemptCount = 0
    private var clipboardReadDidReportFailure = false
    private let maxClipboardReadAttempts = 24

    /// Watchdog timer that periodically checks for stale active states.
    /// WHY: If the app crashes or a Darwin notification is lost, the keyboard
    /// could get stuck showing the recording overlay forever. The watchdog
    /// detects this by checking if waveform data has stopped updating for 5s
    /// while status is still .recording or .transcribing.
    private var watchdogTimer: Timer?

    /// Tracks when waveform energy was last refreshed from App Group.
    /// Used by the watchdog to detect stale states (no updates for 5s).
    private var lastWaveformUpdate: Date = Date()

    /// When set, the watchdog uses a longer threshold (15s) to account for
    /// the app→keyboard transition during cold start. The app needs time to
    /// stabilize audio recording and start posting waveform updates.
    /// Cleared automatically when recording ends (status becomes idle).
    private var coldStartGraceEnd: Date?


    private init() {
        PersistentLog.log(.diagnosticProbe(
            component: "KeyboardState",
            instanceID: instanceID,
            action: "init",
            details: ""
        ))
        // Read initial state from App Group
        refreshFromDefaults()
        // Restore pending ClipboardBridge state from local UserDefaults —
        // the keyboard extension may have been killed by iOS while the user
        // was in the main app.
        restorePendingClipboardIfPresent()

        // Observe Darwin notifications for real-time updates
        DarwinNotificationCenter.addObserver(
            for: DarwinNotificationName.statusChanged
        ) { [weak self] in
            Task { @MainActor in
                self?.logProbe("receivedDarwinStatusChanged")
                self?.refreshFromDefaults()
            }
        }

        DarwinNotificationCenter.addObserver(
            for: DarwinNotificationName.transcriptionReady
        ) { [weak self] in
            Task { @MainActor in
                self?.logProbe("receivedDarwinTranscriptionReady")
                self?.handleTranscriptionReady()
            }
        }

        DarwinNotificationCenter.addObserver(
            for: DarwinNotificationName.transcriptionPartial
        ) { [weak self] in
            Task { @MainActor in
                self?.readLiveTranscription()
            }
        }

        // Observe waveform updates from DictusApp during recording (~5Hz).
        // DictusApp writes JSON-encoded [Float] to SharedKeys.waveformEnergy
        // and elapsed seconds to SharedKeys.recordingElapsedSeconds, then posts
        // this notification. The keyboard reads the values for the overlay UI.
        DarwinNotificationCenter.addObserver(
            for: DarwinNotificationName.waveformUpdate
        ) { [weak self] in
            Task { @MainActor in
                self?.readWaveformData()
            }
        }

    }

    // MARK: - Watchdog

    /// Prevents re-entrant calls to forceResetToIdle().
    /// WHY: forceResetToIdle posts a statusChanged notification, which triggers
    /// refreshFromDefaults on the next run loop. If the watchdog timer fires
    /// again before that run loop pass (e.g., stacked timer events), a second
    /// forceResetToIdle call would post a duplicate notification.
    private var isResettingToIdle = false

    /// Force-reset all dictation state to idle.
    /// Called by the watchdog timer or stale-state detection on keyboard appear.
    /// Writes to App Group so the app side sees the reset too.
    func forceResetToIdle() {
        guard !isResettingToIdle else { return }
        isResettingToIdle = true
        defer { isResettingToIdle = false }

        stopWatchdog()
        dictationStatus = .idle
        waveformEnergy = []
        recordingElapsed = 0
        liveTranscription = nil
        statusMessage = nil
        activeSessionID = nil
        // Write to App Group so app side sees the reset
        defaults.removeObject(forKey: SharedKeys.liveTranscription)
        defaults.removeObject(forKey: SharedKeys.liveTranscriptionTimestamp)
        defaults.set(DictationStatus.idle.rawValue, forKey: SharedKeys.dictationStatus)
        defaults.synchronize()
        DarwinNotificationCenter.post(DarwinNotificationName.statusChanged)
    }

    /// Start a repeating 1s timer that checks for stale active states.
    /// WHY 5s threshold: Waveform updates arrive at ~5Hz during recording.
    /// If 5 seconds pass without any update while status is still active,
    /// the app has likely crashed or been killed by iOS.
    /// During cold start grace period, uses 15s threshold instead.
    private func startWatchdog() {
        stopWatchdog()
        lastWaveformUpdate = Date()
        watchdogTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                let activeStates: [DictationStatus] = [.requested, .recording, .transcribing]
                guard activeStates.contains(self.dictationStatus) else {
                    self.stopWatchdog()
                    return
                }
                // During cold start, the app transitions foreground→background while
                // setting up audio. Waveform data may not flow for ~10s. Use 15s threshold.
                let inGracePeriod = self.coldStartGraceEnd.map { Date() < $0 } ?? false
                let threshold: TimeInterval = inGracePeriod ? 15.0 : 5.0
                if Date().timeIntervalSince(self.lastWaveformUpdate) > threshold {
                    // Before resetting, check the audio-thread heartbeat.
                    // WHY: In background, iOS throttles the main thread so waveform
                    // Darwin notifications may not arrive. But the audio thread keeps
                    // writing a heartbeat directly to App Group. If the heartbeat is
                    // fresh, the app IS still recording — don't kill the overlay.
                    let heartbeat = self.defaults.double(forKey: SharedKeys.recordingHeartbeat)
                    if heartbeat > 0, Date().timeIntervalSince1970 - heartbeat < threshold {
                        self.lastWaveformUpdate = Date()
                        return
                    }
                    PersistentLog.log(.watchdogReset(source: "keyboard", staleState: self.dictationStatus.rawValue))
                    self.forceResetToIdle()
                }
            }
        }
    }

    /// Invalidate and nil the watchdog timer.
    private func stopWatchdog() {
        watchdogTimer?.invalidate()
        watchdogTimer = nil
    }

    // MARK: - Recording commands (keyboard -> app)

    /// Request DictusApp to stop recording and begin transcription.
    /// Uses the Darwin notification + Bool flag pattern: write the flag first,
    /// then post the notification so the app reads the flag when it handles the notification.
    func requestStop() {
        logProbe("requestStop", details: sessionDetails())
        defaults.set(true, forKey: SharedKeys.stopRequested)
        defaults.synchronize()
        DarwinNotificationCenter.post(DarwinNotificationName.stopRecording)
        HapticFeedback.recordingStopped()
    }

    /// Request DictusApp to cancel recording and discard audio.
    /// Resets local keyboard state immediately for instant UI feedback,
    /// while the Darwin notification tells the app to clean up its side.
    func requestCancel() {
        logProbe("requestCancel", details: sessionDetails())
        defaults.set(true, forKey: SharedKeys.cancelRequested)
        defaults.synchronize()
        DarwinNotificationCenter.post(DarwinNotificationName.cancelRecording)

        // Reset local state immediately for responsive UI
        dictationStatus = .idle
        waveformEnergy = []
        recordingElapsed = 0
        liveTranscription = nil
        statusMessage = nil
        activeSessionID = nil
    }

    // MARK: - State observation

    /// Read current state from App Group UserDefaults.
    /// Starts/stops the watchdog timer based on the new status.
    func refreshFromDefaults() {
        logProbe("refreshFromDefaults", details: "storedStatus=\(defaults.string(forKey: SharedKeys.dictationStatus) ?? "nil") visible=\(isKeyboardVisible) \(sessionDetails())")
        if let rawStatus = defaults.string(forKey: SharedKeys.dictationStatus),
           let status = DictationStatus(rawValue: rawStatus) {
            let oldStatus = dictationStatus
            dictationStatus = status

            if oldStatus != status {
                PersistentLog.log(.statusChanged(from: oldStatus.rawValue, to: status.rawValue, source: "keyboardState"))
            }

            // Start/restart watchdog on any active state transition, stop when leaving.
            // WHY restart (not just start): transitioning .requested → .recording
            // must reset lastWaveformUpdate. Without this, the watchdog fires
            // immediately because it still has the timestamp from markRequested().
            let activeStates: [DictationStatus] = [.requested, .recording, .transcribing]
            if activeStates.contains(status) {
                if !activeStates.contains(oldStatus) || status != oldStatus {
                    startWatchdog()
                }
                // During cold start, the app is transitioning between foreground/background.
                // Waveform data may not flow for several seconds. Activate grace period
                // so the watchdog uses a longer threshold (15s instead of 5s).
                if defaults.bool(forKey: SharedKeys.coldStartActive) {
                    coldStartGraceEnd = Date().addingTimeInterval(15)
                    lastWaveformUpdate = Date()
                }
                // Force-read waveform on keyboard reappear to unstick frozen animations.
                // WHY: When the extension is suspended (app in foreground), Darwin
                // notifications are lost. readWaveformData() updates @Published props
                // which forces SwiftUI to re-render the overlay.
                readLiveTranscription()
                readWaveformData()
            } else {
                stopWatchdog()
                coldStartGraceEnd = nil
                if status == .idle || status == .ready || status == .failed {
                    activeSessionID = nil
                    liveTranscription = nil
                    // Read and display error message from App Group
                    if status == .failed, let errorMsg = defaults.string(forKey: SharedKeys.lastError) {
                        statusMessage = errorMsg
                        defaults.removeObject(forKey: SharedKeys.lastError)
                        defaults.synchronize()
                        Task { @MainActor [weak self] in
                            try? await Task.sleep(for: .seconds(3))
                            self?.statusMessage = nil
                        }
                    }
                }
            }

            // Force SwiftUI re-render when status hasn't changed but we're returning
            // from suspension (e.g., swipe-back during cold start recording).
            // WHY: If oldStatus == status == .recording, SwiftUI skips re-render
            // because no @Published value changed. objectWillChange forces it.
            if isKeyboardVisible && oldStatus == status && activeStates.contains(status) {
                objectWillChange.send()
            }
        }
    }

    private func readLiveTranscription() {
        let text = defaults.string(forKey: SharedKeys.liveTranscription)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        liveTranscription = text?.isEmpty == false ? text : nil
    }

    /// Read waveform energy and elapsed time from App Group.
    /// Called when DictusApp posts waveformUpdate notification during recording.
    /// Updates lastWaveformUpdate so the watchdog knows data is still flowing.
    private func readWaveformData() {
        // Update watchdog timestamp — data is still flowing from the app
        lastWaveformUpdate = Date()

        // Read elapsed seconds
        recordingElapsed = defaults.double(forKey: SharedKeys.recordingElapsedSeconds)

        // Read waveform energy: JSON-encoded [Float] array
        if let data = defaults.data(forKey: SharedKeys.waveformEnergy) {
            do {
                let energy = try JSONDecoder().decode([Float].self, from: data)
                // Log transitions between empty/populated energy data
                if waveformEnergy.isEmpty != energy.isEmpty {
                    PersistentLog.log(.waveformEnergyTransition(
                        fromCount: waveformEnergy.count,
                        toCount: energy.count,
                        status: dictationStatus.rawValue
                    ))
                }
                waveformEnergy = energy
            } catch {
                // JSON decode failure — keep existing waveform data
                if #available(iOS 14.0, *) {
                    AppLogger.keyboard.warning("Failed to decode waveform energy: \(error, privacy: .public)")
                }
            }
        }
    }

    /// Handle transcription ready notification: auto-insert text into active field.
    ///
    /// Phase 3 behavior: instead of displaying transcription in a banner,
    /// insert it directly into the text field via textDocumentProxy.insertText().
    /// This matches the standard iOS dictation UX — user speaks, text appears at cursor.
    private func handleTranscriptionReady() {
        logProbe("handleTranscriptionReady", details: sessionDetails())
        refreshFromDefaults()

        if let transcription = defaults.string(forKey: SharedKeys.lastTranscription),
           !transcription.isEmpty {
            // Clear from UserDefaults BEFORE inserting to prevent duplicate insertions.
            // Darwin notifications can be delivered multiple times (extension lifecycle,
            // multiple statusChanged posts). By clearing first, subsequent calls find
            // nothing to insert.
            defaults.removeObject(forKey: SharedKeys.lastTranscription)
            defaults.removeObject(forKey: SharedKeys.lastTranscriptionTimestamp)
            defaults.synchronize()

            controller?.textDocumentProxy.insertText(transcription)
            PersistentLog.log(.keyboardTextInserted)
            HapticFeedback.textInserted()
            onTranscriptionInserted?()

            // Reset state to idle.
            // WHY explicit stopWatchdog: refreshFromDefaults() above may have read
            // .transcribing from App Group (before .ready propagated), starting the
            // watchdog. Setting dictationStatus = .idle here bypasses refreshFromDefaults
            // so the watchdog wouldn't self-stop until its next 1s tick. Stopping
            // explicitly prevents false-positive watchdog resets.
            stopWatchdog()
            dictationStatus = .idle
            waveformEnergy = []
            recordingElapsed = 0
            liveTranscription = nil
            statusMessage = nil
            lastTranscription = nil
            activeSessionID = nil
        } else {
            // Retry after 100ms — mitigates UserDefaults race condition.
            // Darwin notifications are posted immediately after synchronize(),
            // but cross-App-Group propagation can lag on-device.
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .milliseconds(100))
                guard let self = self else { return }
                if let transcription = self.defaults.string(forKey: SharedKeys.lastTranscription),
                   !transcription.isEmpty {
                    self.defaults.removeObject(forKey: SharedKeys.lastTranscription)
                    self.defaults.removeObject(forKey: SharedKeys.lastTranscriptionTimestamp)
                    self.defaults.synchronize()

                    self.controller?.textDocumentProxy.insertText(transcription)
                    PersistentLog.log(.keyboardTextInserted)
                    HapticFeedback.textInserted()
                    self.onTranscriptionInserted?()

                    self.stopWatchdog()
                    self.dictationStatus = .idle
                    self.waveformEnergy = []
                    self.recordingElapsed = 0
                    self.liveTranscription = nil
                    self.statusMessage = nil
                    self.lastTranscription = nil
                    self.activeSessionID = nil
                }
            }
        }
    }

    // MARK: - Keyboard visibility tracking

    /// Called when a controller becomes the active visible keyboard owner.
    func registerControllerAppearance(controllerID: String) {
        logProbe(
            "registerControllerAppearance",
            details: "controllerID=\(controllerID) previousOwner=\(activeControllerID ?? "none") wasVisible=\(isKeyboardVisible) \(sessionDetails())"
        )
        activeControllerID = controllerID
        isKeyboardVisible = true

        // Refresh state from App Group — picks up status changes that
        // happened while the keyboard extension was suspended.
        refreshFromDefaults()

        // ClipboardBridge: if the keyboard launched the main-app handoff page
        // and the user is now returning, attempt a single pasteboard read.
        // No-op when not in pending state.
        readPasteboardOnceIfPending()
    }

    /// Called when a controller disappears. Only the current owner may hide the keyboard.
    func registerControllerDisappearance(controllerID: String) {
        let ownsVisibility = activeControllerID == controllerID
        logProbe(
            "registerControllerDisappearance",
            details: "controllerID=\(controllerID) owner=\(activeControllerID ?? "none") ownsVisibility=\(ownsVisibility) wasVisible=\(isKeyboardVisible) \(sessionDetails())"
        )

        guard ownsVisibility else { return }

        isKeyboardVisible = false
        activeControllerID = nil
        cancelClipboardReadRetry()
    }

    /// Timestamp of last mic tap — used for debouncing.
    /// WHY 1.5s debounce: After a recording completes (transcription inserted),
    /// there's a brief window where the overlay hides and the mic button appears.
    /// Accidental double-taps or frustrated rapid-tapping during this transition
    /// cause sub-1-second recordings that Parakeet rejects, triggering a cascade
    /// of errors. 1.5s matches the natural human rhythm between dictation sessions.
    private var lastMicTapDate = Date.distantPast

    /// Start recording: set local state, then signal DictusApp.
    ///
    /// WHY the keyboard doesn't record directly:
    /// WhisperKit requires loading ML models (~50-200MB) which exceeds the keyboard
    /// extension's ~50MB memory limit. The actual recording runs in DictusApp.
    ///
    /// Flow (Wispr Flow-inspired):
    /// 1. Set local state to .requested (recording overlay appears immediately)
    /// 2. Post startRecording Darwin notification (app records in background if alive)
    /// 3. If app doesn't respond in 500ms → fall back to URL scheme (opens app)
    ///
    /// This means: after the first launch, subsequent recordings happen without
    /// switching apps. The user stays in their current app the entire time.
    ///
    /// Bridge-aware (add-ios-keyboard-clipboard-fallback Phase 3):
    /// Before doing any of the AppGroupBridge steps above, we consult BridgeResolver.
    /// Clipboard mode skips ALL AppGroup steps and opens the clipboard-start deep
    /// link directly. AppGroup mode keeps the original behavior.
    func startRecording() {
        // Debounce: reject taps within 1.5s of the last tap.
        let now = Date()
        guard now.timeIntervalSince(lastMicTapDate) >= 1.5 else {
            PersistentLog.log(.rapidTapRejected)
            return
        }
        lastMicTapDate = now

        // Phase 1: no model-load gate — Mashangxie uses cloud/Apple Speech providers
        // that don't require the long WhisperKit/Parakeet model load that Dictus had.
        // The model-load gate from upstream Dictus (SharedKeys.modelLoadState /
        // ModelLoadState) is intentionally removed for Phase 1. See task 6.2.

        activeSessionID = String(UUID().uuidString.prefix(8))
        logProbe("startRecording", details: sessionDetails())

        PersistentLog.log(.keyboardMicTapped)

        let selection = BridgeResolver.resolve(
            mode: BridgeModeStore.read(),
            appGroupAvailability: AppGroupProbe.probe()
        )

        switch selection.effectiveBridge {
        case .clipboardBridge:
            startClipboardDictationHandoff()
        case .appGroupBridge:
            startAppGroupDictationFlow()
        }
    }

    /// AppGroupBridge path — the original flow. Posts a Darwin notification and
    /// falls back to `mashangxie://dictate?source=keyboard` if the app doesn't
    /// respond within 500ms. Sets local `.requested` status to show the overlay.
    private func startAppGroupDictationFlow() {
        markRequested()

        // Try background recording first — if app is alive, it will handle this
        // notification and start recording without coming to the foreground.
        DarwinNotificationCenter.post(DarwinNotificationName.startRecording)

        // Fallback: if app didn't respond (not running), open URL to launch it.
        // We check after 500ms whether status progressed past .requested.
        // If the app handled the notification, status will be .recording by now.
        let darwinPostTime = Date()
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(500))
            guard let self = self else { return }
            let elapsedMs = Int(Date().timeIntervalSince(darwinPostTime) * 1000)
            if self.dictationStatus == .requested {
                PersistentLog.log(.coldStartDarwinFallback(
                    elapsedMs: elapsedMs,
                    status: self.dictationStatus.rawValue
                ))
                self.logProbe("fallbackOpenURL", details: self.sessionDetails())
                // App didn't respond — not running. Open URL to launch it.
                if let url = URL(string: "mashangxie://dictate?source=keyboard") {
                    if let openURL = self.openURL {
                        openURL(url)
                    } else {
                        self.openURLFromExtension(url)
                    }
                }
            }
        }
    }

    /// ClipboardBridge path — open the main app's clipboard dictation handoff
    /// page via deep link. Does NOT post Darwin notifications, does NOT show
    /// the AppGroup recording overlay, does NOT write `.requested` status.
    ///
    /// Sets a keyboard-local pending flag so that on the next keyboard appearance
    /// we read the pasteboard once and show a preview pill.
    private func startClipboardDictationHandoff() {
        logProbe("startClipboardDictationHandoff", details: sessionDetails())

        // Set pending state — stored locally (not AppGroup) so it survives even
        // when AppGroup is unavailable.
        let pending = PendingClipboardDictation(
            launched: true,
            didAttemptPasteboardRead: false,
            previewText: nil,
            fullText: nil,
            readFailureReason: nil,
            dismissed: false
        )
        clipboardReadAttemptCount = 0
        clipboardReadDidReportFailure = false
        cancelClipboardReadRetry()
        pendingClipboard = pending
        persistPendingClipboardLocally(pending)

        ClipboardBridgeEventLog.shared.record(.init(kind: .deepLinkOpened))

        guard let url = URL(string: "mashangxie://dictation/clipboard-start?source=keyboard") else {
            PersistentLog.log(.diagnosticProbe(
                component: "KeyboardState",
                instanceID: instanceID,
                action: "clipboardDeepLinkBuildFailed",
                details: ""
            ))
            clearPendingClipboard()
            return
        }

        if let openURL = openURL {
            openURL(url)
        } else {
            openURLFromExtension(url)
        }
    }

    /// Write "requested" status to App Group before triggering URL.
    func markRequested() {
        logProbe("markRequested", details: sessionDetails())
        defaults.set(DictationStatus.requested.rawValue, forKey: SharedKeys.dictationStatus)
        defaults.removeObject(forKey: SharedKeys.liveTranscription)
        defaults.removeObject(forKey: SharedKeys.liveTranscriptionTimestamp)
        defaults.synchronize()
        dictationStatus = .requested
        liveTranscription = nil
        startWatchdog()
        HapticFeedback.recordingStarted()
    }

    private func sessionDetails() -> String {
        let sessionID = activeSessionID ?? "none"
        return "sessionID=\(sessionID) status=\(dictationStatus.rawValue) energyCount=\(waveformEnergy.count)"
    }

    private func logProbe(_ action: String, details: String = "") {
        PersistentLog.log(.diagnosticProbe(
            component: "KeyboardState",
            instanceID: instanceID,
            action: action,
            details: details
        ))
    }

    private func waveformStatsDetails(_ values: [Float]) -> String {
        guard !values.isEmpty else { return "count=0" }
        let minValue = values.min() ?? 0
        let maxValue = values.max() ?? 0
        let spread = maxValue - minValue
        let first = values.first ?? 0
        let middle = values[values.count / 2]
        let last = values.last ?? 0
        return String(
            format: "count=%d min=%.3f max=%.3f spread=%.3f first=%.3f mid=%.3f last=%.3f",
            values.count,
            minValue,
            maxValue,
            spread,
            first,
            middle,
            last
        )
    }

    // MARK: - ClipboardBridge pending state

    /// Persist pending state to local UserDefaults so it survives the keyboard
    /// extension being killed by iOS while the user is in the main app.
    /// Uses standard UserDefaults (NOT AppGroup) — ClipboardBridge is the
    /// fallback when AppGroup is unavailable.
    private func persistPendingClipboardLocally(_ pending: PendingClipboardDictation) {
        let standard = UserDefaults.standard
        standard.set(pending.launched, forKey: SharedKeys.pendingClipboardLaunched)
        if let text = pending.fullText {
            standard.set(text, forKey: SharedKeys.pendingClipboardText)
        } else {
            standard.removeObject(forKey: SharedKeys.pendingClipboardText)
        }
        if let failureReason = pending.readFailureReason {
            standard.set(failureReason.rawValue, forKey: SharedKeys.pendingClipboardFailureReason)
        } else {
            standard.removeObject(forKey: SharedKeys.pendingClipboardFailureReason)
        }
        standard.set(Date().timeIntervalSince1970, forKey: SharedKeys.pendingClipboardTimestamp)
        standard.synchronize()
    }

    /// Restore pending state from local UserDefaults. Called during init so
    /// the keyboard can recover its pending state after being killed and
    /// re-launched by iOS.
    private func restorePendingClipboardIfPresent() {
        let standard = UserDefaults.standard
        guard standard.bool(forKey: SharedKeys.pendingClipboardLaunched) else {
            return
        }
        // Stale pending state older than 5 minutes is discarded — the user has
        // almost certainly abandoned the flow by then.
        let timestamp = standard.double(forKey: SharedKeys.pendingClipboardTimestamp)
        let age = Date().timeIntervalSince1970 - timestamp
        if timestamp > 0 && age > 300 {
            clearPendingClipboardLocally()
            return
        }
        let fullText = standard.string(forKey: SharedKeys.pendingClipboardText)
        let failureReason = standard.string(forKey: SharedKeys.pendingClipboardFailureReason)
            .flatMap(ClipboardReadFailureReason.init(rawValue:))
        pendingClipboard = PendingClipboardDictation(
            launched: true,
            didAttemptPasteboardRead: fullText != nil || failureReason != nil,
            previewText: fullText.map { Self.middleTruncatedPreview($0) },
            fullText: fullText,
            readFailureReason: failureReason,
            dismissed: false
        )
    }

    /// Clear in-memory pending state. Does NOT touch UIPasteboard.
    private func clearPendingClipboard() {
        cancelClipboardReadRetry()
        clipboardReadAttemptCount = 0
        clipboardReadDidReportFailure = false
        pendingClipboard = .none
        clearPendingClipboardLocally()
    }

    private func clearPendingClipboardLocally() {
        let standard = UserDefaults.standard
        standard.removeObject(forKey: SharedKeys.pendingClipboardLaunched)
        standard.removeObject(forKey: SharedKeys.pendingClipboardText)
        standard.removeObject(forKey: SharedKeys.pendingClipboardFailureReason)
        standard.removeObject(forKey: SharedKeys.pendingClipboardTimestamp)
        standard.synchronize()
    }

    /// Called by KeyboardRootView / KeyboardViewController when the keyboard
    /// becomes active. Attempts to read the pasteboard if we have a pending
    /// ClipboardBridge launch.
    ///
    /// WHY retry: on real devices, returning from the main app can show the
    /// keyboard before pasteboard content / paste permission is immediately
    /// readable. The old "read once then clear" behavior lost valid results.
    func readPasteboardOnceIfPending() {
        readPasteboardIfPending(reason: "appearance")
    }

    private func readPasteboardIfPending(reason: String) {
        guard pendingClipboard.launched,
              pendingClipboard.fullText == nil,
              !pendingClipboard.dismissed else {
            return
        }

        clipboardReadAttemptCount += 1
        let hasFullAccess = controller?.hasFullAccess
        let hasFullAccessDescription = hasFullAccess.map { $0 ? "true" : "false" } ?? "unknown"
        let changeCount = UIPasteboard.general.changeCount

        if hasFullAccess == false {
            ClipboardBridgeEventLog.shared.record(.init(kind: .pasteboardReadFailed))
            logProbe(
                "clipboardPasteboardReadBlocked",
                details: "attempt=\(clipboardReadAttemptCount) reason=\(reason) hasFullAccess=false changeCount=\(changeCount)"
            )
            markClipboardReadFailed(.fullAccessRequired)
            return
        }

        // UIPasteboard.string can trigger the system permission banner. This is
        // expected behavior — the user just tapped the mic and returned from
        // the main app, so the banner is contextual and not surprising.
        guard let text = pasteboardStringProvider()?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !text.isEmpty else {
            // Empty / non-text / temporarily denied: keep pending and retry.
            // Don't touch the pasteboard itself.
            ClipboardBridgeEventLog.shared.record(.init(kind: .pasteboardReadEmpty))
            logProbe(
                "clipboardPasteboardReadEmpty",
                details: "attempt=\(clipboardReadAttemptCount) reason=\(reason) hasFullAccess=\(hasFullAccessDescription) changeCount=\(changeCount)"
            )
            scheduleClipboardReadRetryIfNeeded()
            return
        }

        ClipboardBridgeEventLog.shared.record(.init(kind: .pasteboardReadSuccess))
        logProbe(
            "clipboardPasteboardReadSuccess",
            details: "attempt=\(clipboardReadAttemptCount) reason=\(reason) hasFullAccess=\(hasFullAccessDescription) changeCount=\(changeCount) length=\(text.count)"
        )
        cancelClipboardReadRetry()
        let updated = PendingClipboardDictation(
            launched: true,
            didAttemptPasteboardRead: true,
            previewText: Self.middleTruncatedPreview(text),
            fullText: text,
            readFailureReason: nil,
            dismissed: false
        )
        pendingClipboard = updated
        persistPendingClipboardLocally(updated)
    }

    private func scheduleClipboardReadRetryIfNeeded() {
        guard clipboardReadAttemptCount < maxClipboardReadAttempts,
              clipboardReadRetryTask == nil,
              isKeyboardVisible else {
            reportClipboardReadFailureIfNeeded(reason: "retryStopped")
            return
        }

        let attempt = clipboardReadAttemptCount
        let delayNanos = UInt64(min(1.25, 0.25 * Double(attempt + 1)) * 1_000_000_000)
        clipboardReadRetryTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: delayNanos)
            guard !Task.isCancelled else { return }
            await self?.performClipboardReadRetry()
        }
    }

    private func performClipboardReadRetry() {
        clipboardReadRetryTask = nil
        readPasteboardIfPending(reason: "retry")
    }

    private func cancelClipboardReadRetry() {
        clipboardReadRetryTask?.cancel()
        clipboardReadRetryTask = nil
    }

    private func reportClipboardReadFailureIfNeeded(reason: String) {
        guard pendingClipboard.launched,
              pendingClipboard.fullText == nil,
              !pendingClipboard.dismissed,
              !clipboardReadDidReportFailure else {
            return
        }

        clipboardReadDidReportFailure = true
        ClipboardBridgeEventLog.shared.record(.init(kind: .pasteboardReadFailed))
        logProbe(
            "clipboardPasteboardReadFailed",
            details: "attempts=\(clipboardReadAttemptCount) reason=\(reason) visible=\(isKeyboardVisible) hasFullAccess=\(controller?.hasFullAccess.description ?? "unknown") changeCount=\(UIPasteboard.general.changeCount)"
        )
        markClipboardReadFailed(.pasteboardUnavailable)
    }

    private func markClipboardReadFailed(_ failureReason: ClipboardReadFailureReason) {
        cancelClipboardReadRetry()
        let updated = PendingClipboardDictation(
            launched: pendingClipboard.launched,
            didAttemptPasteboardRead: true,
            previewText: nil,
            fullText: nil,
            readFailureReason: failureReason,
            dismissed: pendingClipboard.dismissed
        )
        pendingClipboard = updated
        persistPendingClipboardLocally(updated)
    }

    func retryPendingClipboardRead() {
        guard pendingClipboard.launched,
              pendingClipboard.fullText == nil,
              !pendingClipboard.dismissed else {
            return
        }
        clipboardReadAttemptCount = 0
        clipboardReadDidReportFailure = false
        cancelClipboardReadRetry()
        pendingClipboard = PendingClipboardDictation(
            launched: true,
            didAttemptPasteboardRead: false,
            previewText: nil,
            fullText: nil,
            readFailureReason: nil,
            dismissed: false
        )
        readPasteboardIfPending(reason: "manualRetry")
    }

    /// Insert the pending clipboard text into the active text field via
    /// `textDocumentProxy.insertText`. Clears local pending state. Does NOT
    /// clear UIPasteboard. Does NOT show an "inserted" toast.
    func insertPendingTextAndClear() {
        guard let fullText = pendingClipboard.fullText, !fullText.isEmpty else {
            // Nothing to insert — clear silently.
            clearPendingClipboard()
            return
        }
        controller?.textDocumentProxy.insertText(fullText)
        ClipboardBridgeEventLog.shared.record(.init(kind: .inserted))
        PersistentLog.log(.keyboardTextInserted)
        clearPendingClipboard()
    }

    /// Dismiss the pending preview without inserting. Clears local pending
    /// state. Does NOT clear UIPasteboard. Does NOT insert text.
    func dismissPendingAndClear() {
        ClipboardBridgeEventLog.shared.record(.init(kind: .dismissed))
        clearPendingClipboard()
    }

    /// Build a one-line preview with middle truncation, e.g.
    /// "你好世界今天天气真好" -> "你好世…天气真好"
    /// Keeps up to `headCount` + `tailCount` characters around an ellipsis.
    static func middleTruncatedPreview(
        _ text: String,
        headCount: Int = 6,
        tailCount: Int = 6
    ) -> String {
        let trimmed = text.replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > headCount + tailCount + 1 else {
            return trimmed
        }
        let head = trimmed.prefix(headCount)
        let tail = trimmed.suffix(tailCount)
        return "\(head)…\(tail)"
    }

    // MARK: - Test hooks

    /// Test-only: restore pending state from local UserDefaults.
    func restorePendingClipboardIfPresentForTesting() {
        restorePendingClipboardIfPresent()
    }

    /// Test-only: clear all pending state (in-memory + local UD).
    func clearPendingClipboardForTesting() {
        clearPendingClipboard()
    }

    /// Test-only: clear mic debounce between XCTest methods. The production
    /// debounce is intentionally process-wide through the singleton state, but
    /// tests reuse `KeyboardState.shared` and otherwise bleed tap timing across
    /// cases.
    func resetMicDebounceForTesting() {
        lastMicTapDate = .distantPast
    }

    /// Test-only: inject pending state for testing insert/dismiss flows.
    func setPendingClipboardForTesting(_ pending: PendingClipboardDictation) {
        pendingClipboard = pending
        persistPendingClipboardLocally(pending)
    }
}

/// ClipboardBridge pending state.
///
/// Lives in `KeyboardState` and is also persisted to local UserDefaults so it
/// survives the keyboard extension being killed by iOS while the user is in
/// the main app.
struct PendingClipboardDictation: Equatable {
    /// True after the user tapped the mic in Clipboard mode and we opened
    /// the main-app deep link. False in normal typing mode.
    let launched: Bool
    /// True after we attempted a UIPasteboard read on keyboard return. Used
    /// to ensure we only read once per pending session.
    let didAttemptPasteboardRead: Bool
    /// Middle-truncated preview text for the toolbar pill. May be nil even
    /// if `launched` is true (before the read).
    let previewText: String?
    /// Full clipboard text captured on the pending return. Inserted when the
    /// user taps the preview.
    let fullText: String?
    /// Why the keyboard failed to read the pasteboard. Nil while waiting or
    /// after a successful read.
    let readFailureReason: ClipboardReadFailureReason?
    /// True if the user dismissed the preview without inserting. Used for
    /// diagnostics only — once dismissed, the pending state is cleared.
    let dismissed: Bool

    static let none = PendingClipboardDictation(
        launched: false,
        didAttemptPasteboardRead: false,
        previewText: nil,
        fullText: nil,
        readFailureReason: nil,
        dismissed: false
    )

    var hasPreview: Bool {
        previewText != nil && !previewText!.isEmpty
    }
}

enum ClipboardReadFailureReason: String, Equatable {
    case fullAccessRequired
    case pasteboardUnavailable
}
