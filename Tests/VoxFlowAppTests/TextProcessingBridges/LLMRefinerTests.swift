import Foundation
import XCTest
@testable import VoxFlowApp

final class LLMRefinerTests: XCTestCase {
    func testAPIKeyIgnoresUserDefaultsSecret() throws {
        let suiteName = "VoxFlowAppTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }
        let store = InMemoryCredentialStore()
        let defaultsSecret = "defaults-secret-\(UUID().uuidString)"

        defaults.set(defaultsSecret, forKey: "LLMRefiner_APIKey")

        let refiner = LLMRefiner(defaults: defaults, credentialStore: store)

        XCTAssertNil(refiner.apiKey)
        XCTAssertEqual(defaults.string(forKey: "LLMRefiner_APIKey"), defaultsSecret)
        XCTAssertNil(store.value(for: "llm-api-key"))
    }

    func testSettingAPIKeyStoresOnlyInCredentialStore() throws {
        let suiteName = "VoxFlowAppTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }
        let store = InMemoryCredentialStore()
        let refiner = LLMRefiner(defaults: defaults, credentialStore: store)

        refiner.apiKey = "new-secret-\(UUID().uuidString)"

        XCTAssertEqual(refiner.apiKey, store.value(for: "llm-api-key"))
    }

    func testClearingAPIKeyDeletesCredential() throws {
        let suiteName = "VoxFlowAppTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }
        let store = InMemoryCredentialStore()
        let refiner = LLMRefiner(defaults: defaults, credentialStore: store)
        refiner.apiKey = "secret-to-delete"

        refiner.apiKey = nil

        XCTAssertNil(refiner.apiKey)
        XCTAssertNil(store.value(for: "llm-api-key"))
    }

    func testConfiguredStateUsesCredentialStoreAPIKey() throws {
        let suiteName = "VoxFlowAppTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }
        let store = InMemoryCredentialStore()
        let refiner = LLMRefiner(defaults: defaults, credentialStore: store)

        refiner.baseURL = "https://api.openai.com"
        refiner.apiKey = "configured-secret"
        refiner.model = "gpt-4o-mini"

        XCTAssertTrue(refiner.isConfigured)
    }

    func testAPIBaseRootResolvesToChatCompletions() throws {
        let url = try LLMRefiner.chatCompletionsURL(
            baseURL: "https://api.openai.com"
        )

        XCTAssertEqual(url.absoluteString, "https://api.openai.com/v1/chat/completions")
    }

    func testAPIBaseRootWithTrailingSlashDoesNotCreateDoubleSlash() throws {
        let url = try LLMRefiner.chatCompletionsURL(
            baseURL: "https://api.openai.com/"
        )

        XCTAssertEqual(url.absoluteString, "https://api.openai.com/v1/chat/completions")
    }

    func testVersionedAPIBaseDoesNotDuplicateV1() throws {
        let url = try LLMRefiner.chatCompletionsURL(
            baseURL: "https://tokenhub.tencentmaas.com/v1/"
        )

        XCTAssertEqual(
            url.absoluteString,
            "https://tokenhub.tencentmaas.com/v1/chat/completions"
        )
    }

    func testFullChatEndpointIsKeptAsIs() throws {
        let url = try LLMRefiner.chatCompletionsURL(
            baseURL: "https://example.com/openai/v1/chat/completions"
        )

        XCTAssertEqual(
            url.absoluteString,
            "https://example.com/openai/v1/chat/completions"
        )
    }

    func testChatCompletionContentIsDecoded() throws {
        let data = Data(
            """
            {"choices":[{"message":{"content":"我在用 Python 处理 JSON 数据"}}]}
            """.utf8
        )

        XCTAssertEqual(
            try LLMRefiner.parseChatCompletion(data),
            "我在用 Python 处理 JSON 数据"
        )
    }

    func testMalformedChatCompletionIsRejected() {
        let data = Data(#"{"choices":[]}"#.utf8)

        XCTAssertThrowsError(try LLMRefiner.parseChatCompletion(data))
    }

    func testConfiguredOpenAICompatibleServiceRefinesMixedLanguageText() async throws {
        let environment = ProcessInfo.processInfo.environment
        guard let baseURL = environment["VOICEINPUT_TEST_BASE_URL"],
              let apiKey = environment["VOICEINPUT_TEST_API_KEY"],
              let model = environment["VOICEINPUT_TEST_MODEL"] else {
            throw XCTSkip("Set VOICEINPUT_TEST_* to run the live LLM integration test.")
        }

        let suiteName = "VoxFlowAppTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer {
            UserDefaults.standard.removePersistentDomain(forName: suiteName)
        }

        let refiner = LLMRefiner(defaults: defaults, credentialStore: InMemoryCredentialStore())
        refiner.baseURL = baseURL
        refiner.apiKey = apiKey
        refiner.model = model

        let result = try await refiner.refine("我在用配森处理杰森数据")

        XCTAssertTrue(result.contains("Python"))
        XCTAssertTrue(result.contains("JSON"))
        XCTAssertFalse(result.contains("配森"))
        XCTAssertFalse(result.contains("杰森"))
    }
}

private final class InMemoryCredentialStore: CredentialStore {
    private var values: [String: String] = [:]

    func readCredential(account: String) throws -> String? {
        values[account]
    }

    func saveCredential(_ value: String, account: String) throws {
        values[account] = value
    }

    func deleteCredential(account: String) throws {
        values.removeValue(forKey: account)
    }

    func value(for account: String) -> String? {
        values[account]
    }
}
