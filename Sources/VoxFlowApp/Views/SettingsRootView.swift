import AppKit
import SwiftUI

private enum ShortcutBinding: Equatable {
    case voice(VoiceAction)
    case workflow(HotKeyWorkflowShortcut)
}

private enum SettingsDropdown: Equatable {
    case inputDevice
    case recognitionLanguage
    case interfaceLanguage
}

enum SettingsShortcutRecorder {
    static func encodedShortcutKeyCode(
        eventType: NSEvent.EventType,
        keyCode: UInt16,
        modifierFlags: NSEvent.ModifierFlags,
        allowsPureModifierShortcut: Bool
    ) -> Int64? {
        if eventType == .flagsChanged, !allowsPureModifierShortcut {
            return nil
        }
        return ShortcutManager.encodeShortcut(
            keyCode: Int64(keyCode),
            modifierMask: ShortcutManager.modifierMask(
                command: modifierFlags.contains(.command),
                shift: modifierFlags.contains(.shift),
                option: modifierFlags.contains(.option),
                control: modifierFlags.contains(.control)
            )
        )
    }
}

struct SettingsRootView: View {
    @ObservedObject var viewModel: SettingsViewModel
    @ObservedObject var llmProviderViewModel: LLMProviderViewModel
    @ObservedObject var asrProviderViewModel: ASRProviderViewModel
    let onCheckForUpdates: () -> Void
    @StateObject private var ttsCapabilityModelViewModel = CapabilityModelViewModel(kind: .tts)
    @StateObject private var translationCapabilityModelViewModel = CapabilityModelViewModel(kind: .translation)
    @State private var recordingShortcutBinding: ShortcutBinding?
    @State private var shortcutMonitor: Any?
    @State private var importedJSON = ""
    @State private var newAgentAlias = ""
    @State private var aliasTargetAgentID = ""
    @State private var showDeleteAllLocalModelsConfirmation = false
    @State private var showAgentCLIRegistrationConfirmation = false
    @State private var showAgentCLIUnregistrationConfirmation = false
    @State private var openDropdown: SettingsDropdown?
    @State private var pendingInterfaceLanguage: AppLanguage?
    @AppStorage(RepositoryBackedLLMRefiner.enabledDefaultsKey) private var llmCorrectionEnabled = false
    @AppStorage(ContextBoostSettings.enabledDefaultsKey) private var contextBoostEnabled = ContextBoostSettings.defaultEnabled

