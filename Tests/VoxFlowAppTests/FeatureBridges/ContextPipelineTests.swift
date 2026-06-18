import Foundation
import Vision
import XCTest
@testable import VoxFlowApp

final class ContextPipelineTests: XCTestCase {

    func testContextTextSanitizerRemovesJSONChromeAndCorruptedOCRLines() {
        let text = """
        张三：今晚六点前可以发我吗？
        {"role":"button","title":"关闭"}
        关闭按钮
        ��烫烫���
        收到，我会在六点前发你。
        """

        XCTAssertEqual(
            ContextTextSanitizer.sanitize(text),
            "张三：今晚六点前可以发我吗？\n收到，我会在六点前发你。"
        )
    }

    func testContextTextSanitizerPreservesTechnicalJSONMentions() {
        XCTAssertEqual(
            ContextTextSanitizer.sanitize("请检查 JSON 解析和 Chrome 扩展的错误"),
            "请检查 JSON 解析和 Chrome 扩展的错误"
        )
    }

    func testWeChatOCRUsesAccurateChineseRecognitionConfiguration() {
        let request = SystemScreenshotProvider.makeRecognitionRequest()

        XCTAssertEqual(request.recognitionLevel, .accurate)
        XCTAssertTrue(request.usesLanguageCorrection)
        XCTAssertEqual(request.recognitionLanguages, ["zh-Hans", "zh-Hant", "en-US"])
    }

    func testScreenshotWindowSelectionPrefersRecordedTargetWindowID() {
        let candidates = [
            ScreenshotWindowCandidate(
                windowID: 10,
                pid: 42,
                layer: 0,
                isOnScreen: true,
                isActive: true,
                frame: CGRect(x: 0, y: 0, width: 1200, height: 800)
            ),
            ScreenshotWindowCandidate(
                windowID: 20,
                pid: 42,
                layer: 0,
                isOnScreen: true,
                isActive: false,
                frame: CGRect(x: 1500, y: -900, width: 900, height: 700)
            ),
        ]

        let selected = SystemScreenshotProvider.selectWindow(
            from: candidates,
            target: DictationTarget(pid: 42, windowID: "20")
        )

        XCTAssertEqual(selected?.windowID, 20)
    }

    func testScreenshotWindowSelectionFallsBackToActiveWindowForTargetProcess() {
        let candidates = [
            ScreenshotWindowCandidate(
                windowID: 10,
                pid: 42,
                layer: 0,
                isOnScreen: true,
                isActive: false,
                frame: CGRect(x: 0, y: 0, width: 1600, height: 900)
            ),
            ScreenshotWindowCandidate(
                windowID: 20,
                pid: 42,
                layer: 0,
                isOnScreen: true,
                isActive: true,
                frame: CGRect(x: -900, y: -700, width: 800, height: 600)
            ),
            ScreenshotWindowCandidate(
                windowID: 30,
                pid: 99,
                layer: 0,
                isOnScreen: true,
                isActive: true,
                frame: CGRect(x: 0, y: 0, width: 1900, height: 1000)
            ),
        ]

        let selected = SystemScreenshotProvider.selectWindow(
            from: candidates,
            target: DictationTarget(pid: 42)
        )

        XCTAssertEqual(selected?.windowID, 20)
    }

    func testAccessibilityVisibleTextSummaryDeduplicatesAndFiltersNoise() {
        let summary = AccessibilityVisibleTextSummary.make(
            from: [
                "AI 设计的未来",
                " ",
                "AI 设计的未来",
                "孙少君: 学习",
                "x",
                "帮我回复一句收到"
            ],
            maxCharacters: 200
        )

        XCTAssertEqual(
            summary,
            "AI 设计的未来\n孙少君: 学习\n帮我回复一句收到"
        )
    }

    // MARK: - testCollectsWindowTitle

