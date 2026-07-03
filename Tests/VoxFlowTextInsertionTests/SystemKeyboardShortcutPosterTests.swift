import CoreGraphics
import Testing
@testable import VoxFlowTextInsertion

@MainActor
struct SystemKeyboardShortcutPosterTests {
    @Test
    func postKeyEmitsKeyDownAndKeyUpEventsWhenSystemInteractionIsAllowed() throws {
        var events: [CGEvent] = []
        let poster = SystemKeyboardShortcutPoster(
            allowsSystemInteraction: { true },
            postEvents: { down, up in
                events.append(down)
                events.append(up)
            }
        )

        try poster.postKey(named: "escape")

        #expect(events.count == 2)
    }

    @Test
    func unsupportedKeyThrowsWithoutPostingEvents() {
        var events: [CGEvent] = []
        let poster = SystemKeyboardShortcutPoster(
            allowsSystemInteraction: { true },
            postEvents: { down, up in
                events.append(down)
                events.append(up)
            }
        )

        #expect(throws: KeyboardShortcutPostingError.unsupportedKey) {
            try poster.postKey(named: "return")
        }
        #expect(events.isEmpty)
    }
}
