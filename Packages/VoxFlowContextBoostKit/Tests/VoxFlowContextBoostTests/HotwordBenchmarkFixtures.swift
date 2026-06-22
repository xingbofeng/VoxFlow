import XCTest
@testable import VoxFlowContextBoost

final class HotwordBenchmarkFixturesTests: XCTestCase {
    func testExtractAndRankAcrossRepresentativeOCRFixtures() {
        let extractor = HotwordExtractor()
        let ranker = HotwordRanker()

        for fixture in Self.fixtures {
            let candidates = extractor.extract(
                from: fixture.text,
                namedEntities: fixture.namedEntities,
                now: Date(timeIntervalSince1970: 1_800_000_000)
            )
            let ranked = ranker.rank(candidates)

            for expected in fixture.expectedTopK {
                XCTAssertTrue(
                    ranked.containsText(expected),
                    "\(fixture.name) should rank \(expected). ranked=\(ranked.map(\.text))"
                )
            }
            for rejected in fixture.rejected {
                XCTAssertFalse(
                    ranked.containsText(rejected),
                    "\(fixture.name) should not rank \(rejected). ranked=\(ranked.map(\.text))"
                )
            }
            XCTAssertLessThanOrEqual(ranked.count, HotwordRanker.defaultLimit)
        }
    }

    func testExtractAndRankEightThousandCharactersWithoutExplodingCandidateOrRuntime() {
        let extractor = HotwordExtractor()
        let ranker = HotwordRanker()
        let largeOCRText = String(
            Self.fixtures
                .map(\.text)
                .joined(separator: "\n")
                .repeatingToLength(8_000)
        )

        let startedAt = Date()
        for _ in 0..<20 {
            let candidates = extractor.extract(from: largeOCRText, namedEntities: [])
            let ranked = ranker.rank(candidates, limit: 30)
            XCTAssertLessThanOrEqual(candidates.count, 200)
            XCTAssertLessThanOrEqual(ranked.count, HotwordRanker.hardLimit)
        }
        let elapsed = Date().timeIntervalSince(startedAt)

        XCTAssertLessThan(elapsed, 1.0, "20 extraction/rank iterations should stay comfortably under 1s in debug")
    }

    private struct Fixture {
        let name: String
        let text: String
        let namedEntities: [NamedEntityCandidate]
        let expectedTopK: [String]
        let rejected: [String]
    }

