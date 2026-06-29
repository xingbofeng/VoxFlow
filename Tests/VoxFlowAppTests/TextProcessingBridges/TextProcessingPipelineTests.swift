import XCTest
import VoxFlowContextBoost
import VoxFlowVoiceCorrection
import VoxFlowTextProcessing
@testable import VoxFlowApp

@MainActor
final class TextProcessingPipelineTests: XCTestCase {
    func testDisabledRefinerReturnsOriginalText() async {
        let refiner = StubTextRefiner(isEnabled: false, isConfigured: true)
        let pipeline = DefaultTextProcessingPipeline(refiner: refiner)

        let result = await pipeline.process("原始文本")

        XCTAssertEqual(result.rawText, "原始文本")
        XCTAssertEqual(result.finalText, "原始文本")
        XCTAssertEqual(result.warnings, [])
    }

    func testRefinerFailureFallsBackToOriginalText() async {
        let refiner = StubTextRefiner(
            isEnabled: true,
            isConfigured: true,
            result: .failure(TestError.expected)
        )
        let pipeline = DefaultTextProcessingPipeline(refiner: refiner)

        let result = await pipeline.process("不要丢失")

        XCTAssertEqual(result.finalText, "不要丢失")
        XCTAssertEqual(result.warnings, ["llm_refinement_failed"])
    }

    func testConfiguredRefinerReturnsRefinedText() async {
        let refiner = StubTextRefiner(
            isEnabled: true,
            isConfigured: true,
            result: .success("修正文本")
        )
        let pipeline = DefaultTextProcessingPipeline(refiner: refiner)

        let result = await pipeline.process("原始文本")

        XCTAssertEqual(result.finalText, "修正文本")
        XCTAssertEqual(result.warnings, [])
    }

    func testPipelineBuildsPromptWithDefaultStyle() async throws {
        let environment = AppEnvironment(container: try DependencyContainer.inMemory())
        let style = try XCTUnwrap(try environment.styleRepository.profile(id: "builtin.coding"))
        try environment.styleRepository.save(
            StyleProfileRecord(
                id: style.id,
                name: style.name,
                category: style.category,
                subtitle: style.subtitle,
                mode: style.mode,
                prompt: style.prompt,
                sampleInput: style.sampleInput,
                sampleOutput: style.sampleOutput,
                llmProviderID: "provider",
                model: "model-a",
                temperature: 0.2,
                enabled: style.enabled,
                builtIn: style.builtIn,
                isDefault: true,
                createdAt: style.createdAt,
                updatedAt: style.updatedAt
            )
        )
        let refiner = PromptAwareStubTextRefiner(result: .success("Python"))
        let pipeline = DefaultTextProcessingPipeline(
            refiner: refiner,
            styleRepository: environment.styleRepository,
            promptBuilder: PromptBuilder()
        )

        let result = await pipeline.process("配森")

        XCTAssertEqual(result.finalText, "Python")
        XCTAssertNil(result.llmProviderID)
        XCTAssertEqual(result.styleID, "builtin.coding")
        XCTAssertEqual(refiner.requests.map(\.text), ["配森"])
        XCTAssertEqual(refiner.requests.first?.model, "model-a")
        XCTAssertEqual(refiner.requests.first?.temperature, 0.2)
        XCTAssertTrue(refiner.requests.first?.systemPrompt.contains("Vibe Coding") == true)
    }

    func testPipelineSelectsStyleByTargetApplicationRule() async throws {
        let environment = AppEnvironment(container: try DependencyContainer.inMemory())
        try StyleViewModel(environment: environment).saveAppStyleRule(
            id: nil,
            bundleID: "com.example.editor",
            appName: "Editor",
            styleID: "builtin.email"
        )
        let refiner = PromptAwareStubTextRefiner(result: .success("邮件文本"))
        let pipeline = DefaultTextProcessingPipeline(
            refiner: refiner,
            styleSelector: SettingsBackedStyleSelector(
                styleRepository: environment.styleRepository,
                settingsRepository: environment.settingsRepository
            ),
            promptBuilder: PromptBuilder()
        )

        let result = await pipeline.process(
            "邮件文本",
            target: DictationTarget(bundleID: "com.example.editor", appName: "Editor")
        )

        XCTAssertEqual(result.styleID, "builtin.email")
        let emailStyle = try XCTUnwrap(BuiltInStyleCatalog.profile(id: "builtin.email"))
        XCTAssertTrue(refiner.requests.first?.systemPrompt.contains(emailStyle.prompt) == true)
    }

    func testPipelineUsesRequestLocalTraceWhenRefinerProvidesIt() async {
        let localTrace = Self.trace(providerID: "local-provider", model: "local-model")
        let refiner = TraceablePromptAwareStubTextRefiner(
            result: .success(
                TextRefinementTraceResult(
                    text: "修正文本",
                    providerID: "local-provider",
                    trace: localTrace
                )
            ),
            lastTrace: Self.trace(providerID: "poison-provider", model: "poison-model")
        )
        let pipeline = DefaultTextProcessingPipeline(refiner: refiner)

        let result = await pipeline.process("原始文本")

        XCTAssertEqual(result.finalText, "修正文本")
        XCTAssertEqual(result.llmProviderID, "local-provider")
        XCTAssertEqual(result.trace?.llm?.providerID, "local-provider")
        XCTAssertEqual(result.trace?.llm?.model, "local-model")
    }

    func testPipelineUsesRequestLocalTraceWhenStreamingRefinerProvidesIt() async {
        let localTrace = Self.trace(providerID: "stream-local-provider", model: "stream-local-model")
        let refiner = TraceableStreamingPromptAwareStubTextRefiner(
            snapshots: ["修", "修正文本"],
            providerID: "stream-local-provider",
            trace: localTrace,
            lastTrace: Self.trace(providerID: "poison-provider", model: "poison-model")
        )
        let pipeline = DefaultTextProcessingPipeline(refiner: refiner)

        let result = await pipeline.process("原始文本")

        XCTAssertEqual(result.finalText, "修正文本")
        XCTAssertEqual(result.llmProviderID, "stream-local-provider")
        XCTAssertEqual(result.trace?.llm?.providerID, "stream-local-provider")
        XCTAssertEqual(result.trace?.llm?.model, "stream-local-model")
    }

    func testPipelineAcceptsUnchangedStyledOutputWithoutRetry() async throws {
        let environment = AppEnvironment(container: try DependencyContainer.inMemory())
        let refiner = SequencedPromptAwareRefiner(
            results: [
                "小兔子乖乖把门开开快点开开我要进来",
            ]
        )
        let pipeline = DefaultTextProcessingPipeline(
            refiner: refiner,
            styleRepository: environment.styleRepository
        )

        let result = await pipeline.process("小兔子乖乖把门开开快点开开我要进来")

        XCTAssertEqual(result.finalText, "小兔子乖乖把门开开快点开开我要进来")
        XCTAssertEqual(refiner.requests.count, 1)
        XCTAssertFalse(result.warnings.contains("llm_echo_retry"))
    }