    var body: some View {
        HStack(spacing: 0) {
            settingsSidebar
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    Text(viewModel.selectedSection.pageTitle)
                        .font(.system(size: 30, weight: .bold))
                    sectionContent
                }
                .padding(30)
                .frame(maxWidth: 1_080, alignment: .topLeading)
                .frame(maxWidth: .infinity, alignment: .top)
            }
        }
        .background(AppTheme.ColorToken.pageBackground)
        .tint(AppTheme.ColorToken.accent)
        .actionFeedbackOverlay(
            message: actionFeedbackMessage,
            error: actionFeedbackError,
            onDismiss: clearActionFeedback
        )
        .overlay {
            if let pendingInterfaceLanguage {
                SettingsRestartConfirmationModal(
                    languageName: pendingInterfaceLanguage.displayName,
                    onConfirm: {
                        confirmInterfaceLanguageChange(pendingInterfaceLanguage)
                    },
                    onCancel: {
                        self.pendingInterfaceLanguage = nil
                    }
                )
            }
        }
        .confirmationDialog(
            L10n.localize("settings.task.dialog.delete_all_local_models.title", comment: "Delete all local model dialog title"),
            isPresented: $showDeleteAllLocalModelsConfirmation,
            titleVisibility: .visible
        ) {
            Button(L10n.localize("settings.task.action.delete_all_local_models", comment: "Delete all local models"), role: .destructive) {
                perform { try viewModel.deleteAllLocalModels() }
            }
            Button(L10n.localize("settings.task.action.cancel", comment: "Cancel action"), role: .cancel) {}
        } message: {
            Text(
                String(
                    format: L10n.localize(
                        "settings.task.dialog.delete_all_local_models.message_format",
                        comment: "Delete all local model confirmation message"
                    ),
                    viewModel.localModelStorageDescription()
                )
            )
        }
        .confirmationDialog(
            L10n.localize("settings.task.dialog.register_cli.title", comment: "Register terminal command dialog title"),
            isPresented: $showAgentCLIRegistrationConfirmation,
            titleVisibility: .visible
        ) {
            Button(L10n.localize("settings.task.action.register", comment: "Register action")) {
                viewModel.registerAgentCLI()
            }
            Button(L10n.localize("settings.task.action.cancel", comment: "Cancel action"), role: .cancel) {}
        } message: {
            let preview = viewModel.agentCLIRegistrationPreview()
            Text(
                L10n.localize("settings.agent_cli.register_confirmation_message", comment: "Agent CLI registration confirmation message")
                + " \(preview.profileURL.path)\n\n"
                + preview.shellBlock
            )
        }
        .confirmationDialog(
            L10n.localize("settings.task.dialog.unregister_cli.title", comment: "Unregister terminal command dialog title"),
            isPresented: $showAgentCLIUnregistrationConfirmation,
            titleVisibility: .visible
        ) {
            Button(L10n.localize("settings.task.action.unregister", comment: "Unregister action"), role: .destructive) {
                viewModel.unregisterAgentCLI()
            }
            Button(L10n.localize("settings.task.action.cancel", comment: "Cancel action"), role: .cancel) {}
        } message: {
            let preview = viewModel.agentCLIRegistrationPreview()
            Text(
                L10n.localize("settings.agent_cli.unregister_confirmation_message", comment: "Agent CLI unregistration confirmation message")
                + " "
                + preview.profileURL.path
            )
        }
        .onAppear {
            viewModel.loadIfNeeded()
            llmProviderViewModel.loadIfNeeded()
            syncTranslationLLMAvailability()
        }
        .onChange(of: llmProviderViewModel.providers) { _, _ in
            syncTranslationLLMAvailability()
        }
        .onDisappear {
            stopShortcutRecording()
        }
    }

    private var actionFeedbackMessage: String? {
        viewModel.lastActionMessage
            ?? llmProviderViewModel.lastActionMessage
            ?? asrProviderViewModel.lastActionMessage
    }

    private var actionFeedbackError: String? {
        viewModel.lastError
            ?? llmProviderViewModel.lastError
            ?? asrProviderViewModel.lastError
    }

    private func clearActionFeedback() {
        viewModel.clearFeedback()
        llmProviderViewModel.clearFeedback()
        asrProviderViewModel.clearFeedback()
    }

    private func syncTranslationLLMAvailability() {
        translationCapabilityModelViewModel.setLLMTranslationAvailable(
            LLMProviderAvailability.hasUsableProvider(in: llmProviderViewModel.providers)
        )
    }

    private var unresolvedBehaviorHelpText: String {
        L10n.localize("settings.task.unresolved_behavior_help", comment: "Unresolved behavior help text")
    }

    private var settingsSidebar: some View {
        VStack(alignment: .leading, spacing: 8) {
            sidebarGroupTitle(L10n.localize("settings.task.sidebar.group.app", comment: "Sidebar section group title"))

            settingsSidebarButton(.general)
            settingsSidebarButton(.vibeCoding)
            settingsSidebarButton(.system)

            sidebarGroupTitle(L10n.localize("settings.task.sidebar.group.models", comment: "Sidebar section group title"))
                .padding(.top, 16)

            settingsSidebarButton(.dictationModels)
            settingsSidebarButton(.correctionModels)
            settingsSidebarButton(.ttsModels)
            settingsSidebarButton(.translationModels)

            sidebarGroupTitle(L10n.localize("settings.task.sidebar.group.data_privacy", comment: "Sidebar section group title"))
                .padding(.top, 16)

            settingsSidebarButton(.dataPrivacy)
            Spacer()
            Text("v\(AppVersionInfo.current().displayText)")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(AppTheme.ColorToken.secondaryText)
                .padding(.horizontal, 12)
        }
        .padding(16)
        .frame(width: 220)
        .background(AppTheme.ColorToken.sidebarBackground)
    }

    @ViewBuilder
    private var sectionContent: some View {
        switch viewModel.selectedSection {
        case .general:
            generalSection
        case .vibeCoding:
            vibeCodingSection
        case .dictationModels:
            dictationModelsSection
        case .correctionModels:
            correctionModelsSection
        case .ttsModels:
            ttsModelsSection
        case .translationModels:
            translationModelsSection
        case .system:
            systemSection
        case .dataPrivacy:
            dataPrivacySection
        }
    }

    private var dictationModelsSection: some View {
        SettingsGroupCard(
            title: L10n.localize("settings.task.dictation.section.title", comment: "Dictation section title"),
            subtitle: L10n.localize("settings.task.dictation.section.subtitle", comment: "Dictation section subtitle"),
            systemImage: "waveform",
            tint: AppTheme.ColorToken.accent
        ) {
            ASRProviderView(viewModel: asrProviderViewModel, embedded: true)
        }
    }

    private var correctionModelsSection: some View {
        VStack(alignment: .leading, spacing: 22) {
            SettingsGroupCard(
                title: L10n.localize("settings.task.correction.title", comment: "Correction section title"),
                subtitle: L10n.localize("settings.task.correction.subtitle", comment: "Correction section subtitle"),
                systemImage: "sparkles",
                tint: .blue
            ) {
                SettingsToggleRow(
                    title: L10n.localize("settings.task.correction.llm.title", comment: "Enable AI correction title"),
                    subtitle: L10n.localize("settings.task.correction.llm.subtitle", comment: "Enable AI correction subtitle"),
                    systemImage: "sparkles",
                    tint: .blue,
                    isOn: $llmCorrectionEnabled
                )
                SettingsToggleRow(
                    title: L10n.localize("settings.task.correction.context_boost.title", comment: "Context boost title"),
                    subtitle: L10n.localize("settings.task.correction.context_boost.subtitle", comment: "Context boost subtitle"),
                    systemImage: "text.viewfinder",
                    tint: .indigo,
                    isOn: $contextBoostEnabled
                )
                LLMProviderView(viewModel: llmProviderViewModel, embedded: true)
            }

            SettingsGroupCard(
                title: L10n.localize("settings.task.easy_word.title", comment: "Easy word correction title"),
                subtitle: L10n.localize("settings.task.easy_word.subtitle", comment: "Easy word correction subtitle"),
                systemImage: "text.badge.checkmark",
                tint: AppTheme.ColorToken.accent
            ) {
                SettingsToggleRow(
                    title: L10n.localize("settings.task.easy_word.enable.title", comment: "Enable easy word correction title"),
                    subtitle: L10n.localize("settings.task.easy_word.enable.subtitle", comment: "Enable easy word correction subtitle"),
                    systemImage: "checkmark.shield",
                    tint: AppTheme.ColorToken.accent,
                    isOn: voiceCorrectionEnabledBinding
                )
                SettingsToggleRow(
                    title: L10n.localize("settings.task.easy_word.auto_learning.title", comment: "Auto learning title"),
                    subtitle: L10n.localize("settings.task.easy_word.auto_learning.subtitle", comment: "Auto learning subtitle"),
                    systemImage: "sparkle.magnifyingglass",
                    tint: .orange,
                    isOn: voiceCorrectionAutoLearningBinding
                )
                SettingsToggleRow(
                    title: L10n.localize("settings.task.easy_word.auto_learning_immediate.title", comment: "Auto learning immediate title"),
                    subtitle: L10n.localize("settings.task.easy_word.auto_learning_immediate.subtitle", comment: "Auto learning immediate subtitle"),
                    systemImage: "bolt.badge.checkmark",
                    tint: .green,
                    isOn: voiceCorrectionAutoLearningImmediateBinding
                )
                SettingsToggleRow(
                    title: L10n.localize("settings.task.easy_word.shadow_mode.title", comment: "Shadow mode title"),
                    subtitle: L10n.localize("settings.task.easy_word.shadow_mode.subtitle", comment: "Shadow mode subtitle"),
                    systemImage: "shield.lefthalf.filled",
                    tint: .orange,
                    isOn: voiceCorrectionShadowModeBinding
                )
            }
        }
    }

    private var ttsModelsSection: some View {
        SettingsGroupCard(
            title: L10n.localize("settings.task.tts.title", comment: "TTS section title"),
            subtitle: L10n.localize("settings.task.tts.subtitle", comment: "TTS section subtitle"),
            systemImage: "speaker.wave.2",
            tint: .green
        ) {
            CapabilityModelView(viewModel: ttsCapabilityModelViewModel)
        }
    }

    private var translationModelsSection: some View {
        SettingsGroupCard(
            title: L10n.localize("settings.task.translation.title", comment: "Translation section title"),
            subtitle: L10n.localize("settings.task.translation.subtitle", comment: "Translation section subtitle"),
            systemImage: "globe.asia.australia",
            tint: .teal
        ) {
            CapabilityModelView(viewModel: translationCapabilityModelViewModel)
        }
    }

    private var generalSection: some View {
        VStack(alignment: .leading, spacing: 22) {
            inputLanguageCard
                .frame(maxWidth: .infinity, alignment: .leading)

            SettingsGroupCard(
                title: L10n.localize("settings.general.shortcuts.title", comment: "Shortcuts card title"),
                subtitle: L10n.localize("settings.general.shortcuts.subtitle", comment: "Shortcuts card subtitle"),
                systemImage: "keyboard",
                tint: .purple
            ) {
                VStack(alignment: .leading, spacing: 12) {
                    shortcutGroupHeader(
                        title: L10n.localize("settings.general.voice_shortcut.title", comment: "Voice shortcut group title"),
                        subtitle: L10n.localize("settings.general.voice_shortcut.subtitle", comment: "Voice shortcut group subtitle")
                    )

                    actionShortcutRow(
                        action: .dictation,
                        title: L10n.localize("settings.general.dictation.title", comment: "Dictation action row title"),
                        subtitle: L10n.localize("settings.general.dictation.subtitle", comment: "Dictation action row subtitle"),
                        buttonTitle: L10n.localize("settings.general.dictation.button_title", comment: "Dictation action row button")
                    )

                    Divider()
                        .padding(.leading, 70)

                    actionShortcutRow(
                        action: .agentCompose,
                        title: L10n.localize("settings.general.agent_compose.title", comment: "Agent compose action row title"),
                        subtitle: L10n.localize("settings.general.agent_compose.subtitle", comment: "Agent compose action row subtitle"),
                        buttonTitle: L10n.localize("settings.general.agent_compose.button_title", comment: "Agent compose action row button"),
                        badge: L10n.localize("settings.general.agent_compose.badge", comment: "Agent compose badge text"),
                        prominentWhenUnbound: true
                    )

                    Divider()
                        .padding(.leading, 70)

                    SettingsToggleRow(
                        title: L10n.localize("settings.general.middle_mouse.title", comment: "Middle mouse button recording title"),
                        subtitle: L10n.localize("settings.general.middle_mouse.subtitle", comment: "Middle mouse button recording subtitle"),
                        systemImage: "computermouse",
                        tint: .blue,
                        isOn: middleMouseRecordingBinding
                    )

                    Divider()
                        .padding(.leading, 2)

                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 14) {
                            Text(L10n.localize("settings.general.trigger_mode.title", comment: "Trigger mode title"))
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(AppTheme.ColorToken.primaryText)
                            Picker(L10n.localize("settings.general.trigger_mode.title", comment: "Trigger mode picker label"), selection: shortPressTriggerBinding) {
                                Text(L10n.localize("settings.general.trigger_mode.hold", comment: "Trigger mode: hold"))
                                    .tag(false)
                                Text(L10n.localize("settings.general.trigger_mode.toggle", comment: "Trigger mode: toggle"))
                                    .tag(true)
                            }
                            .labelsHidden()
                            .pickerStyle(.segmented)
                            .frame(width: 220)
                            Spacer(minLength: 0)
                        }
                        Text(viewModel.shortcutConflict
                            ? L10n.localize("settings.general.shortcut_conflict", comment: "Shortcut conflict warning")
                            : L10n.localize("settings.general.shortcut_help", comment: "Shortcut behavior help"))
                            .font(.system(size: 12))
                            .foregroundStyle(viewModel.shortcutConflict ? Color.red : AppTheme.ColorToken.secondaryText)
                    }
                    .padding(12)
                    .background(AppTheme.ColorToken.panelBackground.opacity(0.65))
                    .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.card, style: .continuous))

                    Divider()
                        .padding(.leading, 2)

                    shortcutGroupHeader(
                        title: L10n.localize("settings.task.workflow.group.title", comment: "Workflow shortcuts group title"),
                        subtitle: L10n.localize("settings.task.workflow.group.subtitle", comment: "Workflow shortcuts group subtitle")
                    )

                    workflowShortcutRow(
                        shortcut: .palette,
                        title: L10n.localize("settings.task.workflow.palette.title", comment: "Command palette workflow title"),
                        subtitle: L10n.localize("settings.task.workflow.palette.subtitle", comment: "Command palette workflow subtitle"),
                        systemImage: "rectangle.grid.1x2",
                        tint: .teal
                    )

                    Divider()
                        .padding(.leading, 70)

                    workflowShortcutRow(
                        shortcut: .clipboardImageOCR,
                        title: L10n.localize("settings.task.workflow.clipboard_image.title", comment: "Clipboard image OCR title"),
                        subtitle: L10n.localize("settings.task.workflow.clipboard_image.subtitle", comment: "Clipboard image OCR subtitle"),
                        systemImage: "doc.viewfinder",
                        tint: .indigo
                    )

                    Divider()
                        .padding(.leading, 70)

                    workflowShortcutRow(
                        shortcut: .screenshotOCR,
                        title: L10n.localize("settings.task.workflow.screenshot.title", comment: "Screenshot OCR title"),
                        subtitle: L10n.localize("settings.task.workflow.screenshot.subtitle", comment: "Screenshot OCR subtitle"),
                        systemImage: "text.viewfinder",
                        tint: .orange
                    )

                    Divider()
                        .padding(.leading, 70)

                    shortcutGroupHeader(
                        title: L10n.localize("settings.task.selection.group.title", comment: "Selection shortcuts group title"),
                        subtitle: L10n.localize("settings.task.selection.group.subtitle", comment: "Selection shortcuts group subtitle")
                    )

                    workflowShortcutRow(
                        shortcut: .selectionAction,
                        title: L10n.localize("settings.task.selection.action.title", comment: "Selection action title"),
                        subtitle: L10n.localize("settings.task.selection.action.subtitle", comment: "Selection action subtitle"),
                        systemImage: "text.cursor",
                        tint: .teal
                    )

                    Divider()
                        .padding(.leading, 70)

                    workflowShortcutRow(
                        shortcut: .selectionTranslate,
                        title: L10n.localize("settings.task.selection.translate.title", comment: "Direct translate title"),
                        subtitle: L10n.localize("settings.task.selection.translate.subtitle", comment: "Direct translate subtitle"),
                        systemImage: "translate",
                        tint: .teal
                    )

                    Divider()
                        .padding(.leading, 70)

                    workflowShortcutRow(
                        shortcut: .selectionSummarize,
                        title: L10n.localize("settings.task.selection.summarize.title", comment: "Direct summarize title"),
                        subtitle: L10n.localize("settings.task.selection.summarize.subtitle", comment: "Direct summarize subtitle"),
                        systemImage: "text.alignleft",
                        tint: .orange
                    )

                    Divider()
                        .padding(.leading, 70)

                    workflowShortcutRow(
                        shortcut: .selectionAgent,
                        title: L10n.localize("settings.task.selection.agent.title", comment: "Send to task assistant title"),
                        subtitle: L10n.localize("settings.task.selection.agent.subtitle", comment: "Send to task assistant subtitle"),
                        systemImage: "terminal",
                        tint: AppTheme.ColorToken.accent
                    )

                    Divider()
                        .padding(.leading, 70)

                    workflowShortcutRow(
                        shortcut: .selectionAskAI,
                        title: L10n.localize("settings.task.selection.ask_ai.title", comment: "Ask AI title"),
                        subtitle: L10n.localize("settings.task.selection.ask_ai.subtitle", comment: "Ask AI subtitle"),
                        systemImage: "sparkles",
                        tint: .purple
                    )
                }
            }

            appUpdateCard
        }
    }

    private var appUpdateCard: some View {
        SettingsGroupCard(
            title: L10n.localize("settings.task.update.title", comment: "Update section title"),
            subtitle: L10n.localize("settings.task.update.subtitle", comment: "Update section subtitle"),
            systemImage: "arrow.down.circle",
            tint: .green
        ) {
            HStack(spacing: 14) {
                SettingsRowIcon(systemImage: "app.badge", tint: .green)
                VStack(alignment: .leading, spacing: 4) {
                    Text(
                        "\(L10n.localize("updates.prompt.current_version_prefix", comment: "Current version prefix")) \(AppVersionInfo.current().displayText)"
                    )
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(AppTheme.ColorToken.primaryText)
                }
                Spacer(minLength: 12)
                Button(L10n.localize("settings.task.update.action_check", comment: "Check update action")) {
                    onCheckForUpdates()
                }
                .buttonStyle(.borderedProminent)
            }
            .settingsRow()
        }
    }

    private var vibeCodingSection: some View {
        VStack(alignment: .leading, spacing: 22) {
            SettingsGroupCard(
                title: L10n.localize("settings.task.ai_console.title", comment: "AI console title"),
                subtitle: L10n.localize("settings.task.ai_console.subtitle", comment: "AI console subtitle"),
                systemImage: "terminal",
                tint: AppTheme.ColorToken.accent
            ) {
                SettingsToggleRow(
                    title: L10n.localize("settings.task.ai_console.enable.title", comment: "Enable AI console title"),
                    subtitle: L10n.localize("settings.task.ai_console.enable.subtitle", comment: "Enable AI console subtitle"),
                    systemImage: "terminal",
                    tint: AppTheme.ColorToken.accent,
                    isOn: Binding(
                        get: { viewModel.agentDispatchEnabled },
                        set: { enabled in perform { try viewModel.setAgentDispatchEnabled(enabled) } }
                    )
                )

                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(L10n.localize("settings.task.agent_cli.title", comment: "Agent CLI title"))
                                .font(.system(size: 15, weight: .semibold))
                            Text(L10n.localize("settings.task.agent_cli.intro", comment: "Agent CLI intro"))
                                .font(.system(size: 12))
                                .foregroundStyle(AppTheme.ColorToken.secondaryText)
                        }
                        Spacer()
                        Button(L10n.localize("settings.task.action.copy_example", comment: "Copy example")) { viewModel.copyAgentCLIExamples() }
                            .buttonStyle(.bordered)
                        Button(L10n.localize("settings.task.action.unregister", comment: "Unregister action"), role: .destructive) {
                            showAgentCLIUnregistrationConfirmation = true
                        }
                            .buttonStyle(.bordered)
                        Button(L10n.localize("settings.task.action.register", comment: "Register action")) { showAgentCLIRegistrationConfirmation = true }
                            .buttonStyle(.borderedProminent)
                    }

                    VStack(alignment: .leading, spacing: 7) {
                        Text(L10n.localize("settings.task.agent_cli.example_codex", comment: "\"vox flow codex\" command example"))
                        Text(L10n.localize("settings.task.agent_cli.example_claude", comment: "\"vox flow --claude\" command example"))
                        Text(L10n.localize("settings.task.agent_cli.example_codebuddy", comment: "\"vox flow --codebuddy\" command example"))
                    }
                    .font(.system(size: 13, design: .monospaced))
                    .textSelection(.enabled)

                    if let status = viewModel.agentCLIRegistrationStatus {
                        Text(status.isOnCurrentPath
                             ? L10n.localize("settings.task.agent_cli.registered_status", comment: "Agent CLI registered status")
                             : String(
                                format: L10n.localize("settings.task.agent_cli.registered_with_path_status", comment: "Agent CLI registered with path status"),
                                status.binDirectory.path
                             )
                        )
                            .font(.system(size: 12))
                            .foregroundStyle(status.isOnCurrentPath ? Color.green : Color.orange)
                    }
                }
                .settingsRow()

                SettingsToggleRow(
                    title: L10n.localize("settings.task.ai_console.direct_send.title", comment: "Direct send title"),
                    subtitle: L10n.localize("settings.task.ai_console.direct_send.subtitle", comment: "Direct send subtitle"),
                    systemImage: "paperplane.fill",
                    tint: .green,
                    isOn: Binding(
                        get: { viewModel.agentDispatchExactDirectEnabled },
                        set: { enabled in perform { try viewModel.setAgentDispatchExactDirectEnabled(enabled) } }
                    )
                )

                HStack(spacing: 14) {
                    SettingsRowIcon(systemImage: "questionmark.bubble", tint: .orange)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(L10n.localize("settings.task.ai_console.unknown_agent_name", comment: "Unknown assistant name"))
                            .font(.system(size: 15, weight: .semibold))
                        Text(L10n.localize("settings.task.ai_console.low_confidence_note", comment: "Low confidence note"))
                            .font(.system(size: 12))
                            .foregroundStyle(AppTheme.ColorToken.secondaryText)
                    }
                    Spacer()
                    HStack(spacing: 10) {
                        Picker(L10n.localize("settings.task.ai_console.unknown_agent_name", comment: "Unknown assistant name"), selection: Binding(
                            get: { viewModel.agentDispatchUnresolvedBehavior },
                            set: { value in perform { try viewModel.setAgentDispatchUnresolvedBehavior(value) } }
                        )) {
                            Text(L10n.localize("settings.task.unresolved_behavior.option.confirm", comment: "Ask then send option"))
                                .tag("confirm")
                            Text(L10n.localize("settings.task.unresolved_behavior.option.cancel", comment: "Discard option"))
                                .tag("cancel")
                            Text(L10n.localize("settings.task.unresolved_behavior.option.model", comment: "Model-based option"))
                                .tag("model")
                            Text(L10n.localize("settings.task.unresolved_behavior.option.default", comment: "Default send option"))
                                .tag("default")
                        }
                        .labelsHidden()
                        .frame(width: 180, alignment: .trailing)

                        Image(systemName: "questionmark.circle")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(AppTheme.ColorToken.secondaryText)
                            .help(unresolvedBehaviorHelpText)
                    }
                    .frame(width: 248, alignment: .trailing)
                }
                .settingsRow()

                SettingsToggleRow(
                    title: L10n.localize("settings.task.ai_console.mcp_status.title", comment: "MCP status title"),
                    subtitle: L10n.localize("settings.task.ai_console.mcp_status.subtitle", comment: "MCP status subtitle"),
                    systemImage: "person.text.rectangle",
                    tint: .teal,
                    isOn: Binding(
                        get: { viewModel.agentDispatchMCPEnabled },
                        set: { enabled in perform { try viewModel.setAgentDispatchMCPEnabled(enabled) } }
                    )
                )
            }

        }
    }

    private var inputLanguageCard: some View {
        SettingsGroupCard(
            title: L10n.localize("settings.task.input_language.title", comment: "Input and language title"),
            subtitle: L10n.localize("settings.task.input_language.subtitle", comment: "Input and language subtitle"),
            systemImage: "mic",
            tint: .orange
        ) {
            VStack(spacing: 12) {
                inputDeviceRow
                recognitionLanguageRow
                interfaceLanguageRow
            }
        }
    }

    private var inputDeviceRow: some View {
        SettingsDropdownSection(
            title: L10n.localize("settings.task.input_device.title", comment: "Input device title"),
            value: selectedInputDeviceName,
            systemImage: "mic",
            tint: .orange,
            isExpanded: openDropdown == .inputDevice,
            onExpandedChange: { setDropdown(.inputDevice, expanded: $0) }
        ) {
            ForEach(viewModel.inputDevices, id: \.id) { device in
                SettingsDropdownOptionRow(
                    title: device.name,
                    isSelected: device.id == viewModel.selectedInputDeviceID
                ) {
                    setDropdown(.inputDevice, expanded: false)
                    perform { try viewModel.selectInputDevice(id: device.id) }
                }
            }
        }
    }

    private var recognitionLanguageRow: some View {
        SettingsDropdownSection(
            title: L10n.localize("settings.task.recognition_language.title", comment: "Recognition language title"),
            value: selectedRecognitionLanguageName,
            systemImage: "globe.asia.australia",
            tint: .teal,
            isExpanded: openDropdown == .recognitionLanguage,
            onExpandedChange: { setDropdown(.recognitionLanguage, expanded: $0) }
        ) {
            ForEach(viewModel.recognitionLanguages, id: \.rawValue) { language in
                SettingsDropdownOptionRow(
                    title: language.displayName,
                    isSelected: language == viewModel.selectedRecognitionLanguage
                ) {
                    setDropdown(.recognitionLanguage, expanded: false)
                    perform { try viewModel.setRecognitionLanguage(language) }
                }
            }
        }
    }

    private var interfaceLanguageRow: some View {
        SettingsDropdownSection(
            title: L10n.localize("settings.interface_language.title", comment: ""),
            value: viewModel.interfaceLanguage.displayName,
            systemImage: "globe",
            tint: .indigo,
            isExpanded: openDropdown == .interfaceLanguage,
            onExpandedChange: { setDropdown(.interfaceLanguage, expanded: $0) }
        ) {
            ForEach(AppLanguage.allCases, id: \.rawValue) { language in
                SettingsDropdownOptionRow(
                    title: language.displayName,
                    isSelected: language == viewModel.interfaceLanguage
                ) {
                    requestInterfaceLanguageChange(language)
                }
            }
        }
    }

    private var systemSection: some View {
        VStack(alignment: .leading, spacing: 22) {
            SettingsGroupCard(
                title: L10n.localize("settings.audio.group_feedback.title", comment: ""),
                subtitle: L10n.localize("settings.audio.group_feedback.subtitle", comment: ""),
                systemImage: "speaker.wave.2",
                tint: .blue
            ) {
                SettingsToggleRow(
                    title: L10n.localize("settings.audio.mute_toggle.title", comment: ""),
                    subtitle: L10n.localize("settings.audio.mute_toggle.subtitle", comment: ""),
                    systemImage: "speaker.slash",
                    tint: .blue,
                    isOn: muteBinding
                )
                SettingsToggleRow(
                    title: L10n.localize("settings.audio.feedback_tone.title", comment: ""),
                    subtitle: L10n.localize("settings.audio.feedback_tone.subtitle", comment: ""),
                    systemImage: "bell",
                    tint: .blue,
                    isOn: soundBinding
                )
            }

            SettingsGroupCard(
                title: L10n.localize("settings.audio.voice_enhancement_title", comment: ""),
                subtitle: L10n.localize("settings.audio.voice_enhancement_subtitle", comment: ""),
                systemImage: "waveform.path",
                tint: .green
            ) {
                SettingsToggleRow(
                    title: L10n.localize("settings.audio.enable_enhancement.title", comment: ""),
                    subtitle: L10n.localize("settings.audio.enable_enhancement.subtitle", comment: ""),
                    systemImage: "waveform.path",
                    tint: .green,
                    isOn: enhancementBinding
                )
            }

            SettingsGroupCard(
                title: L10n.localize("settings.system.performance_title", comment: ""),
                subtitle: L10n.localize("settings.system.performance_subtitle", comment: ""),
                systemImage: "bolt",
                tint: .yellow
            ) {
                systemToggle(
                    .keepMicrophoneActive,
                    L10n.localize("settings.system.keep_microphone_active.title", comment: ""),
                    L10n.localize("settings.system.keep_microphone_active.subtitle", comment: ""),
                    "bolt",
                    tint: .yellow
                )
                systemToggle(
                    .localModelLivePreview,
                    L10n.localize("settings.system.local_model_live_preview.title", comment: ""),
                    L10n.localize("settings.system.local_model_live_preview.subtitle", comment: ""),
                    "waveform",
                    tint: .yellow
                )
                systemToggle(
                    .autoReleaseLocalModel,
                    L10n.localize("settings.system.auto_release_local_model.title", comment: ""),
                    L10n.localize("settings.system.auto_release_local_model.subtitle", comment: ""),
                    "internaldrive",
                    tint: .yellow
                )
            }

            SettingsGroupCard(
                title: L10n.localize("settings.output.group_title", comment: ""),
                subtitle: L10n.localize("settings.output.group_subtitle", comment: ""),
                systemImage: "textformat",
                tint: .indigo
            ) {
                systemToggle(
                    .avoidClipboard,
                    L10n.localize("settings.output.avoid_clipboard.title", comment: ""),
                    L10n.localize("settings.output.avoid_clipboard.subtitle", comment: ""),
                    "clipboard",
                    tint: .indigo
                )
                systemToggle(
                    .restoreClipboard,
                    L10n.localize("settings.output.restore_clipboard.title", comment: ""),
                    L10n.localize("settings.output.restore_clipboard.subtitle", comment: ""),
                    "clipboard.fill",
                    tint: .indigo
                )
                systemToggle(
                    .clipboardImageOCR,
                    L10n.localize("settings.shortcuts.clipboard_image_ocr.title", comment: ""),
                    L10n.localize("settings.output.clipboard_image_ocr.subtitle", comment: ""),
                    "doc.viewfinder",
                    tint: .indigo
                )
            }

            SettingsGroupCard(
                title: L10n.localize("settings.appearance.group_title", comment: ""),
                subtitle: L10n.localize("settings.appearance.group_subtitle", comment: ""),
                systemImage: "paintpalette",
                tint: .pink
            ) {
                systemToggle(
                    .darkMode,
                    L10n.localize("settings.appearance.dark_mode.title", comment: ""),
                    L10n.localize("settings.appearance.dark_mode.subtitle", comment: ""),
                    "moon",
                    tint: .pink
                )
                systemToggle(
                    .launchAtLogin,
                    L10n.localize("settings.appearance.launch_at_login_title", comment: ""),
                    L10n.localize("settings.launch_at_login_description", comment: "Launch at login description"),
                    "power",
                    tint: .pink
                )
                systemToggle(
                    .grayMenuBarIcon,
                    L10n.localize("settings.appearance.gray_menu_bar_icon.title", comment: ""),
                    L10n.localize("settings.appearance.gray_menu_bar_icon.subtitle", comment: ""),
                    "paintpalette",
                    tint: .pink
                )
                systemToggle(
                    .capsLockIndicator,
                    L10n.localize("settings.appearance.caps_lock_indicator.title", comment: ""),
                    L10n.localize("settings.appearance.caps_lock_indicator.subtitle", comment: ""),
                    "lightbulb",
                    tint: .pink
                )
                systemToggle(
                    .hideDockIconWhenWorkbenchCloses,
                    L10n.localize("settings.appearance.hide_dock_icon.title", comment: ""),
                    L10n.localize("settings.appearance.hide_dock_icon.subtitle", comment: ""),
                    "dock.rectangle",
                    tint: .pink
                )
            }
        }
    }

    private var dataPrivacySection: some View {
        VStack(alignment: .leading, spacing: 22) {
            SettingsGroupCard(
                title: L10n.localize("settings.permissions.section_title", comment: ""),
                subtitle: L10n.localize("settings.permissions.section_subtitle", comment: ""),
                systemImage: "shield",
                tint: .green
            ) {
                permissionRow(
                    title: L10n.localize("settings.permissions.microphone_title", comment: ""),
                    subtitle: L10n.localize("settings.permissions.microphone_subtitle", comment: ""),
                    systemImage: "mic",
                    status: viewModel.microphonePermission.title,
                    granted: viewModel.microphonePermission == .granted,
                    pane: .microphone
                )
                permissionRow(
                    title: L10n.localize("settings.permissions.accessibility_title", comment: ""),
                    subtitle: L10n.localize("settings.permissions.accessibility_subtitle", comment: ""),
                    systemImage: "accessibility",
                    status: viewModel.accessibilityGranted
                        ? L10n.localize("settings.permission_status.granted", comment: "")
                        : L10n.localize("settings.permission_status.denied", comment: ""),
                    granted: viewModel.accessibilityGranted,
                    pane: .accessibility
                )
                permissionRow(
                    title: L10n.localize("settings.permissions.speech_title", comment: ""),
                    subtitle: L10n.localize("settings.permissions.speech_subtitle", comment: ""),
                    systemImage: "waveform",
                    status: viewModel.speechPermission.title,
                    granted: viewModel.speechPermission == .granted,
                    pane: .speech
                )
                permissionRow(
                    title: L10n.localize("settings.permissions.screen_recording_title", comment: ""),
                    subtitle: L10n.localize("settings.permissions.screen_recording_subtitle", comment: ""),
                    systemImage: "rectangle.inset.filled.and.person.filled",
                    status: PermissionSummary.statusText(viewModel.screenRecordingGranted),
                    granted: viewModel.screenRecordingGranted,
                    pane: .screenRecording
                )

                VStack(alignment: .leading, spacing: 6) {
                    Label(L10n.localize("settings.permissions.info_title", comment: ""), systemImage: "info.circle")
                        .font(.system(size: 13, weight: .semibold))
                    Text(L10n.localize("settings.permissions.info_body", comment: ""))
                        .font(.system(size: 12))
                        .foregroundStyle(AppTheme.ColorToken.secondaryText)
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.blue.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }

            SettingsGroupCard(
                title: L10n.localize("settings.privacy.group_title", comment: ""),
                subtitle: L10n.localize("settings.privacy.group_subtitle", comment: ""),
                systemImage: "chart.bar",
                tint: .purple
            ) {
                SettingsToggleRow(
                    title: L10n.localize("settings.privacy.analytics_title", comment: ""),
                    subtitle: L10n.localize("settings.privacy.analytics_subtitle", comment: ""),
                    systemImage: "chart.bar",
                    tint: .purple,
                    isOn: analyticsBinding
                )
                systemToggle(
                    .crashLogs,
                    L10n.localize("settings.privacy.crash_logs_title", comment: ""),
                    L10n.localize("settings.privacy.crash_logs_subtitle", comment: ""),
                    "ladybug",
                    tint: .purple
                )
                systemToggle(
                    .llmTraceDiagnostics,
                    L10n.localize("settings.privacy.llm_trace_title", comment: ""),
                    L10n.localize("settings.privacy.llm_trace_subtitle", comment: ""),
                    "doc.text.magnifyingglass",
                    tint: .orange
                )
                Button(L10n.localize("settings.privacy.llm_trace_delete", comment: ""), role: .destructive) {
                    viewModel.clearLLMTraceDiagnostics()
                }
                .buttonStyle(.bordered)

                Text(L10n.localize("settings.privacy.llm_trace_notice", comment: ""))
                    .font(.system(size: 12))
                    .foregroundStyle(AppTheme.ColorToken.secondaryText)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .settingsRow()
            }

            SettingsGroupCard(
                title: L10n.localize("settings.data.group_title", comment: ""),
                subtitle: L10n.localize("settings.data.group_subtitle", comment: ""),
                systemImage: "externaldrive",
                tint: .orange
            ) {
                HStack(spacing: 14) {
                    SettingsRowIcon(
                        systemImage: viewModel.storageStatus.isHealthy ? "internaldrive" : "exclamationmark.triangle",
                        tint: viewModel.storageStatus.isHealthy ? .green : .orange
                    )
                    VStack(alignment: .leading, spacing: 4) {
                        Text(viewModel.storageStatus.title)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(AppTheme.ColorToken.primaryText)
                        Text(viewModel.storageStatus.message)
                            .font(.system(size: 12))
                            .foregroundStyle(AppTheme.ColorToken.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer()
                    Text(viewModel.storageStatus.badgeText)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(viewModel.storageStatus.isHealthy ? Color.green : Color.orange)
                        .padding(.horizontal, 10)
                        .frame(height: 28)
                        .background((viewModel.storageStatus.isHealthy ? Color.green : Color.orange).opacity(0.09))
                        .clipShape(Capsule())
                }
                .settingsRow()

                HStack(spacing: 10) {
                    Button(L10n.localize("settings.data.open_support_folder", comment: "")) { viewModel.openApplicationSupportFolder() }
                    Button(L10n.localize("settings.data.export_data", comment: "")) { perform { _ = try viewModel.exportDataJSON() } }
                    Button(L10n.localize("settings.data.clear_history", comment: ""), role: .destructive) { perform { try viewModel.clearHistory() } }
                    Button(L10n.localize("settings.data.delete_all_local_models", comment: ""), role: .destructive) {
                        showDeleteAllLocalModelsConfirmation = true
                    }
                    Button(L10n.localize("settings.data.reset_settings", comment: ""), role: .destructive) {
                        perform {
                            try viewModel.resetSettings()
                        }
                    }
                }
                .buttonStyle(.bordered)

                TextEditor(text: $importedJSON)
                    .font(.system(.body, design: .monospaced))
                    .frame(minHeight: 100)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(AppTheme.ColorToken.panelStroke)
                    )
                Button(L10n.localize("settings.data.import_settings", comment: "")) {
                    perform { try viewModel.importSettingsJSON(importedJSON) }
                }
                .buttonStyle(.bordered)
            }

            SettingsGroupCard(
                title: L10n.localize("settings.data.crash_report_title", comment: ""),
                subtitle: L10n.localize("settings.data.crash_report_subtitle", comment: ""),
                systemImage: "ladybug",
                tint: .orange
            ) {
                HStack(spacing: 10) {
                    Button {
                        viewModel.load()
                    } label: {
                        Label(L10n.localize("settings.data.refresh", comment: ""), systemImage: "arrow.clockwise")
                    }
                    Button {
                        viewModel.openApplicationSupportFolder()
                    } label: {
                        Label(L10n.localize("settings.data.open_folder", comment: ""), systemImage: "folder")
                    }
                }
                .buttonStyle(.bordered)

                Text(
                    L10n.localize("settings.storage.diagnostic_privacy_notice", comment: "Diagnostic privacy note")
                )
                    .font(.system(size: 12))
                    .foregroundStyle(AppTheme.ColorToken.secondaryText)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .settingsRow()
            }
        }
    }

    private func settingsSidebarButton(_ section: SettingsSection) -> some View {
        Button {
            viewModel.selectedSection = section
        } label: {
            HStack(spacing: 11) {
                Image(systemName: section.systemImage)
                    .frame(width: 22)
                    .foregroundStyle(
                        viewModel.selectedSection == section
                            ? AppTheme.ColorToken.accent
                            : AppTheme.ColorToken.sidebarText
                    )
                Text(section.title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(
                        viewModel.selectedSection == section
                            ? AppTheme.ColorToken.primaryText
                            : AppTheme.ColorToken.sidebarText
                    )
                Spacer()
            }
            .padding(.horizontal, 12)
            .frame(height: 44)
            .background(
                viewModel.selectedSection == section
                    ? AppTheme.ColorToken.selectionBackground
                    : Color.clear
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(
                        viewModel.selectedSection == section
                            ? AppTheme.ColorToken.accent.opacity(0.25)
                            : Color.clear
                    )
            )
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func sidebarGroupTitle(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(AppTheme.ColorToken.secondaryText)
            .padding(.horizontal, 12)
            .padding(.bottom, 4)
    }

    private var selectedInputDeviceName: String {
        viewModel.inputDevices.first(where: { $0.id == viewModel.selectedInputDeviceID })?.name
            ?? L10n.localize("settings.audio_input.default_system_device", comment: "")
    }

    private var selectedRecognitionLanguageName: String {
        viewModel.selectedRecognitionLanguage.displayName
    }

    private func setDropdown(_ dropdown: SettingsDropdown, expanded: Bool) {
        withAnimation(.snappy(duration: 0.16)) {
            if expanded {
                openDropdown = dropdown
            } else if openDropdown == dropdown {
                openDropdown = nil
            }
        }
    }

    private func requestInterfaceLanguageChange(_ language: AppLanguage) {
        setDropdown(.interfaceLanguage, expanded: false)
        guard language != viewModel.interfaceLanguage else { return }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
            pendingInterfaceLanguage = language
        }
    }

    private func confirmInterfaceLanguageChange(_ language: AppLanguage) {
        pendingInterfaceLanguage = nil
        do {
            try viewModel.setInterfaceLanguage(language)
            try relaunchApplication()
        } catch {
            viewModel.report(error: error)
        }
    }

    private func relaunchApplication() throws {
        try InterfaceLanguageRelauncher.launch(bundleURL: Bundle.main.bundleURL)
        NSApp.terminate(nil)
    }

    private func shortcutKeyIcon(for action: VoiceAction) -> String {
        guard let keyCode = shortcutKeyCode(for: action) else {
            return action.systemImage
        }
        return KeyCodeMapping.iconName(for: keyCode)
    }

    private func shortcutKeyIcon(
        for workflowShortcut: HotKeyWorkflowShortcut,
        fallback: String
    ) -> String {
        guard let keyCode = shortcutKeyCode(for: workflowShortcut) else {
            return fallback
        }
        return KeyCodeMapping.iconName(for: keyCode)
    }

    private func shortcutKeyCode(for action: VoiceAction) -> Int64? {
        switch action {
        case .dictation:
            return viewModel.dictationShortcutKeyCode ?? viewModel.shortcutKeyCode
        case .agentCompose:
            return viewModel.agentComposeShortcutKeyCode
        case .agentDispatch:
            return nil
        }
    }

    private func shortcutKeyCode(for workflowShortcut: HotKeyWorkflowShortcut) -> Int64? {
        switch workflowShortcut {
        case .palette:
            return viewModel.paletteShortcutKeyCode
        case .clipboardImageOCR:
            return viewModel.clipboardImageOCRShortcutKeyCode
        case .screenshotOCR:
            return viewModel.screenshotOCRShortcutKeyCode
        case .selectionAction:
            return viewModel.selectionActionShortcutKeyCode
        case .selectionTranslate:
            return viewModel.selectionTranslateShortcutKeyCode
        case .selectionSummarize:
            return viewModel.selectionSummarizeShortcutKeyCode
        case .selectionAgent:
            return viewModel.selectionAgentShortcutKeyCode
        case .selectionAskAI:
            return viewModel.selectionAskAIShortcutKeyCode
        case .cancel:
            return HotKeyShortcutRouting.escapeKeyCode
        }
    }

    private var shortPressBehaviorDescription: String {
        switch viewModel.shortPressBehavior {
        case .toggleListening:
            return L10n.localize("settings.shortcuts.short_press_toggle_behavior", comment: "")
        case .none:
            return L10n.localize("settings.shortcuts.short_press_no_action_behavior", comment: "")
        }
    }

    private func permissionRow(
        title: String,
        subtitle: String,
        systemImage: String,
        status: String,
        granted: Bool,
        pane: SystemSettingsPane
    ) -> some View {
        HStack(spacing: 14) {
            SettingsRowIcon(systemImage: systemImage, tint: granted ? .green : .orange)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(AppTheme.ColorToken.secondaryText)
            }
            Spacer()
            Text(status)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(granted ? Color.green : Color.orange)
                .padding(.horizontal, 10)
                .frame(height: 28)
                .background((granted ? Color.green : Color.orange).opacity(0.09))
                .clipShape(Capsule())
            if !granted {
                Button {
                    if let url = viewModel.systemSettingsURL(for: pane) {
                        NSWorkspace.shared.open(url)
                    }
                } label: {
                    Text(L10n.localize("settings.permissions.goto_settings", comment: ""))
                        .font(.system(size: 12, weight: .medium))
                        .padding(.horizontal, 12)
                        .frame(height: 28)
                }
                .buttonStyle(.bordered)
            }
            Button {
                viewModel.load()
            } label: {
                Image(systemName: "arrow.clockwise")
                    .frame(width: 32, height: 32)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(L10n.localize("settings.data.refresh_help", comment: ""))
        }
        .settingsRow()
    }

    private func systemToggle(
        _ option: SettingsSystemOption,
        _ title: String,
        _ subtitle: String,
        _ icon: String,
        tint: Color = .gray
    ) -> some View {
        SettingsToggleRow(
            title: title,
            subtitle: subtitle,
            systemImage: icon,
            tint: tint,
            isOn: Binding(
                get: { viewModel.systemOption(option) },
                set: { value in perform { try viewModel.setSystemOption(option, enabled: value) } }
            )
        )
    }

    private var shortPressToggleBinding: Binding<Bool> {
        Binding(
            get: { viewModel.shortPressBehavior == .toggleListening },
            set: { isEnabled in
                perform {
                    try viewModel.updateShortcut(
                        keyCode: viewModel.shortcutKeyCode,
                        longPressThreshold: viewModel.longPressThreshold,
                        shortPressBehavior: isEnabled ? .toggleListening : .none
                    )
                }
            }
        )
    }

    private var shortPressTriggerBinding: Binding<Bool> {
        shortPressToggleBinding
    }

    private var soundBinding: Binding<Bool> {
        Binding(
            get: { viewModel.soundFeedbackEnabled },
            set: { value in
                perform {
                    try viewModel.updateAudioOptions(
                        soundFeedback: value,
                        voiceEnhancement: viewModel.voiceEnhancementEnabled
                    )
                }
            }
        )
    }

    private var enhancementBinding: Binding<Bool> {
        Binding(
            get: { viewModel.voiceEnhancementEnabled },
            set: { value in
                perform {
                    try viewModel.updateAudioOptions(
                        soundFeedback: viewModel.soundFeedbackEnabled,
                        voiceEnhancement: value
                    )
                }
            }
        )
    }

    private var muteBinding: Binding<Bool> {
        Binding(
            get: { viewModel.muteWhileRecordingEnabled },
            set: { value in
                perform {
                    try viewModel.updatePerformanceOptions(
                        muteWhileRecording: value,
                        performanceOptimization: viewModel.performanceOptimizationEnabled
                    )
                }
            }
        )
    }

    private var analyticsBinding: Binding<Bool> {
        Binding(
            get: { viewModel.analyticsEnabled },
            set: { value in perform { try viewModel.setAnalyticsEnabled(value) } }
        )
    }

    private var middleMouseRecordingBinding: Binding<Bool> {
        Binding(
            get: { viewModel.middleMouseRecordingEnabled },
            set: { value in perform { try viewModel.setMiddleMouseRecordingEnabled(value) } }
        )
    }

    private var voiceCorrectionEnabledBinding: Binding<Bool> {
        Binding(
            get: { viewModel.voiceCorrectionEnabled },
            set: { value in perform { try viewModel.setVoiceCorrectionEnabled(value) } }
        )
    }

    private var voiceCorrectionAutoLearningBinding: Binding<Bool> {
        Binding(
            get: { viewModel.voiceCorrectionAutoLearningEnabled },
            set: { value in perform { try viewModel.setVoiceCorrectionAutoLearningEnabled(value) } }
        )
    }

    private var voiceCorrectionAutoLearningImmediateBinding: Binding<Bool> {
        Binding(
            get: { viewModel.voiceCorrectionAutoLearningAppliesImmediately },
            set: { value in perform { try viewModel.setVoiceCorrectionAutoLearningAppliesImmediately(value) } }
        )
    }

    private var voiceCorrectionShadowModeBinding: Binding<Bool> {
        Binding(
            get: { viewModel.voiceCorrectionShadowMode },
            set: { value in perform { try viewModel.setVoiceCorrectionShadowMode(value) } }
        )
    }

    private func perform(_ action: () throws -> Void) {
        do {
            try action()
        } catch {
            viewModel.report(error: error)
        }
    }

    private func actionShortcutRow(
        action: VoiceAction,
        title: String,
        subtitle: String,
        buttonTitle: String,
        badge: String? = nil,
        prominentWhenUnbound: Bool = false
    ) -> some View {
        let binding = ShortcutBinding.voice(action)
        let isRecording = recordingShortcutBinding == binding
        let keyCode = shortcutKeyCode(for: action)
        let isUnbound = keyCode == nil
        return HStack(spacing: 14) {
            SettingsRowIcon(systemImage: shortcutKeyIcon(for: action), tint: action == .agentCompose ? .green : AppTheme.ColorToken.accent)
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 8) {
                    Text(title)
                        .font(.system(size: 15, weight: .semibold))
                    if let badge {
                        Text(badge)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(AppTheme.ColorToken.accent)
                            .padding(.horizontal, 8)
                            .frame(height: 22)
                            .background(AppTheme.ColorToken.selectionBackground)
                            .clipShape(Capsule())
                    }
                }
                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(AppTheme.ColorToken.secondaryText)
            }
            Spacer(minLength: 16)
            ShortcutKeycapsView(
                keyCode: keyCode,
                isRecording: isRecording,
                recordingTitle: L10n.localize("settings.shortcuts.recording", comment: "")
            )
            shortcutActionButton(
                title: isRecording
                    ? L10n.localize("settings.shortcuts.cancel", comment: "")
                    : buttonTitle,
                prominent: prominentWhenUnbound && isUnbound,
                binding: binding
            )
        }
        .settingsRow()
    }

    private func workflowShortcutRow(
        shortcut: HotKeyWorkflowShortcut,
        title: String,
        subtitle: String,
        systemImage: String,
        tint: Color
    ) -> some View {
        let binding = ShortcutBinding.workflow(shortcut)
        let isRecording = recordingShortcutBinding == binding
        let keyCode = shortcutKeyCode(for: shortcut)
        let isUnbound = keyCode == nil
        return HStack(spacing: 14) {
            SettingsRowIcon(
                systemImage: shortcutKeyIcon(for: shortcut, fallback: systemImage),
                tint: tint
            )
            VStack(alignment: .leading, spacing: 5) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(AppTheme.ColorToken.secondaryText)
            }
            Spacer(minLength: 16)
            ShortcutKeycapsView(
                keyCode: keyCode,
                isRecording: isRecording,
                recordingTitle: L10n.localize("settings.shortcuts.recording", comment: "")
            )
            if !isUnbound {
                Button {
                    perform { try viewModel.updateWorkflowShortcut(shortcut, keyCode: nil) }
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 13, weight: .semibold))
                        .frame(width: 30, height: 30)
                        .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                }
                .buttonStyle(.plain)
                .foregroundStyle(AppTheme.ColorToken.secondaryText)
                .background(AppTheme.ColorToken.panelBackground.opacity(0.7))
                .overlay(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .stroke(AppTheme.ColorToken.subtleStroke, lineWidth: AppTheme.Border.panelLineWidth)
                )
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                .help(L10n.localize("settings.shortcuts.clear", comment: ""))
            }
            shortcutActionButton(
                title: isRecording
                    ? L10n.localize("settings.shortcuts.cancel", comment: "")
                    : L10n.localize("settings.shortcuts.modify", comment: ""),
                prominent: isUnbound,
                binding: binding
            )
        }
        .settingsRow()
    }

    private func shortcutGroupHeader(title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(AppTheme.ColorToken.primaryText)
            Text(subtitle)
                .font(.system(size: 12))
                .foregroundStyle(AppTheme.ColorToken.secondaryText)
        }
        .padding(.horizontal, 2)
        .padding(.top, 2)
    }

    @ViewBuilder
    private func shortcutActionButton(title: String, prominent: Bool, binding: ShortcutBinding) -> some View {
        if prominent {
            Button(title) {
                toggleShortcutRecording(for: binding)
            }
            .buttonStyle(.borderedProminent)
        } else {
            Button(title) {
                toggleShortcutRecording(for: binding)
            }
            .buttonStyle(.bordered)
        }
    }

    private func toggleShortcutRecording(for binding: ShortcutBinding = .voice(.dictation)) {
        if recordingShortcutBinding == binding {
            stopShortcutRecording()
            return
        }
        recordingShortcutBinding = binding
        ShortcutCaptureState.shared.isCapturing = true
        shortcutMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { event in
            recordShortcut(from: event)
            return nil
        }
    }

    private func stopShortcutRecording() {
        if let shortcutMonitor {
            NSEvent.removeMonitor(shortcutMonitor)
            self.shortcutMonitor = nil
        }
        recordingShortcutBinding = nil
        ShortcutCaptureState.shared.isCapturing = false
    }

    private func recordShortcut(from event: NSEvent) {
        let binding = recordingShortcutBinding ?? .voice(.dictation)
        let allowsPureModifierShortcut: Bool
        switch binding {
        case .voice:
            allowsPureModifierShortcut = true
        case .workflow:
            allowsPureModifierShortcut = false
        }
        guard let keyCode = SettingsShortcutRecorder.encodedShortcutKeyCode(
            eventType: event.type,
            keyCode: event.keyCode,
            modifierFlags: event.modifierFlags,
            allowsPureModifierShortcut: allowsPureModifierShortcut
        ) else {
            return
        }
        guard keyCode > 0 else {
            viewModel.report(error: SettingsViewModelError.invalidShortcutKeyCode)
            stopShortcutRecording()
            return
        }
        perform {
            switch binding {
            case let .voice(action):
                try viewModel.updateActionShortcut(action: action, keyCode: keyCode)
            case let .workflow(shortcut):
                try viewModel.updateWorkflowShortcut(shortcut, keyCode: keyCode)
            }
        }
        stopShortcutRecording()
    }

}

