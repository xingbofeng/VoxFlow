import XCTest
@testable import VoxFlowApp

final class SettingsRootViewLayoutTests: XCTestCase {
    func testGeneralPreferencesUseSingleInputLanguageGroupCard() throws {
        let sourceURL = try Self.repositoryRoot()
            .appendingPathComponent("Sources/VoxFlowApp/Views/SettingsRootView.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        XCTAssertTrue(source.contains("private var inputLanguageCard"))
        XCTAssertTrue(source.contains("title: \"输入与语言\""))
        XCTAssertTrue(source.contains("inputDeviceRow"))
        XCTAssertTrue(source.contains("recognitionLanguageRow"))
        XCTAssertTrue(source.contains("HStack(alignment: .top, spacing: 12) {\n                inputDeviceRow\n                recognitionLanguageRow\n            }"))
        XCTAssertTrue(source.contains("inputLanguageCard"))
        XCTAssertTrue(source.contains(".frame(maxWidth: .infinity, alignment: .leading)"))
        XCTAssertTrue(source.contains("private var inputDeviceRow"))
        XCTAssertTrue(source.contains("private var recognitionLanguageRow"))
        XCTAssertTrue(source.contains(".menuStyle(.borderlessButton)\n        .frame(maxWidth: .infinity, alignment: .leading)"))
        XCTAssertFalse(source.contains("private var topPreferenceCards"))
        XCTAssertFalse(source.contains("topPreferenceCardWidth"))
        XCTAssertFalse(source.contains("ViewThatFits(in: .horizontal)"))
        XCTAssertFalse(source.contains("GridItem(.adaptive(minimum: 320)"))
    }

    func testModelSettingsIncludeASRTTSTranslationAndCorrectionSections() throws {
        let sourceURL = try Self.repositoryRoot()
            .appendingPathComponent("Sources/VoxFlowApp/Views/SettingsRootView.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        XCTAssertTrue(source.contains("settingsSidebarButton(.dictationModels)"))
        XCTAssertTrue(source.contains("settingsSidebarButton(.correctionModels)"))
        XCTAssertTrue(source.contains("settingsSidebarButton(.ttsModels)"))
        XCTAssertTrue(source.contains("settingsSidebarButton(.translationModels)"))
        XCTAssertTrue(source.contains("private var dictationModelsSection"))
        XCTAssertTrue(source.contains("private var correctionModelsSection"))
        XCTAssertTrue(source.contains("private var ttsModelsSection"))
        XCTAssertTrue(source.contains("private var translationModelsSection"))
        XCTAssertTrue(source.contains("title: \"ASR 模型\""))
        XCTAssertTrue(source.contains("title: \"LLM 模型\""))
        XCTAssertTrue(source.contains("title: \"TTS 模型\""))
        XCTAssertTrue(source.contains("title: \"翻译模型\""))
        XCTAssertTrue(source.contains("ASRProviderView(viewModel: asrProviderViewModel, embedded: true)"))
        XCTAssertTrue(source.contains("LLMProviderView(viewModel: llmProviderViewModel, embedded: true)"))
        XCTAssertTrue(source.contains("CapabilityModelView(viewModel: ttsCapabilityModelViewModel)"))
        XCTAssertTrue(source.contains("CapabilityModelView(viewModel: translationCapabilityModelViewModel)"))
        XCTAssertFalse(source.contains("settingsSidebarButton(.models)"))
        XCTAssertFalse(source.contains("private var modelsSection"))
    }

    func testVibeCodingSettingsUseVerticalCardsAndDocumentAllLaunchCommands() throws {
        let sourceURL = try Self.repositoryRoot()
            .appendingPathComponent("Sources/VoxFlowApp/Views/SettingsRootView.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        XCTAssertTrue(source.contains("settingsSidebarButton(.vibeCoding)"))
        XCTAssertTrue(source.contains("private var vibeCodingSection"))
        XCTAssertTrue(source.contains("title: \"Vibe Coding 指挥中心\""))
        XCTAssertTrue(source.contains("用语音把指令发给正在工作的终端 Agent"))
        XCTAssertTrue(source.contains("Text(\"vox flow codex\")"))
        XCTAssertTrue(source.contains("Text(\"vox flow --claude\")"))
        XCTAssertTrue(source.contains("Text(\"vox flow --codebuddy\")"))
        XCTAssertTrue(source.contains("Button(\"注册命令\")"))
        XCTAssertTrue(source.contains("Button(\"卸载命令\", role: .destructive)"))
        XCTAssertTrue(source.contains("Button(\"复制示例\")"))
        XCTAssertTrue(source.contains("title: \"启用指挥中心\""))
        XCTAssertTrue(source.contains("现有语音输入快捷键会进入 Vibe Coding 指挥 HUD"))
        XCTAssertTrue(source.contains("Text(\"默认发送\").tag(\"default\")"))
        XCTAssertTrue(source.contains("unresolvedBehaviorHelpText"))
        XCTAssertTrue(source.contains("询问确认：让你选择队员"))
        XCTAssertTrue(source.contains("取消发送：保留文本不发送"))
        XCTAssertTrue(source.contains("模型判断：用 LLM 排序候选"))
        XCTAssertTrue(source.contains("默认发送：写入当前输入框"))
        XCTAssertTrue(source.contains(".frame(width: 248, alignment: .trailing)"))
        XCTAssertFalse(source.contains("title: \"当前队员\""))
        XCTAssertFalse(source.contains("title: \"队员别名\""))
        XCTAssertFalse(source.contains("title: \"指挥中心快捷键\""))
        XCTAssertFalse(source.contains("agent.status.rawValue"))
    }

    func testVibeCodingStatusPageOwnsAgentsAliasEditingAndAutoRefresh() throws {
        let sourceURL = try Self.repositoryRoot()
            .appendingPathComponent("Sources/VoxFlowApp/Views/VibeCodingStatusView.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        XCTAssertTrue(source.contains("struct VibeCodingStatusView"))
        XCTAssertTrue(source.contains("title: \"当前队员\""))
        XCTAssertTrue(source.contains("viewModel.agentSessions"))
        XCTAssertTrue(source.contains("Label(\"刷新队员\""))
        XCTAssertTrue(source.contains("Label(\"清理失效队员\""))
        XCTAssertTrue(source.contains("startEditingAlias"))
        XCTAssertTrue(source.contains("TextField(\"队员别名\""))
        XCTAssertTrue(source.contains("await viewModel.setAgentAlias"))
        XCTAssertTrue(source.contains("Button(\"清空记录\", role: .destructive)"))
        XCTAssertTrue(source.contains("语音指挥内容只保存在本地"))
        XCTAssertTrue(source.contains("autoRefreshAgentSessions"))
        XCTAssertTrue(source.contains("Task.sleep(nanoseconds:"))
    }

    func testDeleteAllLocalModelsRequiresConfirmation() throws {
        let sourceURL = try Self.repositoryRoot()
            .appendingPathComponent("Sources/VoxFlowApp/Views/SettingsRootView.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        XCTAssertTrue(source.contains("Button(\"删除全部本地模型\", role: .destructive)"))
        XCTAssertTrue(source.contains("showDeleteAllLocalModelsConfirmation = true"))
        XCTAssertTrue(source.contains(".confirmationDialog("))
        XCTAssertTrue(source.contains("try viewModel.deleteAllLocalModels()"))
        XCTAssertFalse(source.contains("Button(\"清空缓存\", role: .destructive)"))
    }

    private static func repositoryRoot() throws -> URL {
        var directory = URL(fileURLWithPath: #filePath)
        while directory.path != "/" {
            if FileManager.default.fileExists(atPath: directory.appendingPathComponent("Package.swift").path) {
                return directory
            }
            directory.deleteLastPathComponent()
        }
        throw NSError(
            domain: "SettingsRootViewLayoutTests",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "Could not locate Package.swift from test file path."]
        )
    }
}
