import XCTest
@testable import VoiceInputApp

final class ApplicationStyleRecommendationServiceTests: XCTestCase {
    private let service = ApplicationStyleRecommendationService(
        registry: .builtIn()
    )

    func testRegistryHitReturnsSystemPreset() {
        let apps = [
            makeApp(bundleID: "com.microsoft.VSCode", name: "VS Code"),
        ]

        let recs = service.recommend(apps: apps, existingRules: [])

        XCTAssertEqual(recs.count, 1)
        let rec = recs[0]
        XCTAssertEqual(rec.bundleID, "com.microsoft.VSCode")
        XCTAssertEqual(rec.appName, "VS Code")
        XCTAssertEqual(rec.suggestedStyleID, "builtin.coding")
        XCTAssertEqual(rec.source, .systemPreset)
        XCTAssertEqual(rec.confidence, 1.0)
    }

    func testUserRuleSkipsRecommendation() {
        let apps = [
            makeApp(bundleID: "com.microsoft.VSCode", name: "VS Code"),
        ]
        let rules = [
            AppStyleRule(
                id: "rule-1",
                bundleID: "com.microsoft.VSCode",
                appName: "VS Code",
                styleID: "my-custom-style"
            ),
        ]

        let recs = service.recommend(apps: apps, existingRules: rules)

        XCTAssertTrue(recs.isEmpty, "Apps with existing user rules should be skipped")
    }

    func testUnknownAppHasNoRecommendation() {
        let apps = [
            makeApp(bundleID: "com.totally.unknown.app", name: "Unknown"),
        ]

        let recs = service.recommend(apps: apps, existingRules: [])

        XCTAssertTrue(recs.isEmpty, "Unknown apps should not produce recommendations")
    }

    func testAppBundleIDCaseInsensitiveMatch() {
        let apps = [
            makeApp(bundleID: "COM.MICROSOFT.VSCODE", name: "VS Code"),
        ]

        let recs = service.recommend(apps: apps, existingRules: [])

        XCTAssertEqual(recs.count, 1)
        XCTAssertEqual(recs[0].suggestedStyleID, "builtin.coding")
        XCTAssertEqual(recs[0].source, .systemPreset)
    }

    func testAppsWithoutBundleIDGetNoRecommendation() {
        let apps = [
            InstalledApplication(
                id: "path:/applications/nope.app",
                name: "Nope",
                bundleID: nil,
                iconPath: nil,
                path: "/Applications/Nope.app",
                systemCategory: .userApplication
            ),
        ]

        let recs = service.recommend(apps: apps, existingRules: [])

        XCTAssertTrue(recs.isEmpty, "Apps without a bundleID cannot be recommended")
    }

    func testMultipleAppsProcessedCorrectly() {
        let apps = [
            makeApp(bundleID: "com.apple.Safari", name: "Safari"),            // registry hit
            makeApp(bundleID: "com.microsoft.VSCode", name: "VS Code"),        // user rule → skipped
            makeApp(bundleID: "com.unknown.app", name: "Mystery"),             // unknown → skipped
            makeApp(bundleID: "com.tencent.xinWeChat", name: "WeChat"),        // registry hit
        ]
        let rules = [
            AppStyleRule(
                id: "rule-vscode",
                bundleID: "com.microsoft.VSCode",
                appName: "VS Code",
                styleID: "my-style"
            ),
        ]

        let recs = service.recommend(apps: apps, existingRules: rules)

        XCTAssertEqual(recs.count, 2)
        XCTAssertEqual(recs[0].bundleID, "com.apple.Safari")
        XCTAssertEqual(recs[0].suggestedStyleID, "builtin.casual")
        XCTAssertEqual(recs[1].bundleID, "com.tencent.xinWeChat")
        XCTAssertEqual(recs[1].suggestedStyleID, "builtin.chat")
    }

    func testMergeDoesNotCreateDefaultRecommendationsForUnclassifiedApps() {
        let apps = [
            makeApp(bundleID: "com.apple.Safari", name: "Safari"),
            makeApp(bundleID: "com.example.unknown", name: "Unknown"),
        ]
        let registryRecs = [
            ApplicationStyleRecommendation(
                bundleID: "com.apple.Safari",
                appName: "Safari",
                suggestedStyleID: "builtin.casual",
                source: .systemPreset,
                confidence: 1.0
            ),
        ]

        let recs = service.merge(
            registryRecommendations: registryRecs,
            aiResults: [],
            apps: apps,
            existingRules: [],
            defaultStyleID: "builtin.energetic",
            enabledStyleIDs: Set(["builtin.casual", "builtin.energetic"])
        )

        XCTAssertEqual(recs, registryRecs)
        XCTAssertFalse(
            recs.contains { $0.bundleID == "com.example.unknown" },
            "Unclassified apps should remain unconfigured instead of being persisted as the current default style."
        )
    }

    func testMergeKeepsExplicitAIRecommendationButSkipsUnclassifiedApps() {
        let apps = [
            makeApp(bundleID: "com.example.chat", name: "Chatty"),
            makeApp(bundleID: "com.example.unknown", name: "Unknown"),
        ]

        let recs = service.merge(
            registryRecommendations: [],
            aiResults: [
                BatchClassificationResult(bundleID: "com.example.chat", styleID: "builtin.chat"),
            ],
            apps: apps,
            existingRules: [],
            defaultStyleID: "builtin.energetic",
            enabledStyleIDs: Set(["builtin.chat", "builtin.energetic"])
        )

        XCTAssertEqual(recs.count, 1)
        XCTAssertEqual(recs[0].bundleID, "com.example.chat")
        XCTAssertEqual(recs[0].suggestedStyleID, "builtin.chat")
        XCTAssertEqual(recs[0].source, .aiRecommendation)
    }

    // MARK: - Helpers

    private func makeApp(bundleID: String, name: String) -> InstalledApplication {
        InstalledApplication(
            id: bundleID,
            name: name,
            bundleID: bundleID,
            iconPath: nil,
            path: "/Applications/\(name).app",
            systemCategory: .userApplication
        )
    }
}
