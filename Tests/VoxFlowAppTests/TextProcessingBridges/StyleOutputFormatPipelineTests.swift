import XCTest
import VoxFlowTextProcessing
@testable import VoxFlowApp

@MainActor
final class StyleOutputFormatPipelineTests: XCTestCase {
    func testDefaultCasualStyleNoEndingOverridesGlobalPunctuationWhenLLMDisabled() async throws {
        let environment = AppEnvironment(container: try DependencyContainer.inMemory())
        let casual = try XCTUnwrap(try environment.styleRepository.profile(id: "builtin.casual"))
        try environment.styleRepository.save(
            StyleProfileRecord(
                id: casual.id,
                name: casual.name,
                category: casual.category,
                subtitle: casual.subtitle,
                mode: casual.mode,
                prompt: casual.prompt,
                sampleInput: casual.sampleInput,
                sampleOutput: casual.sampleOutput,
                llmProviderID: casual.llmProviderID,
                model: casual.model,
                temperature: casual.temperature,
                enabled: casual.enabled,
                builtIn: casual.builtIn,
                isDefault: true,
                createdAt: casual.createdAt,
                updatedAt: casual.updatedAt,
                outputFormat: casual.outputFormat
            )
        )
        let settings = DeterministicTextProcessingSettings(
            enabled: true,
            punctuationOptimization: true,
            cjkLatinSpacing: false,
            autoCapitalization: false
        )
        let pipeline = DefaultTextProcessingPipeline(
            refiner: DisabledStyleOutputFormatRefiner(),
            styleRepository: environment.styleRepository,
            deterministicSettingsProvider: { settings }
        )

        let result = await pipeline.process("等会儿我把链接发你")

        XCTAssertEqual(result.finalText, "等会儿我把链接发你")
        XCTAssertEqual(
            result.trace?.deterministic?.postLLM.enabledProcessors,
            ["punctuation_optimization", "style_output_format"]
        )
        XCTAssertEqual(
            result.trace?.deterministic?.postLLM.changedProcessorIDs,
            ["punctuation_optimization", "style_output_format"]
        )
    }

    func testNoStyleFallsBackToGlobalPunctuation() async {
        let settings = DeterministicTextProcessingSettings(
            enabled: true,
            punctuationOptimization: true,
            cjkLatinSpacing: false,
            autoCapitalization: false
        )
        let pipeline = DefaultTextProcessingPipeline(
            refiner: DisabledStyleOutputFormatRefiner(),
            deterministicSettingsProvider: { settings }
        )

        let result = await pipeline.process("等会儿我把链接发你")

        XCTAssertEqual(result.finalText, "等会儿我把链接发你。")
        XCTAssertEqual(
            result.trace?.deterministic?.postLLM.enabledProcessors,
            ["punctuation_optimization"]
        )
    }

    func testCustomDefaultStyleWithoutStoredOutputFormatUsesSystemOutputFormat() async throws {
        let environment = AppEnvironment(container: try DependencyContainer.inMemory())
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        try environment.styleRepository.save(
            StyleProfileRecord(
                id: "custom.default",
                name: "Custom",
                category: "custom",
                subtitle: nil,
                mode: "custom",
                prompt: "Keep the text tidy.",
                sampleInput: nil,
                sampleOutput: nil,
                llmProviderID: nil,
                model: nil,
                temperature: 0.2,
                enabled: true,
                builtIn: false,
                isDefault: true,
                createdAt: now,
                updatedAt: now,
                outputFormat: nil
            )
        )
        let settings = DeterministicTextProcessingSettings(
            enabled: true,
            punctuationOptimization: false,
            cjkLatinSpacing: false,
            autoCapitalization: false
        )
        let pipeline = DefaultTextProcessingPipeline(
            refiner: DisabledStyleOutputFormatRefiner(),
            styleRepository: environment.styleRepository,
            deterministicSettingsProvider: { settings }
        )

        let result = await pipeline.process("今天天气不错")

        XCTAssertEqual(result.finalText, "今天天气不错。")
        XCTAssertEqual(
            result.trace?.deterministic?.postLLM.enabledProcessors,
            ["punctuation_optimization", "auto_capitalization", "style_output_format"]
        )
    }
}

private final class DisabledStyleOutputFormatRefiner: TextRefining, @unchecked Sendable {
    let isEnabled = false
    let isConfigured = false

    func refine(_ text: String) async throws -> String {
        text
    }
}
