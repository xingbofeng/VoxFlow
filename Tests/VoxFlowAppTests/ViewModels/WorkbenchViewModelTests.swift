import XCTest
@testable import VoxFlowApp

@MainActor
final class WorkbenchViewModelTests: XCTestCase {
    func testLoadReadsCountsFromRepositories() throws {
        let container = try DependencyContainer.inMemory()
        let environment = AppEnvironment(container: container)
        try environment.historyRepository.save(historyEntry(id: "one"))
        try environment.noteRepository.save(note(id: "note"))
        try environment.glossaryRepository.save(
            GlossaryTerm(
                id: "term",
                term: "Python",
                aliases: ["配森"],
                category: "coding",
                enabled: true,
                priority: 10,
                notes: nil,
                createdAt: testDate,
                updatedAt: testDate
            )
        )

        let viewModel = WorkbenchViewModel(environment: environment)
        viewModel.load()

        XCTAssertEqual(viewModel.snapshot.historyCount, 1)
        XCTAssertEqual(viewModel.snapshot.noteCount, 1)
        XCTAssertEqual(viewModel.snapshot.glossaryCount, 1)
    }

    func testNavigationRoutesCoverRequiredWorkbenchPages() {
        XCTAssertEqual(
            NavigationRoute.allCases.map(\.title),
            ["首页", "词汇表", "风格", "文件转写", "笔记", "设置", "帮助"]
        )
    }

    private func historyEntry(id: String) -> DictationHistoryEntry {
        DictationHistoryEntry(
            id: id,
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
            createdAt: testDate,
            updatedAt: testDate,
            deletedAt: nil
        )
    }

    private func note(id: String) -> NoteRecord {
        NoteRecord(
            id: id,
            title: "Note",
            bodyMarkdown: "Body",
            sourceType: "manual",
            sourceID: nil,
            tags: [],
            createdAt: testDate,
            updatedAt: testDate,
            deletedAt: nil
        )
    }

    private var testDate: Date {
        Date(timeIntervalSince1970: 1_800_000_000)
    }
}
