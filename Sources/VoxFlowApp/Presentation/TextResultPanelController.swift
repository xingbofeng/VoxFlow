import AppKit
import SwiftUI

enum TextResultPanelPlacement {
    case rightSideCentered
    case bottomTrailing(
        bottomMargin: CGFloat,
        trailingMargin: CGFloat = 28,
        visualOutset: CGFloat = 0
    )
}

@MainActor
final class TextResultPanelController {
    private let title: String
    private var window: TextResultPanel?

    init(title: String) {
        self.title = title
    }

    func present<Content: View>(
        rootView: Content,
        contentSize: NSSize = NSSize(width: 440, height: 560),
        placement: TextResultPanelPlacement = .rightSideCentered,
        accessoryView: NSView? = nil,
        onCancel: @escaping () -> Void,
        onInteraction: (@MainActor () -> Void)? = nil
    ) {
        if window == nil {
            window = makeWindow(contentRect: CGRect(origin: .zero, size: contentSize))
        }
        guard let window else { return }
        window.onCancel = onCancel
        window.onInteraction = onInteraction
        window.contentView = makeContentView(rootView: rootView, accessoryView: accessoryView)
        resize(window, to: contentSize)
        position(window, placement: placement)
        window.orderFrontRegardless()
        window.makeKey()
        keepVisible(window)
    }

    func close() {
        window?.close()
        window = nil
    }

    private func makeWindow(contentRect: CGRect) -> TextResultPanel {
        let panel = TextResultPanel(
            contentRect: contentRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.title = title
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [
            .moveToActiveSpace,
            .fullScreenAuxiliary,
            .transient,
            .ignoresCycle
        ]
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.isMovableByWindowBackground = true
        panel.sharingType = .readOnly
        panel.hidesOnDeactivate = false
        panel.worksWhenModal = true
        return panel
    }

    private func makeContentView<Content: View>(
        rootView: Content,
        accessoryView: NSView?
    ) -> NSView {
        let container = NSView()
        let contentHost = NSHostingView(rootView: rootView)
        contentHost.translatesAutoresizingMaskIntoConstraints = false

        if let accessoryView {
            accessoryView.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(accessoryView)
            NSLayoutConstraint.activate([
                accessoryView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
                accessoryView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
                accessoryView.topAnchor.constraint(equalTo: container.topAnchor),
                accessoryView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            ])
        }

        container.addSubview(contentHost)
        NSLayoutConstraint.activate([
            contentHost.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            contentHost.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            contentHost.topAnchor.constraint(equalTo: container.topAnchor),
            contentHost.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
        return container
    }

    private func resize(_ window: NSWindow, to contentSize: NSSize) {
        window.setFrame(
            NSRect(origin: window.frame.origin, size: contentSize),
            display: window.isVisible,
            animate: false
        )
    }

    private func position(_ window: NSWindow, placement: TextResultPanelPlacement) {
        let screenFrame = activeScreenFrame()
        let frame: NSRect
        switch placement {
        case .rightSideCentered:
            frame = WindowPlacementPolicy.rightSideCenteredFrame(
                windowSize: window.frame.size,
                visibleFrame: screenFrame,
                trailingMargin: 28
            )
        case let .bottomTrailing(bottomMargin, trailingMargin, visualOutset):
            frame = WindowPlacementPolicy.bottomTrailingFrame(
                windowSize: window.frame.size,
                visibleFrame: screenFrame,
                trailingMargin: trailingMargin,
                bottomMargin: bottomMargin,
                visualOutset: visualOutset
            )
        }
        window.setFrame(frame, display: window.isVisible, animate: false)
    }

    private func keepVisible(_ window: NSWindow) {
        let screens = NSScreen.screens
        let visibleFrames = screens.map(\.visibleFrame)
        let fullyVisible = WindowPlacementPolicy.isFullyVisible(window.frame, in: visibleFrames)
        guard !fullyVisible else {
            return
        }
        let visibleFrame = WindowPlacementPolicy.visibleFrame(
            containing: window.frame,
            screenFrames: screens.map(\.frame),
            visibleFrames: visibleFrames
        ) ?? activeScreenFrame()
        let targetFrame = WindowPlacementPolicy.clampedFrame(window.frame, visibleFrame: visibleFrame)
        window.setFrame(
            targetFrame,
            display: window.isVisible,
            animate: false
        )
    }

    private func activeScreenFrame() -> CGRect {
        let mouseLocation = NSEvent.mouseLocation
        let screens = NSScreen.screens
        if let selectedIndex = screens.firstIndex(where: { $0.frame.contains(mouseLocation) }) {
            return screens[selectedIndex].visibleFrame
        }
        if let main = NSScreen.main {
            return main.visibleFrame
        }
        return NSScreen.main?.visibleFrame ?? CGRect(x: 0, y: 0, width: 440, height: 560)
    }
}

final class TextResultPanel: NSPanel {
    var onCancel: (() -> Void)?
    var onInteraction: (@MainActor () -> Void)?

    override var canBecomeKey: Bool {
        true
    }

    override var canBecomeMain: Bool {
        false
    }

    override func cancelOperation(_ sender: Any?) {
        onCancel?()
    }

    override func keyDown(with event: NSEvent) {
        if UInt32(event.keyCode) == 53 {
            onCancel?()
        } else {
            super.keyDown(with: event)
        }
    }

    override func sendEvent(_ event: NSEvent) {
        if event.isTextResultPanelInteraction {
            MainActor.assumeIsolated {
                onInteraction?()
            }
        }
        super.sendEvent(event)
    }
}

private extension NSEvent {
    var isTextResultPanelInteraction: Bool {
        switch type {
        case .leftMouseDown,
             .rightMouseDown,
             .otherMouseDown,
             .leftMouseDragged,
             .rightMouseDragged,
             .otherMouseDragged,
             .scrollWheel,
             .keyDown:
            return true
        default:
            return false
        }
    }
}
