import XCTest
import VoxFlowTextProcessing
@testable import VoxFlowApp

@MainActor
final class StyleOutputFormatLiveSmokeTests: XCTestCase {
    func testLiveLLMRespectsStyleOutputFormatRules() async throws {
        guard ProcessInfo.processInfo.environment["VOICEINPUT_TEST_LLM_STYLE_FORMAT_LIVE"] == "1" else {
            throw XCTSkip("Set VOICEINPUT_TEST_LLM_STYLE_FORMAT_LIVE=1 to run the live style output-format smoke test.")
        }

        let live = try DependencyContainer.live()
        let memory = try DependencyContainer.inMemory()
        let defaults = UserDefaults.standard
        let oldEnabled = defaults.bool(forKey: RepositoryBackedLLMRefiner.enabledDefaultsKey)
        defaults.set(true, forKey: RepositoryBackedLLMRefiner.enabledDefaultsKey)
        defer { defaults.set(oldEnabled, forKey: RepositoryBackedLLMRefiner.enabledDefaultsKey) }

        let refiner = RepositoryBackedLLMRefiner(
            providerRepository: live.llmProviderRepository,
            credentialStore: live.credentialStore,
            defaults: defaults
        )
        guard refiner.isConfigured else {
            throw XCTSkip("No configured local LLM provider/API key is available.")
        }

        try makeDefaultStyle("builtin.chat", in: memory.styleRepository)
        let chatPipeline = DefaultTextProcessingPipeline(
            refiner: refiner,
            styleRepository: memory.styleRepository,
            deterministicSettingsProvider: { .defaults }
        )
        let chat = await chatPipeline.process("等会儿我把链接发你")
        XCTAssertFalse(chat.finalText.hasSuffix("。"), chat.finalText)
        XCTAssertFalse(chat.finalText.hasSuffix("."), chat.finalText)

        let question = await chatPipeline.process("这个可以吗？")
        XCTAssertTrue(
            question.finalText.hasSuffix("？") || question.finalText.hasSuffix("?"),
            question.finalText
        )

        try makeDefaultStyle("builtin.energetic", in: memory.styleRepository)
        let energeticPipeline = DefaultTextProcessingPipeline(
            refiner: refiner,
            styleRepository: memory.styleRepository,
            deterministicSettingsProvider: { .defaults }
        )
        let energetic = await energeticPipeline.process("我们今天继续推进")
        XCTAssertFalse(energetic.finalText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        XCTAssertFalse(energetic.finalText.contains("明天"), energetic.finalText)
    }

    private func makeDefaultStyle(_ id: String, in repository: any StyleRepository) throws {
        let style = try XCTUnwrap(try repository.profile(id: id))
        try repository.save(
            StyleProfileRecord(
                id: style.id,
                name: style.name,
                category: style.category,
                subtitle: style.subtitle,
                mode: style.mode,
                prompt: style.prompt,
                sampleInput: style.sampleInput,
                sampleOutput: style.sampleOutput,
                llmProviderID: style.llmProviderID,
                model: style.model,
                temperature: style.temperature,
                enabled: style.enabled,
                builtIn: style.builtIn,
                isDefault: true,
                createdAt: style.createdAt,
                updatedAt: style.updatedAt,
                outputFormat: style.outputFormat
            )
        )
    }
}
