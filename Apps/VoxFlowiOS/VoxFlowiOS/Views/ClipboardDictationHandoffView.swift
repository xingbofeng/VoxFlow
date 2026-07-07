import SwiftUI
import AVFoundation
import Combine
import Speech
import Shared

/// Independent main-app page that records audio, streams partial transcription
/// to the user, and copies the final (or fallback partial) result to
/// UIPasteboard. Designed for the ClipboardBridge fallback path used by
/// free-signed (AltStore / SideStore / free Apple ID) installs where AppGroup
/// is unavailable.
///
/// Why this is a separate page (not a tab, not the AppGroupBridge recording
/// view): the AppGroupBridge formal recording page (`RecordingView`) is built
/// around Darwin notifications and AppGroup shared defaults. ClipboardBridge
/// has a different lifecycle (write to UIPasteboard, user manually returns)
/// and a different UX (auto-start, "Finish & Copy", no auto-return). Mixing
/// the two would tangle their state machines. This page is reached ONLY via
/// the `mashangxie://dictation/clipboard-start` deep link.
struct ClipboardDictationHandoffView: View {
    /// Set by the URL router. The view calls this on dismiss so the router
    /// can clear its presentation state.
    var onDismiss: () -> Void

    @StateObject private var state: ClipboardDictationHandoffState
    @EnvironmentObject private var appState: AppState

    /// Set once in `.onAppear` to avoid restarting when SwiftUI re-renders.
    @State private var didStartSession = false
    @State private var backgroundGraceTimer: Timer?
    @State private var elapsedSeconds = 0
    @State private var elapsedTimer: Timer?
    @State private var finalizingStartedAt: Date?
    @State private var pendingFinalTask: Task<Void, Never>?
    @State private var resultSwipeProgress: CGFloat = 0
    @State private var resultSwipeTimer: Timer?
    /// Combine subscription for forwarding AppState.sessionState -> handoff state.
    @State private var stateCancellable: AnyCancellable?

    init(providerDisplayName: String, onDismiss: @escaping () -> Void) {
        self.onDismiss = onDismiss
        _state = StateObject(
            wrappedValue: ClipboardDictationHandoffState(providerDisplayName: providerDisplayName)
        )
    }

