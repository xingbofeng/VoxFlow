import XCTest
@testable import VoxFlowTextProcessing

final class FillerWordFilterTests: XCTestCase {
    func testPureFillerRemoved() {
        XCTAssertEqual(
            FillerWordFilter.process("嗯这个功能需要改一下"),
            "这个功能需要改一下"
        )
    }

    func testMultipleFillersRemoved() {
        XCTAssertEqual(
            FillerWordFilter.process("嗯呃我觉得这个方案可以"),
            "我觉得这个方案可以"
        )
    }

    func testEnglishFillerRemoved() {
        XCTAssertEqual(
            FillerWordFilter.process("um I think this works"),
            "I think this works"
        )
    }

    func testDiscourseMarkerPreserved() {
        // "其实", "反正", "毕竟", "大概" must NOT be removed.
        XCTAssertEqual(
            FillerWordFilter.process("其实这个方案成本太高"),
            "其实这个方案成本太高"
        )
        XCTAssertEqual(
            FillerWordFilter.process("反正我觉得不行"),
            "反正我觉得不行"
        )
        XCTAssertEqual(
            FillerWordFilter.process("毕竟时间不够了"),
            "毕竟时间不够了"
        )
    }

    func testFillerInsideWordNotRemoved() {
        // "um" inside "hummus" should not be removed.
        XCTAssertEqual(
            FillerWordFilter.process("I love hummus"),
            "I love hummus"
        )
    }

    func testCodingContextPreservesLatinFillers() {
        XCTAssertEqual(
            FillerWordFilter.process("var um = 42", context: .init(isCodingContext: true)),
            "var um = 42"
        )
    }

    func testCodingContextStillRemovesCJKFillers() {
        // CJK fillers are removed even in coding context. Adjacent punctuation
        // is also cleaned up, so the leading `，` after removing `嗯` is gone.
        XCTAssertEqual(
            FillerWordFilter.process("嗯，达到那个嗯十万", context: .init(isCodingContext: true)),
            "达到那个十万"
        )
    }

    // MARK: - Expanded filler list (spec: refactor-deterministic-text-processing §4.1)

    func testCJKFillersRemoved() {
        // All four CJK fillers: 嗯, 呃, 唔, 额
        XCTAssertEqual(FillerWordFilter.process("嗯好的"), "好的")
        XCTAssertEqual(FillerWordFilter.process("呃我觉得"), "我觉得")
        XCTAssertEqual(FillerWordFilter.process("唔我知道了"), "我知道了")
        XCTAssertEqual(FillerWordFilter.process("额那个"), "那个")
    }

    func testLatinFillersRemovedAsStandaloneWords() {
        // All eight Latin fillers: um, uh, hmm, er, uhm, umm, uhh, erm
        let cases: [(String, String)] = [
            ("um I think", "I think"),
            ("uh let me see", "let me see"),
            ("hmm maybe later", "maybe later"),
            ("er what now", "what now"),
            ("uhm not sure", "not sure"),
            ("umm okay then", "okay then"),
            ("uhh really", "really"),
            ("erm perhaps", "perhaps"),
        ]
        for (input, expected) in cases {
            XCTAssertEqual(FillerWordFilter.process(input), expected, "input: \(input)")
        }
    }

    // MARK: - Adjacent punctuation/whitespace cleanup (spec §4.2)

    func testFillerRemovalCleansAdjacentPunctuation() {
        XCTAssertEqual(FillerWordFilter.process("呃，我觉得"), "我觉得")
        XCTAssertEqual(FillerWordFilter.process("嗯，好的"), "好的")
        XCTAssertEqual(FillerWordFilter.process("唔，算了吧"), "算了吧")
    }

    func testFillerRemovalCleansAdjacentLatinPunctuation() {
        XCTAssertEqual(FillerWordFilter.process("um, I think"), "I think")
        XCTAssertEqual(FillerWordFilter.process("uh, let me see"), "let me see")
    }

    func testFillerRemovalMidSentencePunctuationCleanup() {
        // Filler in the middle followed by punctuation: "我觉得呃，这个" → "我觉得这个"
        XCTAssertEqual(FillerWordFilter.process("我觉得呃，这个"), "我觉得这个")
        XCTAssertEqual(FillerWordFilter.process("那个嗯，方案"), "那个方案")
    }

    // MARK: - Discourse marker preservation (spec §4.3)

