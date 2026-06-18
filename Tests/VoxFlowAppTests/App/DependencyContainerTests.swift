import XCTest
@testable import VoxFlowApp

final class DependencyContainerTests: XCTestCase {
    func testInMemoryContainerCreatesMigratedRepositories() throws {
        let container = try DependencyContainer.inMemory()

        try container.settingsRepository.set("test.key", jsonValue: #"{"ok":true}"#)

        XCTAssertEqual(
            try container.settingsRepository.value(forKey: "test.key"),
            #"{"ok":true}"#
        )
    }

    func testAppEnvironmentExposesContainerServices() throws {
        let container = try DependencyContainer.inMemory()

        let environment = AppEnvironment(container: container)

        try environment.historyRepository.save(
            DictationHistoryEntry(
                id: "entry",
                rawText: "raw",
                finalText: "final",
                language: "zh-CN",
                asrProviderID: "apple",
                llmProviderID: nil,
                styleID: nil,
                durationMS: 100,
                charCount: 5,
                cpm: 120,
                targetAppBundleID: nil,
                targetAppName: nil,
                processingWarningsJSON: nil,
                createdAt: Date(timeIntervalSince1970: 1_800_000_000),
                updatedAt: Date(timeIntervalSince1970: 1_800_000_000),
                deletedAt: nil
            )
        )

        XCTAssertEqual(try environment.historyRepository.listRecent(limit: 10).map(\.id), ["entry"])
    }
}
