import SwiftUI

/// CDS switch: clay track when on, hairline ring, spring thumb.
/// The label is laid out by the caller, so this style renders only the track
/// and drops the system label to avoid duplicating row content.
struct CDSToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button {
            withAnimation(CDS.Spring.bouncy) { configuration.isOn.toggle() }
        } label: {
            track(isOn: configuration.isOn)
        }
        .buttonStyle(.plain)
        .accessibilityElement()
        .accessibilityAddTraits(configuration.isOn ? [.isButton, .isSelected] : .isButton)
        .labelsHidden()
        .overlay(configuration.label.opacity(0).frame(width: 0, height: 0))
    }

    private func track(isOn: Bool) -> some View {
        Capsule(style: .continuous)
            .fill(isOn ? AppTheme.ColorToken.accent : CDS.Surface.segmentTrack)
            .overlay(
                Capsule(style: .continuous)
                    .strokeBorder(
                        isOn ? AppTheme.ColorToken.accentHover.opacity(0.5) : CDS.Stroke.hairline,
                        lineWidth: 1
                    )
            )
            .overlay(alignment: isOn ? .trailing : .leading) {
                Circle()
                    .fill(Color.white)
                    .shadow(color: .black.opacity(0.14), radius: 1.5, y: 1)
                    .padding(2)
                    .frame(width: 22, height: 22)
            }
            .frame(width: 40, height: 24)
            .contentShape(Capsule(style: .continuous))
    }
}

extension ToggleStyle where Self == CDSToggleStyle {
    static var cds: CDSToggleStyle { CDSToggleStyle() }
}

extension View {
    /// Applies the CDS switch style (clay track, brand-consistent).
    func cdsToggle() -> some View {
        toggleStyle(CDSToggleStyle())
    }
}