    private static let fixtures: [Fixture] = [
        Fixture(
            name: "project release notes",
            text: "Project Apollo release plan\nCustomer feedback about Project Apollo\nLaunch risk review",
            namedEntities: [],
            expectedTopK: ["Project Apollo"],
            rejected: ["Customer feedback about"]
        ),
        Fixture(
            name: "customer account",
            text: "Acme Northwind renewal\nAccount owner Nina Chen\nFollow up on SOC2 attestation",
            namedEntities: [NamedEntityCandidate(text: "Nina Chen", kind: .person)],
            expectedTopK: ["Nina Chen", "Acme Northwind"],
            rejected: []
        ),
        Fixture(
            name: "design document",
            text: "Review Contextual Correction Spec\nCompare Voice Correction Plan\nOpen docs/voice-correction",
            namedEntities: [],
            expectedTopK: ["Contextual Correction Spec"],
            rejected: []
        ),
        Fixture(
            name: "provider names",
            text: "WhisperKit Qwen3-ASR FunASR SenseVoice\nVNRecognizeTextRequest and Package.swift",
            namedEntities: [],
            expectedTopK: ["Qwen3-ASR", "VNRecognizeTextRequest", "Package.swift"],
            rejected: []
        ),
        Fixture(
            name: "chat app chinese context",
            text: "码上写 发布计划\n语音键盘 体验反馈\n取消\n确定",
            namedEntities: [],
            expectedTopK: ["码上写", "语音键盘"],
            rejected: ["取消", "确定"]
        ),
        Fixture(
            name: "meeting people",
            text: "Sync with Laura Wang and OpenAI platform team\nProject Beacon decision log",
            namedEntities: [
                NamedEntityCandidate(text: "Laura Wang", kind: .person),
                NamedEntityCandidate(text: "OpenAI", kind: .organization),
            ],
            expectedTopK: ["Laura Wang", "OpenAI", "Project Beacon"],
            rejected: []
        ),
        Fixture(
            name: "code review identifiers",
            text: "DefaultTextProcessingPipeline\nCorrectionObservationCoordinator\nHighConfidenceCorrectionExtractor",
            namedEntities: [],
            expectedTopK: ["DefaultTextProcessingPipeline", "CorrectionObservationCoordinator"],
            rejected: []
        ),
        Fixture(
            name: "document filenames",
            text: "Open voice_correction_technical_spec.md\nUpdate Package.resolved\nCheck Makefile",
            namedEntities: [],
            expectedTopK: ["voice_correction_technical_spec.md", "Package.resolved"],
            rejected: []
        ),
        Fixture(
            name: "sales workspace",
            text: "Renewal Forecast North America\nGlobex expansion plan\nQuarterly risk memo",
            namedEntities: [NamedEntityCandidate(text: "Globex", kind: .organization)],
            expectedTopK: ["Globex", "Renewal Forecast"],
            rejected: []
        ),
        Fixture(
            name: "support issue",
            text: "Incident Horizon Rollback\nCustomer reports latency in Singapore\nTriage owner Alex Tan",
            namedEntities: [
                NamedEntityCandidate(text: "Singapore", kind: .place),
                NamedEntityCandidate(text: "Alex Tan", kind: .person),
            ],
            expectedTopK: ["Singapore", "Alex Tan", "Incident Horizon Rollback"],
            rejected: []
        ),
        Fixture(
            name: "wechat work",
            text: "飞书 会议纪要\n微信 客户回复\n下一步\n返回",
            namedEntities: [],
            expectedTopK: ["飞书", "微信"],
            rejected: ["下一步", "返回"]
        ),
        Fixture(
            name: "roadmap names",
            text: "Phase Two Roadmap\nOCR Context Boost\nAhoCorasickGlossaryMatcher later",
            namedEntities: [],
            expectedTopK: ["Phase Two Roadmap", "OCR", "AhoCorasickGlossaryMatcher"],
            rejected: []
        ),
        Fixture(
            name: "finance plan",
            text: "Budget Review Pack\nProject Atlas vendor quote\nStripe reconciliation",
            namedEntities: [NamedEntityCandidate(text: "Stripe", kind: .organization)],
            expectedTopK: ["Stripe", "Budget Review Pack"],
            rejected: []
        ),
        Fixture(
            name: "legal document",
            text: "Master Services Agreement\nData Processing Addendum\nAcme Legal",
            namedEntities: [NamedEntityCandidate(text: "Acme Legal", kind: .organization)],
            expectedTopK: ["Acme Legal", "Master Services Agreement"],
            rejected: []
        ),
        Fixture(
            name: "product analytics",
            text: "Activation Funnel Review\nNorth Star Metric\nRetention Cohort",
            namedEntities: [],
            expectedTopK: ["Activation Funnel Review", "North Star Metric"],
            rejected: []
        ),
        Fixture(
            name: "mac app window",
            text: "VoxFlow Settings\nLLM Provider\nVoice Correction Benchmark",
            namedEntities: [],
            expectedTopK: ["VoxFlow Settings", "LLM"],
            rejected: ["Settings"]
        ),
        Fixture(
            name: "command line",
            text: "swift test --filter HotwordExtractorTests\nmake run-dev\nVOICEINPUT_TEST_PROVIDER",
            namedEntities: [],
            expectedTopK: ["VOICEINPUT_TEST_PROVIDER"],
            rejected: []
        ),
        Fixture(
            name: "ml model names",
            text: "Qwen2.5-VL\nGPT-4o\nDeepSeek-R1\nMLX worker",
            namedEntities: [],
            expectedTopK: ["Qwen2.5-VL", "GPT-4o", "DeepSeek-R1"],
            rejected: []
        ),
        Fixture(
            name: "research note",
            text: "Retrieval Augmented Generation\nKeyword Extraction Survey\nNaturalLanguage named entities",
            namedEntities: [],
            expectedTopK: ["Retrieval Augmented Generation", "Keyword Extraction Survey"],
            rejected: []
        ),
        Fixture(
            name: "current user thread",
            text: "Claude Code 当前聊天框\nOCR Top-K 热词\nObservation Learning 保持启用",
            namedEntities: [],
            expectedTopK: ["OCR", "Top-K", "Observation Learning"],
            rejected: []
        ),
    ]
}

private extension Array where Element == TemporaryHotword {
    func containsText(_ text: String) -> Bool {
        contains { $0.text == text }
    }
}

private extension String {
    func repeatingToLength(_ targetLength: Int) -> String {
        guard !isEmpty else { return self }
        var result = ""
        while result.count < targetLength {
            result += self
            result += "\n"
        }
        return String(result.prefix(targetLength))
    }
}
