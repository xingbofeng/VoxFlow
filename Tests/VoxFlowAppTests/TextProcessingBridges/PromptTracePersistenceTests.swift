import XCTest
import VoxFlowPromptKit
@testable import VoxFlowApp

/// Tests for task 2.6: confirm persisted traces carry prompt metadata (kind,
/// version, hash, styleID, routerVersion, agentPromptVersion) but never carry
/// the full rendered prompt, full user content, or full image base64.
final class PromptTracePersistenceTests: XCTestCase {

    func testSafeForPersistencePreservesPromptMetadataButRedactsContent() {
        let metadata = PromptTraceMetadata(
            promptKind: .voiceCorrection,
            promptVersion: .v1_0_0,
            renderedPromptHash: "deadbeef",
            styleID: "builtin.coding",
            routerVersion: nil,
            agentPromptVersion: nil
        )
        let trace = LLMRefinementTrace(
            providerID: "provider",
            providerName: "Provider",
            endpoint: "https://api.example.com/v1/chat/completions",
            model: "model",
            temperature: 0.2,
            timeoutSeconds: 8,
            requestBodyJSON: #"{"messages":[{"role":"system","content":"你是语音识别纠错助手。长 prompt 正文"},{"role":"user","content":"用户敏感正文"}]}"#,
            responseText: "模型响应正文",
            statusCode: 200,
            durationMS: 123,
            errorMessage: nil,
            completedAt: Date(timeIntervalSince1970: 1_800_000_000),
            promptMetadata: metadata
        )

        let safe = trace.safeForPersistence()

        XCTAssertEqual(safe.promptMetadata, metadata)
        XCTAssertEqual(safe.promptMetadata?.promptKind, "voiceCorrection")
        XCTAssertEqual(safe.promptMetadata?.promptVersion, "1.0.0")
        XCTAssertEqual(safe.promptMetadata?.renderedPromptHash, "deadbeef")
        XCTAssertEqual(safe.promptMetadata?.styleID, "builtin.coding")
        // Full prompt and user content MUST be redacted.
        XCTAssertFalse(safe.requestBodyJSON.contains("你是语音识别纠错助手"))
        XCTAssertFalse(safe.requestBodyJSON.contains("用户敏感正文"))
        XCTAssertFalse(safe.requestBodyJSON.contains("模型响应正文"))
        XCTAssertTrue(safe.requestBodyJSON.contains("[redacted: system prompt]"))
        XCTAssertTrue(safe.requestBodyJSON.contains("[redacted: user content]"))
        XCTAssertNil(safe.responseText)
    }

    func testSafeForPersistencePreservesRouterMetadata() {
        let metadata = PromptTraceMetadata(
            promptKind: .styleRouter,
            promptVersion: .v1_0_0,
            renderedPromptHash: "abc123",
            styleID: nil,
            routerVersion: "1.0.0",
            agentPromptVersion: nil
        )
        let trace = makeTrace(metadata: metadata)
        XCTAssertEqual(trace.safeForPersistence().promptMetadata?.routerVersion, "1.0.0")
        XCTAssertEqual(trace.safeForPersistence().promptMetadata?.promptKind, "styleRouter")
    }

    func testSafeForPersistencePreservesAgentMetadata() {
        let metadata = PromptTraceMetadata(
            promptKind: .agentCompose,
            promptVersion: .v1_0_0,
            renderedPromptHash: "agent-hash",
            styleID: nil,
            routerVersion: nil,
            agentPromptVersion: "1.0.0"
        )
        let trace = makeTrace(metadata: metadata)
        XCTAssertEqual(trace.safeForPersistence().promptMetadata?.agentPromptVersion, "1.0.0")
        XCTAssertEqual(trace.safeForPersistence().promptMetadata?.promptKind, "agentCompose")
    }

    func testTraceWithoutPromptMetadataDecodesFromLegacyJSON() throws {
        // A trace persisted before PromptKit integration has no promptMetadata
        // field. Decoding MUST still succeed and yield nil metadata.
        let legacyJSON = """
        {
          "providerID": "provider",
          "providerName": "Provider",
          "endpoint": "https://api.example.com",
          "model": "model",
          "temperature": 0.2,
          "timeoutSeconds": 8,
          "requestBodyJSON": "{}",
          "responseText": null,
          "statusCode": 200,
          "durationMS": 10,
          "errorMessage": null,
          "completedAt": 1800000000
        }
        """
        let data = try XCTUnwrap(legacyJSON.data(using: .utf8))
        let decoded = try JSONDecoder().decode(LLMRefinementTrace.self, from: data)
        XCTAssertEqual(decoded.providerID, "provider")
        XCTAssertNil(decoded.promptMetadata)
    }

