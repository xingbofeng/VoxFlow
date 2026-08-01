// DictusApp/Views/SwipeBackOverlayView.swift
// Full-screen overlay teaching the swipe-back gesture during cold start dictation.
import SwiftUI
import Shared

/// Full-screen overlay shown when the app is opened from the keyboard during cold start.
///
/// WHY Wispr Flow-style redesign (Phase 26):
/// A real user tester did not know the iOS swipe-back gesture existed. The overlay must
/// TEACH the gesture visually with an iPhone mockup, animated waveform, and a hand
/// showing the swipe direction — not just mention it in words.
///
/// WHY no parameters:
/// MainTabView calls `SwipeBackOverlayView()` with no arguments. Recording happens in
/// DictationCoordinator — this view is purely visual.
struct SwipeBackOverlayView: View {
    @State private var isWaveformAnimating = false
    @State private var swipeProgress: CGFloat = 0

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(hex: 0x0D2040), Color(hex: 0x071020)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                Text(L10n.t("cold_start.title"))
                    .font(.title2.weight(.semibold))
                    .foregroundColor(.white)
                    .padding(.top, 60)

                Spacer()

                // iPhone mockup with BrandWaveform-style bars
                ZStack(alignment: .bottom) {
                    IPhoneMockupView(isAnimating: isWaveformAnimating)
                        .frame(width: 180, height: 390)

                    // Glowing blue dot + chevron trail on the bottom edge of the phone
                    // Straddles the outline — half inside, half outside
                    // Slides left→right in sync with the hand to show WHERE to swipe
                    ZStack {
                        // Chevron trail behind the blue dot
                        ForEach(0..<3, id: \.self) { i in
                            Image(systemName: "chevron.right")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundColor(
                                    Color.dictusAccent.opacity(
                                        (0.5 - Double(i) * 0.15) * Double(swipeProgress)
                                    )
                                )
                                .offset(x: -CGFloat(10 + i * 10))
                        }

                        Circle()
                            .fill(Color.dictusAccent)
                            .frame(width: 14, height: 14)
                            .shadow(color: Color.dictusAccent.opacity(0.7), radius: 10)
                            .shadow(color: Color.dictusAccent.opacity(0.4), radius: 20)
                    }
                    .offset(
                        x: -30 + swipeProgress * 80,
                        y: 7 // half below the phone outline
                    )
                }

                // Swipe hand gesture below the phone mockup (no chevrons — they're on the dot now)
                SwipeHandView(progress: swipeProgress)
                    .frame(width: 140, height: 48)
                    .padding(.top, 2)

                // Empathetic explanation — short key to avoid Xcode xcstrings duplicate bug
                Text(L10n.t("cold_start.subtitle"))
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.7))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
                    .padding(.top, 16)

                Spacer()

                // Bottom instruction
                Text(L10n.t("cold_start.instruction"))
                    .font(.callout.weight(.medium))
                    .foregroundColor(.dictusAccent)
                    .multilineTextAlignment(.center)
                    .padding(.bottom, 40)
            }
        }
        .onAppear {
            withAnimation(
                .easeInOut(duration: 0.7)
                .repeatForever(autoreverses: true)
            ) {
                isWaveformAnimating = true
            }
            startSwipeLoop()
        }
    }

    /// Repeating hand swipe animation with pause between cycles.
    ///
    /// WHY Timer-based instead of .repeatForever:
    /// .repeatForever(autoreverses: false) causes an instant jump-back that looks jarring.
    /// A Timer lets us: animate forward (1.2s) → pause (0.8s) → reset → repeat.
    private func startSwipeLoop() {
        animateSwipeForward()
        Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { _ in
            DispatchQueue.main.async {
                animateSwipeForward()
            }
        }
    }

    /// WHY timingCurve(0.4, 0, 0.2, 1):
    /// Material Design "emphasized" easing — slow start, acceleration through the middle,
    /// gentle deceleration at the end. Feels like a natural human swipe gesture rather
    /// than mechanical linear motion.
    private func animateSwipeForward() {
        swipeProgress = 0
        withAnimation(.timingCurve(0.4, 0, 0.2, 1, duration: 1.2)) {
            swipeProgress = 1
        }
    }
}