    func testNonConfiguredDiscourseMarkersPreserved() {
        // 啊, 哦, 哎 are NOT in the filler list — they carry tone/meaning.
        XCTAssertEqual(FillerWordFilter.process("啊这个不错"), "啊这个不错")
        XCTAssertEqual(FillerWordFilter.process("哦我知道了"), "哦我知道了")
        XCTAssertEqual(FillerWordFilter.process("哎不对"), "哎不对")
    }

    func testDiscourseMarkerPhrasesPreserved() {
        // 其实, 然后, 那个, 这个 must be preserved.
        XCTAssertEqual(FillerWordFilter.process("其实这个方案成本太高"), "其实这个方案成本太高")
        XCTAssertEqual(FillerWordFilter.process("然后那个问题"), "然后那个问题")
        XCTAssertEqual(FillerWordFilter.process("这个我知道"), "这个我知道")
    }

    // MARK: - Coding context preserves Latin identifiers (spec §4.5)

    func testCodingContextPreservesLatinIdentifierLikeWords() {
        // Latin words that match fillers are preserved in coding context,
        // while CJK fillers are still removed.
        XCTAssertEqual(
            FillerWordFilter.process("var um = 42", context: .init(isCodingContext: true)),
            "var um = 42"
        )
        XCTAssertEqual(
            FillerWordFilter.process("let hmm = \"test\"", context: .init(isCodingContext: true)),
            "let hmm = \"test\""
        )
        XCTAssertEqual(
            FillerWordFilter.process("嗯 set x = 1", context: .init(isCodingContext: true)),
            "set x = 1"
        )
    }
}

final class PunctuationOptimizerTests: XCTestCase {
    func testHalfWidthToFullWidthInCJKContext() {
        let result = PunctuationOptimizer.process("你好,世界.")
        XCTAssertTrue(result.contains("，"))
        XCTAssertTrue(result.contains("。"))
    }

    func testHalfWidthPreservedInEnglishContext() {
        let result = PunctuationOptimizer.process("Hello world, this is a test.")
        // English context: commas should remain half-width.
        XCTAssertTrue(result.contains(","))
    }

    func testConsecutivePunctuationCollapsed() {
        let result = PunctuationOptimizer.process("什么。。。")
        // Should reduce to at most 2 consecutive.
        XCTAssertFalse(result.contains("。。。"))
    }

    func testSentenceEndingPunctuationAddedForCJK() {
        let result = PunctuationOptimizer.process("今天天气不错")
        XCTAssertTrue(result.hasSuffix("。"))
    }

    func testExistingEndingPunctuationPreserved() {
        let result = PunctuationOptimizer.process("今天天气不错。")
        XCTAssertEqual(result, "今天天气不错。")
    }

    // MARK: - Protected regions (spec §5.1, §5.2)

    func testURLPunctuationPreserved() {
        let result = PunctuationOptimizer.process("访问 https://example.com 查看情况")
        XCTAssertTrue(result.contains("https://example.com"))
        XCTAssertFalse(result.contains("example。com"))
    }

    func testVersionStringPunctuationPreserved() {
        let result = PunctuationOptimizer.process("升级到版本 2.1.3 了")
        XCTAssertTrue(result.contains("2.1.3"))
        XCTAssertFalse(result.contains("2。1。3"))
    }

    func testBacktickCodeSpanPunctuationPreserved() {
        let result = PunctuationOptimizer.process("使用 `arr.filter(x => x > 0)` 处理")
        XCTAssertTrue(result.contains("arr.filter(x => x > 0)"))
    }

    func testPathPunctuationPreserved() {
        let result = PunctuationOptimizer.process("文件在 /usr/local/bin 目录")
        XCTAssertTrue(result.contains("/usr/local/bin"))
    }

    // MARK: - Threshold-gated sentence completion (spec §5.3)

    func testEnglishSentenceCompletionRespectsWordThreshold() {
        // Below threshold: no period added.
        let short = PunctuationOptimizer.process("hello world", context: .init(cjkThreshold: 3, wordThreshold: 4))
        XCTAssertFalse(short.hasSuffix("."))
        // At or above threshold: period added.
        let sentence = PunctuationOptimizer.process("this is a test sentence", context: .init(cjkThreshold: 3, wordThreshold: 4))
        XCTAssertTrue(sentence.hasSuffix("."))
    }

    func testCJKSentenceCompletionRespectsCJKThreshold() {
        // CJK context with enough characters: period added.
        let result = PunctuationOptimizer.process("今天天气不错", context: .init(cjkThreshold: 3, wordThreshold: 4))
        XCTAssertTrue(result.hasSuffix("。"))
        // High CJK threshold: half→full conversion is skipped (no CJK context
        // detected for conversion), but sentence completion still adds 。 if
        // there are 2+ CJK chars (secondary check in completion logic).
        // This is by design: sentence completion is more aggressive than
        // half→full conversion for CJK text.
        let highThreshold = PunctuationOptimizer.process("你好世界", context: .init(cjkThreshold: 10, wordThreshold: 4))
        XCTAssertTrue(highThreshold.hasSuffix("。"))
    }

