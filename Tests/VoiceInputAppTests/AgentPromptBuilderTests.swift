import Foundation
import XCTest
@testable import VoiceInputApp

final class AgentPromptBuilderTests: XCTestCase {
    private let builder = AgentPromptBuilder()

    // MARK: - testPromptContainsAppName

    func testPromptContainsAppName() {
        let request = builder.build(
            appName: "WeChat",
            stylePrompt: nil,
            context: nil,
            userDictation: "Tell them I'll be late"
        )

        XCTAssertTrue(request.systemPrompt.contains("WeChat"))
    }

    // MARK: - testPromptContainsStyleGuidance

    func testPromptContainsStyleGuidance() {
        let request = builder.build(
            appName: nil,
            stylePrompt: "Use formal business language",
            context: nil,
            userDictation: "Write a reply"
        )

        XCTAssertTrue(request.systemPrompt.contains("Use formal business language"))
    }

    // MARK: - testPromptContainsContext

    func testPromptContainsContext() {
        let context = ContextSnapshot(
            windowTitle: "Inbox - Mail",
            targetAppName: "Mail",
            visibleText: "Subject: Meeting tomorrow",
            selectedText: "Can we reschedule?",
            sources: [.windowMetadata, .accessibilityVisibleText, .accessibilitySelectedText],
            trimmedLength: 100
        )

        let request = builder.build(
            appName: "Mail",
            stylePrompt: nil,
            context: context,
            userDictation: "Reply yes"
        )

        XCTAssertTrue(request.systemPrompt.contains("Inbox - Mail"))
        XCTAssertTrue(request.systemPrompt.contains("Subject: Meeting tomorrow"))
        XCTAssertTrue(request.systemPrompt.contains("Can we reschedule?"))
    }

    // MARK: - testPromptContainsUserDictation

    func testPromptContainsUserDictation() {
        let request = builder.build(
            appName: nil,
            stylePrompt: nil,
            context: nil,
            userDictation: "Ask about the project deadline"
        )

        XCTAssertTrue(request.systemPrompt.contains("Ask about the project deadline"))
    }

    // MARK: - testPromptOutputOnlyInstruction

    func testPromptOutputOnlyInstruction() {
        let request = builder.build(
            appName: nil,
            stylePrompt: nil,
            context: nil,
            userDictation: "Say hello"
        )

        XCTAssertTrue(request.systemPrompt.contains("Output ONLY the final usable text"))
    }

    // MARK: - testCodingStylePreservesCodeTerms

    func testCodingStylePreservesCodeTerms() {
        let request = builder.build(
            appName: "Terminal",
            stylePrompt: nil,
            context: nil,
            userDictation: "run git push origin main"
        )

        // Verify the system prompt has the coding preservation rule
        XCTAssertTrue(request.systemPrompt.contains("preserve them exactly"))
        XCTAssertTrue(request.systemPrompt.contains("technical terminology"))
    }

    // MARK: - testPromptWithoutContextUsesDictationOnly

    func testPromptWithoutContextUsesDictationOnly() {
        let request = builder.build(
            appName: nil,
            stylePrompt: nil,
            context: nil,
            userDictation: "Hello world"
        )

        // Should not contain "Context" section when context is nil
        XCTAssertFalse(request.systemPrompt.contains("Context (use as reference"))
        // Should contain the dictation intent
        XCTAssertTrue(request.systemPrompt.contains("Hello world"))
    }
}
