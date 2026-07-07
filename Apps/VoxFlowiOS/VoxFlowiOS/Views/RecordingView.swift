// DictusApp/Views/RecordingView.swift
// Stable-layout recording screen: waveform + mic button always in place, text appears below.
import SwiftUI
import Shared

/// Determines the context in which RecordingView is shown.
///
/// WHY a mode enum instead of separate views:
/// The recording experience should feel identical whether the user reaches it
/// from onboarding or from HomeView's "New dictation" button.
/// The only difference is what happens when the user finishes:
/// - onboarding: calls onComplete to advance onboarding
/// - standalone: user taps mic again for new recording, or X to dismiss
enum RecordingMode {
    case onboarding
    case standalone
}

/// Stable-layout recording screen with always-visible waveform and fixed mic button.
///
/// WHY stable layout instead of state-driven visibility:
/// Elements appearing/disappearing causes jarring layout shifts. The waveform and mic
/// button stay in place across all states — only their visual appearance changes:
/// - Idle: flat waveform, blue mic
/// - Recording: animated waveform, red stop button
/// - Transcribing: sinusoidal waveform, disabled shimmer mic
/// - Result: flat waveform, blue mic (ready for new recording), text below
///
/// Transcription text appears BELOW the fixed elements, so nothing moves.
struct RecordingView: View {
    let mode: RecordingMode
    var onComplete: (() -> Void)?

    @EnvironmentObject var coordinator: DictationCoordinator

    @State private var transcriptionResult: String?
    @State private var showResult = false
    @State private var showError = false
    @State private var errorMessage: String?
    /// Brief "Copié !" feedback when user taps the transcription result.
    @State private var showCopiedFeedback = false
    /// Two-step dismissal: animate out first, then reset coordinator status.
    @State private var isDismissing = false

    init(mode: RecordingMode, onComplete: (() -> Void)? = nil) {
        self.mode = mode
        self.onComplete = onComplete
    }

    var body: some View {
        ZStack {
            Color.dictusBackground.ignoresSafeArea()

            VStack(spacing: 0) {
                // Close button (top-left) — standalone only
                HStack {
                    if mode == .standalone {
                        Button {
                            HapticFeedback.recordingStopped()
                            // Step 1: animate RecordingView out
                            withAnimation(.easeOut(duration: 0.25)) {
                                isDismissing = true
                            }
                            // Step 2: after animation, reset status (no animation leak to HomeView)
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                                coordinator.resetStatus()
                            }
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 17, weight: .medium))
                                .foregroundColor(.secondary)
                                .frame(width: 40, height: 40)
                                .dictusGlass(in: Circle())
                        }
                        .frame(width: 44, height: 44)
                        .buttonStyle(GlassPressStyle(pressedScale: 1.35))
                        .padding(.leading, 20)
                        .padding(.top, 8)
                    }
                    Spacer()
                }

