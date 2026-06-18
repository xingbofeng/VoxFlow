import XCTest
@testable import VoxFlowApp

@MainActor
final class EscapeKeyMonitorControllerTests: XCTestCase {
    func testLocalEscapeCancelsAndSwallowsEvent() {
        var localHandler: ((UInt16) -> Bool)?
        let controller = EscapeKeyMonitorController(
            addLocalMonitor: { handler in
                localHandler = handler
                return "local" as NSString
            },
            addGlobalMonitor: { _ in "global" as NSString },
            removeMonitor: { _ in },
            scheduleOnMain: { action in action() }
        )
        var cancelCount = 0

        controller.start {
            cancelCount += 1
        }

        XCTAssertEqual(localHandler?(36), true)
        XCTAssertEqual(cancelCount, 0)
        XCTAssertEqual(localHandler?(53), false)
        XCTAssertEqual(cancelCount, 1)
    }

    func testGlobalEscapeSchedulesCancelOnMainActor() {
        var globalHandler: ((UInt16) -> Void)?
        var scheduledActions: [@MainActor () -> Void] = []
        let controller = EscapeKeyMonitorController(
            addLocalMonitor: { _ in "local" as NSString },
            addGlobalMonitor: { handler in
                globalHandler = handler
                return "global" as NSString
            },
            removeMonitor: { _ in },
            scheduleOnMain: { action in scheduledActions.append(action) }
        )
        var cancelCount = 0

        controller.start {
            cancelCount += 1
        }

        globalHandler?(36)
        XCTAssertTrue(scheduledActions.isEmpty)

        globalHandler?(53)
        XCTAssertEqual(scheduledActions.count, 1)

        scheduledActions[0]()
        XCTAssertEqual(cancelCount, 1)
    }

    func testStartStopsExistingMonitorsBeforeInstallingNewOnes() {
        var installedMonitorIndex = 0
        var removedTokens: [String] = []
        let controller = EscapeKeyMonitorController(
            addLocalMonitor: { _ in
                installedMonitorIndex += 1
                return "local-\(installedMonitorIndex)" as NSString
            },
            addGlobalMonitor: { _ in
                installedMonitorIndex += 1
                return "global-\(installedMonitorIndex)" as NSString
            },
            removeMonitor: { token in
                removedTokens.append((token as? NSString).map(String.init) ?? "")
            },
            scheduleOnMain: { action in action() }
        )

        controller.start {}
        controller.start {}

        XCTAssertEqual(removedTokens, ["global-2", "local-1"])
    }

    func testStopRemovesInstalledMonitorsOnce() {
        var removedTokens: [String] = []
        let controller = EscapeKeyMonitorController(
            addLocalMonitor: { _ in "local" as NSString },
            addGlobalMonitor: { _ in "global" as NSString },
            removeMonitor: { token in
                removedTokens.append((token as? NSString).map(String.init) ?? "")
            },
            scheduleOnMain: { action in action() }
        )

        controller.start {}
        controller.stop()
        controller.stop()

        XCTAssertEqual(removedTokens, ["global", "local"])
    }
}
