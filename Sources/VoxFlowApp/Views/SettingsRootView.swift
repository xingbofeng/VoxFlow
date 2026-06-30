import AppKit
import SwiftUI
import VoxFlowTextProcessing

private enum TextProcessingThresholdEditor: String, Identifiable {
    case punctuation
    case longSentence

    var id: String { rawValue }
}

enum SettingsThresholdEditorLayout {
    static let usesSideBySideInteraction = true
    static let showsInternalScrollIndicators = false
    static let hasFooterAction = false
    static let hasControlsPaneResetAction = true
    static let preferredModalWidth: CGFloat = 1_020
    static let minimumModalWidth: CGFloat = 880
    static let horizontalPadding: CGFloat = 24
    static let verticalPadding: CGFloat = 24
    static let contentSpacing: CGFloat = 18
    static let controlsPaneWidth: CGFloat = 430
    static let examplesPaneMinWidth: CGFloat = 360
}

enum SettingsThresholdPreviewSamples {
    static let punctuationEnglish = "Review the build, update QA; confirm the rollback plan"
    static let punctuationChinese = "今天调试,明天验证;是否回滚?"
    static let longSentenceEnglish = "We should keep the interaction clear, update the preview while dragging, explain why the threshold changed, and make the final text easier to scan during review."
    static let longSentenceChinese = "我们需要先确认录音状态，检查转写结果，调整标点策略，对比预览变化，最后同步给团队。"

    static func punctuationEnglishPreview(wordThreshold: Int) -> String {
        DeterministicTextPreviewEngine.preview(
            punctuationEnglish,
            processor: .punctuationOptimization,
            settings: .init(
                enabled: true,
                punctuationOptimization: true,
                punctuationCJKThreshold: .max,
                punctuationWordThreshold: wordThreshold
            )
        )
    }

    static func punctuationChinesePreview(cjkThreshold: Int) -> String {
        DeterministicTextPreviewEngine.preview(
            punctuationChinese,
            processor: .punctuationOptimization,
            settings: .init(
                enabled: true,
                punctuationOptimization: true,
                punctuationCJKThreshold: cjkThreshold,
                punctuationWordThreshold: .max
            )
        )
    }

    static func longSentenceEnglishPreview(wordThreshold: Int) -> String {
        DeterministicTextPreviewEngine.preview(
            longSentenceEnglish,
            processor: .longSentenceBreaking,
            settings: .init(
                enabled: true,
                longSentenceBreaking: true,
                longSentenceWordThreshold: wordThreshold,
                longSentenceCJKThreshold: .max
            )
        )
    }

