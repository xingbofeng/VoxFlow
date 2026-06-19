import XCTest
@testable import VoxFlowApp

final class LLMDiagnosticCaptureTests: XCTestCase {
    func testCaptureIsDisabledByDefault() throws {
        let directory = temporaryDirectory()
        let capture = LLMDiagnosticCapture()

        capture.capture(taskID: "task", trace: trace())

        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.path))
    }

    func testEnabledCaptureStoresRawTraceWithSecretsRedactedOutsideDatabase() throws {
        let directory = temporaryDirectory()
        let capture = LLMDiagnosticCapture()
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }

        capture.configure(enabled: true, directory: directory)
        capture.capture(
            taskID: "task/unsafe",
            trace: trace(
                request: #"{"api_key":"secret","messages":[{"content":"用户原始内容"}],"path":"/Users/alice/private.txt"}"#,
                response: "模型原始响应"
            ),
            at: Date(timeIntervalSince1970: 1_800_000_000)
        )

        let file = try XCTUnwrap(
            FileManager.default.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: nil
            ).first
        )
        let contents = try String(contentsOf: file, encoding: .utf8)
        XCTAssertTrue(contents.contains("用户原始内容"))
        XCTAssertTrue(contents.contains("模型原始响应"))
        XCTAssertFalse(contents.contains("secret"))
        XCTAssertFalse(contents.contains("alice"))
        XCTAssertTrue(contents.contains("[REDACTED]"))
    }

    func testDisablingCaptureDeletesExistingDiagnosticContent() throws {
        let directory = temporaryDirectory()
        let capture = LLMDiagnosticCapture()
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }

        capture.configure(enabled: true, directory: directory)
        capture.capture(taskID: "task", trace: trace())
        capture.configure(enabled: false, directory: directory)

        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.path))
    }

    func testDisabledConfigurationDeletesPreviousSessionDirectory() throws {
        let directory = temporaryDirectory()
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        try Data("previous diagnostic".utf8).write(
            to: directory.appendingPathComponent("previous.json")
        )
        let capture = LLMDiagnosticCapture()

        capture.configure(enabled: false, directory: directory)

        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.path))
    }

    func testPruneEnforcesRetentionAndMaximumTraceCount() throws {
        let directory = temporaryDirectory()
        let capture = LLMDiagnosticCapture(retentionInterval: 60, maximumTraceCount: 2)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let now = Date(timeIntervalSince1970: 1_800_000_000)

        capture.configure(enabled: true, directory: directory)
        capture.capture(taskID: "expired", trace: trace(response: "expired"), at: now.addingTimeInterval(-120))
        capture.capture(taskID: "first", trace: trace(response: "first"), at: now.addingTimeInterval(-20))
        capture.capture(taskID: "second", trace: trace(response: "second"), at: now.addingTimeInterval(-10))
        capture.capture(taskID: "third", trace: trace(response: "third"), at: now)
        capture.prune(now: now)

        let files = try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        )
        let contents = try files.map { try String(contentsOf: $0, encoding: .utf8) }
        XCTAssertEqual(files.count, 2)
        XCTAssertFalse(contents.contains(where: { $0.contains("expired") || $0.contains("first") }))
        XCTAssertTrue(contents.contains(where: { $0.contains("second") }))
        XCTAssertTrue(contents.contains(where: { $0.contains("third") }))
    }

    private func trace(
        request: String = #"{"messages":[{"content":"prompt"}]}"#,
        response: String = "response"
    ) -> TextProcessingTrace {
        TextProcessingTrace(
            llm: LLMRefinementTrace(
                providerID: "provider",
                providerName: "Provider",
                endpoint: "https://api.example.com/v1/chat/completions",
                model: "model",
                temperature: 0.2,
                timeoutSeconds: 8,
                requestBodyJSON: request,
                responseText: response,
                statusCode: 200,
                durationMS: 123,
                errorMessage: nil,
                completedAt: Date(timeIntervalSince1970: 1_800_000_000)
            )
        )
    }

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("VoxFlowLLMDiagnosticsTests-\(UUID().uuidString)", isDirectory: true)
    }
}
