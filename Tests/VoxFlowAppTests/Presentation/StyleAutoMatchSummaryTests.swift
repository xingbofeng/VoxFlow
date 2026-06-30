import XCTest
@testable import VoxFlowApp

/// Phase 4 UI presentation 验证 (OpenSpec §4.5)：风格主页摘要行只展示
/// 轻量信息，并根据全局开关 + 当前 style 自动匹配状态返回正确文案。
@MainActor
final class StyleAutoMatchSummaryTests: XCTestCase {
    func testSummaryGlobalOffShowsGlobalOffLine() throws {
        let viewModel = try makeViewModel(globalEnabled: false, profile: nil)
        XCTAssertEqual(
            StyleAutoMatchSummary.label(for: viewModel),
            L10n.localize("style.app_routing.auto_match_summary.global_off", comment: "")
        )
    }

    func testSummaryGlobalOnDefaultBuiltInStyleShowsEligibleLine() throws {
        let viewModel = try makeViewModel(globalEnabled: true, profile: nil)
        XCTAssertEqual(
            StyleAutoMatchSummary.label(for: viewModel),
            L10n.localize("style.app_routing.auto_match_summary.eligible", comment: "")
        )
    }

    func testSummaryGlobalOnStyleNotAllowedShowsStyleExcludedLine() throws {
        let viewModel = try makeViewModel(
            globalEnabled: true,
            profile: Self.profile(allowAutoMatch: false, description: "适合邮件")
        )
        XCTAssertEqual(
            StyleAutoMatchSummary.label(for: viewModel),
            L10n.localize("style.app_routing.auto_match_summary.style_excluded", comment: "")
        )
    }

    func testSummaryGlobalOnStyleAllowedButNoDescriptionShowsNoDescriptionLine() throws {
        let viewModel = try makeViewModel(
            globalEnabled: true,
            profile: Self.profile(allowAutoMatch: true, description: nil)
        )
        XCTAssertEqual(
            StyleAutoMatchSummary.label(for: viewModel),
            L10n.localize("style.app_routing.auto_match_summary.no_description", comment: "")
        )
    }

    func testSummaryEligibleShowsEligibleLine() throws {
        let viewModel = try makeViewModel(
            globalEnabled: true,
            profile: Self.profile(allowAutoMatch: true, description: "适合技术评审")
        )
        XCTAssertEqual(
            StyleAutoMatchSummary.label(for: viewModel),
            L10n.localize("style.app_routing.auto_match_summary.eligible", comment: "")
        )
    }

    // MARK: - Helpers

    private func makeViewModel(globalEnabled: Bool, profile: StyleProfileRecord?) throws -> StyleViewModel {
        let environment = AppEnvironment(container: try DependencyContainer.inMemory())
        if let profile {
            try environment.styleRepository.save(profile)
        }
        var settings = StyleAutoMatchSettings()
        settings.globalEnabled = globalEnabled
        try StyleAutoMatchSettingsStore(settingsRepository: environment.settingsRepository).save(settings)
        let viewModel = StyleViewModel(environment: environment)
        viewModel.loadIfNeeded()
        if let profile {
            try viewModel.selectProfile(id: profile.id)
        }
        return viewModel
    }

    private static func profile(allowAutoMatch: Bool, description: String?) -> StyleProfileRecord {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        return StyleProfileRecord(
            id: "test.style",
            name: "测试风格",
            category: "work",
            subtitle: nil,
            mode: "conservative",
            prompt: "p",
            sampleInput: nil,
            sampleOutput: nil,
            llmProviderID: nil,
            model: nil,
            temperature: 0.2,
            enabled: true,
            builtIn: false,
            isDefault: false,
            createdAt: now,
            updatedAt: now,
            allowAutoMatch: allowAutoMatch,
            autoMatchDescription: description
        )
    }
}