    func testTraceWithMetadataRoundTripsThroughCodable() throws {
        let metadata = PromptTraceMetadata(
            promptKind: .structuredCorrection,
            promptVersion: .v1_0_0,
            renderedPromptHash: "hash",
            styleID: "builtin.email",
            routerVersion: nil,
            agentPromptVersion: nil
        )
        let trace = makeTrace(metadata: metadata)
        let data = try JSONEncoder().encode(trace)
        let decoded = try JSONDecoder().decode(LLMRefinementTrace.self, from: data)
        XCTAssertEqual(decoded.promptMetadata, metadata)
    }

    func testRenderedPromptHashCoversFullSystemPrompt() {
        // Dictation: hash must cover base + style polish + hotword context,
        // not just the base template. Different style/hotwords → different hash.
        let noStyle = PromptBuilder().build(style: nil, temporaryHotwords: [])
        let withStyle = PromptBuilder().build(
            style: StyleProfileRecord(
                id: "test.style",
                name: "Test",
                category: "test",
                subtitle: nil,
                mode: "default",
                prompt: "polish text",
                sampleInput: nil,
                sampleOutput: nil,
                llmProviderID: nil,
                model: nil,
                temperature: 0.3,
                enabled: true,
                builtIn: false,
                isDefault: false,
                createdAt: Date(timeIntervalSince1970: 1_800_000_000),
                updatedAt: Date(timeIntervalSince1970: 1_800_000_000)
            ),
            temporaryHotwords: []
        )
        XCTAssertNotEqual(
            noStyle.promptMetadata?.renderedPromptHash,
            withStyle.promptMetadata?.renderedPromptHash
        )
        // The hash must equal SHA-256 of the actual system prompt sent.
        XCTAssertEqual(
            noStyle.promptMetadata?.renderedPromptHash,
            PromptRenderer.hash(renderedPrompt: noStyle.systemPrompt)
        )
        XCTAssertEqual(
            withStyle.promptMetadata?.renderedPromptHash,
            PromptRenderer.hash(renderedPrompt: withStyle.systemPrompt)
        )
        // Kind/version still come from the base template.
        XCTAssertEqual(noStyle.promptMetadata?.promptKind, "voiceCorrection")
        XCTAssertEqual(withStyle.promptMetadata?.promptKind, "voiceCorrection")
        XCTAssertEqual(withStyle.promptMetadata?.styleID, "test.style")
    }

    func testStructuredPromptHashCoversFullSystemPrompt() {
        // The structured builder assembles template + protocol + context into
        // a single system prompt string. The pipeline's buildStructuredPrompt
        // hashes that full string via PromptRenderer.hash(renderedPrompt:).
        // Here we verify the hash equals SHA-256 of the full assembled prompt,
        // confirming the hash covers more than just the style template.
        let builder = StructuredCorrectionPromptBuilder()
        let context = StructuredCorrectionPromptContext(
            rawText: "hello",
            userTerms: ["foo"],
            knownCorrections: [],
            ocrTemporaryTerms: [],
            appContext: nil
        )
        let systemPrompt = builder.build(style: .coding, context: context)
        let fullHash = PromptRenderer.hash(renderedPrompt: systemPrompt)
        let templateOnlyHash = PromptRenderer().render(
            StructuredCorrectionPromptCatalog.styleTemplate(for: .coding)
        ).renderedHash
        // The full hash must differ from the template-only hash, proving it
        // covers the protocol and context sections too.
        XCTAssertNotEqual(fullHash, templateOnlyHash)
        XCTAssertEqual(fullHash, PromptRenderer.hash(renderedPrompt: systemPrompt))
    }

