import XCTest
@testable import VoxFlowApp

final class StyleApplicationPresentationTests: XCTestCase {
    func testKnownApplicationRecommendationsDoNotAppearAsConfiguredBindings() {
        let registry = KnownApplicationRegistry(
            version: 1,
            entries: [
                KnownApplicationEntry(
                    bundleID: "com.example.installed",
                    displayName: "Installed App",
                    suggestedStyleID: "builtin.coding"
                ),
                KnownApplicationEntry(
                    bundleID: "com.example.missing",
                    displayName: "Missing App",
                    suggestedStyleID: "builtin.coding"
                ),
            ]
        )

        let displayed = StyleApplicationPresentation.displayedApplications(
            selectedStyleID: "builtin.coding",
            selectedRules: [],
            allRules: [],
            installedApps: [
                installedApp(
                    name: "Installed App",
                    bundleID: "com.example.installed",
                    iconPath: "/tmp/installed.icns"
                ),
            ],
            registry: registry
        )

        XCTAssertTrue(displayed.isEmpty)
    }

    func testExplicitRulesUseRuleFallbackWhenInstalledAppIsMissing() {
        let selectedRules = [
            AppStyleRule(
                id: "installed-rule",
                bundleID: "com.example.installed",
                appName: "Installed Rule Name",
                styleID: "builtin.coding"
            ),
            AppStyleRule(
                id: "missing-rule",
                bundleID: "com.example.missing",
                appName: "Missing Rule Name",
                styleID: "builtin.coding"
            ),
        ]

        let displayed = StyleApplicationPresentation.displayedApplications(
            selectedStyleID: "builtin.coding",
            selectedRules: selectedRules,
            allRules: selectedRules,
            installedApps: [
                installedApp(
                    name: "Installed App",
                    bundleID: "com.example.installed",
                    iconPath: nil
                ),
            ],
            registry: KnownApplicationRegistry(version: 1, entries: [])
        )

        XCTAssertEqual(displayed.map(\.bundleID), ["com.example.installed", "com.example.missing"])
        XCTAssertEqual(displayed.map(\.name), ["Installed App", "Missing Rule Name"])
        XCTAssertEqual(displayed.map(\.iconPath), [nil, nil])
    }

    func testExplicitRulesDoNotPullInAvailableRecommendations() {
        let selectedRules = [
            AppStyleRule(
                id: "manual-rule",
                bundleID: "com.example.manual",
                appName: "Manual App",
                styleID: "builtin.coding"
            ),
        ]
        let registry = KnownApplicationRegistry(
            version: 1,
            entries: [
                KnownApplicationEntry(
                    bundleID: "com.example.recommended",
                    displayName: "Recommended App",
                    suggestedStyleID: "builtin.coding"
                ),
                KnownApplicationEntry(
                    bundleID: "com.example.other",
                    displayName: "Other Style",
                    suggestedStyleID: "builtin.chat"
                ),
            ]
        )

        let displayed = StyleApplicationPresentation.displayedApplications(
            selectedStyleID: "builtin.coding",
            selectedRules: selectedRules,
            allRules: selectedRules,
            installedApps: [
                installedApp(
                    name: "Manual App",
                    bundleID: "com.example.manual",
                    iconPath: nil
                ),
                installedApp(
                    name: "Recommended App",
                    bundleID: "com.example.recommended",
                    iconPath: nil
                ),
                installedApp(
                    name: "Other Style",
                    bundleID: "com.example.other",
                    iconPath: nil
                ),
            ],
            registry: registry
        )

        XCTAssertEqual(displayed.map(\.bundleID), ["com.example.manual"])
    }

    func testAIRouteCacheEntriesAppearAsAutomaticBindingsWithoutDuplicatingManualRules() {
        let selectedRules = [
            AppStyleRule(
                id: "manual-rule",
                bundleID: "com.example.manual",
                appName: "Manual App",
                styleID: "builtin.coding"
            ),
        ]
        var settings = StyleAutoMatchSettings()
        settings.routeCache = [
            "bundle:com.example.ai": StyleRouteCacheEntry(
                styleID: "builtin.coding",
                source: "aiRouter",
                createdAt: Date(timeIntervalSince1970: 1_800_000_000),
                lastUsedAt: Date(timeIntervalSince1970: 1_800_000_000),
                expiresAt: Date(timeIntervalSince1970: 2_000_000_000),
                hitCount: 2
            ),
            "bundle:com.example.manual": StyleRouteCacheEntry(
                styleID: "builtin.coding",
                source: "aiRouter",
                createdAt: Date(timeIntervalSince1970: 1_800_000_000),
                lastUsedAt: Date(timeIntervalSince1970: 1_800_000_000),
                expiresAt: Date(timeIntervalSince1970: 2_000_000_000),
                hitCount: 1
            ),
            "bundle:com.example.othermanual": StyleRouteCacheEntry(
                styleID: "builtin.coding",
                source: "aiRouter",
                createdAt: Date(timeIntervalSince1970: 1_800_000_000),
                lastUsedAt: Date(timeIntervalSince1970: 1_800_000_000),
                expiresAt: Date(timeIntervalSince1970: 2_000_000_000),
                hitCount: 1
            ),
        ]
        let allRules = selectedRules + [
            AppStyleRule(
                id: "other-manual-rule",
                bundleID: "com.example.othermanual",
                appName: "Other Manual App",
                styleID: "builtin.formal"
            ),
        ]

        let displayed = StyleApplicationPresentation.displayedApplications(
            selectedStyleID: "builtin.coding",
            selectedRules: selectedRules,
            allRules: allRules,
            installedApps: [
                installedApp(name: "AI App", bundleID: "com.example.ai", iconPath: nil),
                installedApp(name: "Manual App", bundleID: "com.example.manual", iconPath: nil),
                installedApp(name: "Other Manual App", bundleID: "com.example.othermanual", iconPath: nil),
            ],
            autoMatchSettings: settings,
            registry: KnownApplicationRegistry(version: 1, entries: [])
        )

        XCTAssertEqual(displayed.map(\.bundleID), ["com.example.manual", "com.example.ai"])
        XCTAssertEqual(displayed.map(\.source), [.manual, .aiAutoMatch])
        XCTAssertEqual(displayed.map(\.badges), [[], [.temporary]])
    }

    private func installedApp(
        name: String,
        bundleID: String,
        iconPath: String?
    ) -> InstalledApplication {
        InstalledApplication(
            id: bundleID,
            name: name,
            bundleID: bundleID,
            iconPath: iconPath,
            path: "/Applications/\(name).app",
            systemCategory: .userApplication
        )
    }
}
