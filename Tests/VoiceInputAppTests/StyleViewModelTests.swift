import XCTest
@testable import VoiceInputApp

@MainActor
final class StyleViewModelTests: XCTestCase {
    func testContainerSeedsBuiltInStylesWithOriginalAsDefault() throws {
        let environment = AppEnvironment(container: try DependencyContainer.inMemory())
        let viewModel = StyleViewModel(environment: environment)

        XCTAssertEqual(
            Set(viewModel.profiles.map(\.name)),
            Set(["原文", "正式", "日常", "元气", "聊天", "编程", "邮件"])
        )
        XCTAssertEqual(viewModel.defaultProfile?.id, "builtin.original")
    }

    func testUpdateProfileStoresPromptAndPreservesLegacyRuntimeFields() throws {
        let environment = AppEnvironment(container: try DependencyContainer.inMemory())
        let viewModel = StyleViewModel(environment: environment)
        let coding = try XCTUnwrap(viewModel.profiles.first { $0.id == "builtin.coding" })

        try viewModel.updateProfile(
            id: coding.id,
            prompt: "只修正技术名词"
        )
        try viewModel.setDefaultProfile(id: coding.id)

        let saved = try XCTUnwrap(try environment.styleRepository.profile(id: coding.id))
        XCTAssertEqual(saved.prompt, "只修正技术名词")
        XCTAssertEqual(saved.llmProviderID, coding.llmProviderID)
        XCTAssertEqual(saved.model, coding.model)
        XCTAssertEqual(saved.temperature, coding.temperature)
        XCTAssertEqual(try environment.styleRepository.defaultProfile()?.id, coding.id)
    }

    func testUpdateProfileRejectsEmptyPrompt() throws {
        let environment = AppEnvironment(container: try DependencyContainer.inMemory())
        let viewModel = StyleViewModel(environment: environment)
        let original = try XCTUnwrap(
            try environment.styleRepository.profile(id: "builtin.coding")
        )

        XCTAssertThrowsError(
            try viewModel.updateProfile(id: original.id, prompt: " \n ")
        ) { error in
            XCTAssertEqual(error.localizedDescription, "提示词不能为空。")
        }
        XCTAssertEqual(
            try environment.styleRepository.profile(id: original.id)?.prompt,
            original.prompt
        )
    }

    func testSelectProfileImmediatelyMakesItDefaultAndSelected() throws {
        let environment = AppEnvironment(container: try DependencyContainer.inMemory())
        let viewModel = StyleViewModel(environment: environment)

        try viewModel.selectProfile(id: "builtin.coding")

        XCTAssertEqual(viewModel.selectedProfile?.id, "builtin.coding")
        XCTAssertEqual(viewModel.defaultProfile?.id, "builtin.coding")
        XCTAssertEqual(try environment.styleRepository.defaultProfile()?.id, "builtin.coding")
    }

    func testResetBuiltInPromptRestoresCatalogPrompt() throws {
        let environment = AppEnvironment(container: try DependencyContainer.inMemory())
        let viewModel = StyleViewModel(environment: environment)

        try viewModel.updateProfile(
            id: "builtin.email",
            prompt: "changed"
        )
        try viewModel.resetBuiltInPrompt(id: "builtin.email")

        let saved = try XCTUnwrap(try environment.styleRepository.profile(id: "builtin.email"))
        XCTAssertEqual(saved.prompt, BuiltInStyleCatalog.profile(id: "builtin.email")?.prompt)
        XCTAssertEqual(saved.temperature, BuiltInStyleCatalog.profile(id: "builtin.email")?.temperature)
    }

    func testKnownLegacyPromptIsEligibleForBuiltInUpgrade() {
        let oldPrompt = """
        你正在处理语音识别得到的原文。保持用户原有措辞、语气、句序和信息密度，只修正能够从上下文明确判断的同音字、技术名词、断句与标点错误。不要润色，不要改写，不要补充用户没有表达的事实，不要删除犹豫词或重复内容。无法确定时保留原样。输出只能包含修正后的正文，不要解释修改过程，不要添加标题、引号或前后说明。
        """

        XCTAssertTrue(
            BuiltInStyleCatalog.shouldUpgradeLegacyPrompt(
                oldPrompt,
                profileID: "builtin.original"
            )
        )
    }

    func testCustomizedBuiltInPromptIsNotEligibleForUpgrade() {
        XCTAssertFalse(
            BuiltInStyleCatalog.shouldUpgradeLegacyPrompt(
                "这是用户自定义的提示词",
                profileID: "builtin.original"
            )
        )
    }

