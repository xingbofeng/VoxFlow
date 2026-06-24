@preconcurrency import Translation
import XCTest
@testable import VoxFlowApp

@MainActor
final class AppleTranslationCoordinatorTests: XCTestCase {
    func testTranslatePublishesDetectedEnglishSourceConfiguration() async throws {
        let coordinator = AppleTranslationCoordinator()
        let session = FakeAppleTranslationSession(result: "译文")

        // Start a translation request
        let translateTask = Task { try await coordinator.translate("Hello") }
        await waitForPublishedConfiguration(coordinator)
        let config = coordinator.configuration
        XCTAssertNotNil(config)
        XCTAssertEqual(config?.source?.minimalIdentifier, "en")
        XCTAssertEqual(config?.target?.minimalIdentifier, "zh")

        // Host executes
        await coordinator.executePendingRequest(using: session)
        let result = try await translateTask.value
        XCTAssertEqual(result, "译文")
        XCTAssertNil(coordinator.configuration)
    }

    func testLatinTextFallsBackToEnglishSourceWhenDetectorIsUndetermined() async throws {
        let coordinator = AppleTranslationCoordinator(sourceLanguageDetector: { _ in nil })
        let session = FakeAppleTranslationSession(result: "译文")

        let translateTask = Task { try await coordinator.translate("OK") }
        await waitForPublishedConfiguration(coordinator)

        XCTAssertEqual(coordinator.configuration?.source?.minimalIdentifier, "en")

        await coordinator.executePendingRequest(using: session)
        _ = try await translateTask.value
    }

    func testShortAmbiguousLatinTextUsesEnglishSource() async throws {
        let coordinator = AppleTranslationCoordinator()
        let session = FakeAppleTranslationSession(result: "译文")

        let translateTask = Task { try await coordinator.translate("OK") }
        await waitForPublishedConfiguration(coordinator)

        XCTAssertEqual(coordinator.configuration?.source?.minimalIdentifier, "en")

        await coordinator.executePendingRequest(using: session)
        _ = try await translateTask.value
    }

    func testSessionResultCompletesPendingTranslation() async throws {
        let coordinator = AppleTranslationCoordinator()
        let session = FakeAppleTranslationSession(result: "译文")

        let translateTask = Task { try await coordinator.translate("Hello") }
        await waitForPublishedConfiguration(coordinator)
        await coordinator.executePendingRequest(using: session)
        let result = try await translateTask.value

        XCTAssertEqual(result, "译文")
        XCTAssertEqual(session.translatedTexts, ["Hello"])
    }

    func testOnlyOneHostClaimsPendingRequest() async throws {
        let coordinator = AppleTranslationCoordinator()
        let session1 = FakeAppleTranslationSession(result: "译文1")
        let session2 = FakeAppleTranslationSession(result: "译文2")

        let translateTask = Task { try await coordinator.translate("Hello") }
        await waitForPublishedConfiguration(coordinator)

        // First host claims the request
        await coordinator.executePendingRequest(using: session1)
        // Second host has no pending request
        await coordinator.executePendingRequest(using: session2)

        let result = try await translateTask.value
        XCTAssertEqual(result, "译文1")
        XCTAssertEqual(session1.translatedTexts, ["Hello"])
        XCTAssertTrue(session2.translatedTexts.isEmpty)
    }

    func testConfigurationStaysPublishedWhileSessionTranslates() async throws {
        let coordinator = AppleTranslationCoordinator()
        let session = SuspendedAppleTranslationSession(result: "译文")

        let translateTask = Task { try await coordinator.translate("Hello") }
        await waitForPublishedConfiguration(coordinator)

        let executeTask = Task { await coordinator.executePendingRequest(using: session) }
        await session.waitUntilStarted()

        XCTAssertNotNil(coordinator.configuration)

        session.complete()
        await executeTask.value
        let result = try await translateTask.value

        XCTAssertEqual(result, "译文")
        XCTAssertNil(coordinator.configuration)
    }

