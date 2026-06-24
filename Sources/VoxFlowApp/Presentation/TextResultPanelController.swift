import AppKit
import SwiftUI

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
        bottomMargin: CGFloat = 36,
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
        window.setContentSize(contentSize)
        window.contentView = makeContentView(rootView: rootView, accessoryView: accessoryView)
        position(window, bottomMargin: bottomMargin)
        if accessoryView != nil {
            NSApp.activate(ignoringOtherApps: true)
        }
        window.orderFrontRegardless()
        window.makeKey()
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

    private func position(_ window: NSWindow, bottomMargin: CGFloat) {
        let screenFrame = activeScreenFrame()
        window.setFrame(
            WindowPlacementPolicy.bottomTrailingFrame(
                windowSize: window.frame.size,
                visibleFrame: screenFrame,
                trailingMargin: 28,
                bottomMargin: bottomMargin
            ),
            display: window.isVisible,
            animate: false
        )
    }

    private func activeScreenFrame() -> CGRect {
        let mouseLocation = NSEvent.mouseLocation
        if let screen = NSScreen.screens.first(where: { $0.frame.contains(mouseLocation) }) {
            return screen.visibleFrame
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
