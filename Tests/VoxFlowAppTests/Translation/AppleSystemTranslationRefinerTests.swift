import XCTest
import NaturalLanguage
@testable import VoxFlowApp

final class AppleSystemTranslationRefinerTests: XCTestCase {
    func testReportsConfiguredWhenCoordinatorIsAvailable() {
        let coordinator = FakeAppleTranslationCoordinator(isAvailable: true)
        let refiner = AppleSystemTranslationRefiner(coordinator: coordinator, dominantLanguage: { _ in .english })

        XCTAssertTrue(refiner.isConfigured)
    }

    func testReportsNotConfiguredWhenCoordinatorIsUnavailable() {
        let coordinator = FakeAppleTranslationCoordinator(isAvailable: false)
        let refiner = AppleSystemTranslationRefiner(coordinator: coordinator, dominantLanguage: { _ in .english })

        XCTAssertFalse(refiner.isConfigured)
    }

    func testReturnsEmptyInputWithoutCallingCoordinator() async throws {
        let coordinator = FakeAppleTranslationCoordinator(isAvailable: true)
        let refiner = AppleSystemTranslationRefiner(coordinator: coordinator, dominantLanguage: { _ in nil })

        let result = try await refiner.refine("")

        XCTAssertEqual(result, "")
        XCTAssertEqual(coordinator.translateCallCount, 0)
    }

    func testReturnsEmptyWhitespaceInputWithoutCallingCoordinator() async throws {
        let coordinator = FakeAppleTranslationCoordinator(isAvailable: true)
        let refiner = AppleSystemTranslationRefiner(coordinator: coordinator, dominantLanguage: { _ in nil })

        let result = try await refiner.refine("   \n  ")

        XCTAssertEqual(result, "")
        XCTAssertEqual(coordinator.translateCallCount, 0)
    }

    func testReturnsSimplifiedChineseInputWithoutCallingCoordinator() async throws {
        let coordinator = FakeAppleTranslationCoordinator(isAvailable: true)
        let refiner = AppleSystemTranslationRefiner(coordinator: coordinator, dominantLanguage: { _ in .simplifiedChinese })

        let result = try await refiner.refine("这是一个测试")

        XCTAssertEqual(result, "这是一个测试")
        XCTAssertEqual(coordinator.translateCallCount, 0)
    }

    func testReturnsTraditionalChineseInputWithoutCallingCoordinator() async throws {
        let coordinator = FakeAppleTranslationCoordinator(isAvailable: true)
        let refiner = AppleSystemTranslationRefiner(coordinator: coordinator, dominantLanguage: { _ in .traditionalChinese })

        let result = try await refiner.refine("這是一個測試")

        XCTAssertEqual(result, "這是一個測試")
        XCTAssertEqual(coordinator.translateCallCount, 0)
    }

    func testUndeterminedShortTextStillUsesSystemCoordinator() async throws {
        let coordinator = FakeAppleTranslationCoordinator(isAvailable: true, translateResult: "译文")
        let refiner = AppleSystemTranslationRefiner(coordinator: coordinator, dominantLanguage: { _ in nil })

        let result = try await refiner.refine("Hi")

        XCTAssertEqual(result, "译文")
        XCTAssertEqual(coordinator.translateCallCount, 1)
    }

    func testTranslatesNonChineseInputThroughCoordinator() async throws {
        let coordinator = FakeAppleTranslationCoordinator(isAvailable: true, translateResult: "你好")
        let refiner = AppleSystemTranslationRefiner(coordinator: coordinator, dominantLanguage: { _ in .english })

        let result = try await refiner.refine("Hello")

        XCTAssertEqual(result, "你好")
        XCTAssertEqual(coordinator.translateCallCount, 1)
    }

    func testPropagatesCoordinatorError() async {
        let coordinator = FakeAppleTranslationCoordinator(
            isAvailable: true,
            translateResult: nil,
            translateError: AppleSystemTranslationError.internalFailure
        )
        let refiner = AppleSystemTranslationRefiner(coordinator: coordinator, dominantLanguage: { _ in .english })

        do {
            _ = try await refiner.refine("Hello")
            XCTFail("Expected error")
        } catch {
            XCTAssertEqual(error as? AppleSystemTranslationError, .internalFailure)
        }
    }

    func testRefineRequestPassesTextToRefineText() async throws {
        let coordinator = FakeAppleTranslationCoordinator(isAvailable: true, translateResult: "你好")
        let refiner = AppleSystemTranslationRefiner(coordinator: coordinator, dominantLanguage: { _ in .english })

        let result = try await refiner.refine(
            TextRefinementRequest(text: "Hello", systemPrompt: "translate", model: nil, temperature: nil)
        )

        XCTAssertEqual(result, "你好")
        XCTAssertEqual(coordinator.translateCallCount, 1)
    }
}

// MARK: - Fakes

private final class FakeAppleTranslationCoordinator: AppleTranslationCoordinating, @unchecked Sendable {
    let isAvailable: Bool
    let translateResult: String?
    let translateError: Error?
    private(set) var translateCallCount = 0
    private let lock = NSLock()

    init(isAvailable: Bool, translateResult: String? = nil, translateError: Error? = nil) {
        self.isAvailable = isAvailable
        self.translateResult = translateResult
        self.translateError = translateError
    }

    func translate(_ text: String) async throws -> String {
        lock.withLock { translateCallCount += 1 }
        if let translateError {
            throw translateError
        }
        return translateResult ?? text
    }
}
