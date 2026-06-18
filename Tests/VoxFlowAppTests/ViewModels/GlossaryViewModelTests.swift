import XCTest
@testable import VoxFlowApp

@MainActor
final class GlossaryViewModelTests: XCTestCase {
    func testTermCRUDSearchAndDelete() throws {
        let environment = AppEnvironment(container: try DependencyContainer.inMemory())
        let viewModel = GlossaryViewModel(environment: environment)

        try viewModel.saveTerm(
            id: nil,
            term: "Python",
            aliasesText: "配森, 派森",
            category: "coding",
            enabled: true,
            priority: 10,
            notes: "Language"
        )
        XCTAssertEqual(viewModel.lastActionMessage, "已添加词条 Python")
        viewModel.updateSearch("配森")

        XCTAssertEqual(viewModel.terms.map(\.term), ["Python"])
        XCTAssertEqual(viewModel.terms.first?.aliases, ["配森", "派森"])

        viewModel.deleteTerm(id: viewModel.terms[0].id)
        XCTAssertEqual(viewModel.terms, [])
    }

    func testEmptyTermIsRejectedWithVisibleError() throws {
        let environment = AppEnvironment(container: try DependencyContainer.inMemory())
        let viewModel = GlossaryViewModel(environment: environment)

        XCTAssertThrowsError(
            try viewModel.saveTerm(
                id: nil,
                term: " ",
                aliasesText: "",
                category: "general",
                enabled: true,
                priority: 100,
                notes: nil
            )
        )

        XCTAssertEqual(viewModel.lastError, "标准词不能为空。")
        XCTAssertEqual(viewModel.terms, [])
    }

    func testReplacementRuleCRUDUsesModesAndStages() throws {
        let environment = AppEnvironment(container: try DependencyContainer.inMemory())
        let viewModel = GlossaryViewModel(environment: environment)

        try viewModel.saveReplacementRule(
            id: nil,
            source: #"版本(\d+)"#,
            target: "v$1",
            matchMode: .regex,
            applyStage: .afterLLM,
            category: "coding",
            enabled: true,
            priority: 2
        )

        XCTAssertEqual(viewModel.replacementRules.map(\.matchMode), [.regex])
        XCTAssertEqual(viewModel.replacementRules.map(\.applyStage), [.afterLLM])

        viewModel.deleteReplacementRule(id: viewModel.replacementRules[0].id)
        XCTAssertEqual(viewModel.replacementRules, [])
    }

    func testAddWordListTreatsEveryNonEmptyLineAsOneTermAndSkipsDuplicates() throws {
        let environment = AppEnvironment(container: try DependencyContainer.inMemory())
        let viewModel = GlossaryViewModel(environment: environment)

        let summary = try viewModel.addWordList(
            """
            SwiftUI

            VoiceInput
            swiftui
            右 Command
            """
        )

        XCTAssertEqual(summary, GlossaryImportSummary(created: 3, updated: 0, skipped: 1))
        XCTAssertEqual(Set(viewModel.terms.map(\.term)), Set(["SwiftUI", "VoiceInput", "右 Command"]))
        XCTAssertTrue(viewModel.terms.allSatisfy { $0.aliases.isEmpty })
        XCTAssertTrue(viewModel.terms.allSatisfy { $0.category == "general" })
    }

    func testImportWordListOnlyAcceptsTxtFiles() throws {
        let environment = AppEnvironment(container: try DependencyContainer.inMemory())
        let viewModel = GlossaryViewModel(environment: environment)
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let txtURL = directory.appendingPathComponent("words.txt")
        let csvURL = directory.appendingPathComponent("words.csv")
        try "苹果\n香蕉\n".write(to: txtURL, atomically: true, encoding: .utf8)
        try "苹果,香蕉".write(to: csvURL, atomically: true, encoding: .utf8)

        let summary = try viewModel.importWordList(from: txtURL)

        XCTAssertEqual(summary.created, 2)
        XCTAssertThrowsError(try viewModel.importWordList(from: csvURL)) { error in
            XCTAssertEqual(error.localizedDescription, "只支持导入 TXT 文件。")
        }
    }