private struct SettingsGroupCard<Content: View>: View {
    let title: String
    let subtitle: String
    let systemImage: String
    let tint: Color
    @ViewBuilder let content: Content

    init(
        title: String,
        subtitle: String,
        systemImage: String,
        tint: Color,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.subtitle = subtitle
        self.systemImage = systemImage
        self.tint = tint
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(tint.opacity(0.09))
                    .frame(width: 46, height: 46)
                    .overlay {
                        Image(systemName: systemImage)
                            .font(.system(size: 20, weight: .medium))
                            .foregroundStyle(tint)
                    }
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.system(size: 18, weight: .semibold))
                    Text(subtitle)
                        .font(.system(size: 13))
                        .foregroundStyle(AppTheme.ColorToken.secondaryText)
                }
            }
            VStack(spacing: 10) {
                content
            }
        }
        .padding(20)
        .appPanel(cornerRadius: 14)
    }
}

private struct ShortcutKeycapsView: View {
    let keyCode: Int64?
    let isRecording: Bool
    let recordingTitle: String

    var body: some View {
        if isRecording {
            HStack(spacing: 6) {
                Image(systemName: "record.circle")
                    .font(.system(size: 12, weight: .semibold))
                Text(recordingTitle)
                    .font(.system(size: 12, weight: .semibold))
            }
            .foregroundStyle(AppTheme.ColorToken.accent)
            .padding(.horizontal, 10)
            .frame(height: 30)
            .background(AppTheme.ColorToken.selectionBackground)
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(AppTheme.ColorToken.selectionBorder, lineWidth: AppTheme.Border.panelLineWidth)
            )
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        } else if let keyCode {
            HStack(spacing: 4) {
                ForEach(KeyCodeMapping.keycapLabels(for: keyCode), id: \.self) { label in
                    ShortcutKeycap(label: label)
                }
            }
            .accessibilityLabel(KeyCodeMapping.displayName(for: keyCode))
        } else {
            Text(L10n.localize("settings.shortcuts.unset", comment: ""))
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(AppTheme.ColorToken.secondaryText)
                .padding(.horizontal, 10)
                .frame(height: 28)
                .background(AppTheme.ColorToken.panelBackground.opacity(0.65))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(AppTheme.ColorToken.subtleStroke, lineWidth: AppTheme.Border.panelLineWidth)
                )
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
    }
}