    func testReferenceFixtureDocumentsPunctuationBehavior() throws {
        let fixtureURL = try XCTUnwrap(
            Bundle.module.url(forResource: "punctuation_reference", withExtension: "json"),
            "Missing punctuation reference fixture"
        )
        let fixture = try JSONDecoder().decode(PunctuationReferenceFixture.self, from: Data(contentsOf: fixtureURL))
        XCTAssertEqual(fixture.source, "VoxFlow rules informed by WeTextProcessing Chinese postprocessor")
        XCTAssertEqual(fixture.upstreamReference, "wenet-e2e/WeTextProcessing tn/chinese/rules/postprocessor.py")
        XCTAssertEqual(fixture.cases.count, fixture.caseCount)
        XCTAssertTrue(fixture.exclusions.allSatisfy { !$0.reason.isEmpty })

        for testCase in fixture.cases {
            XCTAssertEqual(
                PunctuationOptimizer.process(
                    testCase.input,
                    context: .init(cjkThreshold: testCase.cjkThreshold, wordThreshold: testCase.wordThreshold)
                ),
                testCase.expected,
                "case: \(testCase.name)"
            )
        }
    }
}

private struct PunctuationReferenceFixture: Decodable {
    struct Case: Decodable {
        let name: String
        let input: String
        let expected: String
        let cjkThreshold: Int
        let wordThreshold: Int
    }

    struct Exclusion: Decodable {
        let upstream: String
        let reason: String
    }

    let source: String
    let upstreamReference: String
    let caseCount: Int
    let cases: [Case]
    let exclusions: [Exclusion]
}

final class LongSentenceBreakerTests: XCTestCase {
    func testLongCJKSentenceBreaks() {
        let long = "今天我们需要讨论一下这个方案的可行性，然后确认一下预算，最后安排一下时间表，确保 everyone 知道自己的任务"
        let result = LongSentenceBreaker.process(long, context: .init(wordThreshold: 5, cjkThreshold: 10))
        XCTAssertTrue(result.contains("\n"))
    }

    func testShortSentenceStaysInline() {
        let short = "今天天气不错"
        let result = LongSentenceBreaker.process(short, context: .init(wordThreshold: 18, cjkThreshold: 40))
        XCTAssertEqual(result, short)
    }

    func testNoSplitPointsReturnsOriginal() {
        let noCommas = "这是一个没有逗号的长句子用于测试在没有分割点的情况下不会发生错误处理"
        let result = LongSentenceBreaker.process(noCommas, context: .init(wordThreshold: 5, cjkThreshold: 5))
        // No split points → return original (no mid-word breaking).
        XCTAssertEqual(result, noCommas)
    }

    func testSentenceEndPunctuationIsStrongSplitBoundary() {
        let text = "明天早上 11 点我来叫你啊。然后你等一下，我再想一下具体应该做些什么。我来查一下设置页预览和真实管线的处理路径，然后重点看一下有没有绕过。"
        let result = LongSentenceBreaker.process(text, context: .init(wordThreshold: 80, cjkThreshold: 32))

        XCTAssertTrue(result.contains("啊。\n然后你等一下，"), result)
        XCTAssertTrue(result.contains("什么。\n我来查一下"), result)
    }

    // MARK: - CJK delimiter splits (spec §6.1)

    func testCJKDelimiterSplitsAtCommaAndSemicolon() {
        let long = "第一部分内容在这里，第二部分内容在这里；第三部分内容在这里，第四部分内容在这里"
        let result = LongSentenceBreaker.process(long, context: .init(wordThreshold: 5, cjkThreshold: 10))
        XCTAssertTrue(result.contains("\n"))
        // Should break at CJK delimiters, not mid-word.
        XCTAssertFalse(result.contains("内容\n内容"))
    }

    // MARK: - English word threshold splits (spec §6.1)

    func testEnglishWordThresholdTriggersSplit() {
        let long = "first segment here, second segment here, third segment here, fourth segment here"
        let result = LongSentenceBreaker.process(long, context: .init(wordThreshold: 5, cjkThreshold: 40))
        XCTAssertTrue(result.contains("\n"))
    }

    // MARK: - Mixed text (spec §6.1)

