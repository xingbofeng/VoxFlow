// DictusCore/Sources/DictusCore/Design/AnimatedMicButton.swift
// Animated microphone button with visual states for idle, recording, transcribing, and success.
import SwiftUI

/// Animated mic button with 4 visual states matching dictation lifecycle.
///
/// WHY separate from keyboard ToolbarView mic button:
/// ToolbarView's mic is a compact icon in the keyboard toolbar. This AnimatedMicButton
/// is a larger, more prominent button for the main app's HomeView -- different visual
/// treatment, same functional purpose.
///
/// State machine:
/// - idle/ready: soft blue glow pulsing at 2s interval
/// - recording: red pulse ring scaling 1.0-1.3 at 0.8s interval
/// - transcribing: blue shimmer sweep moving left-to-right at 1.5s
/// - failed: same as idle (reset to inviting state)
/// - Transition from transcribing to ready: brief green flash (0.3s fade)
public struct AnimatedMicButton: View {
    public let status: DictationStatus
    public let isPill: Bool
    public let onTap: () -> Void

    public init(status: DictationStatus, isPill: Bool = false, onTap: @escaping () -> Void) {
        self.status = status
        self.isPill = isPill
        self.onTap = onTap
    }

    // MARK: - Animation State

    @State private var pulseScale: CGFloat = 1.0
    @State private var glowOpacity: Double = 0.3
    @State private var shimmerOffset: CGFloat = -1.0
    @State private var showSuccessFlash: Bool = false
    @State private var previousStatus: DictationStatus = .idle

    /// Circle mode: 72pt diameter. Pill mode: 56x36 capsule for keyboard toolbar.
    private var buttonWidth: CGFloat { isPill ? 56 : 72 }
    private var buttonHeight: CGFloat { isPill ? 36 : 72 }
    private var ringWidth: CGFloat { isPill ? 66 : 92 }
    private var ringHeight: CGFloat { isPill ? 46 : 92 }

    /// Returns Capsule or Circle based on isPill.
    /// WHY AnyShape: @ViewBuilder wraps conditionals in _ConditionalContent which
    /// doesn't conform to Shape. AnyShape (available since iOS 16) erases the
    /// concrete type so both branches return the same Shape-conforming type.
    private func mainShape() -> AnyShape {
        if isPill {
            return AnyShape(Capsule())
        } else {
            return AnyShape(Circle())
        }
    }

    /// Whether the button is tappable in the current status.
    /// Only idle, ready, and failed allow new dictation starts.
    private var isTappable: Bool {
        status == .idle || status == .ready || status == .failed
    }

    public var body: some View {
        Button(action: {
            // Belt-and-suspenders guard: .disabled should prevent this,
            // but log if somehow reached during a non-tappable state.
            guard isTappable else {
                PersistentLog.log(.rapidTapRejected)
                return
            }
            onTap()
        }) {
            ZStack {
                // Background ring effects
                ringEffect

                // Main button shape (circle or pill)
                mainShape()
                    .fill(buttonFillColor)
                    .frame(width: buttonWidth, height: buttonHeight)

                // Shimmer overlay for transcribing state
                if status == .transcribing {
                    shimmerOverlay
                }

                // Success flash overlay
                if showSuccessFlash {
                    mainShape()
                        .fill(Color.dictusSuccess.opacity(0.6))
                        .frame(width: buttonWidth, height: buttonHeight)
                }

                // Mic icon
                Image(systemName: "mic.fill")
                    .font(.system(size: isPill ? 14 : 16, weight: .medium))
                    .foregroundColor(.white)
                    .scaleEffect(status == .recording ? pulseScale * 0.9 + 0.1 : 1.0)
            }
        }
        .buttonStyle(GlassPressStyle(pressedScale: 0.88))
        .accessibilityIdentifier(isPill ? "keyboardMicButton" : "appMicButton")
        .disabled(!isTappable)
        .onChange(of: status) { _, newStatus in
            handleStatusChange(from: previousStatus, to: newStatus)
            previousStatus = newStatus
        }
        .onAppear {
            startIdleAnimation()
        }
    }

    // MARK: - Ring Effects