private struct ShortcutKeycap: View {
    let label: String

    var body: some View {
        Text(label)
            .font(.system(size: 12, weight: .semibold, design: .monospaced))
            .foregroundStyle(AppTheme.ColorToken.primaryText)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .padding(.horizontal, 8)
            .frame(minWidth: 28)
            .frame(height: 28)
            .background(AppTheme.ColorToken.panelBackground)
            .overlay(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .stroke(AppTheme.ColorToken.subtleStroke, lineWidth: AppTheme.Border.panelLineWidth)
            )
            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
    }
}

private struct SettingsToggleRow: View {
    let title: String
    let subtitle: String
    let systemImage: String
    let tint: Color
    @Binding var isOn: Bool

    var body: some View {
        HStack(spacing: 14) {
            SettingsRowIcon(systemImage: systemImage, tint: tint)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(AppTheme.ColorToken.secondaryText)
            }
            Spacer()
            Toggle("", isOn: $isOn)
                .labelsHidden()
                .toggleStyle(.switch)
        }
        .settingsRow()
    }
}

private struct SettingsDropdownSection<Content: View>: View {
    let title: String
    let value: String
    let systemImage: String
    let tint: Color
    let isExpanded: Bool
    let onExpandedChange: (Bool) -> Void
    @ViewBuilder let content: Content
    @State private var controlWidth: CGFloat = 360