// MARK: - Swipe Hand View

/// Animated hand icon sliding right to teach the swipe-back gesture.
///
/// WHY hand.point.up instead of a circle:
/// User testing showed that a blue circle didn't communicate "swipe gesture" clearly.
/// A pointing finger is universally understood as "touch here and drag".
private struct SwipeHandView: View {
    var progress: CGFloat

    var body: some View {
        // Hand icon only — chevrons are now on the blue dot above
        Image(systemName: "hand.point.up")
            .font(.system(size: 28, weight: .light))
            .foregroundColor(.white.opacity(0.85))
            .offset(x: -30 + progress * 80)
            .opacity(1.0 - progress * 0.3)
    }
}

// MARK: - iPhone Mockup View

/// iPhone mockup with BrandWaveform-style animated bars and home indicator.
///
/// WHY 17 bars with brand color scheme:
/// Matches the real BrandWaveform visual identity — blue gradient center bars,
/// white opacity edge bars. 17 bars fit the 140pt mockup width cleanly.
///
/// WHY fixed-height waveform container:
/// The bars animate height changes. Without a fixed container, the VStack would
/// recalculate layout on each frame, causing the "Listening..." text below to bounce.
/// A fixed 60pt frame contains the animation within its bounds.
private struct IPhoneMockupView: View {
    var isAnimating: Bool

    // 17 bars — symmetric: outer white → inner blue gradient → outer white
    private let barHeightsIdle: [CGFloat] = [
        6, 10, 5, 12, 8, 16, 22, 14, 28, 14, 22, 16, 8, 12, 5, 10, 6
    ]
    private let barHeightsActive: [CGFloat] = [
        12, 18, 10, 22, 16, 30, 40, 24, 46, 24, 38, 28, 14, 20, 8, 16, 10
    ]

    /// Bar colors matching BrandWaveform: gradient blue center, white opacity edges.
    private func barColor(at index: Int) -> Color {
        let center: CGFloat = 8
        let distance = abs(CGFloat(index) - center) / center

        if distance < 0.35 {
            return .dictusGradientStart
        } else if distance < 0.55 {
            return .dictusAccent
        } else {
            let opacity = (1.0 - distance) * 0.7 + 0.2
            return .white.opacity(opacity)
        }
    }

    var body: some View {
        ZStack {
            // Device outline
            RoundedRectangle(cornerRadius: 36, style: .continuous)
                .stroke(Color.white.opacity(0.3), lineWidth: 2.5)

            VStack(spacing: 0) {
                // Dynamic Island — tight to top edge like a real iPhone
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.white.opacity(0.25))
                    .frame(width: 58, height: 16)
                    .padding(.top, 14)

                Spacer()

                // BrandWaveform-style bars in a FIXED height container
                // so the text below doesn't bounce when bars animate
                HStack(spacing: 2) {
                    ForEach(0..<17, id: \.self) { i in
                        RoundedRectangle(cornerRadius: 1.5)
                            .fill(barColor(at: i))
                            .frame(
                                width: 3,
                                height: isAnimating
                                    ? barHeightsActive[i]
                                    : barHeightsIdle[i]
                            )
                    }
                }
                .frame(height: 50) // Fixed container — bars animate within
                .animation(
                    .easeInOut(duration: 0.7).repeatForever(autoreverses: true),
                    value: isAnimating
                )

                // Listening label — FIXED position below the waveform container
                Text(L10n.t("cold_start.listening"))
                    .font(.caption2)
                    .foregroundColor(.white.opacity(0.6))
                    .padding(.top, 10)

                Spacer()

                // Home indicator bar
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color.white.opacity(0.4))
                    .frame(width: 60, height: 5)
                    .padding(.bottom, 16)
            }
        }
    }
}

// MARK: - Previews

#Preview {
    SwipeBackOverlayView()
}