    func testEnergeticPromptWithNumericEmojiLimitIsEligibleForBuiltInUpgrade() {
        let oldPrompt = """
        ## 元气风格

        **用途**：让表达更积极、明快、有行动感，适合团队激励、进展更新和目标驱动场景。

        **规则**：
        - 在完整保留原意和事实的前提下，让语气更积极明快
        - 修正语音识别错误和标点，适度压缩拖沓口头语
        - 可以使用少量自然的感叹语气，但不得影响专业性
        - 可以使用 0-2 个与语境匹配的自然 emoji（如 ✨、💪、🎉），但不是每次都必须添加
        - 不添加用户未说出的计划、承诺、数据或评价
        - 不使用夸张口号，不连续使用感叹号或堆叠 emoji，不替用户发挥

        **与 LLM 纠错的关系**：LLM 纠错负责修正识别错误，此风格在此基础上让语气更有活力。

        **不会改写的情况**：涉及具体数据、截止日期和负面评价的内容不会被美化。

        输出只包含修正后的正文，不要添加任何解释、标题、引号或额外内容。
        """

        XCTAssertTrue(
            BuiltInStyleCatalog.shouldUpgradeLegacyPrompt(
                oldPrompt,
                profileID: "builtin.energetic"
            )
        )
    }

    func testAppStyleRulesPersistThroughSettingsRepository() throws {
        let environment = AppEnvironment(container: try DependencyContainer.inMemory())
        let viewModel = StyleViewModel(environment: environment)

        try viewModel.saveAppStyleRule(
            id: nil,
            bundleID: "com.example.editor",
            appName: "Editor",
            styleID: "builtin.coding"
        )

        XCTAssertEqual(viewModel.appStyleRules.count, 1)
        XCTAssertEqual(viewModel.appStyleRules.first?.bundleID, "com.example.editor")
        XCTAssertEqual(viewModel.appStyleRules.first?.styleID, "builtin.coding")

        let reloadedViewModel = StyleViewModel(environment: environment)
        XCTAssertEqual(reloadedViewModel.appStyleRules, viewModel.appStyleRules)

        reloadedViewModel.deleteAppStyleRule(id: reloadedViewModel.appStyleRules[0].id)
        XCTAssertEqual(reloadedViewModel.appStyleRules, [])
    }

    func testSavingDuplicateApplicationRuleReplacesExistingStyle() async throws {
        let environment = AppEnvironment(container: try DependencyContainer.inMemory())
        let viewModel = StyleViewModel(environment: environment)

        try viewModel.saveAppStyleRule(
            id: nil,
            bundleID: "com.tencent.xinWeChat",
            appName: "微信",
            styleID: "builtin.casual"
        )
        try viewModel.saveAppStyleRule(
            id: nil,
            bundleID: "com.tencent.xinWeChat",
            appName: "微信",
            styleID: "builtin.energetic"
        )

        XCTAssertEqual(viewModel.appStyleRules.count, 1)
        XCTAssertEqual(viewModel.appStyleRules.first?.styleID, "builtin.energetic")

        let selector = SettingsBackedStyleSelector(
            styleRepository: environment.styleRepository,
            settingsRepository: environment.settingsRepository
        )
        let style = try await selector.style(
            for: DictationTarget(bundleID: "com.tencent.xinWeChat", appName: "微信")
        )
        XCTAssertEqual(style?.id, "builtin.energetic")
    }

    func testSmartConfigurationCreatedFromStyleViewModelCallsAIClassifier() async throws {
        let environment = AppEnvironment(container: try DependencyContainer.inMemory())
        let app = InstalledApplication(
            id: "com.example.researched",
            name: "ResearchedApp",
            bundleID: "com.example.researched",
            iconPath: nil,
            path: "/Applications/ResearchedApp.app",
            systemCategory: .userApplication
        )
        let classifier = SpyBatchApplicationClassifier(
            results: [
                BatchClassificationResult(
                    bundleID: "com.example.researched",
                    styleID: "builtin.coding"
                ),
            ]
        )
        let viewModel = StyleViewModel(
            environment: environment,
            smartConfigurationAppProvider: StubInstalledApplicationProvider(apps: [app]),
            smartConfigurationClassifierFactory: { _ in classifier }
        )

        let smartConfigurationViewModel = viewModel.makeSmartConfigurationViewModel()
        await smartConfigurationViewModel.startConfiguration()

        XCTAssertEqual(classifier.calls.count, 1)
        XCTAssertEqual(classifier.calls.first?.apps.map(\.bundleID), ["com.example.researched"])
        let aiGroups = smartConfigurationViewModel.groups.filter { $0.source == .aiRecommendation }
        let aiBundleIDs = aiGroups.flatMap { group in
            group.recommendations.map(\.bundleID)
        }
        XCTAssertTrue(aiBundleIDs.contains("com.example.researched"))
    }
}

private struct StubInstalledApplicationProvider: InstalledApplicationProviding {
    let apps: [InstalledApplication]

    func scanInstalledApplications() -> [InstalledApplication] {
        apps
    }
}

private final class SpyBatchApplicationClassifier: BatchApplicationClassifying, @unchecked Sendable {
    struct Call {
        let apps: [InstalledApplication]
        let styles: [StyleProfileRecord]
    }

    let results: [BatchClassificationResult]
    private(set) var calls: [Call] = []

    init(results: [BatchClassificationResult]) {
        self.results = results
    }

    func classifyBatch(
        apps: [InstalledApplication],
        enabledStyles: [StyleProfileRecord]
    ) async throws -> [BatchClassificationResult] {
        calls.append(Call(apps: apps, styles: enabledStyles))
        return results
    }
}
