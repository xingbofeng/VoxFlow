// DictusKeyboard/Vendored/GiellaUtils.swift
// Utility extensions vendored from giellakbd-ios Keyboard/Utility/Utils.swift
// Stripped: Sentry, DivvunSpell, RxSwift, SQLite, Bundle.top, KeyboardSettings, URLOpener
// These extensions are used by KeyboardView, KeyView, KeyOverlayView, LongPressController, Theme, etc.

import Foundation
import UIKit

// MARK: - iOS Version Detection

@MainActor
struct iOSVersion {
    static var current: OperatingSystemVersion {
        return ProcessInfo.processInfo.operatingSystemVersion
    }

    static var majorVersion: Int {
        return current.majorVersion
    }

    static var isIOS26OrNewer: Bool {
        return majorVersion >= 26
    }
}

// MARK: - UIColor Convenience

extension UIColor {
    convenience init(r: CGFloat, g: CGFloat, b: CGFloat, a: CGFloat = 1.0) {
        self.init(red: r/255.0, green: g/255.0, blue: b/255.0, alpha: a)
    }
}

public extension UIColor {
    private var components: (r: CGFloat, g: CGFloat, b: CGFloat, a: CGFloat) {
        let components = cgColor.components!
        switch components.count == 2 {
        case true: return (r: components[0], g: components[0], b: components[0], a: components[1])
        case false: return (r: components[0], g: components[1], b: components[2], a: components[3])
        }
    }

    static func interpolate(from fromColor: UIColor, to toColor: UIColor, with progress: CGFloat) -> UIColor {
        let fromComponents = fromColor.components
        let toComponents = toColor.components
        let r = (1 - progress) * fromComponents.r + progress * toComponents.r
        let g = (1 - progress) * fromComponents.g + progress * toComponents.g
        let b = (1 - progress) * fromComponents.b + progress * toComponents.b
        let a = (1 - progress) * fromComponents.a + progress * toComponents.a
        return UIColor(red: r, green: g, blue: b, alpha: a)
    }
}

// MARK: - UIView Extensions

extension UIView {
    func fill(superview other: UIView, margins: UIEdgeInsets = .zero) {
        leftAnchor.constraint(equalTo: other.leftAnchor, constant: margins.left).isActive = true
        rightAnchor.constraint(equalTo: other.rightAnchor, constant: -margins.right).isActive = true
        topAnchor.constraint(equalTo: other.topAnchor, constant: margins.top).isActive = true
        bottomAnchor.constraint(equalTo: other.bottomAnchor, constant: -margins.bottom).isActive = true
    }

    func centerIn(superview other: UIView) {
        centerXAnchor.constraint(equalTo: other.centerXAnchor).isActive = true
        centerYAnchor.constraint(equalTo: other.centerYAnchor).isActive = true
    }

    var shouldUseiPadLayout: Bool {
        return DeviceContext.current.shouldUseIPadLayout(traitCollection: self.traitCollection)
    }
}

// MARK: - NSLayoutConstraint Extension

extension NSLayoutConstraint {
    @discardableResult
    func enable(priority: UILayoutPriority? = nil) -> NSLayoutConstraint {
        if let priority = priority {
            self.priority = priority
        }
        self.isActive = true
        return self
    }
}

// MARK: - UIScreen Extension

extension UIScreen {
    var isDeviceLandscape: Bool {
        let size = self.bounds.size
        return size.width > size.height
    }
}
