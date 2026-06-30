import XCTest
@testable import VoxFlowApp

@MainActor
final class ApplicationStyleSelectorTests: XCTestCase {
    func testExplicitRuleTakesPriorityWithoutCallingClassifier() async throws {
        let environment = AppEnvironment(container: try DependencyContainer.inMemory())
        try Self.enableGlobalAutoMatch(environment)
        try Self.enableStyleForAutoMatch("builtin.coding", environment: environment)
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
        XCTAssertEqual(selector.lastRouteTrace?.styleSelectionSource, "manualRule")
    }

    func testGlobalAutoMatchDisabledFallsBackWithoutCallingClassifier() async throws {
        let environment = AppEnvironment(container: try DependencyContainer.inMemory())
        try Self.disableGlobalAutoMatch(environment)
        try Self.enableStyleForAutoMatch("builtin.coding", environment: environment)
        let classifier = StubApplicationStyleClassifier(result: .success("builtin.coding"))
        let selector = SettingsBackedStyleSelector(
            styleRepository: environment.styleRepository,
            settingsRepository: environment.settingsRepository,
            classifier: classifier
        )

        let style = try await selector.style(
            for: DictationTarget(bundleID: "com.apple.dt.Xcode", appName: "Xcode")
        )

        XCTAssertEqual(style?.id, "builtin.original")
        XCTAssertEqual(classifier.targets, [])
        XCTAssertEqual(selector.lastRouteTrace?.styleSelectionSource, "default")
    }

    func testUnconfiguredApplicationUsesClassifierWhenGlobalAutoMatchEnabled() async throws {
        let environment = AppEnvironment(container: try DependencyContainer.inMemory())
        try Self.enableGlobalAutoMatch(environment)
        try Self.enableStyleForAutoMatch("builtin.coding", environment: environment)
        let classifier = StubApplicationStyleClassifier(result: .success("builtin.coding"))
        let selector = SettingsBackedStyleSelector(
            styleRepository: environment.styleRepository,
            settingsRepository: environment.settingsRepository,
            classifier: classifier
        )

        let style = try await selector.style(
            for: DictationTarget(bundleID: "com.apple.dt.Xcode", appName: "Xcode"),
            transcript: "帮我解释这个 Swift 编译错误"
        )

        XCTAssertEqual(style?.id, "builtin.coding")
        XCTAssertEqual(classifier.targets.map(\.appName), ["Xcode"])
        XCTAssertEqual(classifier.transcripts, ["帮我解释这个 Swift 编译错误"])
        XCTAssertEqual(selector.lastRouteTrace?.styleSelectionSource, "aiRouter")
    }

    func testRouteCacheTakesPriorityOverClassifier() async throws {
        let environment = AppEnvironment(container: try DependencyContainer.inMemory())
        try Self.enableStyleForAutoMatch("builtin.coding", environment: environment)
        var settings = StyleAutoMatchSettings(globalEnabled: true)
        settings.routeCache["bundle:com.apple.dt.xcode"] = StyleRouteCacheEntry(
            styleID: "builtin.coding",
            source: "aiRouter",
            createdAt: Date(timeIntervalSince1970: 1_800_000_000),
            lastUsedAt: Date(timeIntervalSince1970: 1_800_000_000),
            expiresAt: Date().addingTimeInterval(3600),
            hitCount: 1
        )
        try StyleAutoMatchSettingsStore(settingsRepository: environment.settingsRepository).save(settings)
        let classifier = StubApplicationStyleClassifier(result: .success("builtin.email"))
        let selector = SettingsBackedStyleSelector(
            styleRepository: environment.styleRepository,
            settingsRepository: environment.settingsRepository,
            classifier: classifier
        )

        let style = try await selector.style(
            for: DictationTarget(bundleID: "com.apple.dt.Xcode", appName: "Xcode")
        )

        XCTAssertEqual(style?.id, "builtin.coding")
        XCTAssertEqual(classifier.targets, [])
        XCTAssertEqual(selector.lastRouteTrace?.styleSelectionSource, "aiRouteCache")
    }

    func testTranscriptRouteIgnoresAppRouteCache() async throws {
        let environment = AppEnvironment(container: try DependencyContainer.inMemory())
        try Self.enableStyleForAutoMatch("builtin.coding", environment: environment)
        try Self.enableStyleForAutoMatch("builtin.email", environment: environment)
        var settings = StyleAutoMatchSettings(globalEnabled: true)
        settings.routeCache["bundle:com.apple.dt.xcode"] = StyleRouteCacheEntry(
            styleID: "builtin.email",
            source: "aiRouter",
            createdAt: Date(timeIntervalSince1970: 1_800_000_000),
            lastUsedAt: Date(timeIntervalSince1970: 1_800_000_000),
            expiresAt: Date().addingTimeInterval(3600),
            hitCount: 1
        )
        try StyleAutoMatchSettingsStore(settingsRepository: environment.settingsRepository).save(settings)
        let classifier = StubApplicationStyleClassifier(result: .success("builtin.coding"))
        let selector = SettingsBackedStyleSelector(
            styleRepository: environment.styleRepository,
            settingsRepository: environment.settingsRepository,
            classifier: classifier
        )

        let style = try await selector.style(
            for: DictationTarget(bundleID: "com.apple.dt.Xcode", appName: "Xcode"),
            transcript: "继续修这个编译错误"
        )

        XCTAssertEqual(style?.id, "builtin.coding")
        XCTAssertEqual(classifier.targets.map(\.appName), ["Xcode"])
        XCTAssertEqual(classifier.transcripts, ["继续修这个编译错误"])
        XCTAssertEqual(selector.lastRouteTrace?.styleSelectionSource, "aiRouter")
    }