    var body: some View {
        ZStack {
            handoffBackground

            redesignedContent
        }
        .onAppear {
            guard !didStartSession else { return }
            didStartSession = true
            prepareFreshSession()
            observeAppState()
            startSession()
        }
        .onDisappear {
            backgroundGraceTimer?.invalidate()
            backgroundGraceTimer = nil
            elapsedTimer?.invalidate()
            elapsedTimer = nil
            pendingFinalTask?.cancel()
            pendingFinalTask = nil
            finalizingStartedAt = nil
            stopResultSwipeLoop()
            stateCancellable?.cancel()
            stateCancellable = nil
            // If recording is still active when the view disappears, cancel.
            // This covers cases where iOS dismisses the view unexpectedly.
            if state.snapshot.phase == .recording || state.snapshot.phase == .finalizing {
                state.cancel()
                appState.cancelDictation()
            }
            appState.clearResult()
        }
        .onChange(of: scenePhase) { _, phase in
            handleScenePhase(phase)
        }
        .onChange(of: state.snapshot.copiedText) { _, copiedText in
            guard let copiedText,
                  !copiedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return
            }
            UIPasteboard.general.string = copiedText
            if UIPasteboard.general.string == copiedText {
                ClipboardBridgeEventLog.shared.record(.init(kind: .pasteboardWriteSuccess))
                PersistentLog.log(.diagnosticProbe(
                    component: "ClipboardDictationHandoffView",
                    instanceID: "main",
                    action: "pasteboardWriteSuccess",
                    details: "length=\(copiedText.count)"
                ))
            } else {
                ClipboardBridgeEventLog.shared.record(.init(kind: .pasteboardWriteFailed))
                PersistentLog.log(.diagnosticProbe(
                    component: "ClipboardDictationHandoffView",
                    instanceID: "main",
                    action: "pasteboardWriteFailed",
                    details: "length=\(copiedText.count)"
                ))
            }
        }
        .onChange(of: state.snapshot.phase) { _, phase in
            if phase == .copied {
                startResultSwipeLoop()
            } else {
                stopResultSwipeLoop()
            }
        }
    }

    @Environment(\.scenePhase) private var scenePhase

    // MARK: - Redesigned ClipboardBridge Page

    private var handoffBackground: some View {
        LinearGradient(
            colors: [
                Color(red: 0.02, green: 0.07, blue: 0.16),
                Color(red: 0.02, green: 0.03, blue: 0.10)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea()
    }

    private var redesignedContent: some View {
        GeometryReader { geometry in
            let contentWidth = max(0, geometry.size.width - 40)

            VStack(spacing: 0) {
                Spacer(minLength: 42)

                Text(phaseTitleText)
                    .font(.system(size: 29, weight: .bold))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.82)
                    .frame(maxWidth: .infinity)

                phaseStatusLine
                    .padding(.top, 12)

                Spacer(minLength: 26)

                centerStage(contentWidth: contentWidth)

                Spacer(minLength: 34)

                Text(phaseInstructionText)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.white.opacity(0.70))
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
                    .padding(.horizontal, 26)

                Spacer(minLength: 28)

                bottomActionButton
                    .padding(.horizontal, 16)

                cancelTextButton
                    .padding(.top, 16)
            }
            .frame(width: contentWidth, height: geometry.size.height)
            .padding(.horizontal, 20)
            .padding(.bottom, 22)
        }
    }

    private var phaseTitleText: String {
        switch state.snapshot.phase {
        case .preparing:
            return L10n.t("clipboard_handoff.preparing_title")
        case .requestingPermission:
            return L10n.t("clipboard_handoff.permission_requesting")
        case .recording:
            return L10n.t("clipboard_handoff.recording_title")
        case .finalizing:
            return L10n.t("clipboard_handoff.finalizing_title")
        case .copied:
            return L10n.t("clipboard_handoff.copied_title")
        case .empty:
            return L10n.t("clipboard_handoff.empty_title")
        case .failed:
            return L10n.t("clipboard_handoff.failed_title")
        case .cancelled:
            return ""
        }
    }

    @ViewBuilder
    private var phaseStatusLine: some View {
        switch state.snapshot.phase {
        case .recording:
            VStack(spacing: 12) {
                Text(elapsedTimeText)
                    .font(.system(size: 24, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(.white.opacity(0.90))

                HStack(spacing: 8) {
                    Circle()
                        .fill(Color.dictusSuccess)
                        .frame(width: 8, height: 8)
                    Text(state.snapshot.providerDisplayName)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.76))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
            }
        case .finalizing:
            HStack(spacing: 10) {
                ProgressView()
                    .tint(Color.dictusSuccess)
                Text(L10n.t("clipboard_handoff.status_waiting_final"))
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.76))
            }
        default:
            Color.clear.frame(height: 18)
        }
    }

    private var phaseInstructionText: String {
        switch state.snapshot.phase {
        case .preparing:
            return state.snapshot.providerDisplayName
        case .requestingPermission:
            return L10n.t("clipboard_handoff.permission_requesting")
        case .recording:
            return L10n.t("clipboard_handoff.subtitle")
        case .finalizing:
            return L10n.t("clipboard_handoff.button_finalizing")
        case .copied:
            return state.snapshot.copiedWasFallbackPartial
                ? L10n.t("clipboard_handoff.copied_temporary_hint")
                : L10n.t("clipboard_handoff.copied_hint")
        case .empty:
            return L10n.t("clipboard_handoff.empty_hint")
        case .failed:
            return state.snapshot.errorMessage ?? L10n.t("clipboard_handoff.failed_title")
        case .cancelled:
            return ""
        }
    }

    private func finalizingCard(width: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(partialTextForDisplay)
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(.white.opacity(0.68))
                .lineLimit(4)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)
                .padding(.top, 20)

            Spacer()

            VStack(spacing: 18) {
                ProgressBar()
                    .frame(height: 7)
                    .padding(.horizontal, 18)

                Text(L10n.t("clipboard_handoff.status_fetching_final"))
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.62))
            }
            .padding(.bottom, 20)
        }
        .frame(width: width, height: 324)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.white.opacity(0.035))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(.white.opacity(0.18), lineWidth: 1.5)
        )
    }

    @ViewBuilder
    private func centerStage(contentWidth: CGFloat) -> some View {
        switch state.snapshot.phase {
        case .recording:
            recordingWaveformStage(width: contentWidth)
        case .finalizing:
            finalizingCard(width: min(max(0, contentWidth - 8), 344))
        default:
            outcomeStage(width: contentWidth)
        }
    }

    private func recordingWaveformStage(width: CGFloat) -> some View {
        VStack(spacing: 28) {
            BrandWaveform(
                energyLevels: recordingWaveformLevels,
                maxHeight: 120,
                isProcessing: false,
                isActive: true
            )
            .opacity(0.62)
            .frame(width: width)
            .accessibilityHidden(true)

            Text(partialTextForDisplay)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(.white.opacity(0.82))
                .multilineTextAlignment(.center)
                .lineSpacing(6)
                .lineLimit(5)
                .minimumScaleFactor(0.78)
                .frame(maxWidth: max(0, width - 12))
        }
        .frame(width: width, height: 268)
    }

    @ViewBuilder
    private func outcomeStage(width: CGFloat) -> some View {
        VStack(spacing: 28) {
            phaseHero

            Text(outcomeCaptionText)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(.white.opacity(0.74))
                .multilineTextAlignment(.center)
                .lineSpacing(6)
                .lineLimit(6)
                .minimumScaleFactor(0.76)
                .frame(maxWidth: max(0, width - 20))

        }
        .frame(width: width, height: 268)
    }

    @ViewBuilder
    private var phaseHero: some View {
        switch state.snapshot.phase {
        case .preparing, .requestingPermission, .finalizing:
            ProgressView()
                .tint(Color.dictusSuccess)
                .controlSize(.large)
                .scaleEffect(1.35)
        case .copied:
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 74, weight: .semibold))
                .foregroundStyle(Color.dictusSuccess)
        case .empty:
            Image(systemName: "waveform.slash")
                .font(.system(size: 64, weight: .semibold))
                .foregroundStyle(.white.opacity(0.62))
        case .failed:
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 60, weight: .semibold))
                .foregroundStyle(.orange)
        case .recording:
            Image(systemName: "waveform")
                .font(.system(size: 64, weight: .semibold))
                .foregroundStyle(Color.dictusSuccess)
        case .cancelled:
            EmptyView()
        }
    }

    private var outcomeCaptionText: String {
        switch state.snapshot.phase {
        case .recording, .finalizing:
            let trimmed = state.snapshot.partialText.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? L10n.t("clipboard_handoff.status_recognizing") : trimmed
        case .copied:
            return state.snapshot.copiedTextPreview ?? L10n.t("clipboard_handoff.copied_title")
        case .empty:
            return L10n.t("clipboard_handoff.empty_hint")
        case .failed:
            return state.snapshot.errorMessage ?? L10n.t("clipboard_handoff.failed_title")
        default:
            return L10n.t("clipboard_handoff.partial_placeholder")
        }
    }

    @ViewBuilder
    private var bottomActionButton: some View {
        switch state.snapshot.phase {
        case .recording:
            Button(action: finishAndCopyTapped) {
                HStack(spacing: 12) {
                    Image(systemName: "stop.fill")
                        .font(.system(size: 14, weight: .bold))
                    Text(L10n.t("clipboard_handoff.button_stop_and_recognize"))
                        .font(.system(size: 18, weight: .bold))
                }
                .foregroundStyle(Color(red: 0.02, green: 0.08, blue: 0.10))
                .frame(maxWidth: .infinity)
                .frame(height: 58)
                .background(
                    Capsule()
                        .fill(Color(red: 0.55, green: 0.93, blue: 0.72))
                )
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L10n.t("clipboard_handoff.button_complete_and_copy"))
        case .finalizing:
            Color.clear.frame(height: 58)
        case .copied:
            ClipboardResultSwipeHint(progress: resultSwipeProgress)
            .frame(maxWidth: .infinity)
            .frame(height: 76)
        case .empty, .failed:
            Button(action: retryTapped) {
                Text(L10n.t("clipboard_handoff.button_retry"))
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(Color(red: 0.02, green: 0.08, blue: 0.10))
                    .frame(maxWidth: .infinity)
                    .frame(height: 58)
                    .background(
                        Capsule()
                            .fill(Color(red: 0.55, green: 0.93, blue: 0.72))
                    )
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L10n.t("clipboard_handoff.button_retry"))
        case .preparing, .requestingPermission, .cancelled:
            Color.clear.frame(height: 58)
        }
    }

    @ViewBuilder
    private var cancelTextButton: some View {
        switch state.snapshot.phase {
        case .recording, .preparing, .requestingPermission:
            Button(L10n.t("clipboard_handoff.button_cancel"), action: cancelTapped)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Color(red: 0.55, green: 0.93, blue: 0.72))
                .buttonStyle(.plain)
        default:
            Color.clear.frame(height: 20)
        }
    }

    private var elapsedTimeText: String {
        String(format: "%02d:%02d", elapsedSeconds / 60, elapsedSeconds % 60)
    }

    /// Bridge AppState.sessionState into the handoff state machine.
    /// - `.recording(liveText)` / `.transcribing(liveText)` → updatePartial
    /// - `.finished(text)` → handleFinal (writes to UIPasteboard)
    /// - `.failed(message)` → fail (no pasteboard write)
    private func observeAppState() {
        stateCancellable = appState.$sessionState.sink { sessionState in
            switch sessionState {
            case .idle, .requestingPermission:
                break
            case .recording(let liveText), .transcribing(let liveText):
                state.updatePartial(liveText)
            case .finished(let text):
                handleObservedFinal(text)
            case .failed(let message):
                pendingFinalTask?.cancel()
                pendingFinalTask = nil
                finalizingStartedAt = nil
                state.fail(message)
            }
        }
    }

    /// Start every ClipboardBridge jump-out session from a clean slate.
    /// Without this, the initial Combine subscription can immediately replay
    /// the previous `.finished(text)` AppState value and show stale "Copied".
    private func prepareFreshSession() {
        backgroundGraceTimer?.invalidate()
        backgroundGraceTimer = nil
        elapsedTimer?.invalidate()
        elapsedTimer = nil
        elapsedSeconds = 0
        pendingFinalTask?.cancel()
        pendingFinalTask = nil
        finalizingStartedAt = nil
        stopResultSwipeLoop()
        stateCancellable?.cancel()
        stateCancellable = nil
        appState.clearResult()
        state.resetForRetry()
    }

    private var partialTextForDisplay: String {
        let trimmed = state.snapshot.partialText.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? L10n.t("clipboard_handoff.partial_placeholder") : trimmed
    }

    private var recordingWaveformLevels: [Float] {
        appState.waveformEnergy.isEmpty
            ? Array(repeating: 0, count: 30)
            : appState.waveformEnergy
    }

    // MARK: - Actions

    private func startSession() {
        state.transitionToRequestingPermission()
        state.transitionToRecording()
        startElapsedTimer()

        Task {
            await beginStreamingDictation()
        }
    }

    private func startElapsedTimer() {
        elapsedTimer?.invalidate()
        elapsedSeconds = 0
        elapsedTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            Task { @MainActor in
                elapsedSeconds += 1
            }
        }
    }

    private func beginStreamingDictation() async {
        // The AppState's existing startDictation() drives the streaming ASR.
        // We observe state changes via Combine and forward them to the
        // handoff state machine.
        await appState.startDictation()
    }

    private func finishAndCopyTapped() {
        guard state.snapshot.phase == .recording else { return }
        elapsedTimer?.invalidate()
        elapsedTimer = nil
        finalizingStartedAt = Date()
        state.beginFinalizing()
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(120))
            guard state.snapshot.phase == .finalizing else { return }
            appState.stopDictation()
        }
        // The final result arrives via the AppState observer below. If no
        // final arrives within 8s, the state machine's finalizing timer
        // fires and falls back to the latest partial.
    }

    private func cancelTapped() {
        elapsedTimer?.invalidate()
        elapsedTimer = nil
        pendingFinalTask?.cancel()
        pendingFinalTask = nil
        finalizingStartedAt = nil
        stopResultSwipeLoop()
        state.cancel()
        appState.cancelDictation()
        onDismiss()
    }

    private func retryTapped() {
        appState.clearResult()
        state.resetForRetry()
        pendingFinalTask?.cancel()
        pendingFinalTask = nil
        finalizingStartedAt = nil
        stopResultSwipeLoop()
        didStartSession = false
        // Re-enter the session on the next render cycle.
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(50))
            startSession()
        }
    }

    private func handleObservedFinal(_ text: String) {
        guard state.snapshot.phase == .finalizing,
              let finalizingStartedAt else {
            state.handleFinal(text)
            return
        }

        let elapsed = Date().timeIntervalSince(finalizingStartedAt)
        let remaining = max(0, 1.15 - elapsed)
        pendingFinalTask?.cancel()
        pendingFinalTask = Task { @MainActor in
            if remaining > 0 {
                try? await Task.sleep(for: .milliseconds(Int(remaining * 1000)))
            }
            guard !Task.isCancelled else { return }
            self.finalizingStartedAt = nil
            state.handleFinal(text)
        }
    }

    private func startResultSwipeLoop() {
        resultSwipeTimer?.invalidate()
        animateResultSwipeForward()
        resultSwipeTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { _ in
            Task { @MainActor in
                animateResultSwipeForward()
            }
        }
    }

    private func stopResultSwipeLoop() {
        resultSwipeTimer?.invalidate()
        resultSwipeTimer = nil
        resultSwipeProgress = 0
    }

    private func animateResultSwipeForward() {
        resultSwipeProgress = 0
        withAnimation(.timingCurve(0.4, 0, 0.2, 1, duration: 1.2)) {
            resultSwipeProgress = 1
        }
    }

    // MARK: - Scene phase

    private func handleScenePhase(_ phase: ScenePhase) {
        switch phase {
        case .background, .inactive:
            // Per spec: recording state → cancel immediately, no copy.
            // finalizing state → 3s grace.
            if state.snapshot.phase == .finalizing {
                state.handleBackgroundTransition()
                backgroundGraceTimer?.invalidate()
                backgroundGraceTimer = Timer.scheduledTimer(
                    withTimeInterval: 3.0,
                    repeats: false
                ) { _ in
                    Task { @MainActor in
                        state.handleFinalizingBackgroundGraceTimeout()
                    }
                }
            } else if state.snapshot.phase == .recording {
                state.handleBackgroundTransition()
                appState.cancelDictation()
            }
        case .active:
            break
        @unknown default:
            break
        }
    }
}

private struct ClipboardResultSwipeHint: View {
    var progress: CGFloat

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                ForEach(0..<3, id: \.self) { index in
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(
                            Color.dictusAccent.opacity(
                                max(0, (0.55 - Double(index) * 0.16) * Double(progress))
                            )
                        )
                        .offset(x: -CGFloat(18 + index * 10) + progress * 70)
                }

                Image(systemName: "hand.point.up")
                    .font(.system(size: 28, weight: .light))
                    .foregroundStyle(.white.opacity(0.86))
                    .offset(x: -30 + progress * 80)
                    .opacity(1.0 - progress * 0.28)
            }
            .frame(width: 150, height: 42)

            Text(L10n.t("cold_start.instruction"))
                .font(.callout.weight(.medium))
                .foregroundStyle(Color.dictusAccent)
                .multilineTextAlignment(.center)
                .lineSpacing(4)
        }
    }
}

private struct ProgressBar: View {
    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(.white.opacity(0.16))
                Capsule()
                    .fill(Color(red: 0.55, green: 0.93, blue: 0.72))
                    .frame(width: geometry.size.width * 0.24)
            }
        }
    }
}