    func testCollectsWindowTitle() async {
        let windowInfo = StubWindowInfoProvider(title: "My Document - Editor")
        let accessibility = StubAccessibilityProvider()
        let screenshot = StubScreenshotProvider(canCapture: false)
        let pipeline = ContextPipeline(
            windowInfoProvider: windowInfo,
            accessibilityProvider: accessibility,
            screenshotProvider: screenshot
        )
        let target = DictationTarget(
            bundleID: "com.example.editor",
            appName: "Editor",
            pid: 42,
            windowTitle: "My Document - Editor"
        )

        let snapshot = await pipeline.collect(target: target, visionSupported: false)

        XCTAssertEqual(snapshot.windowTitle, "My Document - Editor")
        XCTAssertEqual(snapshot.targetAppBundleID, "com.example.editor")
        XCTAssertEqual(snapshot.targetAppName, "Editor")
        XCTAssertTrue(snapshot.sources.contains(.windowMetadata))
    }

    // MARK: - testCollectsAccessibilityVisibleText

    func testCollectsAccessibilityVisibleText() async {
        let accessibility = StubAccessibilityProvider(
            visibleText: String(repeating: "Hello world. ", count: 10)
        )
        let pipeline = ContextPipeline(
            windowInfoProvider: StubWindowInfoProvider(title: nil),
            accessibilityProvider: accessibility,
            screenshotProvider: StubScreenshotProvider(canCapture: false)
        )
        let target = DictationTarget(bundleID: "com.example.app", appName: "App", pid: 1)

        let snapshot = await pipeline.collect(target: target, visionSupported: false)

        XCTAssertNotNil(snapshot.visibleText)
        XCTAssertTrue(snapshot.sources.contains(.accessibilityVisibleText))
    }

    // MARK: - testCollectsSelectedText

    func testCollectsSelectedText() async {
        let accessibility = StubAccessibilityProvider(
            selectedText: "selected paragraph content"
        )
        let pipeline = ContextPipeline(
            windowInfoProvider: StubWindowInfoProvider(title: nil),
            accessibilityProvider: accessibility,
            screenshotProvider: StubScreenshotProvider(canCapture: false)
        )
        let target = DictationTarget(bundleID: "com.example.app", appName: "App", pid: 1)

        let snapshot = await pipeline.collect(target: target, visionSupported: false)

        XCTAssertEqual(snapshot.selectedText, "selected paragraph content")
        XCTAssertTrue(snapshot.sources.contains(.accessibilitySelectedText))
    }

    // MARK: - testDeduplicatesIdenticalText

    func testDeduplicatesIdenticalText() async {
        let sameText = "This is identical content from multiple sources"
        let accessibility = StubAccessibilityProvider(
            visibleText: sameText,
            inputAreaText: sameText
        )
        let pipeline = ContextPipeline(
            windowInfoProvider: StubWindowInfoProvider(title: nil),
            accessibilityProvider: accessibility,
            screenshotProvider: StubScreenshotProvider(canCapture: false)
        )
        let target = DictationTarget(bundleID: "com.example.app", appName: "App", pid: 1)

        let snapshot = await pipeline.collect(target: target, visionSupported: false)

        // inputAreaText should be nil since it duplicates visibleText
        XCTAssertNotNil(snapshot.visibleText)
        XCTAssertNil(snapshot.inputAreaText)
    }

    // MARK: - testFiltersWhitespaceOnlyText

    func testFiltersWhitespaceOnlyText() async {
        let accessibility = StubAccessibilityProvider(
            visibleText: "   \n  \t  ",
            selectedText: "  "
        )
        let pipeline = ContextPipeline(
            windowInfoProvider: StubWindowInfoProvider(title: nil),
            accessibilityProvider: accessibility,
            screenshotProvider: StubScreenshotProvider(canCapture: false)
        )
        let target = DictationTarget(bundleID: "com.example.app", appName: "App", pid: 1)

        let snapshot = await pipeline.collect(target: target, visionSupported: false)

        XCTAssertNil(snapshot.visibleText)
        XCTAssertNil(snapshot.selectedText)
    }

    // MARK: - testRespectsMaxLength