    func testSaveSimpleReplacementUsesFirstPhaseDefaults() throws {
        let environment = AppEnvironment(container: try DependencyContainer.inMemory())
        let viewModel = GlossaryViewModel(environment: environment)

        try viewModel.saveSimpleReplacement(source: "扣顶", target: "coding")

        let rule = try XCTUnwrap(viewModel.replacementRules.first)
        XCTAssertEqual(rule.matchMode, .contains)
        XCTAssertEqual(rule.applyStage, .beforeLLM)
        XCTAssertEqual(rule.category, "general")
        XCTAssertEqual(rule.priority, 100)
    }

    func testImportTermsMergesDuplicatesAndSearchesImportedAliases() throws {
        let environment = AppEnvironment(container: try DependencyContainer.inMemory())
        let viewModel = GlossaryViewModel(environment: environment)

        let summary = try viewModel.importTerms(
            """
            Python,配森|派森,coding
            python,拍森,coding
            JSON,杰森,coding
            """
        )

        XCTAssertEqual(summary.created, 2)
        XCTAssertEqual(summary.updated, 1)
        viewModel.updateSearch("拍森")
        XCTAssertEqual(viewModel.terms.map(\.term), ["Python"])
        XCTAssertEqual(viewModel.terms.first?.aliases, ["配森", "派森", "拍森"])
    }

    func testJSONExportAndImportRoundTripsTermsAndReplacementRules() throws {
        let sourceEnvironment = AppEnvironment(container: try DependencyContainer.inMemory())
        let sourceViewModel = GlossaryViewModel(environment: sourceEnvironment)
        try sourceViewModel.saveTerm(
            id: nil,
            term: "SwiftUI",
            aliasesText: "斯威夫特 UI",
            category: "coding",
            enabled: true,
            priority: 8,
            notes: "Apple UI"
        )
        try sourceViewModel.saveReplacementRule(
            id: nil,
            source: "扣顶",
            target: "coding",
            matchMode: .contains,
            applyStage: .beforeLLM,
            category: "coding",
            enabled: true,
            priority: 9
        )

        let exported = try sourceViewModel.exportData(format: .json)
        let targetEnvironment = AppEnvironment(container: try DependencyContainer.inMemory())
        let targetViewModel = GlossaryViewModel(environment: targetEnvironment)
        let summary = try targetViewModel.importData(exported, format: .json)

        XCTAssertEqual(summary.created, 2)
        XCTAssertEqual(summary.updated, 0)
        XCTAssertEqual(targetViewModel.terms.map(\.term), ["SwiftUI"])
        XCTAssertEqual(targetViewModel.terms.first?.aliases, ["斯威夫特 UI"])
        XCTAssertEqual(targetViewModel.replacementRules.map(\.source), ["扣顶"])
        XCTAssertEqual(targetViewModel.replacementRules.first?.target, "coding")
        XCTAssertEqual(targetViewModel.replacementRules.first?.applyStage, .beforeLLM)
    }

    func testCSVExportEscapesAndImportMergesExistingRecords() throws {
        let environment = AppEnvironment(container: try DependencyContainer.inMemory())
        let viewModel = GlossaryViewModel(environment: environment)
        try viewModel.saveTerm(
            id: nil,
            term: "JSON",
            aliasesText: "杰森",
            category: "coding",
            enabled: true,
            priority: 3,
            notes: "format, data"
        )
        try viewModel.saveReplacementRule(
            id: nil,
            source: "Type Script",
            target: "TypeScript",
            matchMode: .exact,
            applyStage: .afterLLM,
            category: "coding",
            enabled: true,
            priority: 4
        )

        let exported = try viewModel.exportData(format: .csv)
        XCTAssertTrue(exported.contains(#""format, data""#))

        let summary = try viewModel.importData(
            """
            kind,term,aliases,category,enabled,priority,notes,source,target,matchMode,applyStage
            term,JSON,JSON 数据,coding,true,1,,
            replacement,,,,,,,Type Script,TS,exact,afterLLM
            """,
            format: .csv
        )

        XCTAssertEqual(summary.created, 0)
        XCTAssertEqual(summary.updated, 2)
        XCTAssertEqual(viewModel.terms.first?.aliases, ["杰森", "JSON 数据"])
        XCTAssertEqual(viewModel.terms.first?.priority, 3)
        XCTAssertEqual(viewModel.replacementRules.first?.target, "TS")
    }
}
