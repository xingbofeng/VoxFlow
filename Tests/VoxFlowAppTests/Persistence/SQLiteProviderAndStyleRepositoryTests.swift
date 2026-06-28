import XCTest
@testable import VoxFlowApp

final class SQLiteProviderAndStyleRepositoryTests: XCTestCase {
    private var queue: DatabaseQueue!
    private var styles: SQLiteStyleRepository!
    private var asrProviders: SQLiteASRProviderRepository!
    private var llmProviders: SQLiteLLMProviderRepository!
    private var jobs: SQLiteTranscriptionJobRepository!

    override func setUpWithError() throws {
        try super.setUpWithError()
        queue = try DatabaseQueue(connection: .inMemory())
        try AppDatabase.migrator().migrate(queue)
        styles = SQLiteStyleRepository(databaseQueue: queue)
        asrProviders = SQLiteASRProviderRepository(databaseQueue: queue)
        llmProviders = SQLiteLLMProviderRepository(databaseQueue: queue)
        jobs = SQLiteTranscriptionJobRepository(databaseQueue: queue)
    }

    override func tearDown() {
        jobs = nil
        llmProviders = nil
        asrProviders = nil
        styles = nil
        queue = nil
        super.tearDown()
    }

    func testStyleRepositorySavesAndListsDefaultProfile() throws {
        let profile = StyleProfileRecord(
            id: "coding",
            name: "编程",
            category: "work",
            subtitle: "技术词优先",
            mode: "conservative",
            prompt: "只修正明显 ASR 错误",
            sampleInput: "配森",
            sampleOutput: "Python",
            llmProviderID: "llm",
            model: "gpt-test",
            temperature: 0.1,
            enabled: true,
            builtIn: true,
            isDefault: true,
            createdAt: testDate,
            updatedAt: testDate
        )

        try styles.save(profile)

        XCTAssertEqual(try styles.defaultProfile()?.id, "coding")
        XCTAssertEqual(try styles.list(category: "work").map(\.id), ["coding"])
    }

    func testStyleRepositoryReadsLegacyRowWithFractionalSecondTimestamp() throws {
        // 历史上 style_profiles 可能被外部（旧版代码、Python 维护脚本等）写过带毫秒的 ISO8601 时间戳，
        // 仅靠默认 ISO8601DateFormatter 解析会失败并让整个持久化层标 unavailable。
        // 读取路径必须兼容这种历史脏数据。
        try queue.write { connection in
            try connection.execute(
                """
                INSERT INTO style_profiles (id, name, category, subtitle, mode, prompt, sample_input,
                                            sample_output, llm_provider_id, model, temperature, enabled,
                                            built_in, is_default, created_at, updated_at)
                VALUES ('legacy', 'legacy', 'work', NULL, 'conservative', 'p', NULL, NULL, NULL, NULL, 0.0, 1, 0, 0,
                        '2026-06-18T06:31:59Z', '2026-06-28T19:07:59.200Z')
                """
            )
        }

        let profiles = try styles.list(category: nil)
        let legacy = try XCTUnwrap(profiles.first { $0.id == "legacy" })
        XCTAssertEqual(
            legacy.updatedAt.timeIntervalSince1970,
            Date(timeIntervalSince1970: 1_782_673_679).timeIntervalSince1970,
            accuracy: 1
        )
    }

    func testProviderRepositoriesStoreProviderMetadataWithoutPlaintextKey() throws {
        try asrProviders.save(
            ASRProviderRecord(
                id: "apple",
                displayName: "Apple Speech",
                providerType: "appleSpeech",
                capabilitiesJSON: #"{"streaming":true}"#,
                tagsJSON: #"["system"]"#,
                configJSON: #"{}"#,
                enabled: true,
                isDefault: true,
                lastHealthStatus: "ok",
                lastHealthMessage: nil,
                lastCheckedAt: testDate,
                createdAt: testDate,
                updatedAt: testDate
            )
        )
        try llmProviders.save(
            LLMProviderRecord(
                id: "openai",
                displayName: "OpenAI-compatible",
                providerType: "openaiCompatible",
                baseURL: "https://api.example.com/v1",
                defaultModel: "model",
                apiKeyRef: "provider-openai",
                temperature: 0.2,
                timeoutSeconds: 8,
                enabled: true,
                isDefault: true,
                lastHealthStatus: nil,
                lastHealthMessage: nil,
                lastLatencyMS: nil,
                createdAt: testDate,
                updatedAt: testDate
            )
        )

        XCTAssertEqual(try asrProviders.list().map(\.id), ["apple"])
        let llm = try XCTUnwrap(llmProviders.provider(id: "openai"))
        XCTAssertEqual(llm.apiKeyRef, "provider-openai")
    }

    func testTranscriptionJobRepositoryUpdatesProgressAndStatus() throws {
        let job = TranscriptionJobRecord(
            id: "job-1",
            sourceFilePath: "/tmp/audio.m4a",
            sourceFileName: "audio.m4a",
            status: "queued",
            progress: 0,
            rawText: nil,
            finalText: nil,
            asrProviderID: "apple",
            styleID: nil,
            errorMessage: nil,
            durationMS: 0,
            createdAt: testDate,
            updatedAt: testDate,
            completedAt: nil
        )

        try jobs.save(job)
        try jobs.updateStatus(id: "job-1", status: "running", progress: 0.5, updatedAt: testDate)

        let saved = try XCTUnwrap(jobs.job(id: "job-1"))
        XCTAssertEqual(saved.status, "running")
        XCTAssertEqual(saved.progress, 0.5)
    }

    private var testDate: Date {
        Date(timeIntervalSince1970: 1_800_000_000)
    }
}
