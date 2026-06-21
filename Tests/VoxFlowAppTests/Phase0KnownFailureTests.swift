import AVFoundation
import AppKit
import XCTest
import VoxFlowTextInsertion
@testable import VoxFlowApp

final class Phase0KnownFailureTests: XCTestCase {
    private static func repositoryRoot() -> URL {
        var directory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        for _ in 0..<5 {
            if FileManager.default.fileExists(atPath: directory.appendingPathComponent("Package.swift").path) {
                return directory
            }
            directory.deleteLastPathComponent()
        }
        return URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    }

    func testQwen17VariantIsPresentedAsDisabledProviderWithProvisioningDownloadAction() throws {
        let manager = makeManager()
        manager.qwen3ModelSize = .size1_7B
        let registry = ASRProviderRegistry(asrManager: manager)
        let qwen = try XCTUnwrap(registry.descriptor(id: ASRProviderID.qwen3))

        XCTAssertTrue(qwen.tags.contains("1.7B"))
        XCTAssertFalse(qwen.isAvailable)
        XCTAssertEqual(qwen.localModelAction, .download)
        XCTAssertEqual(qwen.healthStatus, .notInstalled)
    }

    func testAudioRecorderUsesLosslessCaptureDefaults() {
        let recorder = AudioRecorder()

        XCTAssertFalse(
            recorder.voiceEnhancementEnabled,
            "Dynamic gain and tanh must be off by default before the tail-safe audio chain is rebuilt."
        )
    }

    func testPasteboardRestoreDoesNotOverwriteUserCopyAfterMarkerChanges() throws {
        let pasteboard = try XCTUnwrap(NSPasteboard(name: NSPasteboard.Name("Phase0Pasteboard-\(UUID().uuidString)")))
        pasteboard.clearContents()
        pasteboard.setString("original clipboard", forType: .string)

        let transaction = PasteboardTransaction.begin(
            on: pasteboard,
            replacementText: "voxflow transaction marker"
        )
        let transactionChangeCount = pasteboard.changeCount

        pasteboard.clearContents()
        pasteboard.setString("user copied after paste", forType: .string)
        XCTAssertGreaterThan(pasteboard.changeCount, transactionChangeCount)

        XCTAssertFalse(transaction.restoreOriginalIfUnchanged(on: pasteboard))
        XCTAssertEqual(
            pasteboard.string(forType: .string),
            "user copied after paste",
            "Clipboard restore must check changeCount/transaction marker and preserve newer user content."
        )
    }

    func testPasteboardRestoreIsNotFixedDelayBased() throws {
        let source = try String(
            contentsOf: Self.repositoryRoot()
                .appendingPathComponent("Sources/VoxFlowTextInsertion/FastPaste/FastPasteTextInserter.swift"),
            encoding: .utf8
        )

        XCTAssertFalse(source.contains("pasteDelay"))
        XCTAssertFalse(source.contains("Task.sleep(nanoseconds: pasteDelay)"))
        XCTAssertTrue(source.contains("PasteCompletionWaiter"))
    }

    func testTextInjectorDoesNotReturnSuccessUntilPasteIsVerified() {
        XCTExpectFailure("VF-0002/TXT-03: Cmd+V event posting currently returns success without verifying the target received the paste.") {
            XCTFail(
                "Text injection must distinguish posted keyboard events from verified paste completion."
            )
        }
    }

    @MainActor
    func testAgentComposeOutputInjectsWhenTargetUnchanged() async {
        let injector = Phase0TextInjector(result: .success)
        let clipboard = Phase0ClipboardService()
        let service = DefaultOutputService(
            textInjector: injector,
            clipboardService: clipboard
        )
        let target = DictationTarget(bundleID: "com.example.editor", appName: "Editor")

        let result = await service.deliver(
            text: "agent text",
            mode: .agentCompose,
            target: target,
            originalTarget: target
        )

        XCTAssertEqual(result, .injected)
        XCTAssertEqual(injector.injectedTexts, ["agent text"])
        XCTAssertTrue(clipboard.copiedTexts.isEmpty)
    }

    private func makeManager() -> ASRManager {
        let suiteName = "test.Phase0KnownFailure.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        addTeardownBlock {
            UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName)
        }
        return ASRManager(defaults: defaults)
    }
}

@MainActor
private final class Phase0TextInjector: TextInserting {
    let result: TextInsertionResult
    private(set) var injectedTexts: [String] = []

    init(result: TextInsertionResult) {
        self.result = result
    }

    func insert(_ text: String) async -> TextInsertionResult {
        injectedTexts.append(text)
        return result
    }
}

@MainActor
private final class Phase0ClipboardService: ClipboardSetting {
    private(set) var copiedTexts: [String] = []

    func setString(_ text: String) -> Bool {
        copiedTexts.append(text)
        return true
    }
}
