import AppKit
import Foundation
import VoxFlowVoiceCorrection
import XCTest
@testable import VoxFlowApp

@MainActor
final class GhosttyAXAutoLearningLiveTests: XCTestCase {
    func testLearnsFromGhosttyFocusedAXText() async throws {
        guard ProcessInfo.processInfo.environment["VOXFLOW_TEST_GHOSTTY_AX"] == "1" else {
            throw XCTSkip("Set VOXFLOW_TEST_GHOSTTY_AX=1 to run the Ghostty AX live test.")
        }
        guard AXIsProcessTrusted() else {
            throw XCTSkip("Accessibility permission is required for the Ghostty AX live test.")
        }
        guard let ghostty = NSWorkspace.shared.runningApplications.first(where: {
            $0.bundleIdentifier == "com.mitchellh.ghostty"
        }) else {
            throw XCTSkip("Ghostty is not running.")
        }

        let clipboard = ClipboardSnapshot.capture()
        defer { clipboard.restore() }

        let original = "偷看"
        let replacement = "token"
        let observer = AccessibilityFocusedTextObserver()

        try activateGhostty()
        try clearLine()
        try await wait(milliseconds: 100)
        let anchor = observer.capture(targetProcessID: Int(ghostty.processIdentifier))

        try paste(original)
        try await wait(milliseconds: 250)

        let capturedBaseline = if let anchor {
            observer.recapture(matching: anchor)
        } else {
            observer.capture(targetProcessID: Int(ghostty.processIdentifier))
        }
        let baseline = try XCTUnwrap(capturedBaseline, "Expected Ghostty focused AX text baseline")
        let currentBaseline = try XCTUnwrap(
            observer.capture(targetProcessID: Int(ghostty.processIdentifier)),
            "Expected current Ghostty focused AX text"
        )
        XCTAssertTrue(
            currentBaseline.value.contains(original),
            "Current Ghostty AX text did not contain inserted text. tail=\(String(currentBaseline.value.suffix(300)))"
        )

        let ruleRepository = GhosttyLiveRuleRepository()
        let targetRepository = GhosttyLiveTargetRepository()
        var diagnostics: [CorrectionObservationDiagnostic] = []
        let coordinator = CorrectionObservationCoordinator(
            observer: observer,
            repository: ruleRepository,
            targetRepository: targetRepository,
            pollOffsets: [.milliseconds(300), .milliseconds(600), .milliseconds(900)],
            isAutoLearningEnabled: { true },
            autoLearningAppliesImmediately: { true },
            onDiagnostic: { diagnostics.append($0) }
        )
        let scheduler = CorrectionObservationScheduler(coordinator: coordinator)

        scheduler.scheduleObservation(
            insertedText: original,
            context: CorrectionContext(
                mode: .dictation,
                providerID: "live-test",
                modelID: nil,
                language: "zh-CN",
                bundleIdentifier: "com.mitchellh.ghostty",
                isFinalTranscript: true,
                isSecureField: false
            ),
            appliedEvents: [],
            baseline: baseline,
            targetProcessID: Int(ghostty.processIdentifier)
        )

        try await wait(milliseconds: 120)
        try clearLine()
        try paste(replacement)
        try await wait(milliseconds: 1_200)
        try clearLine()

        let saved = try XCTUnwrap(ruleRepository.savedRules.first, "diagnostics=\(diagnostics)")
        XCTAssertEqual(saved.original, original)
        XCTAssertEqual(saved.replacement, replacement)
        XCTAssertEqual(saved.scope, .application(bundleIdentifier: "com.mitchellh.ghostty"))
    }

    private func activateGhostty() throws {
        try runOSAScript(#"tell application "Ghostty" to activate"#)
    }

    private func clearLine() throws {
        try runOSAScript(
            """
            tell application "Ghostty" to activate
            delay 0.2
            tell application "System Events" to keystroke "u" using control down
            """
        )
    }

    private func paste(_ text: String) throws {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        try runOSAScript(
            """
            tell application "Ghostty" to activate
            delay 0.2
            tell application "System Events" to keystroke "v" using command down
            """
        )
    }

    private func runOSAScript(_ source: String) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", source]
        try process.run()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0)
    }

    private func wait(milliseconds: UInt64) async throws {
        try await Task.sleep(nanoseconds: milliseconds * 1_000_000)
    }
}

private struct ClipboardSnapshot {
    let string: String?

    static func capture() -> ClipboardSnapshot {
        ClipboardSnapshot(string: NSPasteboard.general.string(forType: .string))
    }

    func restore() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        if let string {
            pasteboard.setString(string, forType: .string)
        }
    }
}

private final class GhosttyLiveRuleRepository: CorrectionRuleRepository {
    private(set) var savedRules: [CorrectionRule] = []

    func list() throws -> [CorrectionRule] { savedRules }
    func save(_ rule: CorrectionRule) throws { savedRules.append(rule) }
    func rule(id: UUID) throws -> CorrectionRule? { savedRules.first { $0.id == id } }
    func setEnabled(_ isEnabled: Bool, id: UUID, updatedAt: Date) throws {}
    func delete(id: UUID) throws {}
    func clearAll() throws { savedRules.removeAll() }
}

private final class GhosttyLiveTargetRepository: CorrectionTargetRepository {
    private var targets: [CorrectionTargetTerm] = []

    func save(_ target: CorrectionTargetTerm) throws {
        targets.removeAll { $0.id == target.id }
        targets.append(target)
    }

    func target(id: UUID) throws -> CorrectionTargetTerm? {
        targets.first { $0.id == id }
    }

    func list() throws -> [CorrectionTargetTerm] {
        targets
    }

    func delete(id: UUID) throws {
        targets.removeAll { $0.id == id }
    }
}
