import XCTest
@testable import VoxFlowApp

@MainActor
final class ApplicationStyleSelectorTests: XCTestCase {
    func testExplicitRuleTakesPriorityWithoutCallingClassifier() async throws {
        let environment = AppEnvironment(container: try DependencyContainer.inMemory())
        let store = AppStyleRuleStore(settingsRepository: environment.settingsRepository)
        try store.save(
            AppStyleRule(
                id: "rule",
                bundleID: "com.example.mail",
                appName: "Mail",
                styleID: "builtin.email"
            )
        )
        let classifier = StubApplicationStyleClassifier(result: .success("builtin.coding"))
        let selector = SettingsBackedStyleSelector(
            styleRepository: environment.styleRepository,
            settingsRepository: environment.settingsRepository,
            classifier: classifier
        )

        let style = try await selector.style(
            for: DictationTarget(bundleID: "com.example.mail", appName: "Mail")
        )

        XCTAssertEqual(style?.id, "builtin.email")
        XCTAssertEqual(classifier.targets, [])
    }

    func testUnconfiguredApplicationUsesClassifier() async throws {
        let environment = AppEnvironment(container: try DependencyContainer.inMemory())
        let classifier = StubApplicationStyleClassifier(result: .success("builtin.coding"))
        let selector = SettingsBackedStyleSelector(
            styleRepository: environment.styleRepository,
            settingsRepository: environment.settingsRepository,
            classifier: classifier
        )

        let style = try await selector.style(
            for: DictationTarget(bundleID: "com.apple.dt.Xcode", appName: "Xcode")
        )

        XCTAssertEqual(style?.id, "builtin.coding")
        XCTAssertEqual(classifier.targets.map(\.appName), ["Xcode"])
    }

    func testClassifierFailureFallsBackToDefaultStyle() async throws {
        let environment = AppEnvironment(container: try DependencyContainer.inMemory())
        let classifier = StubApplicationStyleClassifier(result: .failure(TestError.expected))
        let selector = SettingsBackedStyleSelector(
            styleRepository: environment.styleRepository,
            settingsRepository: environment.settingsRepository,
            classifier: classifier
        )

        let style = try await selector.style(
            for: DictationTarget(bundleID: "com.example.unknown", appName: "Unknown")
        )

        XCTAssertEqual(style?.id, "builtin.original")
    }

    private enum TestError: Error {
        case expected
    }
}

private final class StubApplicationStyleClassifier: ApplicationStyleClassifying, @unchecked Sendable {
    let result: Result<String?, Error>
    private(set) var targets: [DictationTarget] = []

    init(result: Result<String?, Error>) {
        self.result = result
    }

    func classify(target: DictationTarget, styles: [StyleProfileRecord]) async throws -> String? {
        targets.append(target)
        return try result.get()
    }
}