                // MARK: - Upper zone: result text (centered between top and waveform)
                // WHY above waveform: The waveform+mic are anchored in the bottom
                // third. Placing the result in the large empty upper zone avoids
                // pushing anything down when text appears.
                ZStack {
                    if showResult, let result = transcriptionResult {
                        // WHY GeometryReader + ScrollView combo:
                        // GeometryReader gives us the available height so we can
                        // vertically center short text. ScrollView handles long text
                        // that exceeds the zone. Short text sits centered; long text scrolls.
                        GeometryReader { geo in
                            ScrollView {
                                Button {
                                    UIPasteboard.general.string = result
                                    showCopiedFeedback = true
                                    HapticFeedback.recordingStopped()
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                                        showCopiedFeedback = false
                                    }
                                } label: {
                                    Text(result)
                                        .font(.dictusBody)
                                        .foregroundStyle(.primary)
                                        .multilineTextAlignment(.center)
                                        .padding()
                                        .frame(maxWidth: .infinity)
                                        .dictusGlass(in: RoundedRectangle(cornerRadius: 14))
                                }
                                .buttonStyle(GlassPressStyle(pressedScale: 0.96))
                                .padding(.horizontal, 32)
                                .frame(minHeight: geo.size.height)
                            }
                        }
                        .transition(.opacity)
                    } else if showError, let error = errorMessage {
                        VStack(spacing: 12) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.system(size: 32))
                                .foregroundColor(.orange)
                            Text(error)
                                .font(.dictusCaption)
                                .foregroundColor(.dictusRecording)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 32)

                            if mode == .onboarding {
                                Button(L10n.t("recording.retry")) {
                                    errorMessage = nil
                                    showError = false
                                    showResult = false
                                }
                                .font(.dictusBody)
                                .foregroundColor(.dictusAccent)
                                .padding(.top, 8)
                            }
                        }
                    }

                    // Onboarding: auto-advance handled in handleStatusChange
                }
                .frame(maxHeight: .infinity)

                // MARK: - Waveform (always visible, anchored in bottom third)
                waveformSection
                    .padding(.horizontal)
                    .frame(height: 120)

                // MARK: - Status text (duration or processing indicator)
                statusText
                    .frame(height: 30)
                    .padding(.top, 8)

                // MARK: - Mic / Stop button (always in same position)
                micOrStopButton
                    .frame(height: 100)
                    .padding(.top, 16)

                Spacer()
                    .frame(height: 40)
            }
        }
        .opacity(isDismissing ? 0 : 1)
        .animation(.easeOut(duration: 0.3), value: showResult)
        .animation(.easeOut(duration: 0.3), value: showCopiedFeedback)
        .onChange(of: coordinator.status) { _, newStatus in
            handleStatusChange(newStatus)
        }
        .navigationBarHidden(true)
    }

    // MARK: - Waveform Section

    /// Always-visible waveform that changes behavior based on state.
    /// Single BrandWaveform instance — properties change dynamically instead of
    /// swapping 3 separate instances. Prevents ghost CADisplayLinks when the app
    /// continues its run loop in background (UIBackgroundModes:audio).
    private var waveformSection: some View {
        BrandWaveform(
            energyLevels: coordinator.status == .recording
                ? coordinator.bufferEnergy
                : Array(repeating: Float(0), count: 30),
            maxHeight: 120,
            isProcessing: coordinator.status == .transcribing,
            isActive: coordinator.status == .recording || coordinator.status == .transcribing
        )
        .opacity(coordinator.status == .recording ? 0.5 :
                 coordinator.status == .transcribing ? 0.3 : 0.15)
    }

    // MARK: - Status Text

    @ViewBuilder
    private var statusText: some View {
        if coordinator.status == .recording {
            Text(formattedTime)
                .font(.system(size: 20, weight: .light, design: .monospaced))
                .foregroundStyle(.secondary)
        } else if coordinator.status == .transcribing {
            Text(L10n.t("recording.transcribing"))
                .font(.dictusCaption)
                .foregroundStyle(.secondary)
        } else if showCopiedFeedback {
            Text(L10n.t("recording.copied"))
                .font(.dictusCaption)
                .foregroundStyle(Color.dictusSuccess)
        } else if showResult {
            Text(L10n.t("recording.tap_text_to_copy"))
                .font(.dictusCaption)
                .foregroundStyle(.secondary.opacity(0.6))
        } else {
            // Empty placeholder to maintain layout
            Text(" ")
                .font(.dictusCaption)
        }
    }

    // MARK: - Mic / Stop Button

    /// Always-present button that changes appearance based on state.
    /// WHY always present: Prevents layout jumps. The button is the visual anchor
    /// of the screen — it transforms in place (mic → stop → shimmer → mic).
    @ViewBuilder
    private var micOrStopButton: some View {
        if coordinator.status == .recording {
            // Red stop button with glass ring
            Button(action: stopRecording) {
                ZStack {
                    // Glass ring behind the stop button
                    Circle()
                        .fill(Color.clear)
                        .frame(width: 96, height: 96)
                        .dictusGlass(in: Circle())
                    Circle()
                        .fill(Color.dictusRecording)
                        .frame(width: 72, height: 72)
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.white)
                        .frame(width: 26, height: 26)
                }
            }
            .buttonStyle(GlassPressStyle(pressedScale: 0.88))
            .accessibilityLabel(L10n.t("recording.stop_accessibility"))
        } else if coordinator.status == .transcribing {
            // Shimmer mic during processing (disabled)
            AnimatedMicButton(status: .transcribing) {}
                .disabled(true)
        } else {
            // Idle / result state: mic button ready for (new) recording
            AnimatedMicButton(status: .idle) {
                startRecording()
            }
        }
    }

    // MARK: - Actions

    private func startRecording() {
        // Reset previous result state
        transcriptionResult = nil
        showResult = false
        showError = false
        errorMessage = nil
        showCopiedFeedback = false

        HapticFeedback.recordingStarted()
        coordinator.startDictation()
    }

    private func stopRecording() {
        HapticFeedback.recordingStopped()
        coordinator.stopDictation()
    }

    // MARK: - Status Handling

    private func handleStatusChange(_ newStatus: DictationStatus) {
        switch newStatus {
        case .ready:
            if let result = coordinator.lastResult, !result.isEmpty {
                transcriptionResult = result
                withAnimation(.easeOut(duration: 0.4)) {
                    showResult = true
                }
                // Auto-advance to success screen in onboarding mode
                // Shows transcription result for 1.5s then triggers onComplete
                if mode == .onboarding {
                    Task {
                        try? await Task.sleep(for: .milliseconds(1500))
                        await MainActor.run {
                            coordinator.resetStatus()
                            onComplete?()
                        }
                    }
                }
            }
        case .failed:
            showError = true
            errorMessage = coordinator.lastResult ?? L10n.t("recording.failed")
        default:
            break
        }
    }

    // MARK: - Helpers

    private var formattedTime: String {
        let totalSeconds = Int(coordinator.bufferSeconds)
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

#Preview("Recording - Idle") {
    RecordingView(mode: .standalone)
        .environmentObject(DictationCoordinator.shared)
}