    @ViewBuilder
    private var ringEffect: some View {
        switch status {
        case .idle, .ready, .failed:
            // Glass ring with soft glow pulsing 0.3-0.6 opacity over 2s
            mainShape()
                .fill(Color.clear)
                .frame(width: ringWidth, height: ringHeight)
                .dictusGlass(in: isPill ? AnyShape(Capsule()) : AnyShape(Circle()))
                .overlay(
                    mainShape()
                        .stroke(Color.dictusAccent.opacity(glowOpacity), lineWidth: 2)
                        .frame(width: ringWidth, height: ringHeight)
                )

        case .recording:
            // Red pulse ring scaling 1.0-1.3 over 0.8s
            mainShape()
                .fill(Color.clear)
                .frame(width: ringWidth, height: ringHeight)
                .dictusGlass(in: isPill ? AnyShape(Capsule()) : AnyShape(Circle()))
                .overlay(
                    mainShape()
                        .stroke(Color.dictusRecording.opacity(0.5), lineWidth: 3)
                        .frame(width: ringWidth, height: ringHeight)
                )
                .scaleEffect(pulseScale)

        case .transcribing, .requested:
            // Static glass ring during transcription
            mainShape()
                .fill(Color.clear)
                .frame(width: ringWidth, height: ringHeight)
                .dictusGlass(in: isPill ? AnyShape(Capsule()) : AnyShape(Circle()))
                .overlay(
                    mainShape()
                        .stroke(Color.dictusAccent.opacity(0.4), lineWidth: 2)
                        .frame(width: ringWidth, height: ringHeight)
                )
        }
    }

    // MARK: - Shimmer Overlay

    /// Left-to-right shimmer sweep for transcribing state.
    ///
    /// WHY a gradient mask approach:
    /// A moving gradient overlay creates the "shimmer" effect without custom drawing.
    /// The offset animation moves the bright spot across the button surface.
    private var shimmerOverlay: some View {
        mainShape()
            .fill(
                LinearGradient(
                    colors: [
                        Color.white.opacity(0),
                        Color.white.opacity(0.3),
                        Color.white.opacity(0),
                    ],
                    startPoint: UnitPoint(x: shimmerOffset - 0.3, y: 0.5),
                    endPoint: UnitPoint(x: shimmerOffset + 0.3, y: 0.5)
                )
            )
            .frame(width: buttonWidth, height: buttonHeight)
    }

    // MARK: - Helpers

    private var buttonFillColor: Color {
        switch status {
        case .recording:
            return .dictusRecording
        case .transcribing:
            return .dictusAccentHighlight.opacity(0.5)
        default:
            return .dictusAccent
        }
    }

    // MARK: - Animation Control

    private func handleStatusChange(from oldStatus: DictationStatus, to newStatus: DictationStatus) {
        // Log every status transition for diagnostics
        PersistentLog.log(.statusChanged(from: oldStatus.rawValue, to: newStatus.rawValue, source: "micButton"))

        // Reset ALL animation state to concrete values WITHOUT animation first.
        // WHY: This cancels any existing repeating animations that could stack
        // with the new ones, causing jitter or incorrect visual state.
        pulseScale = 1.0
        glowOpacity = 0.3
        shimmerOffset = -1.0

        // Success flash when transitioning from transcribing to ready.
        // WHY withAnimation instead of asyncAfter: SwiftUI animates the transition
        // from true to false over 0.3s, eliminating the timer race condition.
        if oldStatus == .transcribing && newStatus == .ready {
            showSuccessFlash = true
            withAnimation(.easeOut(duration: 0.3)) {
                showSuccessFlash = false
            }
        }

        switch newStatus {
        case .idle, .ready, .failed:
            startIdleAnimation()
        case .recording:
            startRecordingAnimation()
        case .transcribing:
            startTranscribingAnimation()
        case .requested:
            // Static state -- no animations. Button is disabled via isTappable.
            // Visual: standard accent color, no pulse, no glow animation.
            break
        }
    }

    private func startIdleAnimation() {
        pulseScale = 1.0
        withAnimation(.easeInOut(duration: 2).repeatForever(autoreverses: true)) {
            glowOpacity = 0.6
        }
    }

    private func startRecordingAnimation() {
        glowOpacity = 0.5
        withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
            pulseScale = 1.3
        }
    }

    private func startTranscribingAnimation() {
        pulseScale = 1.0
        glowOpacity = 0.4
        shimmerOffset = -1.0
        withAnimation(.linear(duration: 1.5).repeatForever(autoreverses: false)) {
            shimmerOffset = 2.0
        }
    }
}

#Preview("Circle") {
    VStack(spacing: 40) {
        AnimatedMicButton(status: .idle) {}
        AnimatedMicButton(status: .recording) {}
        AnimatedMicButton(status: .transcribing) {}
    }
    .padding()
    .background(Color(hex: 0x0A1628))
}

#Preview("Pill") {
    VStack(spacing: 40) {
        AnimatedMicButton(status: .idle, isPill: true) {}
        AnimatedMicButton(status: .recording, isPill: true) {}
        AnimatedMicButton(status: .transcribing, isPill: true) {}
    }
    .padding()
    .background(Color(hex: 0x0A1628))
}