    func testTranscriptRouteSavesAppRouteCacheForRouteDisplay() async throws {
        let environment = AppEnvironment(container: try DependencyContainer.inMemory())
        try Self.enableGlobalAutoMatch(environment)
        try Self.enableStyleForAutoMatch("builtin.coding", environment: environment)
        let classifier = StubApplicationStyleClassifier(result: .success("builtin.coding"))
        let selector = SettingsBackedStyleSelector(
            styleRepository: environment.styleRepository,
            settingsRepository: environment.settingsRepository,
            classifier: classifier
        )

        let style = try await selector.style(
            for: DictationTarget(bundleID: "com.apple.dt.Xcode", appName: "Xcode"),
            transcript: "帮我解释这个 Swift 编译错误"
        )

        XCTAssertEqual(style?.id, "builtin.coding")
        let savedSettings = StyleAutoMatchSettingsStore(settingsRepository: environment.settingsRepository).load()
        XCTAssertEqual(savedSettings.routeCache["bundle:com.apple.dt.xcode"]?.styleID, "builtin.coding")
        XCTAssertEqual(savedSettings.routeCache["bundle:com.apple.dt.xcode"]?.source, "aiRouter")
    }

    func testExpiredRouteCacheFallsThroughToClassifier() async throws {
        let environment = AppEnvironment(container: try DependencyContainer.inMemory())
        try Self.enableStyleForAutoMatch("builtin.coding", environment: environment)
        var settings = StyleAutoMatchSettings(globalEnabled: true)
        settings.routeCache["bundle:com.apple.dt.xcode"] = StyleRouteCacheEntry(
            styleID: "builtin.email",
            source: "aiRouter",
            createdAt: Date(timeIntervalSince1970: 1_800_000_000),
            lastUsedAt: Date(timeIntervalSince1970: 1_800_000_000),
            expiresAt: Date().addingTimeInterval(-1),
            hitCount: 1
        )
        try StyleAutoMatchSettingsStore(settingsRepository: environment.settingsRepository).save(settings)
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
        XCTAssertEqual(classifier.transcripts, [nil])
        XCTAssertEqual(selector.lastRouteTrace?.styleSelectionSource, "aiRouter")
    }

    func testClassifierNilResultFallsBackToDefaultStyle() async throws {
        let environment = AppEnvironment(container: try DependencyContainer.inMemory())
        try Self.enableGlobalAutoMatch(environment)
        try Self.enableStyleForAutoMatch("builtin.coding", environment: environment)
        let classifier = StubApplicationStyleClassifier(result: .success(nil))
        let selector = SettingsBackedStyleSelector(
            styleRepository: environment.styleRepository,
            settingsRepository: environment.settingsRepository,
            classifier: classifier
        )

        let style = try await selector.style(
            for: DictationTarget(bundleID: "com.example.unknown", appName: "Unknown")
        )

        XCTAssertEqual(style?.id, "builtin.original")
        XCTAssertEqual(selector.lastRouteTrace?.styleSelectionSource, "fallback")
    }

    func testClassifierFailureFallsBackToDefaultStyle() async throws {
        let environment = AppEnvironment(container: try DependencyContainer.inMemory())
        try Self.enableGlobalAutoMatch(environment)
        try Self.enableStyleForAutoMatch("builtin.coding", environment: environment)
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
        XCTAssertEqual(selector.lastRouteTrace?.styleSelectionSource, "fallback")
    }

    private enum TestError: Error {
        case expected
    }

    private static func enableGlobalAutoMatch(_ environment: AppEnvironment) throws {
        var settings = StyleAutoMatchSettings()
        settings.globalEnabled = true
        try StyleAutoMatchSettingsStore(settingsRepository: environment.settingsRepository).save(settings)
    }

    private static func disableGlobalAutoMatch(_ environment: AppEnvironment) throws {
        var settings = StyleAutoMatchSettings()
        settings.globalEnabled = false
        try StyleAutoMatchSettingsStore(settingsRepository: environment.settingsRepository).save(settings)
    }

    private static func enableStyleForAutoMatch(
        _ id: String,
        environment: AppEnvironment
    ) throws {
        let style = try XCTUnwrap(try environment.styleRepository.profile(id: id))
        try environment.styleRepository.save(
            StyleProfileRecord(
                id: style.id,
                name: style.name,
                category: style.category,
                subtitle: style.subtitle,
                mode: style.mode,
                prompt: style.prompt,
                sampleInput: style.sampleInput,
                sampleOutput: style.sampleOutput,
                llmProviderID: style.llmProviderID,
                model: style.model,
                temperature: style.temperature,
                enabled: style.enabled,
                builtIn: style.builtIn,
                isDefault: style.isDefault,
                createdAt: style.createdAt,
                updatedAt: style.updatedAt,
                allowAutoMatch: true,
                autoMatchDescription: "适合代码和技术讨论"
            )
        )
    }
}

private final class StubApplicationStyleClassifier: ApplicationStyleClassifying, @unchecked Sendable {
    let result: Result<String?, Error>
    private(set) var targets: [DictationTarget] = []
    private(set) var transcripts: [String?] = []

    init(result: Result<String?, Error>) {
        self.result = result
    }

    func classify(target: DictationTarget, styles: [StyleProfileRecord]) async throws -> String? {
        targets.append(target)
        transcripts.append(nil)
        return try result.get()
    }

    func classify(target: DictationTarget, transcript: String?, styles: [StyleProfileRecord]) async throws -> String? {
        targets.append(target)
        transcripts.append(transcript)
        return try result.get()
    }
}