    func testMixedCJKAndEnglishBreaks() {
        let long = "我们讨论了the first item然后确认了the second item最后安排了the third item"
        let result = LongSentenceBreaker.process(long, context: .init(wordThreshold: 5, cjkThreshold: 10))
        // Should either break at delimiters or return original if no safe points.
        // The key assertion: no mid-word or mid-token breaking.
        XCTAssertFalse(result.contains("the\nfirst"))
        XCTAssertFalse(result.contains("我\n们"))
    }

    // MARK: - Preserve real line breaks (spec §6.3)

    func testExistingLineBreaksPreserved() {
        let text = "第一行内容\n第二行内容\n第三行内容"
        let result = LongSentenceBreaker.process(text, context: .init(wordThreshold: 18, cjkThreshold: 40))
        XCTAssertEqual(result, text)
    }

    // MARK: - No-safe-boundary preservation (spec §6.1, §6.2)

    func testLongTextWithoutSafeBoundariesPreserved() {
        let long = "这是一个非常非常非常非常非常非常非常非常非常非常长的中文句子没有任何分隔符"
        let result = LongSentenceBreaker.process(long, context: .init(wordThreshold: 5, cjkThreshold: 5))
        // No safe split points → return original unchanged.
        XCTAssertEqual(result, long)
    }

    // MARK: - Threshold sensitivity (spec §6.4)

    func testThresholdChangesAffectBreaking() {
        let text = "短句一，短句二，短句三"
        // High threshold: no breaking.
        let noBreak = LongSentenceBreaker.process(text, context: .init(wordThreshold: 18, cjkThreshold: 40))
        XCTAssertFalse(noBreak.contains("\n"))
        // Low threshold: breaking occurs.
        let withBreak = LongSentenceBreaker.process(text, context: .init(wordThreshold: 1, cjkThreshold: 1))
        XCTAssertTrue(withBreak.contains("\n"))
    }
}

final class CJKLatinSpacerTests: XCTestCase {
    func testNaturalSpacingAdded() {
        XCTAssertEqual(
            CJKLatinSpacer.process("Hello世界"),
            "Hello 世界"
        )
    }

    func testDigitSpacingAdded() {
        XCTAssertEqual(
            CJKLatinSpacer.process("共3个文件"),
            "共 3 个文件"
        )
    }

    func testURLPreserved() {
        let result = CJKLatinSpacer.process("访问 https://example.com 查看")
        XCTAssertTrue(result.contains("https://example.com"))
        // URL should not be split.
        XCTAssertFalse(result.contains("https ://"))
    }

    func testPathPreserved() {
        let result = CJKLatinSpacer.process("文件在 /api/v1/users 目录")
        XCTAssertTrue(result.contains("/api/v1/users"))
    }

    func testBacktickContentPreserved() {
        let result = CJKLatinSpacer.process("使用 `user_id` 字段")
        XCTAssertTrue(result.contains("`user_id`"))
    }

    func testEmailPreserved() {
        let result = CJKLatinSpacer.process("发给 test@example.com 好了")
        XCTAssertTrue(result.contains("test@example.com"))
    }

    func testVersionPreserved() {
        let result = CJKLatinSpacer.process("升级到版本 2.1.3 了")
        XCTAssertTrue(result.contains("2.1.3"))
    }
}

final class AutoCapitalizerTests: XCTestCase {
    func testEnglishSentenceCapitalized() {
        XCTAssertEqual(
            AutoCapitalizer.process("hello world."),
            "Hello world."
        )
    }

    func testCodingContextSkipped() {
        XCTAssertEqual(
            AutoCapitalizer.process("userName is cool", context: .init(isCodingContext: true)),
            "userName is cool"
        )
    }

    func testIdentifierNotCapitalized() {
        // Single token with no space → likely identifier, skip.
        XCTAssertEqual(
            AutoCapitalizer.process("camelCase"),
            "camelCase"
        )
    }

    func testURLNotCapitalized() {
        XCTAssertEqual(
            AutoCapitalizer.process("https://example.com is down"),
            "https://example.com is down"
        )
    }

    func testPathNotCapitalized() {
        XCTAssertEqual(
            AutoCapitalizer.process("/usr/local/bin is the path"),
            "/usr/local/bin is the path"
        )
    }

    func testMultipleLinesCapitalized() {
        let result = AutoCapitalizer.process("hello world.\nsecond line here.")
        XCTAssertTrue(result.hasPrefix("Hello world."))
        XCTAssertTrue(result.contains("Second line here."))
    }
}

