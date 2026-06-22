import XCTest
@testable import VoxFlowApp

final class ScreenshotTextRefinerTests: XCTestCase {
    func testUsesLocalTranslatorBeforeConfiguredCloudFallback() async throws {
        let cloud = CapturingPromptRefiner(result: "云端译文", configured: true)
        let localTranslator = CapturingPromptRefiner(result: "本地译文", configured: true)
        let localSummarizer = CapturingPromptRefiner(result: "本地总结", configured: true)
        let defaults = Self.defaults(selectedTranslationModelID: CapabilityModelID.madladTranslation)
        let refiner = ScreenshotTextRefiner(
            cloudRefiner: cloud,
            localTranslator: localTranslator,
            localSummarizer: localSummarizer,
            defaults: defaults
        )

        let output = try await refiner.refine(
            TextRefinementRequest(
                text: "Error 404",
                systemPrompt: ScreenshotOCRService.translationSystemPrompt,
                model: nil,
                temperature: nil
            )
        )

        XCTAssertEqual(output, "本地译文")
        XCTAssertTrue(cloud.requests.isEmpty)
        XCTAssertEqual(localTranslator.requests.map(\.text), ["Error 404"])
        XCTAssertTrue(localSummarizer.requests.isEmpty)
    }

    func testUsesCloudTranslationFallbackWhenLocalTranslatorIsNotConfigured() async throws {
        let cloud = CapturingPromptRefiner(result: "云端译文", configured: true)
        let localTranslator = CapturingPromptRefiner(result: "ignored", configured: false)
        let localSummarizer = CapturingPromptRefiner(result: "本地总结", configured: true)
        let defaults = Self.defaults(selectedTranslationModelID: CapabilityModelID.madladTranslation)
        let refiner = ScreenshotTextRefiner(
            cloudRefiner: cloud,
            localTranslator: localTranslator,
            localSummarizer: localSummarizer,
            defaults: defaults
        )

        let output = try await refiner.refine(
            TextRefinementRequest(
                text: "Error 404",
                systemPrompt: ScreenshotOCRService.translationSystemPrompt,
                model: nil,
                temperature: nil
            )
        )

        XCTAssertEqual(output, "云端译文")
        XCTAssertEqual(cloud.requests.map(\.text), ["Error 404"])
        XCTAssertTrue(localTranslator.requests.isEmpty)
    }

    func testUsesCloudTranslationDirectlyWhenLLMTranslationIsSelected() async throws {
        let cloud = CapturingPromptRefiner(result: "云端译文", configured: true)
        let localTranslator = CapturingPromptRefiner(result: "本地译文", configured: true)
        let localSummarizer = CapturingPromptRefiner(result: "本地总结", configured: true)
        let defaults = Self.defaults(selectedTranslationModelID: CapabilityModelID.llmTranslation)
        let refiner = ScreenshotTextRefiner(
            cloudRefiner: cloud,
            localTranslator: localTranslator,
            localSummarizer: localSummarizer,
            defaults: defaults
        )

        let output = try await refiner.refine(
            TextRefinementRequest(
                text: "Error 404",
                systemPrompt: ScreenshotOCRService.translationSystemPrompt,
                model: nil,
                temperature: nil
            )
        )

        XCTAssertEqual(output, "云端译文")
        XCTAssertEqual(cloud.requests.map(\.text), ["Error 404"])
        XCTAssertTrue(localTranslator.requests.isEmpty)
    }

    func testLLMTranslationSelectionRequiresConfiguredCloudRefiner() {
        let cloud = CapturingPromptRefiner(result: "云端译文", configured: false)
        let localTranslator = CapturingPromptRefiner(result: "本地译文", configured: true)
        let localSummarizer = CapturingPromptRefiner(result: "本地总结", configured: true)
        let defaults = Self.defaults(selectedTranslationModelID: CapabilityModelID.llmTranslation)
        let refiner = ScreenshotTextRefiner(
            cloudRefiner: cloud,
            localTranslator: localTranslator,
            localSummarizer: localSummarizer,
            defaults: defaults
        )

        XCTAssertFalse(refiner.isTranslationConfigured)
    }

