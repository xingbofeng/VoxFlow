import ApplicationServices
import CoreGraphics

@MainActor
public protocol SimulatedTypingEventPosting: AnyObject {
    func post(_ text: String) -> Bool
}

@MainActor
public final class CoreGraphicsTypingEventPoster: SimulatedTypingEventPosting {
    private let makeKeyDownEvent: () -> CGEvent?
    private let postEvent: (CGEvent) -> Void

    public convenience init() {
        self.init(
            makeKeyDownEvent: {
                let source = CGEventSource(stateID: .hidSystemState)
                let keyDown = CGEvent(
                    keyboardEventSource: source,
                    virtualKey: 0,
                    keyDown: true
                )
                keyDown?.flags = []
                return keyDown
            },
            postEvent: { event in
                event.post(tap: .cghidEventTap)
            }
        )
    }

    init(
        makeKeyDownEvent: @escaping () -> CGEvent?,
        postEvent: @escaping (CGEvent) -> Void
    ) {
        self.makeKeyDownEvent = makeKeyDownEvent
        self.postEvent = postEvent
    }

    public func post(_ text: String) -> Bool {
        guard let keyDown = makeKeyDownEvent() else {
            return false
        }

        let utf16 = Array(text.utf16)
        utf16.withUnsafeBufferPointer { buffer in
            keyDown.keyboardSetUnicodeString(
                stringLength: buffer.count,
                unicodeString: buffer.baseAddress
            )
        }

        postEvent(keyDown)
        return true
    }
}

@MainActor
public final class SimulatedTypingInserter: TextInserting {
    private let eventPoster: any SimulatedTypingEventPosting
    private let permissionChecker: () -> Bool
    private let cancellationMonitor: any TypingCancellationMonitoring
    private let encoder: UnicodeTypingEncoder
    private let interClusterDelayNanoseconds: UInt64

    public init(
        eventPoster: any SimulatedTypingEventPosting = CoreGraphicsTypingEventPoster(),
        permissionChecker: @escaping () -> Bool = AXIsProcessTrusted,
        cancellationMonitor: any TypingCancellationMonitoring = TypingCancellationToken(),
        encoder: UnicodeTypingEncoder = UnicodeTypingEncoder(),
        interClusterDelayNanoseconds: UInt64 = 2_000_000
    ) {
        self.eventPoster = eventPoster
        self.permissionChecker = permissionChecker
        self.cancellationMonitor = cancellationMonitor
        self.encoder = encoder
        self.interClusterDelayNanoseconds = interClusterDelayNanoseconds
    }

    public func insert(_ text: String) async -> TextInsertionResult {
        guard !text.isEmpty else { return .success }

        guard !text.containsLineBreak else {
            return .unavailable(reason: "Simulated typing cannot safely insert line breaks")
        }

        guard permissionChecker() else {
            return .permissionDenied
        }

        for cluster in encoder.graphemeClusters(in: text) {
            if cancellationMonitor.isCancelled {
                return .cancelled
            }

            guard eventPoster.post(cluster) else {
                return .eventCreationFailed
            }

            if cancellationMonitor.isCancelled {
                return .cancelled
            }

            if interClusterDelayNanoseconds > 0 {
                try? await Task.sleep(nanoseconds: interClusterDelayNanoseconds)
            }
        }

        return .success
    }
}

private extension String {
    var containsLineBreak: Bool {
        rangeOfCharacter(from: .newlines) != nil
    }
}