final class DeterministicTextPipelineTests: XCTestCase {
    func testDisabledPipelineIsNoOp() {
        // Explicitly disabled: no-op regardless of sub-toggles.
        let settings = DeterministicTextProcessingSettings(
            enabled: false, fillerWordFiltering: true, cjkLatinSpacing: true
        )
        let pipeline = DeterministicTextPipeline(settings: settings)
        let input = "嗯hello世界"
        XCTAssertEqual(pipeline.preLLM(input), input)
        XCTAssertEqual(pipeline.postLLM(input), input)
    }

    func testDefaultsPreLLMRunsFillerFilter() {
        // Defaults: master on, filler filtering on. Filler should be removed.
        let pipeline = DeterministicTextPipeline(settings: .defaults)
        XCTAssertEqual(pipeline.preLLM("嗯这个功能需要改一下"), "这个功能需要改一下")
    }

    func testDefaultsPostLLMRunsSpacingAndPunctuation() {
        // Defaults: master on, punctuation + spacing on.
        let pipeline = DeterministicTextPipeline(settings: .defaults)
        let result = pipeline.postLLM("Hello世界")
        XCTAssertTrue(result.contains("Hello 世界"))
    }

    func testPostLLMNormalizesEscapedLineBreaksBeforeFormatting() {
        let pipeline = DeterministicTextPipeline(settings: .defaults)
        let result = pipeline.postLLM("系统提示词不应该一上来就直接达到十万或十十K的级别。\\n我看到它一上来就开始压缩")

        XCTAssertFalse(result.contains("\\n"))
        XCTAssertTrue(result.contains("\n"))
        XCTAssertFalse(result.contains("20K"))
        XCTAssertFalse(result.contains("20 K"))
    }