    var body: some View {
        Button { onExpandedChange(!isExpanded) } label: {
            HStack(spacing: 14) {
                SettingsRowIcon(systemImage: systemImage, tint: tint)
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(AppTheme.ColorToken.primaryText)
                    Text(value)
                        .font(.system(size: 12))
                        .foregroundStyle(AppTheme.ColorToken.secondaryText)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .help(value)
                }
                Spacer()
                Image(systemName: "chevron.down")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(AppTheme.ColorToken.accent)
                    .rotationEffect(.degrees(isExpanded ? 180 : 0))
            }
            .settingsRow()
            .contentShape(Rectangle())
            .background(
                GeometryReader { proxy in
                    Color.clear.preference(key: SettingsDropdownWidthPreferenceKey.self, value: proxy.size.width)
                }
            )
        }
        .buttonStyle(.plain)
        .onPreferenceChange(SettingsDropdownWidthPreferenceKey.self) { width in
            controlWidth = width
        }
        .popover(
            isPresented: popoverPresentation,
            attachmentAnchor: .rect(.bounds),
            arrowEdge: .top
        ) {
            SettingsDropdownPopover(width: controlWidth) {
                content
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var popoverPresentation: Binding<Bool> {
        Binding(
            get: { isExpanded },
            set: { presented in
                guard presented != isExpanded else { return }
                onExpandedChange(presented)
            }
        )
    }
}

private struct SettingsDropdownWidthPreferenceKey: PreferenceKey {
    static let defaultValue: CGFloat = 360

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

private struct SettingsDropdownPopover<Content: View>: View {
    let width: CGFloat
    @ViewBuilder let content: Content

    var body: some View {
        ScrollView {
            VStack(spacing: 4) {
                content
            }
            .padding(6)
        }
        .scrollIndicators(.automatic)
        .frame(width: max(width, 320))
        .frame(maxHeight: 260)
        .background(AppTheme.ColorToken.panelBackground)
    }
}

private struct SettingsDropdownOptionRow: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(isSelected ? AppTheme.ColorToken.accent : AppTheme.ColorToken.secondaryText.opacity(0.45))
                    .frame(width: 18)
                Text(title)
                    .font(.system(size: 14, weight: isSelected ? .semibold : .medium))
                    .foregroundStyle(AppTheme.ColorToken.primaryText)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
            }
            .padding(.horizontal, 10)
            .frame(height: 34)
            .background(isSelected ? AppTheme.ColorToken.selectionBackground : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct SettingsRestartConfirmationModal: View {
    let languageName: String
    let onConfirm: () -> Void
    let onCancel: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.20)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture(perform: onCancel)

            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .top, spacing: 14) {
                    SettingsRowIcon(systemImage: "globe", tint: AppTheme.ColorToken.accent)
                    VStack(alignment: .leading, spacing: 6) {
                        Text(L10n.localize("settings.interface_language.restart_dialog.title", comment: "Restart language dialog title"))
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(AppTheme.ColorToken.primaryText)
                        Text(String(
                            format: L10n.localize("settings.interface_language.restart_dialog.message_format", comment: "Restart language dialog message"),
                            languageName
                        ))
                        .font(.system(size: 13))
                        .foregroundStyle(AppTheme.ColorToken.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer()
                    Button(action: onCancel) {
                        Image(systemName: "xmark")
                            .font(.system(size: 12, weight: .bold))
                            .frame(width: 30, height: 30)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .keyboardShortcut(.cancelAction)
                }

                HStack(spacing: 10) {
                    Spacer()
                    Button(L10n.localize("settings.task.action.cancel", comment: "Cancel action"), action: onCancel)
                        .buttonStyle(.bordered)
                    Button(L10n.localize("settings.task.action.confirm", comment: "Confirm action"), action: onConfirm)
                        .buttonStyle(.borderedProminent)
                        .tint(AppTheme.ColorToken.accent)
                        .keyboardShortcut(.defaultAction)
                }
            }
            .padding(24)
            .frame(width: 460)
            .background(AppTheme.ColorToken.panelBackground)
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(AppTheme.ColorToken.selectionBorder.opacity(0.55), lineWidth: AppTheme.Border.panelLineWidth)
            )
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .shadow(color: Color.black.opacity(0.16), radius: 28, x: 0, y: 18)
        }
        .transition(.opacity)
    }
}