    func testRespectsMaxLength() async {
        let longText = String(repeating: "abcdefghij", count: 500) // 5000 chars
        let accessibility = StubAccessibilityProvider(
            visibleText: longText
        )
        let pipeline = ContextPipeline(
            windowInfoProvider: StubWindowInfoProvider(title: nil),
            accessibilityProvider: accessibility,
            screenshotProvider: StubScreenshotProvider(canCapture: false)
        )
        let target = DictationTarget(bundleID: "com.example.app", appName: "App", pid: 1)

        let snapshot = await pipeline.collect(target: target, visionSupported: false)

        XCTAssertLessThanOrEqual(snapshot.trimmedLength, ContextPipeline.maxTotalCharacters)
    }

    // MARK: - testTagsSourcesCorrectly

    func testTagsSourcesCorrectly() async {
        let accessibility = StubAccessibilityProvider(
            visibleText: "Some visible text that is long enough to pass",
            selectedText: "some selection",
            inputAreaText: "typed input content here"
        )
        let pipeline = ContextPipeline(
            windowInfoProvider: StubWindowInfoProvider(title: "Title"),
            accessibilityProvider: accessibility,
            screenshotProvider: StubScreenshotProvider(canCapture: false)
        )
        let target = DictationTarget(bundleID: "com.test", appName: "Test", pid: 1)

        let snapshot = await pipeline.collect(target: target, visionSupported: false)

        XCTAssertTrue(snapshot.sources.contains(.windowMetadata))
        XCTAssertTrue(snapshot.sources.contains(.accessibilityVisibleText))
        XCTAssertTrue(snapshot.sources.contains(.accessibilitySelectedText))
        XCTAssertTrue(snapshot.sources.contains(.accessibilityInputArea))
    }

    // MARK: - testSecureTextFieldBlocksAllCollection

    func testSecureTextFieldBlocksAllCollection() async {
        let accessibility = StubAccessibilityProvider(
            visibleText: "password123",
            selectedText: "password123",
            isSecure: true
        )
        let pipeline = ContextPipeline(
            windowInfoProvider: StubWindowInfoProvider(title: "Login"),
            accessibilityProvider: accessibility,
            screenshotProvider: StubScreenshotProvider(canCapture: true)
        )
        let target = DictationTarget(bundleID: "com.secure.app", appName: "Secure", pid: 1)

        let snapshot = await pipeline.collect(target: target, visionSupported: true)

        XCTAssertNil(snapshot.visibleText)
        XCTAssertNil(snapshot.selectedText)
        XCTAssertNil(snapshot.inputAreaText)
        XCTAssertFalse(snapshot.visualContentAvailable)
        XCTAssertTrue(snapshot.warnings.contains("secure_text_field_detected"))
    }

    // MARK: - testTimeoutReturnsPartialResults

    func testTimeoutReturnsPartialResults() async {
        // Simulate slow providers that exceed the timeout
        let accessibility = SlowAccessibilityProvider(delayMilliseconds: 600)
        let pipeline = ContextPipeline(
            windowInfoProvider: StubWindowInfoProvider(title: "Window"),
            accessibilityProvider: accessibility,
            screenshotProvider: StubScreenshotProvider(canCapture: false)
        )
        let target = DictationTarget(bundleID: "com.example.app", appName: "App", pid: 1)

        let snapshot = await pipeline.collect(target: target, visionSupported: false)

        // Should have window metadata (fast) but not accessibility data (slow)
        XCTAssertTrue(snapshot.sources.contains(.windowMetadata))
        XCTAssertTrue(snapshot.warnings.contains("context_collection_timeout"))
    }

    // MARK: - testEmptyResultWhenNothingAvailable

    func testEmptyResultWhenNothingAvailable() async {
        let pipeline = ContextPipeline(
            windowInfoProvider: StubWindowInfoProvider(title: nil),
            accessibilityProvider: StubAccessibilityProvider(),
            screenshotProvider: StubScreenshotProvider(canCapture: false)
        )

        let snapshot = await pipeline.collect(target: nil, visionSupported: false)

        XCTAssertNil(snapshot.windowTitle)
        XCTAssertNil(snapshot.visibleText)
        XCTAssertNil(snapshot.selectedText)
        XCTAssertNil(snapshot.inputAreaText)
        XCTAssertEqual(snapshot.trimmedLength, 0)
        XCTAssertTrue(snapshot.sources.isEmpty)
    }

