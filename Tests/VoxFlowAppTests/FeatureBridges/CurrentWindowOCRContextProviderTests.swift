import XCTest
import VoxFlowContextBoost
@testable import VoxFlowApp

final class CurrentWindowOCRContextProviderTests: XCTestCase {
    func testCaptureContextReturnsRankedHotwordsForTargetWindowOCR() async {
        let screenshotProvider = FakeScreenshotProvider(
            canCapture: true,
            visibleText: """
            Project Apollo release plan
            OpenAI customer notes
            Qwen3-ASR package update
            """
        )
        let provider = CurrentWindowOCRContextProvider(
            screenshotProvider: screenshotProvider,
            namedEntityProvider: FakeOCRNamedEntityProvider(
                entities: [NamedEntityCandidate(text: "OpenAI", kind: .organization)]
            ),
            now: { Date(timeIntervalSince1970: 1_800_000_000) }
        )

        let snapshot = await provider.captureContext(
            for: DictationTarget(
                bundleID: "com.example.editor",
                appName: "Editor",
                pid: 42,
                windowID: "7",
                windowTitle: "Release Notes"
            )
        )

        XCTAssertEqual(snapshot?.bundleID, "com.example.editor")
        XCTAssertEqual(snapshot?.appName, "Editor")
        XCTAssertEqual(snapshot?.windowTitle, "Release Notes")
        XCTAssertEqual(snapshot?.ocrCharacterCount, screenshotProvider.visibleText?.count)
        XCTAssertNotNil(snapshot?.candidateCount)
        XCTAssertGreaterThan(snapshot?.candidateCount ?? 0, 0)
        XCTAssertTrue(snapshot?.hotwords.containsText("OpenAI") == true)
        XCTAssertTrue(snapshot?.hotwords.containsText("Project Apollo") == true)
        XCTAssertTrue(snapshot?.hotwords.containsText("Qwen3-ASR") == true)
    }

    func testCaptureContextReturnsNilWhenScreenCaptureIsUnauthorized() async {
        let screenshotProvider = FakeScreenshotProvider(canCapture: false, visibleText: "Project Apollo")
        let provider = CurrentWindowOCRContextProvider(
            screenshotProvider: screenshotProvider,
            namedEntityProvider: FakeOCRNamedEntityProvider(entities: [])
        )

        let snapshot = await provider.captureContext(for: DictationTarget(pid: 42))

        XCTAssertNil(snapshot)
        XCTAssertFalse(screenshotProvider.didRequestVisibleText)
    }

    func testCaptureContextReturnsNilForMissingTargetOrEmptyOCR() async {
        let screenshotProvider = FakeScreenshotProvider(canCapture: true, visibleText: "  ")
        let provider = CurrentWindowOCRContextProvider(
            screenshotProvider: screenshotProvider,
            namedEntityProvider: FakeOCRNamedEntityProvider(entities: [])
        )

        let missingTarget = await provider.captureContext(for: nil)
        let emptyOCR = await provider.captureContext(for: DictationTarget(pid: 42))

        XCTAssertNil(missingTarget)
        XCTAssertNil(emptyOCR)
    }
}

private final class FakeScreenshotProvider: ScreenshotProviding, @unchecked Sendable {
    let canCapture: Bool
    let visibleText: String?
    private(set) var didRequestVisibleText = false

    init(canCapture: Bool, visibleText: String?) {
        self.canCapture = canCapture
        self.visibleText = visibleText
    }

    func canCaptureScreen() -> Bool {
        canCapture
    }

    func visibleText(target: DictationTarget?) async -> String? {
        didRequestVisibleText = true
        return visibleText
    }
}

private struct FakeOCRNamedEntityProvider: OCRNamedEntityProviding {
    let entities: [NamedEntityCandidate]

    func namedEntities(in text: String) -> [NamedEntityCandidate] {
        entities
    }
}

private extension Array where Element == TemporaryHotword {
    func containsText(_ text: String) -> Bool {
        contains { $0.text == text }
    }
}