    func testCodingContextPreservesEscapedLineBreaks() {
        let pipeline = DeterministicTextPipeline(settings: .defaults)
        let result = pipeline.postLLM(#"let separator = "\n""#, isCodingContext: true)

        XCTAssertEqual(result, #"let separator = "\n""#)
    }

    func testDefaultsLongSentenceBreakingIsOff() {
        // Defaults: longSentenceBreaking is off even when master is on.
        let pipeline = DeterministicTextPipeline(settings: .defaults)
        let long = "今天我们需要讨论一下这个方案的可行性，然后确认一下预算，最后安排一下时间表，确保 everyone 知道自己的任务"
        let result = pipeline.postLLM(long)
        // No line breaking applied because longSentenceBreaking defaults off.
        XCTAssertFalse(result.contains("\n"))
    }

    func testPreLLMDoesNotRunPostLLMProcessors() {
        // Pre-LLM should NOT do CJK-Latin spacing (that's post-LLM's job).
        let settings = DeterministicTextProcessingSettings(
            enabled: true, fillerWordFiltering: true, cjkLatinSpacing: true
        )
        let pipeline = DeterministicTextPipeline(settings: settings)
        let preResult = pipeline.preLLM("嗯Hello世界")
        // Filler removed, but spacing NOT applied in pre-LLM.
        XCTAssertEqual(preResult, "Hello世界")
    }

    func testPostLLMDoesNotRunPreLLMProcessors() {
        // Post-LLM should NOT do filler filtering (that's pre-LLM's job).
        let settings = DeterministicTextProcessingSettings(
            enabled: true, fillerWordFiltering: true, cjkLatinSpacing: true
        )
        let pipeline = DeterministicTextPipeline(settings: settings)
        let postResult = pipeline.postLLM("嗯Hello世界")
        // Filler NOT removed in post-LLM, but spacing applied.
        XCTAssertTrue(postResult.contains("嗯"))
        XCTAssertTrue(postResult.contains("Hello 世界"))
    }

    func testFullPipelinePrePostOrder() {
        let settings = DeterministicTextProcessingSettings(
            enabled: true,
            punctuationOptimization: true,
            fillerWordFiltering: true,
            cjkLatinSpacing: true
        )
        let pipeline = DeterministicTextPipeline(settings: settings)
        let raw = "嗯今天测试一下Hello世界"
        let preProcessed = pipeline.preLLM(raw)
        // Pre-LLM: filler removed.
        XCTAssertFalse(preProcessed.contains("嗯"))
        // Post-LLM: spacing + punctuation applied.
        let postProcessed = pipeline.postLLM(preProcessed)
        XCTAssertTrue(postProcessed.contains("Hello 世界"))
        XCTAssertTrue(postProcessed.hasSuffix("。") || postProcessed.hasSuffix("世界。"))
    }

    func testCodingContextProtectsLatinFillersAndCapitalization() {
        // Coding context protects Latin filler-like identifiers and disables capitalization, but
        // NOT punctuation/spacing/numbers. Disable those here to isolate the
        // filler + capitalization behavior.
        let settings = DeterministicTextProcessingSettings(
            enabled: true,
            smartNumberRecognition: false,
            punctuationOptimization: false,
            fillerWordFiltering: true,
            cjkLatinSpacing: false,
            autoCapitalization: true
        )
        let pipeline = DeterministicTextPipeline(settings: settings)
        let code = "var um = hello world"
        XCTAssertEqual(pipeline.preLLM(code, isCodingContext: true), code)
        XCTAssertEqual(pipeline.postLLM(code, isCodingContext: true), code)
    }

    func testCodingContextStillRemovesCJKFillersInPreLLM() {
        let settings = DeterministicTextProcessingSettings(
            enabled: true,
            smartNumberRecognition: false,
            fillerWordFiltering: true
        )
        let pipeline = DeterministicTextPipeline(settings: settings)

        // CJK fillers are removed even in coding context. Adjacent punctuation
        // is also cleaned up, so the leading `，` after removing `嗯` is gone.
        XCTAssertEqual(
            pipeline.preLLM("嗯，达到那个嗯十万", isCodingContext: true),
            "达到那个十万"
        )
    }
}

final class DeterministicTextProcessingSettingsTests: XCTestCase {
    func testDefaultsAreEnabledExceptLongSentenceBreaking() {
        let s = DeterministicTextProcessingSettings.defaults
        XCTAssertTrue(s.enabled)
        XCTAssertTrue(s.smartNumberRecognition)
        XCTAssertTrue(s.punctuationOptimization)
        XCTAssertFalse(s.longSentenceBreaking)
        XCTAssertTrue(s.fillerWordFiltering)
        XCTAssertTrue(s.cjkLatinSpacing)
        XCTAssertTrue(s.autoCapitalization)
    }

    func testDefaultThresholdsMatchSettingsResetTargets() {
        let s = DeterministicTextProcessingSettings.defaults
        XCTAssertEqual(s.longSentenceWordThreshold, 8)
        XCTAssertEqual(s.longSentenceCJKThreshold, 12)
        XCTAssertEqual(s.punctuationWordThreshold, 4)
        XCTAssertEqual(s.punctuationCJKThreshold, 3)
    }

    func testEffectiveSettingsWhenDisabled() {
        let s = DeterministicTextProcessingSettings(
            enabled: false, fillerWordFiltering: true, cjkLatinSpacing: true
        )
        let effective = s.effectiveSettings()
        XCTAssertFalse(effective.enabled)

        XCTAssertFalse(effective.fillerWordFiltering)
        XCTAssertFalse(effective.cjkLatinSpacing)
    }

    func testEffectiveSettingsWhenEnabled() {
        let s = DeterministicTextProcessingSettings(
            enabled: true, fillerWordFiltering: true
        )
        let effective = s.effectiveSettings()
        XCTAssertTrue(effective.enabled)
        XCTAssertTrue(effective.fillerWordFiltering)
    }

    func testSettingsCodableRoundTrip() throws {
        let s = DeterministicTextProcessingSettings(
            enabled: true, fillerWordFiltering: true, cjkLatinSpacing: true,
            longSentenceWordThreshold: 25, punctuationCJKThreshold: 5
        )
        let data = try JSONEncoder().encode(s)
        let decoded = try JSONDecoder().decode(DeterministicTextProcessingSettings.self, from: data)
        XCTAssertEqual(s, decoded)
    }
}

final class DeterministicTextProcessingSettingsStoreTests: XCTestCase {
    func testLoadReturnsDefaultsWhenEmpty() {
        let storage = InMemoryKeyValueStorage()
        let loaded = DeterministicTextProcessingSettingsStore.load(storage: storage)
        XCTAssertEqual(loaded, .defaults)
        XCTAssertTrue(loaded.enabled)
        XCTAssertTrue(loaded.fillerWordFiltering)
        XCTAssertFalse(loaded.longSentenceBreaking)
    }

    func testSaveAndLoadRoundTrip() throws {
        let storage = InMemoryKeyValueStorage()
        let settings = DeterministicTextProcessingSettings(
            enabled: true, fillerWordFiltering: true, cjkLatinSpacing: true
        )
        try DeterministicTextProcessingSettingsStore.save(settings, storage: storage)
        let loaded = DeterministicTextProcessingSettingsStore.load(storage: storage)
        XCTAssertEqual(loaded, settings)
    }

    func testLoadFallsBackOnCorruptJSON() {
        let storage = InMemoryKeyValueStorage()
        try? storage.set(
            DeterministicTextProcessingSettingsStore.settingsKey,
            jsonValue: "{invalid json}"
        )
        let loaded = DeterministicTextProcessingSettingsStore.load(storage: storage)
        XCTAssertEqual(loaded, .defaults)
    }

    func testLegacyAllOffPayloadMigratesToDefaults() throws {
        // Simulate a payload saved under the old all-off defaults (before
        // schemaVersion existed). The store should migrate it to the new
        // defaults (master on, all processors on except longSentenceBreaking)
        // on load, and persist the migrated payload.
        let storage = InMemoryKeyValueStorage()
        let legacyJSON = """
            {"enabled":false,"smartNumberRecognition":false,"punctuationOptimization":false,"longSentenceBreaking":false,"fillerWordFiltering":false,"cjkLatinSpacing":false,"autoCapitalization":false,"longSentenceWordThreshold":18,"longSentenceCJKThreshold":40,"punctuationCJKThreshold":3,"punctuationWordThreshold":4,"schemaVersion":0}
            """
        try storage.set(DeterministicTextProcessingSettingsStore.settingsKey, jsonValue: legacyJSON)

        let loaded = DeterministicTextProcessingSettingsStore.load(storage: storage)
        XCTAssertEqual(loaded, .defaults)
        XCTAssertEqual(loaded.schemaVersion, DeterministicTextProcessingSettings.currentSchemaVersion)

        // Subsequent load should not re-migrate (schemaVersion is now current).
        let reloaded = DeterministicTextProcessingSettingsStore.load(storage: storage)
        XCTAssertEqual(reloaded, .defaults)
    }

    func testExplicitlyDisabledSettingsArePreserved() throws {
        // A user who explicitly turned the master switch off (after migration
        // or with schemaVersion >= 1) should NOT be re-migrated to defaults.
        let storage = InMemoryKeyValueStorage()
        let explicit = DeterministicTextProcessingSettings(
            enabled: false,
            schemaVersion: DeterministicTextProcessingSettings.currentSchemaVersion
        )
        try DeterministicTextProcessingSettingsStore.save(explicit, storage: storage)

        let loaded = DeterministicTextProcessingSettingsStore.load(storage: storage)
        XCTAssertEqual(loaded, explicit)
        XCTAssertFalse(loaded.enabled)
    }
}

private final class InMemoryKeyValueStorage: KeyValueSettingsStorage, @unchecked Sendable {
    private var store: [String: String] = [:]
    private let lock = NSLock()

    func value(forKey key: String) throws -> String? {
        lock.withLock { store[key] }
    }

    func set(_ key: String, jsonValue: String) throws {
        lock.withLock { store[key] = jsonValue }
    }
}

// MARK: - SmartNumberRecognizer tests

final class SmartNumberRecognizerTests: XCTestCase {
    func testQuantityConversion() {
        // "三个" → "3个", "五次" → "5次"
        XCTAssertEqual(
            SmartNumberRecognizer.process("三个文件五次提交"),
            "3个文件5次提交"
        )
    }

    func testOneWithMeasureWordConverted() {
        // "一" alone is ambiguous; only convert with a measure word.
        // Per spec, 一+measureWord is a clear quantity context → convert.
        XCTAssertEqual(
            SmartNumberRecognizer.process("我有一条消息"),
            "我有1条消息"
        )
        // "十一" → "11" (structural: 10 + 1).
        XCTAssertEqual(
            SmartNumberRecognizer.process("十一个人"),
            "11个人"
        )
    }

    func testPercentConversion() {
        XCTAssertEqual(
            SmartNumberRecognizer.process("百分之三十的进度"),
            "30%的进度"
        )
    }

    func testYaoDigitSequenceConversion() {
        // "幺九二" → "192"
        XCTAssertEqual(
            SmartNumberRecognizer.process("电话号码幺九二"),
            "电话号码192"
        )
    }

    func testVersionStringPreserved() {
        // Version strings are protected from number conversion.
        let result = SmartNumberRecognizer.process("升级到版本 2.1.3 了")
        XCTAssertTrue(result.contains("2.1.3"))
    }

    func testUrlPreserved() {
        let url = "https://example.com/api/v1/users"
        let result = SmartNumberRecognizer.process("访问 \(url) 看看")
        XCTAssertTrue(result.contains(url))
    }

    func testBacktickContentPreserved() {
        let result = SmartNumberRecognizer.process("使用 `var_three` 字段")
        XCTAssertTrue(result.contains("`var_three`"))
    }

    func testStructuralNumberConversion() {
        // "十二" → "12", "一百" → "100"
        XCTAssertEqual(
            SmartNumberRecognizer.process("十二点开会"),
            "12点开会"
        )
    }

    func testTenBeforeUnitConvertsInQuantityContext() {
        XCTAssertEqual(
            SmartNumberRecognizer.process("达到十万或十K的级别"),
            "达到100000或10K的级别"
        )
    }

    func testInvalidRepeatedTenIsPreserved() {
        XCTAssertEqual(
            SmartNumberRecognizer.process("达到十十K的级别"),
            "达到十十K的级别"
        )
    }

    func testColloquialLargeUnitIsConvertedAsOneNumber() {
        XCTAssertEqual(
            SmartNumberRecognizer.process("一个亿"),
            "1个亿"
        )
        XCTAssertEqual(
            SmartNumberRecognizer.process("两个亿和十个亿"),
            "2个亿和10个亿"
        )
    }

    func testBareLargeUnitsAreNotConvertedToZero() {
        XCTAssertEqual(
            SmartNumberRecognizer.process("这里说的是亿和万"),
            "这里说的是亿和万"
        )
    }

    func testMalformedDigitRunBeforeTenIsPreserved() {
        XCTAssertEqual(
            SmartNumberRecognizer.process("一二三四五六七八九十个是百万"),
            "一二三四五六七八九十个是百万"
        )
    }

    func testCommonChineseWordsArePreserved() {
        XCTAssertEqual(
            SmartNumberRecognizer.process("一定要一起讨论一下三明治"),
            "一定要一起讨论一下三明治"
        )
        XCTAssertEqual(
            SmartNumberRecognizer.process("三十而立属于固定短语"),
            "三十而立属于固定短语"
        )
    }
}

// MARK: - PunctuationOptimizer word threshold tests

final class PunctuationWordThresholdTests: XCTestCase {
    func testWordThresholdGatesEnglishSentenceEnding() {
        // 2 words, threshold 4 → no auto-period.
        let result = PunctuationOptimizer.process(
            "hello world",
            context: .init(cjkThreshold: 3, wordThreshold: 4)
        )
        XCTAssertFalse(result.hasSuffix("."))
    }

    func testWordThresholdAllowsEnglishSentenceEnding() {
        // 5 words, threshold 4 → auto-period added.
        let result = PunctuationOptimizer.process(
            "this is a simple test",
            context: .init(cjkThreshold: 3, wordThreshold: 4)
        )
        XCTAssertTrue(result.hasSuffix("."))
    }

    func testWordThresholdDoesNotAffectCJK() {
        // CJK context: word threshold is irrelevant, 。 is added.
        let result = PunctuationOptimizer.process(
            "今天天气不错",
            context: .init(cjkThreshold: 2, wordThreshold: 100)
        )
        XCTAssertTrue(result.hasSuffix("。"))
    }

    func testExistingEndingPunctuationSkipsCompletion() {
        let result = PunctuationOptimizer.process(
            "this is a simple test.",
            context: .init(cjkThreshold: 3, wordThreshold: 4)
        )
        XCTAssertEqual(result, "this is a simple test.")
    }
}

// MARK: - Pipeline integration with smart numbers and settings

final class DeterministicTextPipelineSmartNumberTests: XCTestCase {
    func testSmartNumberRunsInPreLLMWhenEnabled() {
        let settings = DeterministicTextProcessingSettings(
            enabled: true, smartNumberRecognition: true
        )
        let pipeline = DeterministicTextPipeline(settings: settings)
        let pre = pipeline.preLLM("百分之三十的进度")
        XCTAssertTrue(pre.contains("30%"))
    }

    func testSmartNumberDoesNotRunInPostLLM() {
        // Smart number recognition is a pre-LLM processor only.
        let settings = DeterministicTextProcessingSettings(
            enabled: true, smartNumberRecognition: true
        )
        let pipeline = DeterministicTextPipeline(settings: settings)
        let post = pipeline.postLLM("百分之三十的进度")
        // post-LLM should NOT have converted the number.
        XCTAssertFalse(post.contains("30%"))
    }

    func testSmartNumberSkippedWhenDisabled() {
        let settings = DeterministicTextProcessingSettings(
            enabled: true, smartNumberRecognition: false
        )
        let pipeline = DeterministicTextPipeline(settings: settings)
        let pre = pipeline.preLLM("百分之三十的进度")
        XCTAssertEqual(pre, "百分之三十的进度")
    }
}