    // MARK: - testSkipsVisualFallbackWhenAccessibilitySufficient

    func testSkipsVisualFallbackWhenAccessibilitySufficient() async {
        let longText = String(repeating: "Sufficient accessibility content. ", count: 5) // > 50 chars
        let accessibility = StubAccessibilityProvider(visibleText: longText)
        let screenshot = TrackingScreenshotProvider(canCapture: true)
        let pipeline = ContextPipeline(
            windowInfoProvider: StubWindowInfoProvider(title: nil),
            accessibilityProvider: accessibility,
            screenshotProvider: screenshot
        )
        let target = DictationTarget(bundleID: "com.example.app", appName: "App", pid: 1)

        let snapshot = await pipeline.collect(target: target, visionSupported: true)

        XCTAssertFalse(snapshot.visualContentAvailable)
        XCTAssertFalse(snapshot.sources.contains(.visualFallback))
        XCTAssertFalse(screenshot.wasCalled)
    }

    // MARK: - testSkipsVisualFallbackWhenNoVisionSupport

    func testSkipsVisualFallbackWhenNoVisionSupport() async {
        let accessibility = StubAccessibilityProvider()
        let pipeline = ContextPipeline(
            windowInfoProvider: StubWindowInfoProvider(title: nil),
            accessibilityProvider: accessibility,
            screenshotProvider: StubScreenshotProvider(canCapture: true)
        )
        let target = DictationTarget(bundleID: "com.example.app", appName: "App", pid: 1)

        let snapshot = await pipeline.collect(target: target, visionSupported: false)

        XCTAssertFalse(snapshot.visualContentAvailable)
        XCTAssertFalse(snapshot.sources.contains(.visualFallback))
        XCTAssertTrue(snapshot.warnings.contains("vision_not_supported"))
    }

    // MARK: - testWarnsWhenVisualFallbackNeedsScreenRecordingPermission

    func testWarnsWhenVisualFallbackNeedsScreenRecordingPermission() async {
        let accessibility = StubAccessibilityProvider(visibleText: "微信")
        let pipeline = ContextPipeline(
            windowInfoProvider: StubWindowInfoProvider(title: "微信"),
            accessibilityProvider: accessibility,
            screenshotProvider: StubScreenshotProvider(canCapture: false)
        )
        let target = DictationTarget(bundleID: "com.tencent.xinWeChat", appName: "微信", pid: 1)

        let snapshot = await pipeline.collect(target: target, visionSupported: true)

        XCTAssertFalse(snapshot.visualContentAvailable)
        XCTAssertFalse(snapshot.sources.contains(.visualFallback))
        XCTAssertTrue(snapshot.warnings.contains("screen_recording_not_authorized"))
    }

    // MARK: - testUsesVisualTextFallbackWhenAccessibilityInsufficient

    func testUsesVisualTextFallbackWhenAccessibilityInsufficient() async {
        let accessibility = StubAccessibilityProvider(visibleText: "微信")
        let screenshot = StubScreenshotProvider(
            canCapture: true,
            visualText: "孙少君：六点前可以发我吗？\n我：可以，我六点前发你。"
        )
        let pipeline = ContextPipeline(
            windowInfoProvider: StubWindowInfoProvider(title: "微信"),
            accessibilityProvider: accessibility,
            screenshotProvider: screenshot
        )
        let target = DictationTarget(bundleID: "com.tencent.xinWeChat", appName: "微信", pid: 1)

        let snapshot = await pipeline.collect(target: target, visionSupported: true)

        XCTAssertEqual(snapshot.visibleText, "孙少君：六点前可以发我吗？\n我：可以，我六点前发你。")
        XCTAssertTrue(snapshot.visualContentAvailable)
        XCTAssertTrue(snapshot.sources.contains(.visualFallback))
    }

