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

    func testMiddleMouseRecordingCopyDescribesClickToToggle() throws {
        let sourceURL = try Self.repositoryRoot()
            .appendingPathComponent("Sources/VoxFlowApp/Views/SettingsRootView.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        XCTAssertTrue(source.contains("title: \"鼠标中键录音\""))
        XCTAssertTrue(source.contains("点击鼠标中键开始录音，再次点击结束并输入"))
        XCTAssertFalse(source.contains("开启后，按住鼠标中键说话，松开后转写并输入"))
    }

    func testModelSettingsIncludeASRTTSTranslationAndCorrectionSections() throws {
        let sourceURL = try Self.repositoryRoot()
            .appendingPathComponent("Sources/VoxFlowApp/Views/SettingsRootView.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        XCTAssertTrue(source.contains("settingsSidebarButton(.dictationModels)"))
        XCTAssertTrue(source.contains("settingsSidebarButton(.correctionModels)"))
        XCTAssertTrue(source.contains("settingsSidebarButton(.ttsModels)"))
        XCTAssertTrue(source.contains("settingsSidebarButton(.translationModels)"))
        XCTAssertTrue(source.contains("sidebarGroupTitle(\"应用设置\")"))
        XCTAssertTrue(source.contains("sidebarGroupTitle(\"模型配置\")"))
        XCTAssertTrue(source.contains("sidebarGroupTitle(\"数据与隐私\")"))
        let appGroupRange = try XCTUnwrap(source.range(of: "sidebarGroupTitle(\"应用设置\")"))
        let modelGroupRange = try XCTUnwrap(source.range(of: "sidebarGroupTitle(\"模型配置\")"))
        XCTAssertLessThan(appGroupRange.lowerBound, modelGroupRange.lowerBound)
        let generalButtonRange = try XCTUnwrap(source.range(of: "settingsSidebarButton(.general)"))
        XCTAssertLessThan(appGroupRange.lowerBound, generalButtonRange.lowerBound)
        XCTAssertLessThan(generalButtonRange.lowerBound, modelGroupRange.lowerBound)
        XCTAssertTrue(source.contains("private var dictationModelsSection"))
        XCTAssertTrue(source.contains("private var correctionModelsSection"))
        XCTAssertTrue(source.contains("private var ttsModelsSection"))
        XCTAssertTrue(source.contains("private var translationModelsSection"))
        XCTAssertTrue(source.contains("title: \"语音识别\""))
        XCTAssertTrue(source.contains("title: \"纠错与上下文\""))
        XCTAssertTrue(source.contains("title: \"易错词修正\""))
        XCTAssertTrue(source.contains("title: \"启用易错词修正\""))
        XCTAssertTrue(source.contains("title: \"影子模式\""))
        XCTAssertTrue(source.contains("title: \"朗读\""))
        XCTAssertTrue(source.contains("title: \"翻译\""))
        XCTAssertTrue(source.contains("ASRProviderView(viewModel: asrProviderViewModel, embedded: true)"))
        XCTAssertTrue(source.contains("LLMProviderView(viewModel: llmProviderViewModel, embedded: true)"))
        XCTAssertTrue(source.contains("CapabilityModelView(viewModel: ttsCapabilityModelViewModel)"))
        XCTAssertTrue(source.contains("CapabilityModelView(viewModel: translationCapabilityModelViewModel)"))
        XCTAssertTrue(source.contains("@AppStorage(ContextBoostSettings.enabledDefaultsKey)"))
        XCTAssertTrue(source.contains("title: \"当前窗口图片文字识别上下文增强\""))
        XCTAssertTrue(source.contains("仅将当前窗口提取的前 K 条候选词临时加入模型纠错提示词"))
        XCTAssertTrue(source.contains("title: \"剪贴板图片文字识别\""))
        XCTAssertTrue(source.contains("title: \"截图文字识别\""))
        XCTAssertTrue(source.contains("title: \"启动台\""))
        XCTAssertTrue(source.contains("subtitle: \"打开 VoxFlow Palette，搜索最近资产与命令\""))
        XCTAssertTrue(source.contains("workflowShortcutRow("))
        XCTAssertTrue(source.contains("viewModel.updateWorkflowShortcut(shortcut"))
        XCTAssertFalse(source.contains("settingsSidebarButton(.models)"))
        XCTAssertFalse(source.contains("private var modelsSection"))
    }

    func testVibeCodingSettingsUseVerticalCardsAndDocumentAllLaunchCommands() throws {
        let sourceURL = try Self.repositoryRoot()
            .appendingPathComponent("Sources/VoxFlowApp/Views/SettingsRootView.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        XCTAssertTrue(source.contains("settingsSidebarButton(.vibeCoding)"))
        XCTAssertTrue(source.contains("private var vibeCodingSection"))
        XCTAssertTrue(source.contains("title: \"AI 编程控制台\""))
        XCTAssertTrue(source.contains("用语音把指令发给正在工作的终端助手"))
        XCTAssertTrue(source.contains("Text(\"vox flow codex\")"))
        XCTAssertTrue(source.contains("Text(\"vox flow --claude\")"))
        XCTAssertTrue(source.contains("Text(\"vox flow --codebuddy\")"))
        XCTAssertTrue(source.contains("Button(\"注册命令\")"))
        XCTAssertTrue(source.contains("Button(\"卸载命令\", role: .destructive)"))
        XCTAssertTrue(source.contains("Button(\"复制示例\")"))
        XCTAssertTrue(source.contains("title: \"启用AI 编程控制台\""))
        XCTAssertTrue(source.contains("开启后，现有语音输入快捷键会进入AI 编程控制台"))
        XCTAssertTrue(source.contains("Text(\"默认发送\").tag(\"default\")"))
        XCTAssertTrue(source.contains("unresolvedBehaviorHelpText"))
        XCTAssertTrue(source.contains("询问确认：先让你选择目标任务助手"))
        XCTAssertTrue(source.contains("取消发送：保留文本，不发送给任务助手"))
        XCTAssertTrue(source.contains("智能排序：按模型置信度排序候选"))
        XCTAssertTrue(source.contains("默认发送：直接写入当前输入框"))
        XCTAssertTrue(source.contains(".frame(width: 248, alignment: .trailing)"))
        XCTAssertFalse(source.contains("title: \"当前任务助手\""))
        XCTAssertFalse(source.contains("title: \"任务助手别名\""))
        XCTAssertFalse(source.contains("title: \"HUD 控制台快捷键\""))
        XCTAssertFalse(source.contains("agent.status.rawValue"))
    }

    func testSettingsSidebarDoesNotExposeSelectionActionsAsStandalonePage() throws {
        let sourceURL = try Self.repositoryRoot()
            .appendingPathComponent("Sources/VoxFlowApp/Views/SettingsRootView.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)
        let viewModelSourceURL = try Self.repositoryRoot()
            .appendingPathComponent("Sources/VoxFlowApp/ViewModels/SettingsViewModel.swift")
        let viewModelSource = try String(contentsOf: viewModelSourceURL, encoding: .utf8)

        let appGroup = try XCTUnwrap(
            source.range(
                of: #"sidebarGroupTitle\("应用设置"\)[\s\S]*?sidebarGroupTitle\("模型配置"\)"#,
                options: .regularExpression
            ).map { String(source[$0]) }
        )

        XCTAssertTrue(appGroup.contains("settingsSidebarButton(.general)"))
        XCTAssertTrue(appGroup.contains("settingsSidebarButton(.vibeCoding)"))
        XCTAssertTrue(appGroup.contains("settingsSidebarButton(.system)"))
        XCTAssertFalse(appGroup.contains("settingsSidebarButton(.selectionActions)"))
        XCTAssertFalse(source.contains("private var selectionActionsSection"))
        XCTAssertFalse(viewModelSource.contains("case selectionActions"))
    }

    func testGeneralShortcutSettingsIncludeDirectSelectionActions() throws {
        let sourceURL = try Self.repositoryRoot()
            .appendingPathComponent("Sources/VoxFlowApp/Views/SettingsRootView.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)
        let section = try XCTUnwrap(
            source.range(
                of: #"private var generalSection:[\s\S]*?\n    private var vibeCodingSection"#,
                options: .regularExpression
            ).map { String(source[$0]) }
        )

        XCTAssertTrue(section.contains("title: \"划词动作快捷键\""))
        XCTAssertTrue(section.contains("shortcut: .selectionAction"))
        XCTAssertTrue(section.contains("shortcut: .selectionTranslate"))
        XCTAssertTrue(section.contains("shortcut: .selectionSummarize"))
        XCTAssertTrue(section.contains("shortcut: .selectionAgent"))
    }

    func testGeneralSettingsIncludesAppUpdateCheckEntry() throws {
        let sourceURL = try Self.repositoryRoot()
            .appendingPathComponent("Sources/VoxFlowApp/Views/SettingsRootView.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)
        let section = try XCTUnwrap(
            source.range(
                of: #"private var generalSection:[\s\S]*?\n    private var vibeCodingSection"#,
                options: .regularExpression
            ).map { String(source[$0]) }
        )

        XCTAssertTrue(section.contains("appUpdateCard"))
        XCTAssertTrue(source.contains("private var appUpdateCard"))
        XCTAssertTrue(source.contains("title: \"应用更新\""))
        XCTAssertTrue(source.contains("Button(\"检查更新\")"))
        XCTAssertTrue(source.contains("onCheckForUpdates()"))
        XCTAssertTrue(source.contains("AppVersionInfo.current().displayText"))
    }

    func testVoiceTriggerModeLivesWithVoiceShortcuts() throws {
        let sourceURL = try Self.repositoryRoot()
            .appendingPathComponent("Sources/VoxFlowApp/Views/SettingsRootView.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)
        let section = try XCTUnwrap(
            source.range(
                of: #"private var generalSection:[\s\S]*?\n    private var vibeCodingSection"#,
                options: .regularExpression
            ).map { String(source[$0]) }
        )

        let voiceHeader = try XCTUnwrap(section.range(of: #"title: "语音快捷键""#))
        let triggerMode = try XCTUnwrap(section.range(of: #"Text\("触发方式"\)"#, options: .regularExpression))
        let workflowHeader = try XCTUnwrap(section.range(of: #"title: "工作流快捷键""#))

        XCTAssertLessThan(voiceHeader.lowerBound, triggerMode.lowerBound)
        XCTAssertLessThan(triggerMode.lowerBound, workflowHeader.lowerBound)
    }

    func testWorkflowShortcutRecordingIgnoresModifierOnlyEvents() throws {
        let commandOnly = SettingsShortcutRecorder.encodedShortcutKeyCode(
            eventType: .flagsChanged,
            keyCode: UInt16(55),
            modifierFlags: .command,
            allowsPureModifierShortcut: false
        )
        XCTAssertNil(commandOnly)

        let commandShiftJ = SettingsShortcutRecorder.encodedShortcutKeyCode(
            eventType: .keyDown,
            keyCode: UInt16(HotKeyShortcutRouting.jKeyCode),
            modifierFlags: [.command, .shift],
            allowsPureModifierShortcut: false
        )
        XCTAssertEqual(
            commandShiftJ,
            ShortcutManager.encodeShortcut(
                keyCode: HotKeyShortcutRouting.jKeyCode,
                modifierMask: ShortcutManager.commandModifierMask | ShortcutManager.shiftModifierMask
            )
        )

        let voiceCommand = SettingsShortcutRecorder.encodedShortcutKeyCode(
            eventType: .flagsChanged,
            keyCode: UInt16(55),
            modifierFlags: .command,
            allowsPureModifierShortcut: true
        )
        XCTAssertEqual(voiceCommand, 55)
    }

    func testVibeCodingStatusPageOwnsAgentsAliasEditingAndAutoRefresh() throws {
        let sourceURL = try Self.repositoryRoot()
            .appendingPathComponent("Sources/VoxFlowApp/Views/VibeCodingStatusView.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        XCTAssertTrue(source.contains("struct VibeCodingStatusView"))
        XCTAssertTrue(source.contains("title: \"当前任务助手\""))
        XCTAssertTrue(source.contains("viewModel.currentAgentSessions"))
        XCTAssertTrue(source.contains("Label(\"刷新任务助手\""))
        XCTAssertTrue(source.contains("Label(\"清理已退出/失效任务助手\""))
        XCTAssertTrue(source.contains("startEditingAlias"))
        XCTAssertTrue(source.contains("TextField(\"任务助手别名\""))
        XCTAssertTrue(source.contains("await viewModel.setAgentAlias"))
        XCTAssertTrue(source.contains("Button(\"清空记录\", role: .destructive)"))
        XCTAssertTrue(source.contains("语音任务内容只保存在本地"))
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

    func testSystemAppearanceGroupExposesHideDockToggleWithMenuBarCopy() throws {
        let sourceURL = try Self.repositoryRoot()
            .appendingPathComponent("Sources/VoxFlowApp/Views/SettingsRootView.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        XCTAssertTrue(source.contains("systemToggle(.hideDockIconWhenWorkbenchCloses"))
        XCTAssertTrue(source.contains("关闭工作台后隐藏 Dock 图标"))
        XCTAssertTrue(source.contains("菜单栏图标仍可使用"))
        XCTAssertTrue(source.contains("\"dock.rectangle\""))
        XCTAssertFalse(source.contains("\"dock.arrow\""))
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
