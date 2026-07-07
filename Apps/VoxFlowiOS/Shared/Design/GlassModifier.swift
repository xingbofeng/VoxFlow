// DictusCore/Sources/DictusCore/Design/GlassModifier.swift
// Reusable glass effect modifier supporting iOS 26 Liquid Glass with graceful fallback.
import SwiftUI

/// Applies glass effect: `.glassEffect()` on iOS 26+, `.regularMaterial` on iOS 16-25.
///
/// WHY a custom modifier instead of applying material directly:
/// Centralizes the iOS version check. Every surface that should look "glassy" calls
/// `.dictusGlass()` and automatically gets the best available effect for the device.
/// When iOS 26 ships, all surfaces upgrade to Liquid Glass without any code changes.
public struct GlassModifier<S: Shape>: ViewModifier {
    public let shape: S

    public init(shape: S) {
        self.shape = shape
    }

    public func body(content: Content) -> some View {
        // Phase 1: always use regularMaterial. The iOS 26+ Liquid Glass `.glassEffect`
        // API is not available in the current SDK; revisit when building with iOS 26 SDK.
        content
            .background(shape.fill(.regularMaterial))
    }
}

/// Button style mimicking iOS Liquid Glass press interaction.
///
/// WHY a custom ButtonStyle:
/// iOS 26 Liquid Glass elements have a characteristic press animation — a subtle
/// scale-down on touch with a spring bounce on release. This style replicates that
/// feel for all interactive glass elements (buttons, cards, close icons).
public struct GlassPressStyle: ButtonStyle {
    /// Scale when finger is down. 0.92 = subtle, not cartoonish.
    private let pressedScale: CGFloat

    public init(pressedScale: CGFloat = 0.92) {
        self.pressedScale = pressedScale
    }

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? pressedScale : 1.0)
            .opacity(configuration.isPressed ? 0.85 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

/// Convenience View extension for applying glass effects.
public extension View {
    /// Apply glass effect with a custom shape (default: rounded rectangle with 16pt corners).
    ///
    /// - Parameter shape: The shape to use for the glass effect clipping.
    /// - Returns: View with glass effect applied.
    func dictusGlass<S: Shape>(in shape: S = RoundedRectangle(cornerRadius: 16)) -> some View {
        modifier(GlassModifier(shape: shape))
    }

    /// Apply glass effect optimized for toolbar/navigation bar surfaces.
    /// Uses Capsule shape for a pill-shaped glass background.
    func dictusGlassBar() -> some View {
        modifier(GlassModifier(shape: Capsule()))
    }
}