    func testRejectsNewRequestWhileSessionIsStillTranslating() async throws {
        let coordinator = AppleTranslationCoordinator()
        let session = SuspendedAppleTranslationSession(result: "译文")

        let firstTask = Task { try await coordinator.translate("Hello") }
        await waitForPublishedConfiguration(coordinator)
        let executeTask = Task { await coordinator.executePendingRequest(using: session) }
        await session.waitUntilStarted()

        do {
            _ = try await coordinator.translate("World")
            XCTFail("Expected active translation to reject concurrent request")
        } catch let error as AppleSystemTranslationError {
            XCTAssertEqual(error, .internalFailure)
        } catch {
            XCTFail("Wrong error type: \(error)")
        }

        session.complete()
        await executeTask.value
        let result = try await firstTask.value
        XCTAssertEqual(result, "译文")
    }

    func testRequestsRunSeriallyInSubmissionOrder() async throws {
        let coordinator = AppleTranslationCoordinator()
        let session = FakeAppleTranslationSession(result: "译文")

        let first = Task { try await coordinator.translate("Hello") }
        await waitForPublishedConfiguration(coordinator)

        // Complete first request
        await coordinator.executePendingRequest(using: session)
        _ = try await first.value

        // Second request should work
        let second = Task { try await coordinator.translate("World") }
        await waitForPublishedConfiguration(coordinator)
        await coordinator.executePendingRequest(using: session)
        let result2 = try await second.value

        XCTAssertEqual(result2, "译文")
        XCTAssertEqual(session.translatedTexts, ["Hello", "World"])
    }

    func testWaitingForHostTimesOutWithActionableMessage() async {
        let coordinator = AppleTranslationCoordinator(sessionHostTimeout: .milliseconds(50))

        do {
            _ = try await coordinator.translate("Hello")
            XCTFail("Expected timeout error")
        } catch {
            let err = try? XCTUnwrap(error as? AppleSystemTranslationError)
            XCTAssertEqual(err, .sessionHostUnavailable)
        }
    }

    func testCancellingCallerRemovesPendingRequest() async {
        let coordinator = AppleTranslationCoordinator()
        let session = FakeAppleTranslationSession(result: "译文")

        // Start a translation request but cancel it before host connects
        let translateTask = Task { try await coordinator.translate("Hello") }
        await waitForPublishedConfiguration(coordinator)

        coordinator.cancelCurrentRequest()
        do {
            _ = try await translateTask.value
            XCTFail("Expected cancellation to propagate")
        } catch is CancellationError {
            // Expected.
        } catch {
            XCTFail("Wrong error type: \(error)")
        }

        // No pending request after cancellation
        await coordinator.executePendingRequest(using: session)
        XCTAssertTrue(session.translatedTexts.isEmpty)
        XCTAssertNil(coordinator.configuration)

        // Second request should work fine
        let second = Task { try await coordinator.translate("World") }
        await waitForPublishedConfiguration(coordinator)
        XCTAssertNotNil(coordinator.configuration)
        await coordinator.executePendingRequest(using: session)
        let result = try? await second.value
        XCTAssertEqual(result, "译文")
        XCTAssertEqual(session.translatedTexts, ["World"])
    }

    func testTaskCancellationBeforeHostConnectionClearsPendingRequest() async throws {
        let coordinator = AppleTranslationCoordinator()
        let session = FakeAppleTranslationSession(result: "译文")

        let cancelledTask = Task { try await coordinator.translate("Hello") }
        await waitForPublishedConfiguration(coordinator)

        cancelledTask.cancel()
        await Task.yield()

        await coordinator.executePendingRequest(using: session)
        do {
            _ = try await cancelledTask.value
            XCTFail("Expected cancellation to propagate")
        } catch is CancellationError {
            // Expected.
        } catch {
            XCTFail("Wrong error type: \(error)")
        }

        XCTAssertTrue(session.translatedTexts.isEmpty)
        XCTAssertNil(coordinator.configuration)

        let nextTask = Task { try await coordinator.translate("World") }
        await waitForPublishedConfiguration(coordinator)
        await coordinator.executePendingRequest(using: session)
        let result = try await nextTask.value
        XCTAssertEqual(result, "译文")
        XCTAssertEqual(session.translatedTexts, ["World"])
    }

    func testSessionCancellationErrorMapsToCancelled() async {
        let coordinator = AppleTranslationCoordinator()
        let session = FakeAppleTranslationSession(result: "", shouldThrow: CancellationError())

        let translateTask = Task { try await coordinator.translate("Hello") }
        await waitForPublishedConfiguration(coordinator)
        await coordinator.executePendingRequest(using: session)

        do {
            _ = try await translateTask.value
            XCTFail("Expected cancellation error")
        } catch let error as AppleSystemTranslationError {
            XCTAssertEqual(error, .cancelled)
        } catch {
            XCTFail("Wrong error type: \(error)")
        }
    }