private struct SettingsRowIcon: View {
    let systemImage: String
    let tint: Color

    var body: some View {
        RoundedRectangle(cornerRadius: AppTheme.Radius.icon, style: .continuous)
            .fill(tint.opacity(0.09))
            .frame(width: 42, height: 42)
            .overlay {
                Image(systemName: systemImage)
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(tint)
            }
    }
}

extension View {
    func settingsRow() -> some View {
        padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AppTheme.ColorToken.controlBackground.opacity(0.72))
            .overlay(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .stroke(AppTheme.ColorToken.subtleStroke, lineWidth: AppTheme.Border.panelLineWidth)
            )
            .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
    }
}

private extension SettingsSection {
    var pageTitle: String {
        switch self {
        case .general: return L10n.localize("settings.section.general", comment: "")
        case .vibeCoding: return L10n.localize("settings.section.vibe_coding", comment: "")
        case .dictationModels: return L10n.localize("settings.section.dictation_models", comment: "")
        case .correctionModels: return L10n.localize("settings.section.correction_models", comment: "")
        case .ttsModels: return L10n.localize("settings.section.tts_models", comment: "")
        case .translationModels: return L10n.localize("settings.section.translation_models", comment: "")
        case .system: return L10n.localize("settings.section.system_root", comment: "")
        case .dataPrivacy: return L10n.localize("settings.section.data_privacy", comment: "")
        }
    }
}

extension AudioRecorder.PermissionStatus {
    var title: String {
        switch self {
        case .granted: return L10n.localize("settings.permission_status.granted", comment: "")
        case .denied: return L10n.localize("settings.permission_status.denied", comment: "")
        case .notDetermined: return L10n.localize("settings.permission_status.not_determined", comment: "")
        }
    }
}