    func testLLMTranslationSelectionRequiresEnabledCloudRefiner() async {
        let cloud = CapturingPromptRefiner(result: "云端译文", configured: true)
        cloud.isEnabled = false
        let localTranslator = CapturingPromptRefiner(result: "本地译文", configured: true)
        let localSummarizer = CapturingPromptRefiner(result: "本地总结", configured: true)
        let defaults = Self.defaults(selectedTranslationModelID: CapabilityModelID.llmTranslation)
        let refiner = ScreenshotTextRefiner(
            cloudRefiner: cloud,
            localTranslator: localTranslator,
            localSummarizer: localSummarizer,
            defaults: defaults
        )

        XCTAssertFalse(refiner.isTranslationConfigured)
        do {
            _ = try await refiner.refine(
                TextRefinementRequest(
                    text: "Error 404",
                    systemPrompt: ScreenshotOCRService.translationSystemPrompt,
                    model: nil,
                    temperature: nil
                )
            )
            XCTFail("Expected disabled LLM translation to fail")
        } catch {
            XCTAssertEqual(error.localizedDescription, "翻译前请先配置模型")
        }
        XCTAssertTrue(cloud.requests.isEmpty)
    }

    func testKeepsLocalTranslationOutputWithoutRepetitionHeuristic() async throws {
        let cloud = CapturingPromptRefiner(result: "云端译文", configured: true)
        let localTranslator = CapturingPromptRefiner(
            result: Array(repeating: "r.translate()", count: 24).joined(separator: " "),
            configured: true
        )
        let localSummarizer = CapturingPromptRefiner(result: "本地总结", configured: true)
        let defaults = Self.defaults(selectedTranslationModelID: CapabilityModelID.madladTranslation)
        let refiner = ScreenshotTextRefiner(
            cloudRefiner: cloud,
            localTranslator: localTranslator,
            localSummarizer: localSummarizer,
            defaults: defaults
        )

        let output = try await refiner.refine(
            TextRefinementRequest(
                text: "let translator = ScreenshotOCRResult",
                systemPrompt: ScreenshotOCRService.translationSystemPrompt,
                model: nil,
                temperature: nil
            )
        )

        XCTAssertEqual(output, Array(repeating: "r.translate()", count: 24).joined(separator: " "))
        XCTAssertEqual(localTranslator.requests.map(\.text), ["let translator = ScreenshotOCRResult"])
        XCTAssertTrue(cloud.requests.isEmpty)
    }

    func testLocalMADLADNormalizesShortLineListsBeforeTranslation() async throws {
        let engine = CapturingMADLADTranslationEngine(result: "设置。语言/语言。语音识别引擎。")
        let refiner = SoniqoMADLADTranslationRefiner(
            engine: engine,
            isModelInstalled: { true }
        )

        let output = try await refiner.refine(
            """
            Settings
            Language / Language
            Speech recognition engine
            """
        )

        XCTAssertEqual(output, "设置。语言/语言。语音识别引擎。")
        XCTAssertEqual(
            engine.requests,
            [
                CapturingMADLADTranslationEngine.Request(
                    text: "Settings. Language / Language. Speech recognition engine.",
                    targetLanguage: "zh"
                ),
            ]
        )
    }