    func testSystemNotInstalledDescriptionMapsToLanguagePackDownloadFailed() async {
        let coordinator = AppleTranslationCoordinator()
        let error = NSError(
            domain: "TranslationError",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "Required language pack is not installed"]
        )
        let session = FakeAppleTranslationSession(result: "", shouldThrow: error)

        let translateTask = Task { try await coordinator.translate("Hello") }
        await waitForPublishedConfiguration(coordinator)
        await coordinator.executePendingRequest(using: session)

        do {
            _ = try await translateTask.value
            XCTFail("Expected language pack error")
        } catch let error as AppleSystemTranslationError {
            XCTAssertEqual(error, .languagePackDownloadFailed)
        } catch {
            XCTFail("Wrong error type: \(error)")
        }
    }

    func testURLErrorMapsToLanguagePackDownloadFailed() async {
        let session = FakeAppleTranslationSession(result: "", shouldThrow: URLError(.notConnectedToInternet))
        let coordinator = AppleTranslationCoordinator()

        let translateTask = Task { try await coordinator.translate("Hello") }
        await waitForPublishedConfiguration(coordinator)
        await coordinator.executePendingRequest(using: session)

        do {
            _ = try await translateTask.value
            XCTFail("Expected error")
        } catch let error as AppleSystemTranslationError {
            XCTAssertEqual(error, .languagePackDownloadFailed)
        } catch {
            XCTFail("Wrong error type: \(error)")
        }
    }

    func testCocoaFileWriteErrorMapsToLanguagePackDownloadFailed() async {
        let session = FakeAppleTranslationSession(result: "", shouldThrow: CocoaError(.fileWriteOutOfSpace))
        let coordinator = AppleTranslationCoordinator()

        let translateTask = Task { try await coordinator.translate("Hello") }
        await waitForPublishedConfiguration(coordinator)
        await coordinator.executePendingRequest(using: session)

        do {
            _ = try await translateTask.value
            XCTFail("Expected error")
        } catch let error as AppleSystemTranslationError {
            XCTAssertEqual(error, .languagePackDownloadFailed)
        } catch {
            XCTFail("Wrong error type: \(error)")
        }
    }

    func testEmptyTextReturnsDirectly() async throws {
        let coordinator = AppleTranslationCoordinator()
        let session = FakeAppleTranslationSession(result: "译文")

        let result = try await coordinator.translate("  ")
        XCTAssertEqual(result, "")
        // No pending request created
        await coordinator.executePendingRequest(using: session)
        XCTAssertTrue(session.translatedTexts.isEmpty)
    }

    private func waitForPublishedConfiguration(
        _ coordinator: AppleTranslationCoordinator,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        for _ in 0..<100 {
            if coordinator.configuration != nil {
                return
            }
            await Task.yield()
        }
        XCTFail("Timed out waiting for translation configuration", file: file, line: line)
    }
}

// MARK: - Fakes

@MainActor
private final class FakeAppleTranslationSession: AppleTranslationSessionRunning {
    let result: String
    let shouldThrow: Error?
    private(set) var translatedTexts: [String] = []

    init(result: String, shouldThrow: Error? = nil) {
        self.result = result
        self.shouldThrow = shouldThrow
    }

    func translate(_ text: String) async throws -> String {
        translatedTexts.append(text)
        if let shouldThrow {
            throw shouldThrow
        }
        return result
    }
}

@MainActor
private final class SuspendedAppleTranslationSession: AppleTranslationSessionRunning {
    private let result: String
    private var startContinuation: CheckedContinuation<Void, Never>?
    private var resultContinuation: CheckedContinuation<String, any Error>?
    private(set) var translatedTexts: [String] = []
    private var didStart = false

    init(result: String) {
        self.result = result
    }

    func translate(_ text: String) async throws -> String {
        translatedTexts.append(text)
        return try await withCheckedThrowingContinuation { continuation in
            resultContinuation = continuation
            didStart = true
            startContinuation?.resume()
            startContinuation = nil
        }
    }

    func waitUntilStarted() async {
        if didStart {
            return
        }
        await withCheckedContinuation { continuation in
            startContinuation = continuation
        }
    }

    func complete() {
        resultContinuation?.resume(returning: result)
        resultContinuation = nil
    }
}