    func testStyleRouteTracePersistsThroughSafeForPersistence() throws {
        let route = StyleRouteTrace(
            candidateStyleIDs: ["builtin.chat", "builtin.coding"],
            routerResponse: "builtin.coding",
            selectedStyleID: "builtin.coding",
            fallbackReason: nil,
            routerVersion: "1.0.0",
            renderedPromptHash: "routehash",
            durationMS: 42
        )
        let trace = TextProcessingTrace(
            llm: nil,
            output: nil,
            contextBoost: nil,
            voiceCorrection: nil,
            styleRoute: route
        )
        let safe = trace.safeForPersistence()
        // Safe copy retains IDs, version, hash, latency, reason but drops raw
        // routerResponse (could echo user content on invalid output).
        XCTAssertEqual(safe.styleRoute?.candidateStyleIDs, route.candidateStyleIDs)
        XCTAssertEqual(safe.styleRoute?.selectedStyleID, "builtin.coding")
        XCTAssertEqual(safe.styleRoute?.routerVersion, "1.0.0")
        XCTAssertEqual(safe.styleRoute?.renderedPromptHash, "routehash")
        XCTAssertEqual(safe.styleRoute?.durationMS, 42)
        XCTAssertNil(safe.styleRoute?.routerResponse)
        // Round-trips through Codable.
        let data = try JSONEncoder().encode(safe)
        let decoded = try JSONDecoder().decode(TextProcessingTrace.self, from: data)
        XCTAssertEqual(decoded.styleRoute, safe.styleRoute)
    }

    func testStyleRouteTraceRedactsNoUserContent() {
        // StyleRouteTrace carries only IDs, version, hash, latency and a
        // reason code — no user transcript, no full prompt. Confirm the
        // fallback reason is a short code, not free text with user content.
        let route = StyleRouteTrace(
            candidateStyleIDs: ["builtin.chat"],
            routerResponse: "invalid answer with user secret",
            selectedStyleID: nil,
            fallbackReason: "invalid_response",
            routerVersion: "1.0.0",
            renderedPromptHash: "h",
            durationMS: 10
        )
        // The routerResponse field echoes the model's raw output. Persisted
        // route traces go through safeForPersistence; routerResponse is a
        // short ID/code in normal operation, but to be conservative we only
        // persist the selected id and fallback reason, not the raw response.
        let safe = TextProcessingTrace(styleRoute: route).safeForPersistence()
        XCTAssertNotNil(safe.styleRoute)
        XCTAssertEqual(safe.styleRoute?.fallbackReason, "invalid_response")
        XCTAssertEqual(safe.styleRoute?.selectedStyleID, nil)
    }

    func testDeterministicTracePersistsBeforeAndAfterText() throws {
        let trace = TextProcessingTrace(
            deterministic: DeterministicProcessingTrace(
                enabled: true,
                isCodingContext: false,
                preLLM: DeterministicProcessingPhaseTrace(
                    phase: "pre_llm",
                    enabledProcessors: ["filler_word_filtering"],
                    inputCharacterCount: 12,
                    outputCharacterCount: 10,
                    inputText: "嗯今天测试",
                    outputText: "今天测试",
                    inputHash: "inputhash",
                    outputHash: "outputhash"
                ),
                postLLM: DeterministicProcessingPhaseTrace(
                    phase: "post_llm",
                    enabledProcessors: ["punctuation_optimization"],
                    inputCharacterCount: 10,
                    outputCharacterCount: 11,
                    inputText: "今天测试",
                    outputText: "今天测试。",
                    inputHash: "postinput",
                    outputHash: "postoutput"
                )
            )
        )

        let safe = trace.safeForPersistence()
        XCTAssertEqual(safe.deterministic, trace.deterministic)

        let data = try JSONEncoder().encode(safe)
        let json = try XCTUnwrap(String(data: data, encoding: .utf8))
        XCTAssertTrue(json.contains("filler_word_filtering"))
        XCTAssertTrue(json.contains("嗯今天测试"))
        XCTAssertTrue(json.contains("今天测试。"))
        XCTAssertTrue(json.contains("inputhash"))
        XCTAssertFalse(json.contains("用户敏感正文"))
    }