    func testLocalMADLADDefaultInstallCheckUsesCapabilityDownloaderStore() throws {
        let cacheRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: cacheRoot) }
        try FileManager.default.createDirectory(
            at: cacheRoot
                .appendingPathComponent("models", isDirectory: true)
                .appendingPathComponent("aufklarer", isDirectory: true)
                .appendingPathComponent("MADLAD400-3B-MT-MLX", isDirectory: true)
                .appendingPathComponent("int4", isDirectory: true),
            withIntermediateDirectories: true
        )
        try Data().write(
            to: cacheRoot
                .appendingPathComponent("models", isDirectory: true)
                .appendingPathComponent("aufklarer", isDirectory: true)
                .appendingPathComponent("MADLAD400-3B-MT-MLX", isDirectory: true)
                .appendingPathComponent("int4", isDirectory: true)
                .appendingPathComponent("model.safetensors")
        )
        try Data().write(
            to: cacheRoot
                .appendingPathComponent("models", isDirectory: true)
                .appendingPathComponent("aufklarer", isDirectory: true)
                .appendingPathComponent("MADLAD400-3B-MT-MLX", isDirectory: true)
                .appendingPathComponent("int4", isDirectory: true)
                .appendingPathComponent("config.json")
        )
        let downloader = SoniqoCapabilityModelDownloader(cacheBaseDirectory: cacheRoot)

        let refiner = SoniqoMADLADTranslationRefiner(
            engine: CapturingMADLADTranslationEngine(result: "译文"),
            capabilityDownloader: downloader
        )

        XCTAssertTrue(downloader.isInstalled(modelID: CapabilityModelID.madladTranslation))
        XCTAssertTrue(refiner.isConfigured)
    }

    func testLocalMADLADUnwrapsOCRProseBeforeTranslation() async throws {
        let engine = CapturingMADLADTranslationEngine { requestIndex, _ in
            "译文\(requestIndex + 1)"
        }
        let refiner = SoniqoMADLADTranslationRefiner(
            engine: engine,
            isModelInstalled: { true }
        )

        let output = try await refiner.refine(
            """
            Why It Exists
            Modern builders can ship astonishingly far on free tiers:
            LLM APIs, databases, object storage, hosting, auth,
            email,
            monitoring, vector databases, and more.
            The problem is not that these services are unavailable. The
            problem is operational drag.
            Every service has a different console, API key page, quota
            model, onboarding flow, environment variable shape, and
            security convention. AI coding agents can help, but they
            need a structured task, a safe boundary, and a place to
            hand the result back.
            baipiao is that control plane.
            """
        )

        XCTAssertEqual(output, engine.requests.indices.map { "译文\($0 + 1)" }.joined(separator: "\n\n"))
        XCTAssertGreaterThan(engine.requests.count, 1)
        XCTAssertTrue(engine.requests.allSatisfy { !$0.text.contains("\n") })
        XCTAssertFalse(engine.requests.contains { $0.text.contains("The. problem") })
        XCTAssertTrue(
            engine.requests.contains {
                $0.text.contains("The problem is not that these services are unavailable. The problem is operational drag.")
            }
        )
        XCTAssertTrue(
            engine.requests.contains {
                $0.text.contains("auth, email, monitoring, vector databases, and more.")
            }
        )
    }

    func testLocalMADLADTokenBudgetScalesWithInputLength() {
        let shortBudget = MADLADTranslationTokenBudget.maxTokens(for: "Settings.")
        let mediumBudget = MADLADTranslationTokenBudget.maxTokens(
            for: """
            This document describes the product configuration workflow for a desktop application. Users can choose a speech recognition model, configure a language model, and select text-to-speech and translation models.
            """
        )
        let longBudget = MADLADTranslationTokenBudget.maxTokens(
            for: Array(repeating: "This is a long English paragraph for translation.", count: 80).joined(separator: " ")
        )

        XCTAssertEqual(shortBudget, 64)
        XCTAssertGreaterThan(mediumBudget, shortBudget)
        XCTAssertEqual(longBudget, 512)
    }

    func testLocalMADLADChunksLongScreenshotsBeforeTranslation() async throws {
        let engine = CapturingMADLADTranslationEngine { requestIndex, _ in
            "译文\(requestIndex + 1)"
        }
        let refiner = SoniqoMADLADTranslationRefiner(
            engine: engine,
            isModelInstalled: { true }
        )
        let text = Array(
            repeating: "This is a sentence from a long English screenshot that should be translated without truncation.",
            count: 80
        ).joined(separator: " ")

        let output = try await refiner.refine(text)

        XCTAssertGreaterThan(engine.requests.count, 1)
        XCTAssertEqual(output, engine.requests.indices.map { "译文\($0 + 1)" }.joined(separator: "\n\n"))
        XCTAssertTrue(engine.requests.allSatisfy { request in
            MADLADTranslationTokenBudget.maxTokens(for: request.text) <= MADLADTranslationTokenBudget.maximum
        })
    }

    func testUsesAppleSystemTranslationWhenSystemDefaultIsSelected() async throws {
        let cloud = CapturingPromptRefiner(result: "云端译文", configured: true)
        let systemTranslator = CapturingPromptRefiner(result: "系统译文", configured: true)
        let localTranslator = CapturingPromptRefiner(result: "本地译文", configured: true)
        let localSummarizer = CapturingPromptRefiner(result: "本地总结", configured: true)
        let defaults = Self.defaults(selectedTranslationModelID: CapabilityModelID.systemDefaultTranslation)
        let refiner = ScreenshotTextRefiner(
            cloudRefiner: cloud,
            systemTranslator: systemTranslator,
            localTranslator: localTranslator,
            localSummarizer: localSummarizer,
            defaults: defaults
        )

        let output = try await refiner.refine(
            TextRefinementRequest(
                text: "Error 404",
                systemPrompt: ScreenshotOCRService.translationSystemPrompt,
                model: nil,
                temperature: nil
            )
        )

        XCTAssertEqual(output, "系统译文")
        XCTAssertEqual(systemTranslator.requests.map(\.text), ["Error 404"])
        XCTAssertTrue(localTranslator.requests.isEmpty)
        XCTAssertTrue(cloud.requests.isEmpty)
    }

    func testSystemDefaultTranslationRequiresAppleTranslationOrCloudFallback() {
        let cloud = CapturingPromptRefiner(result: "云端译文", configured: false)
        let systemTranslator = CapturingPromptRefiner(result: "系统译文", configured: false)
        let localTranslator = CapturingPromptRefiner(result: "本地译文", configured: false)
        let localSummarizer = CapturingPromptRefiner(result: "本地总结", configured: false)
        let defaults = Self.defaults(selectedTranslationModelID: CapabilityModelID.systemDefaultTranslation)
        let refiner = ScreenshotTextRefiner(
            cloudRefiner: cloud,
            systemTranslator: systemTranslator,
            localTranslator: localTranslator,
            localSummarizer: localSummarizer,
            defaults: defaults
        )

        XCTAssertFalse(refiner.isTranslationConfigured)
    }

    func testTranslationPromptAlwaysTargetsSimplifiedChinese() {
        XCTAssertTrue(ScreenshotOCRService.translationSystemPrompt.contains("翻译成简体中文"))
        XCTAssertFalse(ScreenshotOCRService.translationSystemPrompt.contains("翻译成英文"))
    }

    func testSummaryRequiresConfiguredCloudRefiner() async {
        let cloud = CapturingPromptRefiner(result: "ignored", configured: false)
        let localTranslator = CapturingPromptRefiner(result: "本地译文", configured: true)
        let localSummarizer = CapturingPromptRefiner(result: "本地总结", configured: true)
        let refiner = ScreenshotTextRefiner(
            cloudRefiner: cloud,
            localTranslator: localTranslator,
            localSummarizer: localSummarizer
        )

        do {
            _ = try await refiner.refine(
                TextRefinementRequest(
                    text: "错误 404 - 页面未找到",
                    systemPrompt: ScreenshotOCRService.summarySystemPrompt,
                    model: nil,
                    temperature: nil
                )
            )
            XCTFail("Expected summary without configured LLM to fail")
        } catch {
            XCTAssertEqual(error.localizedDescription, "总结前请先配置模型")
        }
        XCTAssertTrue(cloud.requests.isEmpty)
        XCTAssertTrue(localSummarizer.requests.isEmpty)
    }

    func testSummaryRequiresEnabledCloudRefiner() async {
        let cloud = CapturingPromptRefiner(result: "ignored", configured: true)
        cloud.isEnabled = false
        let localTranslator = CapturingPromptRefiner(result: "本地译文", configured: true)
        let localSummarizer = CapturingPromptRefiner(result: "本地总结", configured: true)
        let refiner = ScreenshotTextRefiner(
            cloudRefiner: cloud,
            localTranslator: localTranslator,
            localSummarizer: localSummarizer
        )

        XCTAssertFalse(refiner.isSummaryConfigured)
        do {
            _ = try await refiner.refine(
                TextRefinementRequest(
                    text: "错误 404 - 页面未找到",
                    systemPrompt: ScreenshotOCRService.summarySystemPrompt,
                    model: nil,
                    temperature: nil
                )
            )
            XCTFail("Expected summary with disabled LLM to fail")
        } catch {
            XCTAssertEqual(error.localizedDescription, "总结前请先配置模型")
        }
        XCTAssertTrue(cloud.requests.isEmpty)
        XCTAssertTrue(localSummarizer.requests.isEmpty)
    }

    func testRejectsHTMLSummaryOutput() async {
        let cloud = CapturingPromptRefiner(
            result: """
            ```html
            <!DOCTYPE html>
            <html><body>不是总结</body></html>
            ```
            """,
            configured: true
        )
        let localTranslator = CapturingPromptRefiner(result: "本地译文", configured: true)
        let localSummarizer = CapturingPromptRefiner(result: "本地总结", configured: true)
        let refiner = ScreenshotTextRefiner(
            cloudRefiner: cloud,
            localTranslator: localTranslator,
            localSummarizer: localSummarizer
        )

        do {
            _ = try await refiner.refine(
                TextRefinementRequest(
                    text: "错误 404 - 页面未找到",
                    systemPrompt: ScreenshotOCRService.summarySystemPrompt,
                    model: nil,
                    temperature: nil
                )
            )
            XCTFail("Expected HTML summary output to be rejected")
        } catch {
            XCTAssertEqual(error.localizedDescription, "总结模型输出了网页/代码内容，请重试或改用其他已配置模型")
        }
    }

    private static func defaults(selectedTranslationModelID: String) -> UserDefaults {
        let suiteName = "test.ScreenshotTextRefinerTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.set(selectedTranslationModelID, forKey: "settings.capabilityModel.translation.selectedModelID")
        return defaults
    }
}

private final class CapturingPromptRefiner: PromptAwareTextRefining, @unchecked Sendable {
    var isEnabled = true
    var isConfigured: Bool
    let result: String
    private(set) var requests: [TextRefinementRequest] = []

    init(result: String, configured: Bool) {
        self.result = result
        self.isConfigured = configured
    }

    func refine(_ text: String) async throws -> String {
        result
    }

    func refine(_ request: TextRefinementRequest) async throws -> String {
        requests.append(request)
        return result
    }
}

private final class CapturingMADLADTranslationEngine: SoniqoMADLADTranslating, @unchecked Sendable {
    struct Request: Equatable {
        let text: String
        let targetLanguage: String
    }

    let translateResult: (Int, Request) -> String
    private(set) var requests: [Request] = []

    init(result: String) {
        self.translateResult = { _, _ in result }
    }

    init(translateResult: @escaping (Int, Request) -> String) {
        self.translateResult = translateResult
    }

    func translate(_ text: String, to targetLanguage: String) async throws -> String {
        let request = Request(text: text, targetLanguage: targetLanguage)
        requests.append(request)
        return translateResult(requests.count - 1, request)
    }
}