    static func longSentenceChinesePreview(cjkThreshold: Int) -> String {
        DeterministicTextPreviewEngine.preview(
            longSentenceChinese,
            processor: .longSentenceBreaking,
            settings: .init(
                enabled: true,
                longSentenceBreaking: true,
                longSentenceWordThreshold: .max,
                longSentenceCJKThreshold: cjkThreshold
            )
        )
    }
}

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
    @State private var showCrashReportSendConfirmation = false
    @State private var openDropdown: SettingsDropdown?
    @State private var textProcessingThresholdEditor: TextProcessingThresholdEditor?
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
        .overlay {
            textProcessingThresholdOverlay
        }
        .animation(.easeOut(duration: 0.16), value: textProcessingThresholdEditor?.id)
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
                L10n.format("settings.task.dialog.delete_all_local_models.message_format", comment: "Delete all local model confirmation message",
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
        .confirmationDialog(
            L10n.localize("settings.privacy.manual_crash_report_confirm_title", comment: ""),
            isPresented: $showCrashReportSendConfirmation,
            titleVisibility: .visible
        ) {
            Button(L10n.localize("settings.privacy.manual_crash_report_send_latest", comment: "")) {
                viewModel.sendLatestCrashReport()
            }
            Button(L10n.localize("settings.task.action.cancel", comment: ""), role: .cancel) {}
        } message: {
            Text(viewModel.latestCrashReportSummaryText ?? "")
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

    @ViewBuilder
    private var textProcessingThresholdOverlay: some View {
        if let textProcessingThresholdEditor {
            GeometryReader { proxy in
                let availableWidth = max(0, proxy.size.width - 72)
                let modalWidth = min(
                    SettingsThresholdEditorLayout.preferredModalWidth,
                    max(SettingsThresholdEditorLayout.minimumModalWidth, availableWidth)
                )
                let modalMaxHeight = max(360, proxy.size.height - 72)

                ZStack {
                    Color.black.opacity(0.22)
                        .ignoresSafeArea()
                        .contentShape(Rectangle())
                        .onTapGesture {
                            self.textProcessingThresholdEditor = nil
                        }

                    textProcessingThresholdEditorSheet(textProcessingThresholdEditor)
                        .frame(width: modalWidth)
                        .frame(maxHeight: modalMaxHeight)
                        .shadow(color: Color.black.opacity(0.18), radius: 28, x: 0, y: 18)
                        .transition(.scale(scale: 0.98).combined(with: .opacity))
                        .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .transition(.opacity)
                .zIndex(10)
                .onExitCommand {
                    self.textProcessingThresholdEditor = nil
                }
            }
            .ignoresSafeArea(.container, edges: [])
        }
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
            settingsSidebarButton(.textProcessing)

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
        case .textProcessing:
            textProcessingSection
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
                             : L10n.format("settings.task.agent_cli.registered_with_path_status", comment: "Agent CLI registered with path status",
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

    private var textProcessingSection: some View {
        VStack(alignment: .leading, spacing: 22) {
            SettingsGroupCard(
                title: L10n.localize("settings.text_processing.group.title", comment: "Text processing group title"),
                subtitle: L10n.localize("settings.text_processing.group.subtitle", comment: "Text processing group subtitle"),
                systemImage: "wand.and.stars",
                tint: .indigo
            ) {
                VStack(alignment: .leading, spacing: 10) {
                    SettingsToggleRow(
                        title: L10n.localize("settings.text_processing.master.title", comment: "Master toggle title"),
                        subtitle: L10n.localize("settings.text_processing.master.subtitle", comment: "Master toggle subtitle"),
                        systemImage: "power",
                        tint: .indigo,
                        isOn: deterministicMasterBinding
                    )

                    Divider().padding(.leading, 2)

                    VStack(alignment: .leading, spacing: 10) {
                        SettingsToggleRow(
                            title: L10n.localize("settings.text_processing.smart_number.title", comment: "Smart number toggle title"),
                            subtitle: L10n.localize("settings.text_processing.smart_number.subtitle", comment: "Smart number toggle subtitle"),
                            systemImage: "number",
                            tint: .blue,
                            isOn: deterministicSubToggleBinding(
                                value: viewModel.deterministicSmartNumberRecognition
                            ) { newValue in
                                try viewModel.updateDeterministicTextProcessing(smartNumberRecognition: newValue)
                            }
                        )

                        SettingsThresholdToggleRow(
                            title: L10n.localize("settings.text_processing.punctuation.title", comment: "Punctuation toggle title"),
                            subtitle: L10n.localize("settings.text_processing.punctuation.subtitle", comment: "Punctuation toggle subtitle"),
                            summary: punctuationThresholdSummary,
                            systemImage: "exclamationmark.bubble",
                            tint: .orange,
                            isOn: deterministicSubToggleBinding(
                                value: viewModel.deterministicPunctuationOptimization
                            ) { newValue in
                                try viewModel.updateDeterministicTextProcessing(punctuationOptimization: newValue)
                            },
                            onConfigure: {
                                textProcessingThresholdEditor = .punctuation
                            }
                        )

                        SettingsThresholdToggleRow(
                            title: L10n.localize("settings.text_processing.long_sentence.title", comment: "Long sentence toggle title"),
                            subtitle: L10n.localize("settings.text_processing.long_sentence.subtitle", comment: "Long sentence toggle subtitle"),
                            summary: longSentenceThresholdSummary,
                            systemImage: "text.insert",
                            tint: .teal,
                            isOn: deterministicSubToggleBinding(
                                value: viewModel.deterministicLongSentenceBreaking
                            ) { newValue in
                                try viewModel.updateDeterministicTextProcessing(longSentenceBreaking: newValue)
                            },
                            onConfigure: {
                                textProcessingThresholdEditor = .longSentence
                            }
                        )

                        SettingsToggleRow(
                            title: L10n.localize("settings.text_processing.filler_filter.title", comment: "Filler filter toggle title"),
                            subtitle: L10n.localize("settings.text_processing.filler_filter.subtitle", comment: "Filler filter toggle subtitle"),
                            systemImage: "scissors",
                            tint: .pink,
                            isOn: deterministicSubToggleBinding(
                                value: viewModel.deterministicFillerWordFiltering
                            ) { newValue in
                                try viewModel.updateDeterministicTextProcessing(fillerWordFiltering: newValue)
                            }
                        )

                        SettingsToggleRow(
                            title: L10n.localize("settings.text_processing.cjk_latin_spacing.title", comment: "CJK-Latin spacing toggle title"),
                            subtitle: L10n.localize("settings.text_processing.cjk_latin_spacing.subtitle", comment: "CJK-Latin spacing toggle subtitle"),
                            systemImage: "character.textbox",
                            tint: .purple,
                            isOn: deterministicSubToggleBinding(
                                value: viewModel.deterministicCjkLatinSpacing
                            ) { newValue in
                                try viewModel.updateDeterministicTextProcessing(cjkLatinSpacing: newValue)
                            }
                        )

                        SettingsToggleRow(
                            title: L10n.localize("settings.text_processing.auto_capitalization.title", comment: "Auto capitalization toggle title"),
                            subtitle: L10n.localize("settings.text_processing.auto_capitalization.subtitle", comment: "Auto capitalization toggle subtitle"),
                            systemImage: "textformat",
                            tint: .yellow,
                            isOn: deterministicSubToggleBinding(
                                value: viewModel.deterministicAutoCapitalization
                            ) { newValue in
                                try viewModel.updateDeterministicTextProcessing(autoCapitalization: newValue)
                            }
                        )
                    }
                    .disabled(!viewModel.deterministicTextProcessingEnabled)
                    .opacity(viewModel.deterministicTextProcessingEnabled ? 1.0 : 0.5)
                }
            }
        }
    }

    private var punctuationThresholdSummary: String {
        L10n.format("settings.text_processing.thresholds.punctuation_summary_format", comment: "Punctuation threshold summary",
            viewModel.deterministicPunctuationWordThreshold,
            viewModel.deterministicPunctuationCJKThreshold
        )
    }

    private var longSentenceThresholdSummary: String {
        L10n.format("settings.text_processing.thresholds.long_sentence_summary_format", comment: "Long sentence threshold summary",
            viewModel.deterministicLongSentenceWordThreshold,
            viewModel.deterministicLongSentenceCJKThreshold
        )
    }

    @ViewBuilder
    private func textProcessingThresholdEditorSheet(_ editor: TextProcessingThresholdEditor) -> some View {
        switch editor {
        case .punctuation:
            SettingsThresholdEditorSheet(
                title: L10n.localize("settings.text_processing.punctuation.title", comment: "Punctuation title"),
                subtitle: L10n.localize("settings.text_processing.thresholds.punctuation_editor_subtitle", comment: "Punctuation threshold editor subtitle"),
                systemImage: "exclamationmark.bubble",
                tint: .orange,
                onReset: {
                    perform { try viewModel.resetPunctuationThresholds() }
                },
                onDone: { textProcessingThresholdEditor = nil }
            ) {
                SettingsThresholdSliderRow(
                    title: L10n.localize("settings.text_processing.thresholds.punctuation_word", comment: "Punctuation word threshold label"),
                    subtitle: L10n.localize("settings.text_processing.thresholds.punctuation_word_subtitle", comment: "Punctuation word threshold subtitle"),
                    systemImage: "textformat.abc",
                    tint: .orange,
                    value: viewModel.deterministicPunctuationWordThreshold,
                    valueSuffix: L10n.localize("settings.text_processing.thresholds.unit_words", comment: "Words unit"),
                    range: 1...20,
                    onChange: { newValue in
                        perform { try viewModel.updateDeterministicTextProcessingThresholds(punctuationWord: newValue) }
                    }
                )
                SettingsThresholdSliderRow(
                    title: L10n.localize("settings.text_processing.thresholds.punctuation_cjk", comment: "Punctuation CJK threshold label"),
                    subtitle: L10n.localize("settings.text_processing.thresholds.punctuation_cjk_subtitle", comment: "Punctuation CJK threshold subtitle"),
                    systemImage: "character.textbox",
                    tint: .orange,
                    value: viewModel.deterministicPunctuationCJKThreshold,
                    valueSuffix: L10n.localize("settings.text_processing.thresholds.unit_chars", comment: "Characters unit"),
                    range: 1...20,
                    onChange: { newValue in
                        perform { try viewModel.updateDeterministicTextProcessingThresholds(punctuationCJK: newValue) }
                    }
                )
            } examples: {
                SettingsThresholdExamplePanel {
                    SettingsThresholdExampleRow(
                        label: "EN",
                        before: punctuationEnglishExampleInput,
                        after: punctuationEnglishExampleOutput
                    )
                    SettingsThresholdExampleRow(
                        label: "中",
                        before: punctuationChineseExampleInput,
                        after: punctuationChineseExampleOutput
                    )
                }
            }
        case .longSentence:
            SettingsThresholdEditorSheet(
                title: L10n.localize("settings.text_processing.long_sentence.title", comment: "Long sentence title"),
                subtitle: L10n.localize("settings.text_processing.thresholds.long_sentence_editor_subtitle", comment: "Long sentence threshold editor subtitle"),
                systemImage: "text.insert",
                tint: .teal,
                onReset: {
                    perform { try viewModel.resetLongSentenceThresholds() }
                },
                onDone: { textProcessingThresholdEditor = nil }
            ) {
                SettingsThresholdSliderRow(
                    title: L10n.localize("settings.text_processing.thresholds.long_sentence_word", comment: "Long sentence word threshold label"),
                    subtitle: L10n.localize("settings.text_processing.thresholds.long_sentence_word_subtitle", comment: "Long sentence word threshold subtitle"),
                    systemImage: "textformat.abc",
                    tint: .teal,
                    value: viewModel.deterministicLongSentenceWordThreshold,
                    valueSuffix: L10n.localize("settings.text_processing.thresholds.unit_words", comment: "Words unit"),
                    range: 5...50,
                    onChange: { newValue in
                        perform { try viewModel.updateDeterministicTextProcessingThresholds(longSentenceWord: newValue) }
                    }
                )
                SettingsThresholdSliderRow(
                    title: L10n.localize("settings.text_processing.thresholds.long_sentence_cjk", comment: "Long sentence CJK threshold label"),
                    subtitle: L10n.localize("settings.text_processing.thresholds.long_sentence_cjk_subtitle", comment: "Long sentence CJK threshold subtitle"),
                    systemImage: "character.textbox",
                    tint: .teal,
                    value: viewModel.deterministicLongSentenceCJKThreshold,
                    valueSuffix: L10n.localize("settings.text_processing.thresholds.unit_chars", comment: "Characters unit"),
                    range: 10...120,
                    onChange: { newValue in
                        perform { try viewModel.updateDeterministicTextProcessingThresholds(longSentenceCJK: newValue) }
                    }
                )
            } examples: {
                SettingsThresholdExamplePanel {
                    SettingsThresholdExampleRow(
                        label: "EN",
                        before: longSentenceEnglishExampleInput,
                        after: longSentenceEnglishExampleOutput
                    )
                    SettingsThresholdExampleRow(
                        label: "中",
                        before: longSentenceChineseExampleInput,
                        after: longSentenceChineseExampleOutput
                    )
                }
            }
        }
    }

    private var punctuationEnglishExampleInput: String {
        SettingsThresholdPreviewSamples.punctuationEnglish
    }

    private var punctuationEnglishExampleOutput: String {
        SettingsThresholdPreviewSamples.punctuationEnglishPreview(
            wordThreshold: viewModel.deterministicPunctuationWordThreshold
        )
    }

    private var punctuationChineseExampleInput: String {
        SettingsThresholdPreviewSamples.punctuationChinese
    }

    private var punctuationChineseExampleOutput: String {
        SettingsThresholdPreviewSamples.punctuationChinesePreview(
            cjkThreshold: viewModel.deterministicPunctuationCJKThreshold
        )
    }

    private var longSentenceEnglishExampleInput: String {
        SettingsThresholdPreviewSamples.longSentenceEnglish
    }

    private var longSentenceEnglishExampleOutput: String {
        SettingsThresholdPreviewSamples.longSentenceEnglishPreview(
            wordThreshold: viewModel.deterministicLongSentenceWordThreshold
        )
    }

    private var longSentenceChineseExampleInput: String {
        SettingsThresholdPreviewSamples.longSentenceChinese
    }

    private var longSentenceChineseExampleOutput: String {
        SettingsThresholdPreviewSamples.longSentenceChinesePreview(
            cjkThreshold: viewModel.deterministicLongSentenceCJKThreshold
        )
    }

    private var deterministicMasterBinding: Binding<Bool> {
        Binding(
            get: { viewModel.deterministicTextProcessingEnabled },
            set: { value in perform { try viewModel.updateDeterministicTextProcessing(enabled: value) } }
        )
    }

    /// Binding for an individual deterministic processor toggle. The setter
    /// is a no-op when the master switch is off (the row is also visually
    /// disabled, but this guards against programmatic updates).
    private func deterministicSubToggleBinding(
        value: Bool,
        setter: @escaping (Bool) throws -> Void
    ) -> Binding<Bool> {
        Binding(
            get: { value },
            set: { newValue in
                guard viewModel.deterministicTextProcessingEnabled else { return }
                perform { try setter(newValue) }
            }
        )
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
                ForEach(SettingsPrivacyPresentation.toggleRows) { row in
                    systemToggle(
                        row.option,
                        row.title,
                        row.subtitle,
                        row.systemImage,
                        tint: row.option == .crashLogs ? .purple : .orange
                    )
                }

                let support = SettingsPrivacyPresentation.manualCrashReportSupport
                HStack(alignment: .center, spacing: 14) {
                    SettingsRowIcon(systemImage: "exclamationmark.bubble", tint: .orange)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(support.title)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(AppTheme.ColorToken.primaryText)
                        Text(support.subtitle)
                            .font(.system(size: 12))
                            .foregroundStyle(AppTheme.ColorToken.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer()
                    Button(support.viewSummaryButtonTitle) {
                        viewModel.viewLatestCrashReportSummary()
                    }
                    Button(support.sendLatestButtonTitle) {
                        showCrashReportSendConfirmation = viewModel.prepareLatestCrashReportSendConfirmation()
                    }
                    .buttonStyle(.borderedProminent)
                }
                .buttonStyle(.bordered)
                .settingsRow()

                if let summary = viewModel.latestCrashReportSummaryText {
                    Text(summary)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(AppTheme.ColorToken.secondaryText)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .settingsRow()
                }

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

private struct SettingsThresholdToggleRow: View {
    let title: String
    let subtitle: String
    let summary: String
    let systemImage: String
    let tint: Color
    @Binding var isOn: Bool
    let onConfigure: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            SettingsRowIcon(systemImage: systemImage, tint: tint)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(AppTheme.ColorToken.primaryText)
                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(AppTheme.ColorToken.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                Text(summary)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(tint)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 12)
            Button(action: onConfigure) {
                Image(systemName: "gearshape")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(AppTheme.ColorToken.secondaryText)
                    .frame(width: 34, height: 34)
                    .background(AppTheme.ColorToken.panelBackground)
                    .overlay(
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .stroke(AppTheme.ColorToken.subtleStroke, lineWidth: AppTheme.Border.panelLineWidth)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
            }
            .buttonStyle(.plain)
            .help(L10n.localize("settings.text_processing.thresholds.configure", comment: "Configure thresholds tooltip"))

            Toggle("", isOn: $isOn)
                .labelsHidden()
                .toggleStyle(.switch)
        }
        .settingsRow()
    }
}

private struct SettingsThresholdEditorSheet<Controls: View, Examples: View>: View {
    let title: String
    let subtitle: String
    let systemImage: String
    let tint: Color
    let onReset: (() -> Void)?
    let onDone: () -> Void
    @ViewBuilder let controls: Controls
    @ViewBuilder let examples: Examples

    init(
        title: String,
        subtitle: String,
        systemImage: String,
        tint: Color,
        onReset: (() -> Void)? = nil,
        onDone: @escaping () -> Void,
        @ViewBuilder controls: () -> Controls,
        @ViewBuilder examples: () -> Examples
    ) {
        self.title = title
        self.subtitle = subtitle
        self.systemImage = systemImage
        self.tint = tint
        self.onReset = onReset
        self.onDone = onDone
        self.controls = controls()
        self.examples = examples()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.horizontal, 24)
                .padding(.top, 22)
                .padding(.bottom, 18)

            Divider()

            HStack(alignment: .top, spacing: SettingsThresholdEditorLayout.contentSpacing) {
                VStack(alignment: .leading, spacing: 12) {
                    controls
                    Spacer(minLength: 24)
                    resetButton
                }
                .frame(width: SettingsThresholdEditorLayout.controlsPaneWidth, alignment: .topLeading)
                .frame(maxHeight: .infinity, alignment: .topLeading)

                Divider()
                    .frame(maxHeight: .infinity)

                examples
                    .frame(
                        minWidth: SettingsThresholdEditorLayout.examplesPaneMinWidth,
                        maxWidth: .infinity,
                        alignment: .topLeading
                    )
            }
            .padding(.horizontal, SettingsThresholdEditorLayout.horizontalPadding)
            .padding(.vertical, SettingsThresholdEditorLayout.verticalPadding)
            .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity, alignment: .top)
        .background(AppTheme.ColorToken.pageBackground)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(AppTheme.ColorToken.subtleStroke, lineWidth: AppTheme.Border.panelLineWidth)
        )
        .contentShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .onTapGesture {}
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 14) {
            SettingsRowIcon(systemImage: systemImage, tint: tint)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(AppTheme.ColorToken.primaryText)
                    .lineLimit(2)
                    .minimumScaleFactor(0.86)
                Text(subtitle)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(AppTheme.ColorToken.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 12)
            Button(action: onDone) {
                Image(systemName: "xmark")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(AppTheme.ColorToken.secondaryText)
                    .frame(width: 36, height: 36)
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.cancelAction)
        }
    }

    @ViewBuilder
    private var resetButton: some View {
        if let onReset {
            Button(action: onReset) {
                Label(
                    L10n.localize("settings.text_processing.thresholds.reset_defaults", comment: "Reset thresholds"),
                    systemImage: "arrow.counterclockwise"
                )
                .frame(minWidth: 132, minHeight: 34)
            }
            .buttonStyle(.bordered)
            .help(L10n.localize("settings.text_processing.thresholds.reset_defaults_help", comment: "Reset thresholds help"))
        }
    }
}

private struct SettingsThresholdExamplePanel<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(
                L10n.localize("settings.text_processing.thresholds.examples", comment: "Examples title"),
                systemImage: "sparkles"
            )
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(AppTheme.ColorToken.secondaryText)

            VStack(alignment: .leading, spacing: 10) {
                content
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppTheme.ColorToken.controlBackground.opacity(0.72))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(AppTheme.ColorToken.subtleStroke, lineWidth: AppTheme.Border.panelLineWidth)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

private struct SettingsThresholdExampleRow: View {
    let label: String
    let before: String
    let after: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(label)
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundStyle(AppTheme.ColorToken.accent)
                    .frame(width: 32, height: 24)
                    .background(AppTheme.ColorToken.accent.opacity(0.10))
                    .clipShape(Capsule())

                Text(L10n.localize("settings.text_processing.thresholds.example_live_preview", comment: "Live preview label"))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(AppTheme.ColorToken.secondaryText)
                    .lineLimit(1)
                    .truncationMode(.tail)

                Spacer(minLength: 8)

                Image(systemName: "arrow.right")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(AppTheme.ColorToken.accent)
            }

            VStack(alignment: .leading, spacing: 6) {
                SettingsThresholdExampleTextBlock(
                    title: L10n.localize("settings.text_processing.thresholds.example_before", comment: "Example before label"),
                    text: before,
                    isResult: false
                )
                SettingsThresholdExampleTextBlock(
                    title: L10n.localize("settings.text_processing.thresholds.example_after", comment: "Example after label"),
                    text: after,
                    isResult: true
                )
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppTheme.ColorToken.panelBackground)
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(AppTheme.ColorToken.subtleStroke, lineWidth: AppTheme.Border.panelLineWidth)
        )
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

private struct SettingsThresholdExampleTextBlock: View {
    let title: String
    let text: String
    let isResult: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(AppTheme.ColorToken.secondaryText)

            Text(text)
                .font(.system(size: 12, weight: isResult ? .semibold : .regular, design: .monospaced))
                .foregroundStyle(isResult ? AppTheme.ColorToken.primaryText : AppTheme.ColorToken.secondaryText)
                .lineLimit(isResult ? 6 : 4)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(isResult ? AppTheme.ColorToken.accent.opacity(0.08) : AppTheme.ColorToken.controlBackground.opacity(0.72))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(isResult ? AppTheme.ColorToken.accent.opacity(0.22) : AppTheme.ColorToken.subtleStroke, lineWidth: AppTheme.Border.panelLineWidth)
        )
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct SettingsThresholdSliderRow: View {
    let title: String
    let subtitle: String
    let systemImage: String
    let tint: Color
    let value: Int
    var valueSuffix: String? = nil
    let range: ClosedRange<Int>
    let onChange: (Int) -> Void

    @State private var isDragging = false
    @State private var dragValue: Int?

    private var displayedValue: Int { dragValue ?? value }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 14) {
                SettingsRowIcon(systemImage: systemImage, tint: tint)
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(AppTheme.ColorToken.primaryText)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(subtitle)
                        .font(.system(size: 12))
                        .foregroundStyle(AppTheme.ColorToken.secondaryText)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .layoutPriority(1)
                Spacer(minLength: 10)
                valueBadge
                stepper
            }

            sliderTrack
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppTheme.ColorToken.controlBackground.opacity(isDragging ? 0.92 : 0.72))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(isDragging ? AppTheme.ColorToken.accent.opacity(0.55) : AppTheme.ColorToken.subtleStroke, lineWidth: isDragging ? 1.5 : AppTheme.Border.panelLineWidth)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .shadow(
            color: isDragging ? AppTheme.ColorToken.accent.opacity(0.12) : Color.clear,
            radius: isDragging ? 10 : 0,
            x: 0,
            y: 5
        )
        .animation(.easeOut(duration: 0.16), value: isDragging)
    }

    private var valueBadge: some View {
        Text(valueText)
            .font(.system(size: isDragging ? 17 : 15, weight: .bold, design: .monospaced))
            .foregroundStyle(isDragging ? Color.white : AppTheme.ColorToken.primaryText)
            .lineLimit(1)
            .minimumScaleFactor(0.82)
            .frame(minWidth: 58, maxWidth: 92)
            .frame(height: 34)
            .padding(.horizontal, 8)
            .background(isDragging ? AppTheme.ColorToken.accent : AppTheme.ColorToken.panelBackground)
            .overlay(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .stroke(isDragging ? AppTheme.ColorToken.accent : AppTheme.ColorToken.subtleStroke, lineWidth: AppTheme.Border.panelLineWidth)
            )
            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
            .accessibilityLabel(Text("\(title)：\(valueText)"))
    }

    private var stepper: some View {
        Stepper(
            value: Binding(
                get: { value },
                set: { newValue in
                    let clamped = clamp(newValue)
                    guard clamped != value else { return }
                    onChange(clamped)
                }
            ),
            in: range
        ) {
            EmptyView()
        }
        .labelsHidden()
        .frame(width: 34)
    }

    private var sliderTrack: some View {
        GeometryReader { proxy in
            let width = max(proxy.size.width, 1)
            let progress = progress(for: displayedValue)
            let thumbX = min(max(width * progress, 12), max(width - 12, 12))

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(AppTheme.ColorToken.subtleStroke.opacity(0.75))
                    .frame(height: 8)
                    .position(x: width / 2, y: 30)

                Capsule()
                    .fill(AppTheme.ColorToken.accent)
                    .frame(width: max(thumbX, 0), height: 8)
                    .position(x: thumbX / 2, y: 30)

                thresholdTicks(width: width)

                if isDragging {
                    Text(valueText)
                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                        .foregroundStyle(Color.white)
                        .padding(.horizontal, 8)
                        .frame(height: 24)
                        .background(AppTheme.ColorToken.accent)
                        .clipShape(Capsule())
                        .shadow(color: AppTheme.ColorToken.accent.opacity(0.25), radius: 6, x: 0, y: 3)
                        .position(x: thumbX, y: 4)
                        .transition(.opacity.combined(with: .scale(scale: 0.92)))
                }

                Circle()
                    .fill(AppTheme.ColorToken.accent)
                    .frame(width: isDragging ? 28 : 22, height: isDragging ? 28 : 22)
                    .shadow(color: AppTheme.ColorToken.accent.opacity(0.25), radius: 6, x: 0, y: 3)
                    .overlay(
                        Circle()
                            .stroke(Color.white.opacity(0.92), lineWidth: 2)
                    )
                    .position(x: thumbX, y: 30)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { gesture in
                        isDragging = true
                        updateDragValue(locationX: gesture.location.x, width: width)
                    }
                    .onEnded { gesture in
                        updateDragValue(locationX: gesture.location.x, width: width)
                        dragValue = nil
                        isDragging = false
                    }
            )
        }
        .frame(height: 48)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(title))
        .accessibilityValue(Text(valueText))
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment:
                let next = clamp(value + 1)
                if next != value { onChange(next) }
            case .decrement:
                let next = clamp(value - 1)
                if next != value { onChange(next) }
            @unknown default:
                break
            }
        }
    }

    private func thresholdTicks(width: CGFloat) -> some View {
        ZStack(alignment: .leading) {
            ForEach([0.0, 0.25, 0.5, 0.75, 1.0], id: \.self) { tick in
                Capsule()
                    .fill(AppTheme.ColorToken.secondaryText.opacity(0.20))
                    .frame(width: 2, height: tick == 0.0 || tick == 1.0 ? 12 : 8)
                    .position(x: width * tick, y: 30)
            }
        }
    }

    private func updateDragValue(locationX: CGFloat, width: CGFloat) {
        let boundedX = min(max(locationX, 0), width)
        let ratio = width == 0 ? 0 : boundedX / width
        let raw = Double(range.lowerBound) + Double(range.upperBound - range.lowerBound) * Double(ratio)
        let next = clamp(Int(raw.rounded()))
        dragValue = next
        guard next != value else { return }
        onChange(next)
    }

    private func progress(for value: Int) -> CGFloat {
        guard range.upperBound > range.lowerBound else { return 0 }
        return CGFloat(value - range.lowerBound) / CGFloat(range.upperBound - range.lowerBound)
    }

    private func clamp(_ value: Int) -> Int {
        min(max(value, range.lowerBound), range.upperBound)
    }

    private var valueText: String {
        if let valueSuffix, !valueSuffix.isEmpty {
            return "\(displayedValue) \(valueSuffix)"
        }
        return "\(displayedValue)"
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
                        Text(L10n.format("settings.interface_language.restart_dialog.message_format", comment: "Restart language dialog message",
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
        case .textProcessing: return L10n.localize("settings.section.text_processing", comment: "")
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