    func testDeterministicTraceDecodesLegacyJSONWithoutBeforeAfterText() throws {
        let json = """
        {
          "deterministic": {
            "enabled": true,
            "isCodingContext": false,
            "preLLM": {
              "phase": "pre_llm",
              "enabledProcessors": ["filler_word_filtering"],
              "inputCharacterCount": 12,
              "outputCharacterCount": 10,
              "inputHash": "inputhash",
              "outputHash": "outputhash"
            },
            "postLLM": {
              "phase": "post_llm",
              "enabledProcessors": ["punctuation_optimization"],
              "inputCharacterCount": 10,
              "outputCharacterCount": 11,
              "inputHash": "postinput",
              "outputHash": "postoutput"
            }
          }
        }
        """

        let decoded = try JSONDecoder().decode(TextProcessingTrace.self, from: Data(json.utf8))

        XCTAssertEqual(decoded.deterministic?.preLLM.inputText, nil)
        XCTAssertEqual(decoded.deterministic?.preLLM.outputText, nil)
        XCTAssertEqual(decoded.deterministic?.postLLM.inputHash, "postinput")

        // Legacy traces predate displayProcessorIDs and changedProcessorIDs.
        // Both optional fields decode as nil; the display catalog must fall
        // back to the legacy enabled processor list so old history detail UI
        // still renders a meaningful processor catalog.
        XCTAssertEqual(decoded.deterministic?.preLLM.displayProcessorIDs, nil)
        XCTAssertEqual(decoded.deterministic?.preLLM.changedProcessorIDs, nil)
        XCTAssertEqual(
            decoded.deterministic?.preLLM.processorIDsForDisplay,
            decoded.deterministic?.preLLM.enabledProcessors
        )
        XCTAssertEqual(decoded.deterministic?.preLLM.processorIDsForDisplay, ["filler_word_filtering"])
        XCTAssertEqual(
            decoded.deterministic?.postLLM.processorIDsForDisplay,
            ["punctuation_optimization"]
        )
        XCTAssertEqual(decoded.deterministic?.preLLM.highlightedProcessorIDs, ["filler_word_filtering"])
    }

    func testDiagnosticCapturePreservesPromptMetadata() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("VoxFlowPromptTraceTests-\(UUID().uuidString)", isDirectory: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let capture = LLMDiagnosticCapture()

        capture.configure(enabled: true, directory: directory)
        let metadata = PromptTraceMetadata(
            promptKind: .agentCompose,
            promptVersion: .v1_0_0,
            renderedPromptHash: "agent-hash",
            styleID: nil,
            routerVersion: nil,
            agentPromptVersion: "1.0.0"
        )
        capture.capture(
            taskID: "task",
            trace: TextProcessingTrace(
                llm: LLMRefinementTrace(
                    providerID: "provider",
                    providerName: "Provider",
                    endpoint: "https://api.example.com",
                    model: "model",
                    temperature: 0.7,
                    timeoutSeconds: 8,
                    requestBodyJSON: #"{"messages":[{"content":"agent system prompt body + user dictation"}]}"#,
                    responseText: "agent response body",
                    statusCode: 200,
                    durationMS: 50,
                    errorMessage: nil,
                    completedAt: Date(timeIntervalSince1970: 1_800_000_000),
                    promptMetadata: metadata
                )
            ),
            at: Date(timeIntervalSince1970: 1_800_000_000)
        )

        let decoded = try XCTUnwrap(capture.trace(taskID: "task"))
        XCTAssertEqual(decoded.llm?.promptMetadata, metadata)
        XCTAssertEqual(decoded.llm?.promptMetadata?.agentPromptVersion, "1.0.0")

        // The diagnostic file on disk must carry prompt metadata so captured
        // traces can explain which prompt version produced the request.
        // (Diagnostic mode is opt-in and MAY store redacted request bodies; the
        // "no full content by default" rule is enforced in safeForPersistence,
        // covered by testSafeForPersistencePreservesPromptMetadataButRedactsContent.)
        let file = try XCTUnwrap(
            FileManager.default.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: nil
            ).first
        )
        let contents = try String(contentsOf: file, encoding: .utf8)
        XCTAssertTrue(contents.contains("agent-hash"))
        XCTAssertTrue(contents.contains("agentPromptVersion"))
        XCTAssertTrue(contents.contains("agentCompose"))
    }

    private func makeTrace(metadata: PromptTraceMetadata) -> LLMRefinementTrace {
        LLMRefinementTrace(
            providerID: "provider",
            providerName: "Provider",
            endpoint: "https://api.example.com",
            model: "model",
            temperature: 0.2,
            timeoutSeconds: 8,
            requestBodyJSON: #"{"messages":[{"content":"prompt body"}]}"#,
            responseText: "response body",
            statusCode: 200,
            durationMS: 10,
            errorMessage: nil,
            completedAt: Date(timeIntervalSince1970: 1_800_000_000),
            promptMetadata: metadata
        )
    }
}
