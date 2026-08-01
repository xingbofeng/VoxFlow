// DictusKeyboard/Vendored/Models/KeyboardHeightProvider.swift
// Vendored from giellakbd-ios Keyboard/Models/KeyboardHeightProvider.swift
// Stripped: import Sentry, SentrySDK.capture calls

import UIKit
import Shared

typealias KeyboardHeight = (portrait: CGFloat, landscape: CGFloat)

@MainActor
struct KeyboardHeightProvider {
    // Issue #116 diagnostic: static-let evaluates once. If first access lands during
    // an app-switch transition when UIScreen.main.bounds is transient, the cached
    // value sticks for the rest of the process lifetime. Log on first evaluation.
    private static let portraitDeviceHeight: CGFloat = {
        let size = UIScreen.main.bounds.size
        let value = max(size.height, size.width)
        PersistentLog.log(.diagnosticProbe(
            component: "KeyboardHeightProvider",
            instanceID: "",
            action: "portraitCache_eval",
            details: "screen=\(Int(size.width))x\(Int(size.height)) cached=\(value)"
        ))
        return value
    }()

    private static let landscapeDeviceHeight: CGFloat = {
        let size = UIScreen.main.bounds.size
        let value = min(size.height, size.width)
        PersistentLog.log(.diagnosticProbe(
            component: "KeyboardHeightProvider",
            instanceID: "",
            action: "landscapeCache_eval",
            details: "screen=\(Int(size.width))x\(Int(size.height)) cached=\(value)"
        ))
        return value
    }()

    /// Returns keyboard height for a given device and orientation, optionally adjusted for custom row counts
    static func height(
        for deviceContext: DeviceContext,
        traitCollection: UITraitCollection,
        rowCount: Int? = nil
    ) -> CGFloat {
        let heights = heights(for: deviceContext, traitCollection: traitCollection)
        let isLandscape = deviceContext.isLandscape
        let baseHeight = isLandscape ? heights.landscape : heights.portrait

        guard let rowCount = rowCount else {
            return baseHeight
        }

        let normalRowCount: CGFloat = deviceContext.isLargeIPad ? 5.0 : 4.0
        let rowHeight = baseHeight / normalRowCount
        var adjustedHeight = rowHeight * CGFloat(rowCount)

        if !deviceContext.isLargeIPad, rowCount > 4, isLandscape {
            adjustedHeight -= 40
        }

        return adjustedHeight
    }

    private static func heights(for deviceContext: DeviceContext, traitCollection: UITraitCollection) -> KeyboardHeight {
        if deviceContext.isIPhoneAppRunningOnIPad(traitCollection: traitCollection) {
            let portrait: CGFloat = deviceContext.isLargeIPad ? 328 : 258
            let landscape = portrait - 56
            return (portrait: portrait, landscape: landscape)
        }

        if let override = deviceOverride(for: deviceContext) {
            return override
        }

        if let height = height(forDiagonal: Double(deviceContext.screenInches)) {
            return height
        }

        return fallbackHeight(for: deviceContext)
    }

    private static func deviceOverride(for deviceContext: DeviceContext) -> KeyboardHeight? {
        if !deviceContext.isPad, Double(deviceContext.screenInches) == 6.5 {
            return (portrait: 272, landscape: 196)
        }
        return nil
    }

    private static func height(forDiagonal diagonal: Double) -> KeyboardHeight? {
        if let screenSize = ScreenSize(diagonal: diagonal) {
            return heightForScreenSize(screenSize)
        }

        if let nearest = nearestScreenSize(to: diagonal) {
            return heightForScreenSize(nearest)
        }

        return nil
    }

    private static func nearestScreenSize(to diagonal: Double, maxDistance: Double = 0.2) -> ScreenSize? {
        // Stripped: SentrySDK.capture call for unrecognized screen sizes

        guard let nearest = ScreenSize.allCases.min(by: { size1, size2 in
            let distance1 = abs(size1.rawValue - diagonal)
            let distance2 = abs(size2.rawValue - diagonal)
            return distance1 < distance2
        }) else {
            return nil
        }

        let distance = abs(nearest.rawValue - diagonal)
        guard distance <= maxDistance else {
            return nil
        }

        return nearest
    }

    private static func heightForScreenSize(_ screenSize: ScreenSize) -> KeyboardHeight {
        // Heights tuned to match Apple's native iOS keyboard row height (~42-44pt per row).
        // Original giellakbd-ios values were 262-272pt (Sami keyboards with larger keys).
        // Apple keyboard is ~216pt on 6.1" devices, ~226pt on 6.7" devices.
        switch screenSize {
        case .size4_7:
            return (portrait: 216, landscape: 175)
        case .size5_4:
            return (portrait: 216, landscape: 170)
        case .size5_5:
            return (portrait: 216, landscape: 175)
        case .size5_8:
            return (portrait: 216, landscape: 170)
        case .size6_1, .size6_3, .size6_5:
            return (portrait: 216, landscape: 175)
        case .size6_7, .size6_9:
            // Empirical measurement vs Apple system keyboard on iPhone 15 Pro Max
            // (issue #117): Apple visible row height = 45pt. With keyVerticalMargin
            // 5.5pt × 2 = 11pt cell padding, target cell = 56pt → grid = 224pt.
            return (portrait: 224, landscape: 175)
        case .size7_9, .size8_3, .size9_7, .size10_2, .size10_5, .size11_0:
            return (portrait: 318, landscape: 404)
        case .size10_9:
            return (portrait: 314, landscape: 398)
        case .size12_9, .size13_0:
            return (portrait: 384, landscape: 476)
        }
    }

    private static func fallbackHeight(for deviceContext: DeviceContext) -> KeyboardHeight {
        if deviceContext.isPad {
            let landscape = landscapeDeviceHeight / 2.0 - 70
            return (portrait: 384, landscape: landscape)
        } else if deviceContext.isPhone {
            return (portrait: 216, landscape: 175)
        } else {
            let portraitHeight = portraitDeviceHeight / 3.0
            let landscapeHeight = portraitHeight - 56
            return (portrait: portraitHeight, landscape: landscapeHeight)
        }
    }
}

@MainActor
enum ScreenSize: Double, CaseIterable {
    case size4_7 = 4.7
    case size5_4 = 5.4
    case size5_5 = 5.5
    case size5_8 = 5.8
    case size6_1 = 6.1
    case size6_3 = 6.3
    case size6_5 = 6.5
    case size6_7 = 6.7
    case size6_9 = 6.9
    case size7_9 = 7.9
    case size8_3 = 8.3
    case size9_7 = 9.7
    case size10_2 = 10.2
    case size10_5 = 10.5
    case size10_9 = 10.9
    case size11_0 = 11.0
    case size12_9 = 12.9
    case size13_0 = 13.0

    init?(diagonal: Double) {
        self.init(rawValue: diagonal)
    }
}
