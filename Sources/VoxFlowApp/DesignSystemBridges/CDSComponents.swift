import SwiftUI

// MARK: - Ghost button

/// CDS interactive states: transparent by default, 5% neutral on hover,
/// 8% neutral plus a hairline ring when selected. No shadows, no accent fill.
struct CDSGhostButtonStyle: ButtonStyle {
    var cornerRadius: CGFloat = CDS.Radius.lg
    var isSelected: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(fillColor(pressed: configuration.isPressed))
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(isSelected ? CDS.Stroke.hairline : .clear, lineWidth: 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }

    private func fillColor(pressed: Bool) -> Color {
        if isSelected { return CDS.Fill.ghostSelected }
        return pressed ? CDS.Fill.secondaryHover : .clear
    }
}

// MARK: - Segmented control

/// Pill segmented control: 999px track, 2px inset thumb, spring driven.
/// Replaces the native macOS segmented picker, which ignores the app tint.
struct CDSSegmentedControl<Item: Hashable>: View {
    @Binding var selection: Item
    let items: [Item]
    let title: (Item) -> String
    var isDisabled: (Item) -> Bool = { _ in false }
    var isEqualWidth: Bool = true
    var height: CGFloat = 26

    var body: some View {
        HStack(spacing: 0) {
            ForEach(items, id: \.self) { item in
                let selected = item == selection
                let disabled = isDisabled(item)
                Button {
                    guard !disabled, !selected else { return }
                    withAnimation(CDS.Spring.bouncy) { selection = item }
                } label: {
                    Text(title(item))
                        .font(.system(size: 12, weight: selected ? .medium : .regular))
                        .lineLimit(1)
                        .foregroundStyle(
                            selected
                                ? AppTheme.ColorToken.primaryText
                                : (disabled
                                   ? AppTheme.ColorToken.secondaryText.opacity(0.4)
                                   : AppTheme.ColorToken.secondaryText)
                        )
                        .padding(.horizontal, 10)
                        .frame(maxWidth: isEqualWidth ? .infinity : nil)
                        .frame(height: height)
                        .background {
                            if selected {
                                RoundedRectangle(cornerRadius: CDS.Radius.pill, style: .continuous)
                                    .fill(CDS.Surface.segmentThumb)
                                    .shadow(color: .black.opacity(0.06), radius: 1, y: 1)
                            }
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(disabled)
            }
        }
        .padding(2)
        .background(Capsule(style: .continuous).fill(CDS.Surface.segmentTrack))
    }
}
// MARK: - Scroll fade mask

extension View {
    /// Seven-stop non-linear edge fade, approximating CDS `mask-image` stops.
    /// Applied to scroll content so the top and bottom dissolve instead of
    /// cutting off with a hard edge (which bands on Retina displays).
    func scrollFadeMask(axis: Axis = .vertical, size: CGFloat = CDS.scrollFadeSize) -> some View {
        mask(GradientEdgeFadeMask(axis: axis, size: size))
    }
}

private struct GradientEdgeFadeMask: View {
    let axis: Axis
    let size: CGFloat

    var body: some View {
        // Canvas never participates in layout sizing, which keeps the mask
        // from widening its host (a multi-child VStack would).
        Canvas { context, canvasSize in
            context.fill(
                Path(CGRect(origin: .zero, size: canvasSize)),
                with: .color(.black)
            )
            drawBand(in: &context, canvasSize: canvasSize, reversed: false)
            drawBand(in: &context, canvasSize: canvasSize, reversed: true)
        }
        .allowsHitTesting(false)
    }

    /// Seven discrete stops from a transparent edge to an opaque interior,
    /// following the CDS `mask-image` alpha ladder.
    private func drawBand(in context: inout GraphicsContext, canvasSize: CGSize, reversed: Bool) {
        let extent = axis == .vertical ? canvasSize.height : canvasSize.width
        let length = min(size, extent / 2)
        guard length > 0 else { return }

        for index in CDS.scrollFadeStops.indices {
            let rank = reversed ? CDS.scrollFadeStops.count - 1 - index : index
            let stop = CDS.scrollFadeStops[rank]
            let start = offset(for: rank, length: length)
            let end = offset(for: rank + 1 <= CDS.scrollFadeStops.count - 1 ? rank + 1 : rank, length: length)
            let span = max(end - start, 0.5)
            let rect = reversed
                ? bandRect(fromEnd: canvasSize, start: start, span: span)
                : bandRect(fromStart: canvasSize, start: start, span: span)
            context.blendMode = .destinationIn
            context.opacity = 1 - stop.alpha
            context.fill(Path(rect), with: .color(.black))
        }
    }

    private func bandRect(fromStart canvasSize: CGSize, start: CGFloat, span: CGFloat) -> CGRect {
        axis == .vertical
            ? CGRect(x: 0, y: start, width: canvasSize.width, height: span)
            : CGRect(x: start, y: 0, width: span, height: canvasSize.height)
    }

    private func bandRect(fromEnd canvasSize: CGSize, start: CGFloat, span: CGFloat) -> CGRect {
        axis == .vertical
            ? CGRect(x: 0, y: canvasSize.height - start - span, width: canvasSize.width, height: span)
            : CGRect(x: canvasSize.width - start - span, y: 0, width: span, height: canvasSize.height)
    }

    private func offset(for index: Int, length: CGFloat) -> CGFloat {
        index <= 0 ? 0 : length * CGFloat(CDS.scrollFadeStops[min(index, CDS.scrollFadeStops.count - 1)].location)
    }
}

// MARK: - Surfaces

extension View {
    /// Card surface (Surface 2 + hairline ring), used for stat and list cards.
    func cdsCard(cornerRadius: CGFloat = CDS.Radius.xl) -> some View {
        background(AppTheme.ColorToken.panelBackground)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(AppTheme.ColorToken.panelStroke, lineWidth: 1)
            )
    }

    /// Inset row inside a card: secondary fill, no border (single-stroke discipline).
    func cdsInsetRow(cornerRadius: CGFloat = CDS.Radius.panel) -> some View {
        background(AppTheme.ColorToken.controlBackground)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}

// MARK: - Clay status dot

/// Breathing clay indicator (2.4s cycle) used for live/recording states.
struct CDSClayDot: View {
    var size: CGFloat = 8
    var isAnimating: Bool = true
    @State private var phase = false

    var body: some View {
        Circle()
            .fill(AppTheme.ColorToken.accent)
            .frame(width: size, height: size)
            .scaleEffect(phase && isAnimating ? 1.18 : 1.0)
            .opacity(phase && isAnimating ? 1.0 : 0.65)
            .animation(
                isAnimating
                    ? CDS.Easing.pulse.repeatForever(autoreverses: true)
                    : .default,
                value: phase
            )
            .onAppear { phase = true }
    }
}
