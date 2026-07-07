// DictusCore/Sources/DictusCore/Design/ProcessingAnimation.swift
// Branded processing/transcribing animation using logo-inspired pulsing bars.
import SwiftUI

/// Animated processing indicator using brand colors.
///
/// WHY not a standard ProgressView spinner:
/// The default iOS spinner feels generic. This uses 3 bars (echoing the logo)
/// that pulse sequentially with the brand blue gradient, creating a branded
/// "thinking" animation that fits the Dictus identity.
public struct ProcessingAnimation: View {
    @State private var phase: CGFloat = 0

    /// Overall height of the animation.
    public var height: CGFloat = 48

    @ScaledMetric private var barWidth: CGFloat = 8

    public init(height: CGFloat = 48) {
        self.height = height
    }

    public var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<3, id: \.self) { index in
                let delay = Double(index) * 0.2
                let scale = pulseScale(for: delay)

                RoundedRectangle(cornerRadius: barWidth / 2)
                    .fill(
                        LinearGradient(
                            colors: [.dictusGradientStart, .dictusGradientEnd],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: barWidth, height: height * scale)
                    .opacity(0.5 + scale * 0.5)
            }
        }
        .frame(height: height)
        .onAppear {
            withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                phase = 1
            }
        }
    }

    /// Compute a pulse scale for a given delay offset.
    private func pulseScale(for delay: Double) -> CGFloat {
        // Each bar pulses between 0.4 and 1.0 with staggered timing
        let adjustedPhase = (phase + CGFloat(delay)).truncatingRemainder(dividingBy: 1.4)
        return 0.4 + 0.6 * abs(sin(adjustedPhase * .pi))
    }
}