    func testPipelineInjectsCurrentWindowContextHotwordsIntoLLMPrompt() async {
        let refiner = PromptAwareStubTextRefiner(result: .success("Qwen3-ASR"))
        let contextProvider = StubCurrentWindowOCRContextProvider(
            snapshot: OCRContextSnapshot(
                bundleID: "com.example.editor",
                appName: "Editor",
                windowTitle: "Release Notes",
                capturedAt: Date(timeIntervalSince1970: 1_800_000_000),
                hotwords: [
                    temporaryHotword("Qwen3-ASR"),
                    temporaryHotword("Project Apollo"),
                ],
                ocrCharacterCount: 120,
                candidateCount: 18
            )
        )
        let pipeline = DefaultTextProcessingPipeline(
            refiner: refiner,
            contextBoostProvider: contextProvider,
            contextBoostEnabled: { true }
        )

        let result = await pipeline.process(
            "去问三 ASR",
            target: DictationTarget(bundleID: "com.example.editor", appName: "Editor", pid: 42)
        )

        XCTAssertEqual(result.finalText, "Qwen3-ASR")
        XCTAssertEqual(contextProvider.requestedTargets.map { $0?.bundleID }, ["com.example.editor"])
        XCTAssertTrue(refiner.requests.first?.systemPrompt.contains("Temporary screen context terms") == true)
        XCTAssertTrue(refiner.requests.first?.systemPrompt.contains(#""Qwen3-ASR""#) == true)
        XCTAssertTrue(refiner.requests.first?.systemPrompt.contains(#""Project Apollo""#) == true)
        XCTAssertEqual(result.trace?.contextBoost?.ocrCharacterCount, 120)
        XCTAssertEqual(result.trace?.contextBoost?.candidateCount, 18)
        XCTAssertEqual(result.trace?.contextBoost?.hotwordDetails.first?.text, "Qwen3-ASR")
        XCTAssertEqual(result.trace?.contextBoost?.hotwordDetails.first?.score, 5)
        XCTAssertEqual(result.trace?.contextBoost?.hotwordDetails.first?.source, "ocrShape")
        XCTAssertEqual(result.trace?.contextBoost?.hotwordDetails.first?.evidenceReasons, ["test"])
    }

    func testPipelineDoesNotCaptureContextWhenContextBoostToggleIsDisabled() async {
        let refiner = PromptAwareStubTextRefiner(result: .success("原始文本"))
        let contextProvider = StubCurrentWindowOCRContextProvider(
            snapshot: OCRContextSnapshot(
                bundleID: "com.example.editor",
                appName: "Editor",
                windowTitle: "Release Notes",
                capturedAt: Date(timeIntervalSince1970: 1_800_000_000),
                hotwords: [temporaryHotword("Qwen3-ASR")]
            )
        )
        let pipeline = DefaultTextProcessingPipeline(
            refiner: refiner,
            contextBoostProvider: contextProvider,
            contextBoostEnabled: { false }
        )

        let result = await pipeline.process(
            "原始文本",
            target: DictationTarget(bundleID: "com.example.editor", appName: "Editor", pid: 42)
        )

        XCTAssertEqual(result.finalText, "原始文本")
        XCTAssertTrue(contextProvider.requestedTargets.isEmpty)
        XCTAssertFalse(refiner.requests.first?.systemPrompt.contains("Temporary screen context terms") == true)
        XCTAssertNil(result.trace?.contextBoost)
    }

    func testPipelineDoesNotCaptureContextWhenCorrectionContextIsSecure() async {
        let refiner = PromptAwareStubTextRefiner(result: .success("原始文本"))
        let contextProvider = StubCurrentWindowOCRContextProvider(
            snapshot: OCRContextSnapshot(
                bundleID: "com.example.password-manager",
                appName: "Password Manager",
                windowTitle: "Secret",
                capturedAt: Date(timeIntervalSince1970: 1_800_000_000),
                hotwords: [temporaryHotword("secret-token")]
            )
        )
        let pipeline = DefaultTextProcessingPipeline(
            refiner: refiner,
            contextBoostProvider: contextProvider,
            contextBoostEnabled: { true }
        )

        let result = await pipeline.process(
            "原始文本",
            target: DictationTarget(bundleID: "com.example.password-manager", appName: "Password Manager", pid: 42),
            correctionContext: CorrectionContext(
                mode: .dictation,
                providerID: "apple",
                modelID: nil,
                language: nil,
                bundleIdentifier: "com.example.password-manager",
                isFinalTranscript: true,
                isSecureField: true
            )
        )

        XCTAssertEqual(result.finalText, "原始文本")
        XCTAssertTrue(contextProvider.requestedTargets.isEmpty)
        XCTAssertNil(result.trace?.contextBoost)
        XCTAssertFalse(refiner.requests.first?.systemPrompt.contains("secret-token") == true)
    }

    func testPipelineRecordsContextBoostTraceWhenEnabledButNoOCRContextIsAvailable() async {
        let refiner = PromptAwareStubTextRefiner(result: .success("原始文本"))
        let contextProvider = StubCurrentWindowOCRContextProvider(snapshot: nil)
        let pipeline = DefaultTextProcessingPipeline(
            refiner: refiner,
            contextBoostProvider: contextProvider,
            contextBoostEnabled: { true }
        )

        let result = await pipeline.process(
            "原始文本",
            target: DictationTarget(bundleID: "com.example.editor", appName: "Editor", pid: 42)
        )

        XCTAssertEqual(result.trace?.contextBoost?.appName, "Editor")
        XCTAssertEqual(result.trace?.contextBoost?.bundleID, "com.example.editor")
        XCTAssertEqual(result.trace?.contextBoost?.hotwords, [])
        XCTAssertEqual(result.trace?.contextBoost?.failureReason, "no_ocr_context")
        XCTAssertFalse(result.trace?.contextBoost?.appliedToLLMPrompt == true)
        XCTAssertFalse(refiner.requests.first?.systemPrompt.contains("Temporary screen context terms") == true)
    }

    func testPipelineRecordsContextBoostTimeoutWhenOCRContextIsSlow() async {
        let refiner = PromptAwareStubTextRefiner(result: .success("原始文本"))
        let contextProvider = StubCurrentWindowOCRContextProvider(
            snapshot: OCRContextSnapshot(
                bundleID: "com.example.editor",
                appName: "Editor",
                windowTitle: "Release Notes",
                capturedAt: Date(timeIntervalSince1970: 1_800_000_000),
                hotwords: [temporaryHotword("Qwen3-ASR")]
            ),
            delayNanoseconds: 50_000_000
        )
        let pipeline = DefaultTextProcessingPipeline(
            refiner: refiner,
            contextBoostProvider: contextProvider,
            contextBoostEnabled: { true },
            contextBoostTimeoutNanoseconds: 1
        )

        let result = await pipeline.process(
            "原始文本",
            target: DictationTarget(bundleID: "com.example.editor", appName: "Editor", pid: 42)
        )

        XCTAssertEqual(result.trace?.contextBoost?.failureReason, "context_boost_timeout")
        XCTAssertEqual(result.trace?.contextBoost?.hotwords, [])
        XCTAssertFalse(refiner.requests.first?.systemPrompt.contains("Qwen3-ASR") == true)
    }

    func testPipelineUsesPrefetchedContextWithoutStartingPostFinalCapture() async {
        let refiner = PromptAwareStubTextRefiner(result: .success("原始文本"))
        let legacyProvider = StubCurrentWindowOCRContextProvider(snapshot: nil)
        let snapshot = OCRContextSnapshot(
            bundleID: "com.example.editor",
            appName: "Editor",
            windowTitle: "Release Notes",
            capturedAt: Date(timeIntervalSince1970: 1_800_000_000),
            hotwords: [temporaryHotword("Qwen3-ASR")]
        )
        let coordinator = ContextBoostPrefetchCoordinator(
            sessionProvider: PipelinePrefetchSessionProvider(
                session: PipelinePrefetchSession(outcome: .captured(snapshot))
            )
        )
        let pipeline = DefaultTextProcessingPipeline(
            refiner: refiner,
            contextBoostProvider: legacyProvider,
            contextBoostCoordinator: coordinator,
            contextBoostEnabled: { true }
        )
        let target = DictationTarget(
            bundleID: "com.example.editor",
            appName: "Editor",
            pid: 42
        )

        pipeline.prepareContextBoost(target: target)
        await Task.yield()
        let result = await pipeline.process("原始文本", target: target)

        XCTAssertEqual(result.trace?.contextBoost?.hotwords, ["Qwen3-ASR"])
        XCTAssertTrue(refiner.requests.first?.systemPrompt.contains("Qwen3-ASR") == true)
        XCTAssertTrue(legacyProvider.requestedTargets.isEmpty)
    }

    func testPipelineCancelsPrefetchWhenRefinerBecomesDisabledBeforeProcessing() async {
        let refiner = PromptAwareStubTextRefiner(result: .success("原始文本"))
        let session = PipelinePrefetchSession(outcome: .noContext)
        let coordinator = ContextBoostPrefetchCoordinator(
            sessionProvider: PipelinePrefetchSessionProvider(session: session)
        )
        let pipeline = DefaultTextProcessingPipeline(
            refiner: refiner,
            contextBoostCoordinator: coordinator,
            contextBoostEnabled: { true }
        )
        let target = DictationTarget(bundleID: "com.example.editor", appName: "Editor", pid: 42)

        pipeline.prepareContextBoost(target: target)
        await Task.yield()
        refiner.isEnabled = false
        _ = await pipeline.process("原始文本", target: target)

        XCTAssertEqual(session.cancelCallCount, 1)
    }

    func testPipelineSkipsContextBoostForVoxFlowWindows() async {
        let refiner = PromptAwareStubTextRefiner(result: .success("原始文本"))
        let contextProvider = StubCurrentWindowOCRContextProvider(
            snapshot: OCRContextSnapshot(
                bundleID: ProductBrand.bundleIdentifier,
                appName: ProductBrand.englishName,
                windowTitle: "识别完成",
                capturedAt: Date(timeIntervalSince1970: 1_800_000_000),
                hotwords: [temporaryHotword("context_boost_timeout")]
            )
        )
        let pipeline = DefaultTextProcessingPipeline(
            refiner: refiner,
            contextBoostProvider: contextProvider,
            contextBoostEnabled: { true },
            contextBoostTimeoutNanoseconds: 1
        )

        let result = await pipeline.process(
            "原始文本",
            target: DictationTarget(
                bundleID: ProductBrand.bundleIdentifier,
                appName: ProductBrand.englishName,
                pid: 42,
                windowTitle: "识别完成"
            )
        )

        XCTAssertTrue(contextProvider.requestedTargets.isEmpty)
        XCTAssertNil(result.trace?.contextBoost)
        XCTAssertFalse(refiner.requests.first?.systemPrompt.contains("context_boost_timeout") == true)
    }

    func testPipelineSkipsContextBoostWhenSuppressedByVisibleOCRPanel() async {
        let refiner = PromptAwareStubTextRefiner(result: .success("原始文本"))
        let contextProvider = StubCurrentWindowOCRContextProvider(
            snapshot: OCRContextSnapshot(
                bundleID: "com.example.editor",
                appName: "Editor",
                windowTitle: "Notes",
                capturedAt: Date(timeIntervalSince1970: 1_800_000_000),
                hotwords: [temporaryHotword("static func contextBoostFailureReasonText")]
            )
        )
        let pipeline = DefaultTextProcessingPipeline(
            refiner: refiner,
            contextBoostProvider: contextProvider,
            contextBoostEnabled: { true },
            contextBoostSuppressed: { true }
        )

        let result = await pipeline.process(
            "原始文本",
            target: DictationTarget(bundleID: "com.example.editor", appName: "Editor", pid: 42)
        )

        XCTAssertTrue(contextProvider.requestedTargets.isEmpty)
        XCTAssertNil(result.trace?.contextBoost)
        XCTAssertFalse(
            refiner.requests.first?.systemPrompt.contains("static func contextBoostFailureReasonText") == true
        )
    }

    func testPipelineDoesNotCaptureContextWhenLLMRefinerIsDisabled() async {
        let refiner = StubTextRefiner(isEnabled: false, isConfigured: true)
        let contextProvider = StubCurrentWindowOCRContextProvider(snapshot: nil)
        let pipeline = DefaultTextProcessingPipeline(
            refiner: refiner,
            contextBoostProvider: contextProvider,
            contextBoostEnabled: { true }
        )

        let result = await pipeline.process(
            "原始文本",
            target: DictationTarget(bundleID: "com.example.editor", appName: "Editor", pid: 42)
        )

        XCTAssertEqual(result.finalText, "原始文本")
        XCTAssertTrue(contextProvider.requestedTargets.isEmpty)
    }

    func testPipelineFallsBackWhenLLMDeletesProtectedTokens() async {
        let refiner = PromptAwareStubTextRefiner(result: .success("部署完成"))
        let pipeline = DefaultTextProcessingPipeline(refiner: refiner)
        let raw = "部署版本 1.5.0 到 /tmp/VoxFlow.app，然后打开 https://example.com"

        let result = await pipeline.process(raw, target: nil)

        XCTAssertEqual(result.finalText, raw)
        XCTAssertTrue(result.warnings.contains("llm_refinement_rejected"))
    }

    func testPipelineFallsBackWhenLLMReturnsExplanationInsteadOfText() async {
        let refiner = PromptAwareStubTextRefiner(result: .success("修改说明：已帮你润色成正式版本。"))
        let pipeline = DefaultTextProcessingPipeline(refiner: refiner)
        let raw = "明天发 Qwen3-ASR 的发布计划"

        let result = await pipeline.process(raw, target: nil)

        XCTAssertEqual(result.finalText, raw)
        XCTAssertTrue(result.warnings.contains("llm_refinement_rejected"))
    }

    func testPipelineFallsBackWhenLLMInjectsMultipleContextHotwordsIntoUnrelatedText() async {
        let refiner = PromptAwareStubTextRefiner(result: .success("Qwen3-ASR WhisperKit"))
        let contextProvider = StubCurrentWindowOCRContextProvider(
            snapshot: OCRContextSnapshot(
                bundleID: "com.example.editor",
                appName: "Editor",
                windowTitle: "Release Notes",
                capturedAt: Date(timeIntervalSince1970: 1_800_000_000),
                hotwords: [
                    temporaryHotword("Qwen3-ASR"),
                    temporaryHotword("WhisperKit"),
                ]
            )
        )
        let pipeline = DefaultTextProcessingPipeline(
            refiner: refiner,
            contextBoostProvider: contextProvider,
            contextBoostEnabled: { true }
        )

        let result = await pipeline.process(
            "好的",
            target: DictationTarget(bundleID: "com.example.editor", appName: "Editor", pid: 42)
        )

        XCTAssertEqual(result.finalText, "好的")
        XCTAssertTrue(result.warnings.contains("llm_refinement_rejected"))
    }

    func testStructuredPipelineUsesPolishedTextAndInjectsHotwordsIntoPrompt() async throws {
        let queue = try DatabaseQueue(connection: .inMemory())
        try AppDatabase.migrator().migrate(queue)
        let repository = SQLiteCorrectionTargetRepository(databaseQueue: queue)
        try repository.save(CorrectionTargetTerm(text: "VoxFlow", lifecycle: .active, source: .manual))
        let refiner = PromptAwareStubTextRefiner(
            result: .success(#"{"polished":"使用 VoxFlow","corrections":[],"key_terms":[]}"#)
        )
        let pipeline = DefaultTextProcessingPipeline(
            refiner: refiner,
            structuredPromptBuilder: StructuredCorrectionPromptBuilder(),
            correctionTargetRepository: repository
        )

        let result = await pipeline.process(
            "使用 vox flow",
            target: DictationTarget(bundleID: "com.example.editor", appName: "Editor", pid: 42),
            correctionContext: Self.dictationContext()
        )

        XCTAssertEqual(result.finalText, "使用 VoxFlow")
        XCTAssertEqual(result.warnings, [])
        let systemPrompt = try XCTUnwrap(refiner.requests.first?.systemPrompt)
        XCTAssertTrue(systemPrompt.contains("user_terms"))
        XCTAssertTrue(systemPrompt.contains("VoxFlow"))
        XCTAssertTrue(systemPrompt.contains("应用：Editor"))
    }

    func testStructuredPipelineInjectsRelevantKnownCorrectionsIntoPrompt() async throws {
        let queue = try DatabaseQueue(connection: .inMemory())
        try AppDatabase.migrator().migrate(queue)
        let evidenceRepository = SQLiteCorrectionEvidenceRepository(databaseQueue: queue)
        try evidenceRepository.upsert(
            StructuredCorrection(original: "口子空间", corrected: "扣子空间", type: .term)
        )
        try evidenceRepository.upsert(
            StructuredCorrection(original: "陈瑞", corrected: "陈睿", type: .homophone)
        )
        let refiner = PromptAwareStubTextRefiner(
            result: .success(#"{"polished":"打开扣子空间","corrections":[],"key_terms":[]}"#)
        )
        let pipeline = DefaultTextProcessingPipeline(
            refiner: refiner,
            structuredPromptBuilder: StructuredCorrectionPromptBuilder(),
            correctionEvidenceRepository: evidenceRepository
        )

        _ = await pipeline.process(
            "打开口子空间",
            target: nil,
            correctionContext: Self.dictationContext()
        )

        let systemPrompt = try XCTUnwrap(refiner.requests.first?.systemPrompt)
        XCTAssertTrue(systemPrompt.contains("known_corrections"))
        XCTAssertTrue(systemPrompt.contains("口子空间 -> 扣子空间"))
        XCTAssertFalse(systemPrompt.contains("陈瑞 -> 陈睿"))
    }

    func testStructuredPipelinePromotesRepeatedKeyTermsToHotwords() async throws {
        let queue = try DatabaseQueue(connection: .inMemory())
        try AppDatabase.migrator().migrate(queue)
        let repository = SQLiteCorrectionTargetRepository(databaseQueue: queue)
        let learningService = StructuredCorrectionLearningService(
            repository: repository,
            termCounter: RepositoryBackedKeyTermCounter(repository: repository)
        )
        let refiner = PromptAwareStubTextRefiner(
            result: .success(#"{"polished":"PostgreSQL","corrections":[],"key_terms":["PostgreSQL"]}"#)
        )
        let pipeline = DefaultTextProcessingPipeline(
            refiner: refiner,
            structuredPromptBuilder: StructuredCorrectionPromptBuilder(),
            structuredLearningService: learningService,
            correctionTargetRepository: repository
        )

        for _ in 0..<StructuredCorrectionLearningService.promotionThreshold {
            _ = await pipeline.process(
                "post grace q l",
                target: nil,
                correctionContext: Self.dictationContext()
            )
        }

        let hotwords = try repository.listHotwords().map(\.text)
        XCTAssertTrue(hotwords.contains("PostgreSQL"))
    }

    func testStructuredPipelinePostsVocabularyChangeWhenKeyTermEntersDrawer() async throws {
        let queue = try DatabaseQueue(connection: .inMemory())
        try AppDatabase.migrator().migrate(queue)
        let repository = SQLiteCorrectionTargetRepository(databaseQueue: queue)
        let learningService = StructuredCorrectionLearningService(
            repository: repository,
            termCounter: RepositoryBackedKeyTermCounter(repository: repository)
        )
        let refiner = PromptAwareStubTextRefiner(
            result: .success(#"{"polished":"PostgreSQL","corrections":[],"key_terms":["PostgreSQL"]}"#)
        )
        let pipeline = DefaultTextProcessingPipeline(
            refiner: refiner,
            structuredPromptBuilder: StructuredCorrectionPromptBuilder(),
            structuredLearningService: learningService,
            correctionTargetRepository: repository
        )

        _ = await pipeline.process(
            "post grace q l",
            target: nil,
            correctionContext: Self.dictationContext()
        )

        let didNotify = expectation(description: "structured learning notifies vocabulary UI")
        let observer = NotificationCenter.default.addObserver(
            forName: .correctionVocabularyDidChange,
            object: nil,
            queue: .main
        ) { _ in
            didNotify.fulfill()
        }
        defer { NotificationCenter.default.removeObserver(observer) }

        _ = await pipeline.process(
            "post grace q l",
            target: nil,
            correctionContext: Self.dictationContext()
        )

        await fulfillment(of: [didNotify], timeout: 1)
        XCTAssertEqual(try repository.listLearningCandidates(limit: 10).map(\.text), ["PostgreSQL"])
    }

    func testStructuredPipelinePostsVocabularyChangeWhenFirstKeyTermObservationCreatesCandidate() async throws {
        let queue = try DatabaseQueue(connection: .inMemory())
        try AppDatabase.migrator().migrate(queue)
        let repository = SQLiteCorrectionTargetRepository(databaseQueue: queue)
        let learningService = StructuredCorrectionLearningService(
            repository: repository,
            termCounter: RepositoryBackedKeyTermCounter(repository: repository)
        )
        let refiner = PromptAwareStubTextRefiner(
            result: .success(#"{"polished":"QQ","corrections":[],"key_terms":["QQ"]}"#)
        )
        let pipeline = DefaultTextProcessingPipeline(
            refiner: refiner,
            structuredPromptBuilder: StructuredCorrectionPromptBuilder(),
            structuredLearningService: learningService,
            correctionTargetRepository: repository
        )

        let didNotify = expectation(description: "first structured key term observation notifies vocabulary UI")
        let observer = NotificationCenter.default.addObserver(
            forName: .correctionVocabularyDidChange,
            object: nil,
            queue: .main
        ) { _ in
            didNotify.fulfill()
        }
        defer { NotificationCenter.default.removeObserver(observer) }

        _ = await pipeline.process(
            "扣扣",
            target: nil,
            correctionContext: Self.dictationContext()
        )

        await fulfillment(of: [didNotify], timeout: 1)
        XCTAssertEqual(try repository.listLearningCandidates(limit: 10).map(\.text), ["QQ"])
    }

    func testStructuredPipelineWritesPromotedHotwordsToFile() async throws {
        let queue = try DatabaseQueue(connection: .inMemory())
        try AppDatabase.migrator().migrate(queue)
        let repository = SQLiteCorrectionTargetRepository(databaseQueue: queue)
        let learningService = StructuredCorrectionLearningService(
            repository: repository,
            termCounter: InMemoryKeyTermCounter()
        )
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDirectory) }
        let fileSyncService = HotwordFileSyncService(
            fileURL: tempDirectory.appendingPathComponent("hotwords.txt"),
            repository: repository,
            writebackQueue: DispatchQueue(label: "test.hotwords.pipeline.writeback"),
            writebackDelay: 0
        )
        let refiner = PromptAwareStubTextRefiner(
            result: .success(#"{"polished":"PostgreSQL","corrections":[],"key_terms":["PostgreSQL"]}"#)
        )
        let pipeline = DefaultTextProcessingPipeline(
            refiner: refiner,
            structuredPromptBuilder: StructuredCorrectionPromptBuilder(),
            structuredLearningService: learningService,
            correctionTargetRepository: repository,
            hotwordFileSyncService: fileSyncService
        )

        for _ in 0..<StructuredCorrectionLearningService.promotionThreshold {
            _ = await pipeline.process(
                "post grace q l",
                target: nil,
                correctionContext: Self.dictationContext()
            )
        }

        let fileURL = tempDirectory.appendingPathComponent("hotwords.txt")
        let content = try await waitForFileContent(at: fileURL, containing: "PostgreSQL")
        XCTAssertTrue(content.contains("PostgreSQL"))
    }

    func testStructuredPipelineDoesNotLearnWhenAutoLearningDisabled() async throws {
        let queue = try DatabaseQueue(connection: .inMemory())
        try AppDatabase.migrator().migrate(queue)
        let repository = SQLiteCorrectionTargetRepository(databaseQueue: queue)
        let learningService = StructuredCorrectionLearningService(
            repository: repository,
            termCounter: InMemoryKeyTermCounter()
        )
        let refiner = PromptAwareStubTextRefiner(
            result: .success(#"{"polished":"PostgreSQL","corrections":[],"key_terms":["PostgreSQL"]}"#)
        )
        let pipeline = DefaultTextProcessingPipeline(
            refiner: refiner,
            structuredPromptBuilder: StructuredCorrectionPromptBuilder(),
            structuredLearningService: learningService,
            correctionTargetRepository: repository,
            structuredLearningEnabled: { false }
        )

        for _ in 0..<StructuredCorrectionLearningService.promotionThreshold {
            _ = await pipeline.process(
                "post grace q l",
                target: nil,
                correctionContext: Self.dictationContext()
            )
        }

        let hotwords = try repository.listHotwords().map(\.text)
        XCTAssertFalse(hotwords.contains("PostgreSQL"))
    }

    private enum TestError: Error {
        case expected
    }

    private func waitForFileContent(
        at url: URL,
        containing expected: String,
        timeoutNanoseconds: UInt64 = 1_000_000_000
    ) async throws -> String {
        let deadline = DispatchTime.now().uptimeNanoseconds + timeoutNanoseconds
        while DispatchTime.now().uptimeNanoseconds < deadline {
            if let content = try? String(contentsOf: url, encoding: .utf8),
               content.contains(expected) {
                return content
            }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        return try String(contentsOf: url, encoding: .utf8)
    }

    private static func dictationContext(
        isFinalTranscript: Bool = true,
        isSecureField: Bool = false
    ) -> CorrectionContext {
        CorrectionContext(
            mode: .dictation,
            providerID: "test-provider",
            modelID: "test-model",
            language: "zh-CN",
            bundleIdentifier: "com.example.editor",
            isFinalTranscript: isFinalTranscript,
            isSecureField: isSecureField
        )
    }

    private static func trace(providerID: String, model: String) -> LLMRefinementTrace {
        LLMRefinementTrace(
            providerID: providerID,
            providerName: "Provider \(providerID)",
            endpoint: "https://api.example.com/v1/chat/completions",
            model: model,
            temperature: 0.2,
            timeoutSeconds: 13,
            requestBodyJSON: "{}",
            responseText: nil,
            statusCode: 200,
            durationMS: 10,
            errorMessage: nil,
            completedAt: Date(timeIntervalSince1970: 1_800_000_000)
        )
    }

    private final class StubTextRefiner: TextRefining, @unchecked Sendable {
        var isEnabled: Bool
        var isConfigured: Bool
        var result: Result<String, Error>

        init(
            isEnabled: Bool,
            isConfigured: Bool,
            result: Result<String, Error> = .success("unused")
        ) {
            self.isEnabled = isEnabled
            self.isConfigured = isConfigured
            self.result = result
        }

        func refine(_ text: String) async throws -> String {
            try result.get()
        }
    }

    private final class PromptAwareStubTextRefiner: TextRefining, PromptAwareTextRefining, @unchecked Sendable {
        var isEnabled = true
        var isConfigured = true
        var result: Result<String, Error>
        private(set) var requests: [TextRefinementRequest] = []

        init(result: Result<String, Error>) {
            self.result = result
        }

        func refine(_ text: String) async throws -> String {
            try await refine(
                TextRefinementRequest(
                    text: text,
                    systemPrompt: PromptBuilder.conservativeSystemPrompt,
                    model: nil,
                    temperature: nil
                )
            )
        }

        func refine(_ request: TextRefinementRequest) async throws -> String {
            requests.append(request)
            return try result.get()
        }
    }

    private final class TraceablePromptAwareStubTextRefiner: TextRefining, TraceablePromptAwareTextRefining, RefinementTraceProviding, @unchecked Sendable {
        var isEnabled = true
        var isConfigured = true
        var result: Result<TextRefinementTraceResult, Error>
        private(set) var requests: [TextRefinementRequest] = []
        private(set) var lastTrace: LLMRefinementTrace?

        init(
            result: Result<TextRefinementTraceResult, Error>,
            lastTrace: LLMRefinementTrace?
        ) {
            self.result = result
            self.lastTrace = lastTrace
        }

        func refine(_ text: String) async throws -> String {
            try await refine(
                TextRefinementRequest(
                    text: text,
                    systemPrompt: PromptBuilder.conservativeSystemPrompt,
                    model: nil,
                    temperature: nil
                )
            )
        }

        func refine(_ request: TextRefinementRequest) async throws -> String {
            try await refineWithTrace(request).text
        }

        func refineWithTrace(_ request: TextRefinementRequest) async throws -> TextRefinementTraceResult {
            requests.append(request)
            return try result.get()
        }

        func clearLastTrace() {}
    }

    private final class TraceableStreamingPromptAwareStubTextRefiner: TextRefining, TraceableStreamingPromptAwareTextRefining, RefinementTraceProviding, @unchecked Sendable {
        var isEnabled = true
        var isConfigured = true
        private let snapshots: [String]
        private let providerID: String
        private let trace: LLMRefinementTrace
        private(set) var lastTrace: LLMRefinementTrace?

        init(
            snapshots: [String],
            providerID: String,
            trace: LLMRefinementTrace,
            lastTrace: LLMRefinementTrace?
        ) {
            self.snapshots = snapshots
            self.providerID = providerID
            self.trace = trace
            self.lastTrace = lastTrace
        }

        func refine(_ text: String) async throws -> String {
            try await refine(
                TextRefinementRequest(
                    text: text,
                    systemPrompt: PromptBuilder.conservativeSystemPrompt,
                    model: nil,
                    temperature: nil
                )
            )
        }

        func refine(_ request: TextRefinementRequest) async throws -> String {
            var finalText = ""
            let result = refineStreamWithTrace(request)
            for try await snapshot in result.stream {
                finalText = snapshot
            }
            return finalText
        }

        func refineStream(_ request: TextRefinementRequest) -> AsyncThrowingStream<String, Error> {
            refineStreamWithTrace(request).stream
        }

        func refineStreamWithTrace(_ request: TextRefinementRequest) -> TextRefinementStreamTraceResult {
            let traceHandle = TextRefinementTraceHandle()
            let stream = AsyncThrowingStream<String, Error> { continuation in
                for snapshot in snapshots {
                    continuation.yield(snapshot)
                }
                traceHandle.complete(trace)
                continuation.finish()
            }
            return TextRefinementStreamTraceResult(stream: stream, providerID: providerID, trace: traceHandle)
        }

        func clearLastTrace() {}
    }

    private final class SequencedPromptAwareRefiner: TextRefining, PromptAwareTextRefining, @unchecked Sendable {
        var isEnabled = true
        var isConfigured = true
        private var results: [String]
        private(set) var requests: [TextRefinementRequest] = []

        init(results: [String]) {
            self.results = results
        }

        func refine(_ text: String) async throws -> String {
            try await refine(
                TextRefinementRequest(
                    text: text,
                    systemPrompt: PromptBuilder.conservativeSystemPrompt,
                    model: nil,
                    temperature: nil
                )
            )
        }

        func refine(_ request: TextRefinementRequest) async throws -> String {
            requests.append(request)
            return results.removeFirst()
        }
    }

    private final class StubCurrentWindowOCRContextProvider: CurrentWindowOCRContextProviding, @unchecked Sendable {
        let snapshot: OCRContextSnapshot?
        let delayNanoseconds: UInt64
        private(set) var requestedTargets: [DictationTarget?] = []

        init(snapshot: OCRContextSnapshot?, delayNanoseconds: UInt64 = 0) {
            self.snapshot = snapshot
            self.delayNanoseconds = delayNanoseconds
        }

        func captureContext(for target: DictationTarget?) async -> OCRContextSnapshot? {
            requestedTargets.append(target)
            if delayNanoseconds > 0 {
                try? await Task.sleep(nanoseconds: delayNanoseconds)
            }
            return snapshot
        }
    }

    private final class PipelinePrefetchSessionProvider: ContextBoostOCRCaptureSessionProviding, @unchecked Sendable {
        let session: any ContextBoostOCRCaptureSession

        init(session: any ContextBoostOCRCaptureSession) {
            self.session = session
        }

        func makeCaptureSession(for target: DictationTarget) -> (any ContextBoostOCRCaptureSession)? {
            session
        }
    }

    private final class PipelinePrefetchSession: ContextBoostOCRCaptureSession, @unchecked Sendable {
        let outcome: ContextBoostOCRRecognitionOutcome
        private(set) var cancelCallCount = 0

        init(outcome: ContextBoostOCRRecognitionOutcome) {
            self.outcome = outcome
        }

        func recognize(quality: ContextBoostOCRQuality) async -> ContextBoostOCRRecognitionOutcome {
            outcome
        }

        func cancelCurrentRecognition() {
            cancelCallCount += 1
        }
    }

    private func temporaryHotword(_ text: String, source: HotwordSource = .ocrShape) -> TemporaryHotword {
        TemporaryHotword(
            text: text,
            normalizedText: text.lowercased(),
            score: 5,
            source: source,
            evidence: [HotwordEvidence(reason: "test", weight: 5)],
            expiresAt: Date(timeIntervalSince1970: 1_800_000_120)
        )
    }
}

// MARK: - Deterministic text processing integration tests

@MainActor
final class TextProcessingPipelineDeterministicIntegrationTests: XCTestCase {
    /// When deterministic settings are explicitly disabled, the pipeline
    /// must behave exactly as before: no pre-LLM or post-LLM processing.
    func testDisabledSettingsAreNoOp() async {
        let refiner = PromptAwareStubTextRefiner(result: .success("Hello世界"))
        let settings = DeterministicTextProcessingSettings(enabled: false)
        let pipeline = DefaultTextProcessingPipeline(
            refiner: refiner,
            deterministicSettingsProvider: { settings }
        )

        let result = await pipeline.process("嗯Hello世界")

        XCTAssertEqual(result.finalText, "Hello世界")
        XCTAssertEqual(result.rawText, "嗯Hello世界")
    }

    /// With default settings (master on, all sub-toggles on except
    /// longSentenceBreaking), pre-LLM filler filtering runs on the raw text,
    /// and post-LLM punctuation adds a sentence-ending 。 to the CJK output.
    func testDefaultsRunPreLLMFillerFilter() async {
        let refiner = PromptAwareStubTextRefiner(result: .success("这个功能需要改一下"))
        let pipeline = DefaultTextProcessingPipeline(
            refiner: refiner,
            deterministicSettingsProvider: { .defaults }
        )

        let result = await pipeline.process("嗯这个功能需要改一下")

        // pre-LLM: filler removed → refiner receives cleaned text.
        XCTAssertEqual(refiner.requests.first?.text, "这个功能需要改一下")
        // post-LLM (defaults): punctuation adds 。 for CJK sentence.
        XCTAssertTrue(result.finalText.hasSuffix("。"))
        XCTAssertTrue(result.finalText.contains("这个功能需要改一下"))
    }

    /// pre-LLM filler filtering runs on the raw ASR text before it's sent to
    /// the LLM. The refiner receives the cleaned text, not the raw text.
    /// Post-LLM processors are disabled to isolate the pre-LLM behavior.
    func testPreLLMFillerFilteringRunsBeforeRefiner() async {
        let refiner = PromptAwareStubTextRefiner(result: .success("这个功能需要改一下"))
        let settings = DeterministicTextProcessingSettings(
            enabled: true,
            smartNumberRecognition: false,
            punctuationOptimization: false,
            fillerWordFiltering: true,
            cjkLatinSpacing: false,
            autoCapitalization: false
        )
        let pipeline = DefaultTextProcessingPipeline(
            refiner: refiner,
            deterministicSettingsProvider: { settings }
        )

        let result = await pipeline.process("嗯这个功能需要改一下")

        XCTAssertEqual(result.finalText, "这个功能需要改一下")
        // The refiner should have received the pre-processed (filler-removed)
        // text, not the raw text with the filler.
        XCTAssertEqual(refiner.requests.first?.text, "这个功能需要改一下")
    }

    /// post-LLM CJK-Latin spacing runs on the accepted LLM output before
    /// insertion. The final text has the spacing applied. Other post-LLM
    /// processors are disabled to isolate spacing.
    func testPostLLMSpacingRunsAfterRefiner() async {
        let refiner = PromptAwareStubTextRefiner(result: .success("Hello世界"))
        let settings = DeterministicTextProcessingSettings(
            enabled: true,
            smartNumberRecognition: false,
            punctuationOptimization: false,
            cjkLatinSpacing: true,
            autoCapitalization: false
        )
        let pipeline = DefaultTextProcessingPipeline(
            refiner: refiner,
            deterministicSettingsProvider: { settings }
        )

        let result = await pipeline.process("Hello世界")

        XCTAssertTrue(result.finalText.contains("Hello 世界"))
    }

    /// post-LLM punctuation optimization adds sentence-ending 。 for CJK text.
    /// Other processors disabled to isolate punctuation.
    func testPostLLMPunctuationAddsEnding() async {
        let refiner = PromptAwareStubTextRefiner(result: .success("今天天气不错"))
        let settings = DeterministicTextProcessingSettings(
            enabled: true,
            smartNumberRecognition: false,
            punctuationOptimization: true,
            cjkLatinSpacing: false,
            autoCapitalization: false
        )
        let pipeline = DefaultTextProcessingPipeline(
            refiner: refiner,
            deterministicSettingsProvider: { settings }
        )

        let result = await pipeline.process("今天天气不错")

        XCTAssertTrue(result.finalText.hasSuffix("。"))
    }

    /// When LLM refinement fails, deterministic text processing still provides
    /// the configured fallback cleanup before insertion.
    func testDeterministicFallbackRunsWhenLLMFails() async {
        let refiner = StubTextRefiner(
            isEnabled: true,
            isConfigured: true,
            result: .failure(TestError.expected)
        )
        let settings = DeterministicTextProcessingSettings(
            enabled: true, punctuationOptimization: true, cjkLatinSpacing: true
        )
        let pipeline = DefaultTextProcessingPipeline(
            refiner: refiner,
            deterministicSettingsProvider: { settings }
        )

        let result = await pipeline.process("Hello世界")

        XCTAssertEqual(result.finalText, "Hello 世界。")
        XCTAssertEqual(result.warnings, ["llm_refinement_failed"])
    }

    /// Deterministic processing is a normal dictation setting, so it should run
    /// even when AI correction is disabled or unavailable.
    func testDeterministicFallbackRunsWhenLLMIsDisabled() async {
        let refiner = StubTextRefiner(
            isEnabled: false,
            isConfigured: true
        )
        let settings = DeterministicTextProcessingSettings(
            enabled: true,
            punctuationOptimization: true,
            fillerWordFiltering: true,
            cjkLatinSpacing: true
        )
        let pipeline = DefaultTextProcessingPipeline(
            refiner: refiner,
            deterministicSettingsProvider: { settings }
        )

        let result = await pipeline.process("嗯Hello世界")

        XCTAssertEqual(result.finalText, "Hello 世界。")
        XCTAssertEqual(result.warnings, [])
    }

    /// pre-LLM smart number recognition converts Chinese numerals in quantity
    /// and percent contexts before the LLM sees the text. Post-LLM processors
    /// are disabled to isolate the pre-LLM behavior.
    func testPreLLMSmartNumberRunsBeforeRefiner() async {
        let refiner = PromptAwareStubTextRefiner(result: .success("进度30%"))
        let settings = DeterministicTextProcessingSettings(
            enabled: true,
            smartNumberRecognition: true,
            punctuationOptimization: false,
            cjkLatinSpacing: false,
            autoCapitalization: false
        )
        let pipeline = DefaultTextProcessingPipeline(
            refiner: refiner,
            deterministicSettingsProvider: { settings }
        )

        let result = await pipeline.process("百分之三十的进度")

        XCTAssertEqual(result.finalText, "进度30%")
        // The refiner should have received the pre-processed text with the
        // number already converted.
        XCTAssertEqual(refiner.requests.first?.text, "30%的进度")
    }

    /// Coding style disables filler filtering and capitalization, but not
    /// smart number recognition (which protects code-like regions via the
    /// ProtectedRegions mask).
    func testCodingStyleDisablesFillerFiltering() async throws {
        let environment = AppEnvironment(container: try DependencyContainer.inMemory())
        let codingStyle = try XCTUnwrap(try environment.styleRepository.profile(id: "builtin.coding"))
        // Make coding the default style so the pipeline resolves it without
        // a manual rule or AI router.
        try environment.styleRepository.save(
            StyleProfileRecord(
                id: codingStyle.id,
                name: codingStyle.name,
                category: codingStyle.category,
                subtitle: codingStyle.subtitle,
                mode: codingStyle.mode,
                prompt: codingStyle.prompt,
                sampleInput: codingStyle.sampleInput,
                sampleOutput: codingStyle.sampleOutput,
                llmProviderID: codingStyle.llmProviderID,
                model: codingStyle.model,
                temperature: codingStyle.temperature,
                enabled: codingStyle.enabled,
                builtIn: codingStyle.builtIn,
                isDefault: true,
                createdAt: codingStyle.createdAt,
                updatedAt: codingStyle.updatedAt
            )
        )
        let refiner = PromptAwareStubTextRefiner(result: .success("var um = 42"))
        let settings = DeterministicTextProcessingSettings(
            enabled: true, fillerWordFiltering: true, autoCapitalization: true
        )
        let pipeline = DefaultTextProcessingPipeline(
            refiner: refiner,
            styleRepository: environment.styleRepository,
            deterministicSettingsProvider: { settings }
        )

        let result = await pipeline.process("var um = 42")

        // Filler filter skipped in coding context: "um" preserved.
        XCTAssertEqual(result.finalText, "var um = 42")
    }

    func testDeterministicTraceOmitsProcessorsSkippedByCodingContext() async throws {
        let environment = AppEnvironment(container: try DependencyContainer.inMemory())
        let codingStyle = try XCTUnwrap(try environment.styleRepository.profile(id: "builtin.coding"))
        try environment.styleRepository.save(
            StyleProfileRecord(
                id: codingStyle.id,
                name: codingStyle.name,
                category: codingStyle.category,
                subtitle: codingStyle.subtitle,
                mode: codingStyle.mode,
                prompt: codingStyle.prompt,
                sampleInput: codingStyle.sampleInput,
                sampleOutput: codingStyle.sampleOutput,
                llmProviderID: codingStyle.llmProviderID,
                model: codingStyle.model,
                temperature: codingStyle.temperature,
                enabled: codingStyle.enabled,
                builtIn: codingStyle.builtIn,
                isDefault: true,
                createdAt: codingStyle.createdAt,
                updatedAt: codingStyle.updatedAt
            )
        )
        let refiner = PromptAwareStubTextRefiner(result: .success("var um = 42"))
        let settings = DeterministicTextProcessingSettings(
            enabled: true,
            smartNumberRecognition: true,
            punctuationOptimization: true,
            fillerWordFiltering: true,
            cjkLatinSpacing: true,
            autoCapitalization: true
        )
        let pipeline = DefaultTextProcessingPipeline(
            refiner: refiner,
            styleRepository: environment.styleRepository,
            deterministicSettingsProvider: { settings }
        )

        let result = await pipeline.process("var um = 42")
        let trace = try XCTUnwrap(result.trace?.deterministic)

        XCTAssertTrue(trace.isCodingContext)
        XCTAssertEqual(trace.preLLM.enabledProcessors, ["filler_word_filtering", "smart_number_recognition"])
        XCTAssertEqual(trace.postLLM.enabledProcessors, ["punctuation_optimization", "cjk_latin_spacing"])
        XCTAssertEqual(trace.preLLM.changedProcessorIDs, [])
        XCTAssertEqual(trace.postLLM.changedProcessorIDs, [])
        XCTAssertFalse(trace.postLLM.enabledProcessors.contains("auto_capitalization"))
    }

    func testDeterministicTraceHighlightsOnlyProcessorsThatChangedText() async throws {
        let refinedText = "第一点，他上夜班时需要具体告诉我在哪个位置，第二点，在 2:00 时，他诊断区的车底到底是怎么折叠的"
        let refiner = PromptAwareStubTextRefiner(result: .success(refinedText))
        let settings = DeterministicTextProcessingSettings(
            enabled: true,
            smartNumberRecognition: false,
            punctuationOptimization: true,
            longSentenceBreaking: true,
            fillerWordFiltering: false,
            cjkLatinSpacing: true,
            autoCapitalization: false,
            longSentenceWordThreshold: 10,
            longSentenceCJKThreshold: 18
        )
        let pipeline = DefaultTextProcessingPipeline(
            refiner: refiner,
            deterministicSettingsProvider: { settings }
        )

        let result = await pipeline.process("第一点他上夜班哪里")
        let trace = try XCTUnwrap(result.trace?.deterministic)

        XCTAssertEqual(
            trace.postLLM.enabledProcessors,
            ["punctuation_optimization", "cjk_latin_spacing", "long_sentence_breaking"]
        )
        XCTAssertEqual(
            trace.postLLM.changedProcessorIDs,
            ["punctuation_optimization", "long_sentence_breaking"]
        )
        // highlightedProcessorIDs tracks ALL called processors, including
        // those that did not change text. cjk_latin_spacing was called but
        // did not modify the refined text, so it appears in highlighted but
        // not in changedProcessorIDs.
        XCTAssertTrue(trace.postLLM.highlightedProcessorIDs.contains("punctuation_optimization"))
        XCTAssertTrue(trace.postLLM.highlightedProcessorIDs.contains("long_sentence_breaking"))
        XCTAssertTrue(trace.postLLM.highlightedProcessorIDs.contains("cjk_latin_spacing"))
        XCTAssertFalse(trace.postLLM.changedProcessorIDs?.contains("cjk_latin_spacing") ?? true)
    }

    func testDeterministicTraceDisplaysAllPhaseProcessorsButHighlightsOnlyCalledOnes() async throws {
        let refiner = PromptAwareStubTextRefiner(result: .success("系统提示词不应该一上来"))
        let settings = DeterministicTextProcessingSettings(
            enabled: true,
            smartNumberRecognition: true,
            punctuationOptimization: false,
            longSentenceBreaking: false,
            fillerWordFiltering: false,
            cjkLatinSpacing: false,
            autoCapitalization: false
        )
        let pipeline = DefaultTextProcessingPipeline(
            refiner: refiner,
            deterministicSettingsProvider: { settings }
        )

        let result = await pipeline.process("达到十万")
        let trace = try XCTUnwrap(result.trace?.deterministic)

        XCTAssertEqual(trace.preLLM.processorIDsForDisplay, ["filler_word_filtering", "smart_number_recognition"])
        XCTAssertEqual(trace.preLLM.enabledProcessors, ["smart_number_recognition"])
        XCTAssertEqual(trace.preLLM.changedProcessorIDs, ["smart_number_recognition"])
        XCTAssertEqual(trace.preLLM.highlightedProcessorIDs, ["smart_number_recognition"])

        XCTAssertEqual(
            trace.postLLM.processorIDsForDisplay,
            ["punctuation_optimization", "cjk_latin_spacing", "long_sentence_breaking", "auto_capitalization"]
        )
        XCTAssertEqual(trace.postLLM.enabledProcessors, [])
        XCTAssertEqual(trace.postLLM.highlightedProcessorIDs, [])
    }

    func testDeterministicTraceHighlightsCalledProcessorEvenWhenTextIsUnchanged() async throws {
        let refiner = PromptAwareStubTextRefiner(result: .success("Hello world."))
        let settings = DeterministicTextProcessingSettings(
            enabled: true,
            smartNumberRecognition: false,
            punctuationOptimization: true,
            longSentenceBreaking: false,
            fillerWordFiltering: false,
            cjkLatinSpacing: false,
            autoCapitalization: false
        )
        let pipeline = DefaultTextProcessingPipeline(
            refiner: refiner,
            deterministicSettingsProvider: { settings }
        )

        let result = await pipeline.process("Hello world.")
        let trace = try XCTUnwrap(result.trace?.deterministic)

        XCTAssertEqual(trace.postLLM.enabledProcessors, ["punctuation_optimization"])
        XCTAssertEqual(trace.postLLM.changedProcessorIDs, [])
        XCTAssertEqual(trace.postLLM.highlightedProcessorIDs, ["punctuation_optimization"])
    }

    /// Full pre+post pipeline: filler removed pre-LLM, spacing applied
    /// post-LLM. The LLM only sees the cleaned text.
    func testFullPipelinePrePostOrder() async {
        let refiner = PromptAwareStubTextRefiner(result: .success("今天测试Hello世界"))
        let settings = DeterministicTextProcessingSettings(
            enabled: true,
            punctuationOptimization: true,
            fillerWordFiltering: true,
            cjkLatinSpacing: true
        )
        let pipeline = DefaultTextProcessingPipeline(
            refiner: refiner,
            deterministicSettingsProvider: { settings }
        )

        let result = await pipeline.process("嗯今天测试Hello世界")

        // pre-LLM: filler removed → refiner receives "今天测试Hello世界".
        XCTAssertEqual(refiner.requests.first?.text, "今天测试Hello世界")
        // post-LLM: spacing + punctuation applied to the refined text.
        XCTAssertTrue(result.finalText.contains("Hello 世界"))
        XCTAssertTrue(result.finalText.hasSuffix("。"))
    }

    func testDeterministicTraceRecordsPreAndPostProcessingText() async {
        let refiner = PromptAwareStubTextRefiner(result: .success("今天测试Hello世界"))
        let settings = DeterministicTextProcessingSettings(
            enabled: true,
            punctuationOptimization: true,
            fillerWordFiltering: true,
            cjkLatinSpacing: true
        )
        let pipeline = DefaultTextProcessingPipeline(
            refiner: refiner,
            deterministicSettingsProvider: { settings }
        )

        let result = await pipeline.process("嗯今天测试Hello世界")
        let trace = result.trace?.deterministic

        XCTAssertEqual(trace?.enabled, true)
        XCTAssertEqual(trace?.preLLM.enabledProcessors, ["filler_word_filtering", "smart_number_recognition"])
        XCTAssertEqual(trace?.postLLM.enabledProcessors, ["punctuation_optimization", "cjk_latin_spacing", "auto_capitalization"])
        XCTAssertEqual(trace?.preLLM.changedProcessorIDs, ["filler_word_filtering"])
        XCTAssertEqual(trace?.postLLM.changedProcessorIDs, ["punctuation_optimization", "cjk_latin_spacing"])
        XCTAssertEqual(trace?.preLLM.changed, true)
        XCTAssertEqual(trace?.postLLM.changed, true)
        XCTAssertEqual(trace?.preLLM.inputText, "嗯今天测试Hello世界")
        XCTAssertEqual(trace?.preLLM.outputText, "今天测试Hello世界")
        XCTAssertEqual(trace?.postLLM.inputText, "今天测试Hello世界")
        XCTAssertEqual(trace?.postLLM.outputText, result.finalText)
        XCTAssertEqual(trace?.preLLM.inputCharacterCount, "嗯今天测试Hello世界".count)
        XCTAssertEqual(trace?.preLLM.outputCharacterCount, "今天测试Hello世界".count)
        XCTAssertFalse(trace?.preLLM.inputHash.contains("嗯今天测试Hello世界") ?? true)
        XCTAssertFalse(trace?.postLLM.outputHash.contains("Hello 世界") ?? true)
    }

    // MARK: - Stubs

    private final class PromptAwareStubTextRefiner: TextRefining, PromptAwareTextRefining, @unchecked Sendable {
        var isEnabled = true
        var isConfigured = true
        var result: Result<String, Error>
        private(set) var requests: [TextRefinementRequest] = []

        init(result: Result<String, Error>) {
            self.result = result
        }

        func refine(_ text: String) async throws -> String {
            try await refine(
                TextRefinementRequest(
                    text: text,
                    systemPrompt: PromptBuilder.conservativeSystemPrompt,
                    model: nil,
                    temperature: nil
                )
            )
        }

        func refine(_ request: TextRefinementRequest) async throws -> String {
            requests.append(request)
            return try result.get()
        }
    }

    private final class StubTextRefiner: TextRefining, @unchecked Sendable {
        var isEnabled: Bool
        var isConfigured: Bool
        var result: Result<String, Error>

        init(
            isEnabled: Bool,
            isConfigured: Bool,
            result: Result<String, Error> = .success("unused")
        ) {
            self.isEnabled = isEnabled
            self.isConfigured = isConfigured
            self.result = result
        }

        func refine(_ text: String) async throws -> String {
            try result.get()
        }
    }

    private enum TestError: Error {
        case expected
    }
}
