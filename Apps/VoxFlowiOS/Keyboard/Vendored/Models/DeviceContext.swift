// DictusKeyboard/Vendored/Models/DeviceContext.swift
// Vendored from giellakbd-ios Keyboard/Models/DeviceContext.swift

import UIKit

/// Centralized source of truth for device type, size, and orientation detection
@MainActor
struct DeviceContext {
    let userInterfaceIdiom: UIUserInterfaceIdiom
    let isLandscape: Bool
    let screenSize: CGSize
    let nativeScale: CGFloat

    // MARK: - Device Property Accessors

    var isPad: Bool { userInterfaceIdiom == .pad }
    var isPhone: Bool { userInterfaceIdiom == .phone }
    var hasSensorHousing: Bool {
        isPhone && max(screenSize.width, screenSize.height) >= 812
    }

    var screenInches: CGFloat {
        let points = screenSize
        let longSide = max(points.width, points.height)
        let shortSide = min(points.width, points.height)

        if isPad {
            switch longSide {
            case ..<1130: return 8.3
            case ..<1190: return 10.2
            case ..<1210: return 10.5
            case ..<1370: return 11.0
            default: return 12.9
            }
        }

        guard isPhone else { return 13.0 }
        switch (longSide, shortSide) {
        case (..<670, _): return 4.7
        case (..<750, _): return 5.4
        case (..<820, _): return 5.8
        case (..<860, _): return 6.1
        case (..<875, _): return 6.3
        case (..<920, _): return 6.7
        default: return 6.9
        }
    }

    // MARK: - iPad Size Categories

    var isMiniIPad: Bool {
        isPad && screenInches < 9
    }

    var isMediumIPad: Bool {
        isPad && !isMiniIPad && !isLargeIPad
    }

    var isLargeIPad: Bool {
        isPad && screenInches >= 12
    }

    // MARK: - Orientation-Specific iPad Categories

    var isLargeLandscape: Bool {
        isLargeIPad && isLandscape
    }

    var isSmallOrMediumLandscape: Bool {
        (isMiniIPad || isMediumIPad) && isLandscape
    }

    // MARK: - Trait Collection Helpers

    func shouldUseIPadLayout(traitCollection: UITraitCollection) -> Bool {
        isPad && traitCollection.userInterfaceIdiom == .pad
    }

    func isIPhoneAppRunningOnIPad(traitCollection: UITraitCollection) -> Bool {
        isPad && traitCollection.userInterfaceIdiom == .phone
    }

    // MARK: - Factory

    static var current: DeviceContext {
        let screen = UIScreen.main
        return DeviceContext(
            userInterfaceIdiom: UIDevice.current.userInterfaceIdiom,
            isLandscape: screen.isDeviceLandscape,
            screenSize: screen.bounds.size,
            nativeScale: screen.nativeScale
        )
    }
}
