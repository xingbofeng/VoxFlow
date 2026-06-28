import XCTest
@testable import VoxFlowApp

final class SettingsRootViewLayoutTests: XCTestCase {
    func testGeneralPreferencesUseSingleInputLanguageGroupCard() throws {
        let sourceURL = try Self.repositoryRoot()
            .appendingPathComponent("Sources/VoxFlowApp/Views/SettingsRootView.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        XCTAssertTrue(source.contains("private var inputLanguageCard"))
        XCTAssertTrue(source.contains("settings.task.input_language.title"))
        XCTAssertTrue(source.contains("inputDeviceRow"))
        XCTAssertTrue(source.contains("recognitionLanguageRow"))
        XCTAssertTrue(source.contains("VStack(spacing: 12)"))
        XCTAssertTrue(source.contains("interfaceLanguageRow"))
        XCTAssertTrue(source.contains("inputLanguageCard"))
        XCTAssertTrue(source.contains(".frame(maxWidth: .infinity, alignment: .leading)"))
        XCTAssertTrue(source.contains("private var inputDeviceRow"))
        XCTAssertTrue(source.contains("private var recognitionLanguageRow"))
        XCTAssertTrue(source.contains(".buttonStyle(.plain)"))
        XCTAssertTrue(source.contains(".popover("))
        XCTAssertFalse(source.contains("private var topPreferenceCards"))
        XCTAssertFalse(source.contains("topPreferenceCardWidth"))
        XCTAssertFalse(source.contains("ViewThatFits(in: .horizontal)"))
        XCTAssertFalse(source.contains("GridItem(.adaptive(minimum: 320)"))
    }

    func testSettingsDropdownUsesFloatingPopoverWithoutExpandingPageHeight() throws {
        let sourceURL = try Self.repositoryRoot()
            .appendingPathComponent("Sources/VoxFlowApp/Views/SettingsRootView.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)
        let dropdown = try XCTUnwrap(
            source.range(
                of: #"private struct SettingsDropdownSection[\s\S]*?\nprivate struct SettingsDropdownOptionRow"#,
                options: .regularExpression
            ).map { String(source[$0]) }
        )

        XCTAssertTrue(dropdown.contains(".popover("))
        XCTAssertTrue(dropdown.contains("SettingsDropdownPopover"))
        XCTAssertFalse(dropdown.contains("if isExpanded {\n                ScrollView"))
        XCTAssertFalse(dropdown.contains(".overlay(alignment: .top)"))
    }

    func testSettingsDropdownDismissalUsesExplicitExpansionState() throws {
        let sourceURL = try Self.repositoryRoot()
            .appendingPathComponent("Sources/VoxFlowApp/Views/SettingsRootView.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)
        let dropdown = try XCTUnwrap(
            source.range(
                of: #"private struct SettingsDropdownSection[\s\S]*?\nprivate struct SettingsDropdownOptionRow"#,
                options: .regularExpression
            ).map { String(source[$0]) }
        )

        XCTAssertTrue(dropdown.contains("let onExpandedChange: (Bool) -> Void"))
        XCTAssertTrue(dropdown.contains("Button { onExpandedChange(!isExpanded) }"))
        XCTAssertTrue(dropdown.contains("onExpandedChange(presented)"))
        XCTAssertFalse(dropdown.contains("onToggle()"))
    }

    func testInterfaceLanguageSelectionDismissesPopoverBeforeRestartModal() throws {
        let sourceURL = try Self.repositoryRoot()
            .appendingPathComponent("Sources/VoxFlowApp/Views/SettingsRootView.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        XCTAssertTrue(source.contains("private func requestInterfaceLanguageChange(_ language: AppLanguage)"))
        XCTAssertTrue(source.contains("setDropdown(.interfaceLanguage, expanded: false)"))
        XCTAssertTrue(source.contains("DispatchQueue.main.asyncAfter(deadline: .now() + 0.18)"))
        XCTAssertTrue(source.contains("pendingInterfaceLanguage = language"))
        XCTAssertTrue(source.contains("requestInterfaceLanguageChange(language)"))
    }

    func testMiddleMouseRecordingCopyDescribesClickToToggle() throws {
        let sourceURL = try Self.repositoryRoot()
            .appendingPathComponent("Sources/VoxFlowApp/Views/SettingsRootView.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        XCTAssertTrue(source.contains("settings.general.middle_mouse.title"))
        XCTAssertTrue(source.contains("settings.general.middle_mouse.subtitle"))
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
        XCTAssertTrue(source.contains("settings.task.sidebar.group.app"))
        XCTAssertTrue(source.contains("settings.task.sidebar.group.models"))
        XCTAssertTrue(source.contains("settings.task.sidebar.group.data_privacy"))
        let appGroupRange = try XCTUnwrap(source.range(of: "settings.task.sidebar.group.app"))
        let modelGroupRange = try XCTUnwrap(source.range(of: "settings.task.sidebar.group.models"))
        XCTAssertLessThan(appGroupRange.lowerBound, modelGroupRange.lowerBound)
        let generalButtonRange = try XCTUnwrap(source.range(of: "settingsSidebarButton(.general)"))
        XCTAssertLessThan(appGroupRange.lowerBound, generalButtonRange.lowerBound)
        XCTAssertLessThan(generalButtonRange.lowerBound, modelGroupRange.lowerBound)
        XCTAssertTrue(source.contains("private var dictationModelsSection"))
        XCTAssertTrue(source.contains("private var correctionModelsSection"))
        XCTAssertTrue(source.contains("private var ttsModelsSection"))
        XCTAssertTrue(source.contains("private var translationModelsSection"))
        XCTAssertTrue(source.contains("settings.task.dictation.section.title"))
        XCTAssertTrue(source.contains("settings.task.correction.title"))
        XCTAssertTrue(source.contains("settings.task.easy_word.title"))
        XCTAssertTrue(source.contains("settings.task.easy_word.enable.title"))
        XCTAssertTrue(source.contains("settings.task.easy_word.shadow_mode.title"))
        XCTAssertTrue(source.contains("settings.task.tts.title"))
        XCTAssertTrue(source.contains("settings.task.translation.title"))
        XCTAssertTrue(source.contains("ASRProviderView(viewModel: asrProviderViewModel, embedded: true)"))
        XCTAssertTrue(source.contains("LLMProviderView(viewModel: llmProviderViewModel, embedded: true)"))
        XCTAssertTrue(source.contains("CapabilityModelView(viewModel: ttsCapabilityModelViewModel)"))
        XCTAssertTrue(source.contains("CapabilityModelView(viewModel: translationCapabilityModelViewModel)"))
        XCTAssertTrue(source.contains("@AppStorage(ContextBoostSettings.enabledDefaultsKey)"))
        XCTAssertTrue(source.contains("settings.task.correction.context_boost.title"))
        XCTAssertTrue(source.contains("settings.task.correction.context_boost.subtitle"))
        XCTAssertTrue(source.contains("settings.task.workflow.clipboard_image.title"))
        XCTAssertTrue(source.contains("settings.task.workflow.screenshot.title"))
        XCTAssertTrue(source.contains("settings.task.workflow.palette.title"))
        XCTAssertTrue(source.contains("settings.task.workflow.palette.subtitle"))
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
        XCTAssertTrue(source.contains("settings.task.ai_console.title"))
        XCTAssertTrue(source.contains("settings.task.ai_console.subtitle"))
        XCTAssertTrue(source.contains("settings.task.agent_cli.example_codex"))
        XCTAssertTrue(source.contains("settings.task.agent_cli.example_claude"))
        XCTAssertTrue(source.contains("settings.task.agent_cli.example_codebuddy"))
        XCTAssertTrue(source.contains("settings.task.action.register"))
        XCTAssertTrue(source.contains("settings.task.action.unregister"))
        XCTAssertTrue(source.contains("settings.task.action.copy_example"))
        XCTAssertTrue(source.contains("settings.task.ai_console.enable.title"))
        XCTAssertTrue(source.contains("settings.task.ai_console.enable.subtitle"))
        XCTAssertTrue(source.contains("settings.task.unresolved_behavior.option.default"))
        XCTAssertTrue(source.contains("unresolvedBehaviorHelpText"))
        XCTAssertTrue(source.contains("settings.task.unresolved_behavior.option.confirm"))
        XCTAssertTrue(source.contains("settings.task.unresolved_behavior.option.cancel"))
        XCTAssertTrue(source.contains("settings.task.unresolved_behavior.option.model"))
        XCTAssertTrue(source.contains("settings.task.unresolved_behavior.option.default"))
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
                of: #"settings\.task\.sidebar\.group\.app[\s\S]*?settings\.task\.sidebar\.group\.models"#,
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

        XCTAssertTrue(section.contains("settings.task.selection.group.title"))
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
        XCTAssertTrue(source.contains("settings.task.update.title"))
        XCTAssertTrue(source.contains("settings.task.update.action_check"))
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

        let voiceHeader = try XCTUnwrap(section.range(of: "settings.general.voice_shortcut.title"))
        let triggerMode = try XCTUnwrap(section.range(of: "settings.general.trigger_mode.title"))
        let workflowHeader = try XCTUnwrap(section.range(of: "settings.task.workflow.group.title"))

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
        XCTAssertTrue(source.contains("vibe.current_agents.title"))
        XCTAssertTrue(source.contains("viewModel.currentAgentSessions"))
        XCTAssertTrue(source.contains("Label(L10n.localize(\"vibe.current_agents.refresh\""))
        XCTAssertTrue(source.contains("Label(L10n.localize(\"vibe.current_agents.clean_stale\""))
        XCTAssertTrue(source.contains("startEditingAlias"))
        XCTAssertTrue(source.contains("TextField(L10n.localize(\"vibe.alias.field_title\""))
        XCTAssertTrue(source.contains("await viewModel.setAgentAlias"))
        XCTAssertTrue(source.contains("Button(L10n.localize(\"vibe.recent_dispatches.clear\""))
        XCTAssertTrue(source.contains("vibe.recent_dispatches.local_notice"))
        XCTAssertTrue(source.contains("autoRefreshAgentSessions"))
        XCTAssertTrue(source.contains("Task.sleep(nanoseconds:"))
    }

    func testDeleteAllLocalModelsRequiresConfirmation() throws {
        let sourceURL = try Self.repositoryRoot()
            .appendingPathComponent("Sources/VoxFlowApp/Views/SettingsRootView.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        XCTAssertTrue(source.contains("Button(L10n.localize(\"settings.task.action.delete_all_local_models\""))
        XCTAssertTrue(source.contains("showDeleteAllLocalModelsConfirmation = true"))
        XCTAssertTrue(source.contains(".confirmationDialog("))
        XCTAssertTrue(source.contains("try viewModel.deleteAllLocalModels()"))
        XCTAssertFalse(source.contains("Button(\"清空缓存\", role: .destructive)"))
    }

    func testSystemAppearanceGroupExposesHideDockToggleWithMenuBarCopy() throws {
        let sourceURL = try Self.repositoryRoot()
            .appendingPathComponent("Sources/VoxFlowApp/Views/SettingsRootView.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        XCTAssertTrue(source.contains(".hideDockIconWhenWorkbenchCloses"))
        XCTAssertTrue(source.contains("settings.appearance.hide_dock_icon.title"))
        XCTAssertTrue(source.contains("settings.appearance.hide_dock_icon.subtitle"))
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
