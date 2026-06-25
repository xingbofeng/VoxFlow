import Foundation
import VoxFlowProviderCloudCore
import VoxFlowProviderGroq
import XCTest

final class GroqCloudASRClientTests: XCTestCase {
    func testConnectionReadsCredentialAndCallsOfficialModelsEndpoint() async throws {
        let credentials = InMemoryGroqCredentialStore(values: ["groq-key": "secret"])
        let transport = CapturingCloudASRTransport(
            data: Data(#"{"data":[]}"#.utf8),
            statusCode: 200
        )
        let client = GroqCloudASRClient(credentialStore: credentials, transport: transport)

        let result = try await client.testConnection(configuration: configuration())

        let request = try XCTUnwrap(transport.requests.first)
        XCTAssertEqual(request.url?.absoluteString, "https://api.groq.com/openai/v1/models")
        XCTAssertEqual(request.httpMethod, "GET")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer secret")
        XCTAssertEqual(result.status, .ok)
    }

    func testTranscriptionUploadsMultipartAudioAndDecodesVerboseJSON() async throws {
        let audioURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("groq-\(UUID().uuidString).wav")
        try Data("audio-bytes".utf8).write(to: audioURL)
        addTeardownBlock { try? FileManager.default.removeItem(at: audioURL) }
        let credentials = InMemoryGroqCredentialStore(values: ["groq-key": "secret"])
        let transport = CapturingCloudASRTransport(
            data: Data(#"{"text":"识别结果","duration":1.25}"#.utf8),
            statusCode: 200
        )
        let client = GroqCloudASRClient(credentialStore: credentials, transport: transport)
        let progress = LockedGroqProgressCapture()

        let result = try await client.transcribeFile(
            CloudASRFileRequest(
                fileURL: audioURL,
                locale: Locale(identifier: "zh_CN"),
                configuration: configuration(),
                prompt: "VoxFlow, tokenhub"
            )
        ) { progress.append($0) }

        let request = try XCTUnwrap(transport.uploadRequests.first)
        let body = try XCTUnwrap(transport.uploadBodies.first)
        let bodyText = String(decoding: body, as: UTF8.self)
        XCTAssertEqual(request.url?.absoluteString, "https://api.groq.com/openai/v1/audio/transcriptions")
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertTrue(request.value(forHTTPHeaderField: "Content-Type")?.hasPrefix("multipart/form-data; boundary=") == true)
        XCTAssertNil(request.httpBody)
        XCTAssertTrue(bodyText.contains(#"name="model""#))
        XCTAssertTrue(bodyText.contains("whisper-large-v3-turbo"))
        XCTAssertTrue(bodyText.contains(#"name="language""#))
        XCTAssertTrue(bodyText.contains("zh"))
        XCTAssertTrue(bodyText.contains(#"name="prompt""#))
        XCTAssertTrue(bodyText.contains("VoxFlow, tokenhub"))
        XCTAssertTrue(bodyText.contains("audio-bytes"))
        XCTAssertEqual(progress.values, [0, 1])
        XCTAssertEqual(result.text, "识别结果")
        XCTAssertEqual(result.durationSeconds, 1.25)
        XCTAssertEqual(result.providerID, GroqCloudASRClient.defaultProviderID)
    }

    func testTranscriptionUsesFileBackedMultipartUpload() async throws {
        let audioURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("groq-\(UUID().uuidString).wav")
        try Data("audio-bytes".utf8).write(to: audioURL)
        addTeardownBlock { try? FileManager.default.removeItem(at: audioURL) }
        let credentials = InMemoryGroqCredentialStore(values: ["groq-key": "secret"])
        let transport = CapturingCloudASRTransport(
            data: Data(#"{"text":"识别结果","duration":1.25}"#.utf8),
            statusCode: 200
        )
        let client = GroqCloudASRClient(credentialStore: credentials, transport: transport)

        _ = try await client.transcribeFile(
            CloudASRFileRequest(
                fileURL: audioURL,
                locale: Locale(identifier: "zh_CN"),
                configuration: configuration()
            ),
            progress: { _ in }
        )

        let request = try XCTUnwrap(transport.uploadRequests.first)
        let body = try XCTUnwrap(transport.uploadBodies.first)
        let bodyText = String(decoding: body, as: UTF8.self)
        XCTAssertNil(request.httpBody)
        XCTAssertTrue(bodyText.contains(#"name="model""#))
        XCTAssertTrue(bodyText.contains("whisper-large-v3-turbo"))
        XCTAssertTrue(bodyText.contains("audio-bytes"))
    }

    func testMissingCredentialFailsBeforeNetworkRequest() async {
        let transport = CapturingCloudASRTransport(data: Data(), statusCode: 200)
        let client = GroqCloudASRClient(
            credentialStore: InMemoryGroqCredentialStore(),
            transport: transport
        )

        do {
            _ = try await client.testConnection(configuration: configuration())
            XCTFail("Expected missing credential error")
        } catch {
            XCTAssertEqual(error as? CloudASRClientError, .missingCredential)
        }
        XCTAssertTrue(transport.requests.isEmpty)
    }

    func testHTTPFailureReturnsProviderMessageWithoutLeakingCredential() async {
        let transport = CapturingCloudASRTransport(
            data: Data(#"{"error":{"message":"invalid key"}}"#.utf8),
            statusCode: 401
        )
        let client = GroqCloudASRClient(
            credentialStore: InMemoryGroqCredentialStore(values: ["groq-key": "secret"]),
            transport: transport
        )

        do {
            _ = try await client.testConnection(configuration: configuration())
            XCTFail("Expected request failure")
        } catch let error as CloudASRClientError {
            XCTAssertEqual(error, .requestFailed(statusCode: 401, message: "invalid key"))
            XCTAssertFalse(error.localizedDescription.contains("secret"))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testHTTPFailureRedactsCredentialEchoedByProvider() async {
        let transport = CapturingCloudASRTransport(
            data: Data(#"{"error":{"message":"invalid API key secret for account"}}"#.utf8),
            statusCode: 401
        )
        let client = GroqCloudASRClient(
            credentialStore: InMemoryGroqCredentialStore(values: ["groq-key": "secret"]),
            transport: transport
        )

        do {
            _ = try await client.testConnection(configuration: configuration())
            XCTFail("Expected request failure")
        } catch let error as CloudASRClientError {
            XCTAssertEqual(error, .requestFailed(statusCode: 401, message: "invalid API key <redacted> for account"))
            XCTAssertFalse(error.localizedDescription.contains("secret"))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    private func configuration() -> CloudASRProviderConfiguration {
            CloudASRProviderConfiguration(
            providerID: GroqCloudASRClient.defaultProviderID,
            displayName: "Groq（免费）",
            baseURL: GroqCloudASRClient.defaultBaseURL,
            model: GroqCloudASRClient.defaultModel,
            apiKeyRef: "groq-key",
            timeoutSeconds: 30
        )
    }
}

private final class InMemoryGroqCredentialStore: CloudASRCredentialReading, @unchecked Sendable {
    private var values: [String: String]

    init(values: [String: String] = [:]) {
        self.values = values
    }

    func readCredential(account: String) throws -> String? { values[account] }
    func saveCredential(_ value: String, account: String) throws { values[account] = value }
    func deleteCredential(account: String) throws { values.removeValue(forKey: account) }
}

private final class CapturingCloudASRTransport: CloudASRHTTPTransport, @unchecked Sendable {
    private(set) var requests: [URLRequest] = []
    private(set) var uploadRequests: [URLRequest] = []
    private(set) var uploadFileURLs: [URL] = []
    private(set) var uploadBodies: [Data] = []
    private let data: Data
    private let statusCode: Int

    init(data: Data, statusCode: Int) {
        self.data = data
        self.statusCode = statusCode
    }

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        requests.append(request)
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: statusCode,
            httpVersion: "HTTP/1.1",
            headerFields: nil
        )!
        return (data, response)
    }

    func upload(for request: URLRequest, fromFile fileURL: URL) async throws -> (Data, HTTPURLResponse) {
        uploadRequests.append(request)
        uploadFileURLs.append(fileURL)
        uploadBodies.append(try Data(contentsOf: fileURL))
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: statusCode,
            httpVersion: "HTTP/1.1",
            headerFields: nil
        )!
        return (data, response)
    }
}

private final class LockedGroqProgressCapture: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [Double] = []

    var values: [Double] {
        lock.withLock { storage }
    }

    func append(_ value: Double) {
        lock.withLock { storage.append(value) }
    }
}
