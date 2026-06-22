import AppKit
import CoreGraphics
@preconcurrency import ScreenCaptureKit

public struct ScreenshotDisplay: Equatable, Identifiable, Sendable {
    public let id: CGDirectDisplayID
    public let name: String
    public let frame: CGRect
    public let overlayFrame: CGRect
    public let scale: CGFloat
    public let isPrimary: Bool

    public init(
        id: CGDirectDisplayID,
        name: String,
        frame: CGRect,
        overlayFrame: CGRect? = nil,
        scale: CGFloat,
        isPrimary: Bool
    ) {
        self.id = id
        self.name = name
        self.frame = frame
        self.overlayFrame = overlayFrame ?? frame
        self.scale = scale
        self.isPrimary = isPrimary
    }

    public var pixelSize: CGSize {
        CGSize(width: frame.width * scale, height: frame.height * scale)
    }
}

public struct ScreenshotDisplayFrame: Equatable, Sendable {
    public let display: ScreenshotDisplay
    public let image: CGImage?

    public init(display: ScreenshotDisplay, image: CGImage?) {
        self.display = display
        self.image = image
    }
}

public enum ScreenCaptureFrameProviderError: Error, Equatable, LocalizedError, Sendable {
    case cancelled
    case permissionDenied
    case displayUnavailable(CGDirectDisplayID)
    case captureFailed(String)

    public var errorDescription: String? {
        switch self {
        case .cancelled:
            return "截图已取消"
        case .permissionDenied:
            return "缺少屏幕录制权限"
        case .displayUnavailable:
            return "当前显示器不可用"
        case .captureFailed(let message):
            return "截图失败：\(message)"
        }
    }
}

public final class ScreenCaptureFrameProvider: @unchecked Sendable {
    public typealias DisplayLoader = () async throws -> [ScreenshotDisplay]
    public typealias DisplayCapture = (ScreenshotDisplay, [CGWindowID]) async throws -> CGImage
    public typealias ExcludedWindowIDs = () -> [CGWindowID]

    private let displayLoader: DisplayLoader
    private let displayCapture: DisplayCapture
    private let excludedWindowIDs: ExcludedWindowIDs

    public convenience init(
        excludedWindowIDs: @escaping ExcludedWindowIDs = { [] }
    ) {
        self.init(
            displayLoader: Self.loadDisplays,
            displayCapture: Self.captureDisplayImage,
            excludedWindowIDs: excludedWindowIDs
        )
    }

    public init(
        displayLoader: @escaping DisplayLoader,
        displayCapture: @escaping DisplayCapture,
        excludedWindowIDs: @escaping ExcludedWindowIDs = { [] }
    ) {
        self.displayLoader = displayLoader
        self.displayCapture = displayCapture
        self.excludedWindowIDs = excludedWindowIDs
    }

    public func availableDisplays() async throws -> [ScreenshotDisplay] {
        do {
            return try await displayLoader()
        } catch {
            throw Self.providerError(from: error)
        }
    }

    public func captureDisplay(_ display: ScreenshotDisplay) async throws -> CGImage {
        do {
            return try await displayCapture(display, excludedWindowIDs())
        } catch {
            throw Self.providerError(from: error)
        }
    }

    public func captureDisplayFrames() async throws -> [ScreenshotDisplayFrame] {
        let displays = try await availableDisplays()
        var frames: [ScreenshotDisplayFrame] = []
        for display in displays {
            frames.append(
                ScreenshotDisplayFrame(
                    display: display,
                    image: try await captureDisplay(display)
                )
            )
        }
        return frames
    }

    private static func loadDisplays() async throws -> [ScreenshotDisplay] {
        guard CGPreflightScreenCaptureAccess() else {
            throw ScreenCaptureFrameProviderError.permissionDenied
        }

        let content = try await SCShareableContent.current
        let metadataByID = await MainActor.run {
            Dictionary(
                uniqueKeysWithValues: NSScreen.screens.compactMap { screen -> (CGDirectDisplayID, ScreenMetadata)? in
                    guard let id = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID else {
                        return nil
                    }
                    return (
                        id,
                        ScreenMetadata(
                            name: screen.localizedName,
                            overlayFrame: screen.frame,
                            scale: screen.backingScaleFactor,
                            isPrimary: CGDisplayIsMain(id) != 0
                        )
                    )
                }
            )
        }

        return content.displays.map { display in
            let metadata = metadataByID[display.displayID]
            return ScreenshotDisplay(
                id: display.displayID,
                name: metadata?.name ?? "Display \(display.displayID)",
                frame: display.frame,
                overlayFrame: metadata?.overlayFrame ?? display.frame,
                scale: metadata?.scale ?? 1,
                isPrimary: metadata?.isPrimary ?? (CGDisplayIsMain(display.displayID) != 0)
            )
        }
    }

    private static func captureDisplayImage(
        display: ScreenshotDisplay,
        excludedWindowIDs: [CGWindowID]
    ) async throws -> CGImage {
        guard CGPreflightScreenCaptureAccess() else {
            throw ScreenCaptureFrameProviderError.permissionDenied
        }

        let content = try await SCShareableContent.current
        guard let scDisplay = content.displays.first(where: { $0.displayID == display.id }) else {
            throw ScreenCaptureFrameProviderError.displayUnavailable(display.id)
        }

        let excludedWindowIDSet = Set(excludedWindowIDs)
        let excludedWindows = content.windows.filter { window in
            shouldExcludeWindow(
                windowID: window.windowID,
                owningBundleIdentifier: window.owningApplication?.bundleIdentifier,
                excludedWindowIDs: excludedWindowIDSet,
                ownBundleIdentifier: Bundle.main.bundleIdentifier
            )
        }
        let filter = SCContentFilter(display: scDisplay, excludingWindows: excludedWindows)
        let configuration = captureConfiguration(for: display)

        return try await SCScreenshotManager.captureImage(
            contentFilter: filter,
            configuration: configuration
        )
    }

    static func shouldExcludeWindow(
        windowID: CGWindowID,
        owningBundleIdentifier: String?,
        excludedWindowIDs: Set<CGWindowID>,
        ownBundleIdentifier: String?
    ) -> Bool {
        if excludedWindowIDs.contains(windowID) {
            return true
        }
        return false
    }

    static func captureConfiguration(for display: ScreenshotDisplay) -> SCStreamConfiguration {
        let configuration = SCStreamConfiguration()
        configuration.width = Int(display.frame.width * display.scale)
        configuration.height = Int(display.frame.height * display.scale)
        configuration.showsCursor = false
        configuration.scalesToFit = false
        configuration.captureResolution = .best
        return configuration
    }

    private static func providerError(from error: any Error) -> ScreenCaptureFrameProviderError {
        if let providerError = error as? ScreenCaptureFrameProviderError {
            return providerError
        }
        return .captureFailed(error.localizedDescription)
    }
}

private struct ScreenMetadata: Sendable {
    let name: String
    let overlayFrame: CGRect
    let scale: CGFloat
    let isPrimary: Bool
}
