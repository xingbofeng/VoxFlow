import AppKit
import XCTest
@testable import VoiceInputApp

final class LiveContextPipelineTests: XCTestCase {
    func testCollectsVisibleTextFromRunningWeChatWhenEnabled() async throws {
        try XCTSkipUnless(Self.liveContextEnabled)
        let snapshot = try await collect(bundleID: "com.tencent.xinWeChat", appName: "微信")

        XCTAssertGreaterThan(snapshot.trimmedLength, 0)
        XCTAssertTrue(snapshot.sources.contains(.accessibilityVisibleText))
        XCTAssertFalse(Self.isOnlyWindowChrome(snapshot.visibleText))
    }

    func testCollectsVisibleTextFromRunningChromeWhenEnabled() async throws {
        try XCTSkipUnless(Self.liveContextEnabled)
        let snapshot = try await collect(bundleID: "com.google.Chrome", appName: "Google Chrome")

        XCTAssertGreaterThan(snapshot.trimmedLength, 10)
        XCTAssertTrue(snapshot.sources.contains(.accessibilityVisibleText))
    }

    private static var liveContextEnabled: Bool {
        ProcessInfo.processInfo.environment["VOICEINPUT_LIVE_CONTEXT"] == "1"
    }

    private func collect(bundleID: String, appName: String) async throws -> ContextSnapshot {
        guard let application = NSWorkspace.shared.runningApplications.first(where: {
            $0.bundleIdentifier == bundleID
        }) else {
            throw XCTSkip("\(appName) is not running")
        }

        let target = DictationTarget(
            bundleID: bundleID,
            appName: appName,
            pid: Int(application.processIdentifier)
        )
        return await ContextPipeline().collect(target: target, visionSupported: true)
    }

    private static func isOnlyWindowChrome(_ text: String?) -> Bool {
        guard let text else { return true }
        let lines = Set(
            text
                .components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        )
        return !lines.isEmpty && lines.isSubset(of: [
            "微信",
            "此按钮也可以执行缩放窗口的操作"
        ])
    }
}