    func testVisualFallbackSanitizesOCRBeforeAddingContext() async {
        let accessibility = StubAccessibilityProvider(visibleText: "微信")
        let screenshot = StubScreenshotProvider(
            canCapture: true,
            visualText: """
            李明：明天十点开会
            {"AXRole":"AXButton"}
            最小化按钮
            ���
            我：好的
            """
        )
        let pipeline = ContextPipeline(
            windowInfoProvider: StubWindowInfoProvider(title: "微信"),
            accessibilityProvider: accessibility,
            screenshotProvider: screenshot
        )
        let target = DictationTarget(bundleID: "com.tencent.xinWeChat", appName: "微信", pid: 1)

        let snapshot = await pipeline.collect(target: target, visionSupported: true)

        XCTAssertEqual(snapshot.visibleText, "李明：明天十点开会\n我：好的")
    }

    // MARK: - testDoesNotPersistScreenshots

    func testDoesNotPersistScreenshots() async {
        // Even when visual fallback is triggered, the snapshot must not contain
        // screenshot data - only a boolean flag
        let accessibility = StubAccessibilityProvider()
        let screenshot = StubScreenshotProvider(canCapture: true)
        let pipeline = ContextPipeline(
            windowInfoProvider: StubWindowInfoProvider(title: nil),
            accessibilityProvider: accessibility,
            screenshotProvider: screenshot
        )
        let target = DictationTarget(bundleID: "com.example.app", appName: "App", pid: 1)

        let snapshot = await pipeline.collect(target: target, visionSupported: true)

        // Verify the snapshot is Codable and contains no screenshot data
        XCTAssertTrue(snapshot.visualContentAvailable)
        let encoded = try! JSONEncoder().encode(snapshot)
        let decoded = try! JSONDecoder().decode(ContextSnapshot.self, from: encoded)
        XCTAssertEqual(decoded.visualContentAvailable, true)
        // No actual image data in the snapshot
        XCTAssertNil(decoded.visibleText)
    }
}

// MARK: - Test Doubles

private struct StubWindowInfoProvider: WindowInfoProviding {
    let title: String?

    func windowTitle(pid: Int?) -> String? {
        title
    }
}

private struct StubAccessibilityProvider: AccessibilityProviding {
    var visibleText: String?
    var selectedText: String?
    var inputAreaText: String?
    var isSecure: Bool = false

    func visibleText(pid: Int?) -> String? { visibleText }
    func selectedText(pid: Int?) -> String? { selectedText }
    func inputAreaText(pid: Int?) -> String? { inputAreaText }
    func isSecureTextField(pid: Int?) -> Bool { isSecure }
}

private struct StubScreenshotProvider: ScreenshotProviding {
    let canCapture: Bool
    var visualText: String?

    func canCaptureScreen() -> Bool { canCapture }
    func visibleText(target: DictationTarget?) async -> String? { visualText }
}

private final class SlowAccessibilityProvider: AccessibilityProviding, @unchecked Sendable {
    let delayMilliseconds: Int

    init(delayMilliseconds: Int) {
        self.delayMilliseconds = delayMilliseconds
    }

    func visibleText(pid: Int?) -> String? {
        Thread.sleep(forTimeInterval: Double(delayMilliseconds) / 1000.0)
        return "delayed text"
    }

    func selectedText(pid: Int?) -> String? {
        Thread.sleep(forTimeInterval: Double(delayMilliseconds) / 1000.0)
        return nil
    }

    func inputAreaText(pid: Int?) -> String? {
        Thread.sleep(forTimeInterval: Double(delayMilliseconds) / 1000.0)
        return nil
    }

    func isSecureTextField(pid: Int?) -> Bool { false }
}

private final class TrackingScreenshotProvider: ScreenshotProviding, @unchecked Sendable {
    let canCapture: Bool
    var wasCalled = false

    init(canCapture: Bool) {
        self.canCapture = canCapture
    }

    func canCaptureScreen() -> Bool {
        wasCalled = true
        return canCapture
    }

    func visibleText(target: DictationTarget?) async -> String? {
        wasCalled = true
        return nil
    }
}
