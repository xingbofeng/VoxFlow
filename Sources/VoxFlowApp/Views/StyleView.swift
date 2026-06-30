import SwiftUI

enum StyleViewLayout {
    static let menuWidth: CGFloat = 300
    static let minimumEditorPaneWidth: CGFloat = 300
    static let minimumContentWidth =
        menuWidth
        + AppTheme.Spacing.page * 2
        + minimumEditorPaneWidth * 2
        + 2
}

enum StyleConfigurationModalPresentationPolicy {
    static let showsCloseButton = true
    static let dismissesOnBackdropTap = true
    static let dismissesOnEscapeKey = true
}

struct StyleView: View {
    @ObservedObject var viewModel: StyleViewModel
    @State private var prompt = ""
    @State private var installedApps: [InstalledApplication] = []
    @State private var showingAppSelector = false
    @State private var showingSmartConfiguration = false
    @State private var smartConfigurationViewModel: SmartConfigurationViewModel
    @State private var autoMatchSheetDraft: StyleAutoMatchSheetDraft?
    @State private var outputFormatDraft: StyleOutputFormatSheetDraft?

    init(viewModel: StyleViewModel) {
        self.viewModel = viewModel
        _smartConfigurationViewModel = State(
            initialValue: viewModel.makeSmartConfigurationViewModel()
        )
    }

    var body: some View {
        ZStack {
            HStack(spacing: 0) {
                styleList
                    .frame(width: StyleViewLayout.menuWidth)
                    .background(AppTheme.ColorToken.sidebarBackground)
                Divider()
                editor
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }

            if showingSmartConfiguration {
                smartConfigurationOverlay
                    .zIndex(10)
            }

            styleConfigurationOverlay
        }
        .background(AppTheme.ColorToken.pageBackground)
        .tint(AppTheme.ColorToken.accent)
        .actionFeedbackOverlay(
            message: viewModel.lastActionMessage,
            error: viewModel.lastError,
            onDismiss: viewModel.clearFeedback
        )
        .onAppear {
            viewModel.load()
            prompt = viewModel.selectedProfile?.prompt ?? ""
            loadInstalledAppsIfNeeded()
        }
        .sheet(isPresented: $showingAppSelector) {
            appSelectorSheet
        }
    }

    private var smartConfigurationOverlay: some View {
        ZStack {
            Color.black.opacity(0.22)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture {
                    if SmartConfigurationPresentationPolicy.dismissesOnBackdropTap {
                        dismissSmartConfiguration()
                    }
                }

            SmartConfigurationView(
                viewModel: smartConfigurationViewModel,
                onClose: dismissSmartConfiguration,
                onApplied: { result in
                    viewModel.refreshAfterSmartConfigurationApplied(primaryStyleID: result.primaryStyleID)
                    prompt = viewModel.selectedProfile?.prompt ?? prompt
                    loadInstalledApps(force: true)
                }
            )
            .frame(width: 760, height: 640)
            .background(AppTheme.ColorToken.pageBackground)
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .shadow(color: .black.opacity(0.18), radius: 28, y: 12)
            .padding(24)
        }
        .transition(.opacity)
        .onExitCommand {
            if SmartConfigurationPresentationPolicy.dismissesOnEscapeKey {
                dismissSmartConfiguration()
            }
        }
    }

    @ViewBuilder
    private var styleConfigurationOverlay: some View {
        if autoMatchSheetDraft != nil || outputFormatDraft != nil {
            GeometryReader { proxy in
                let modalMaxHeight = max(360, proxy.size.height - 72)
                ZStack {
                    Color.black.opacity(0.22)
                        .ignoresSafeArea()
                        .contentShape(Rectangle())
                        .onTapGesture {
                            if StyleConfigurationModalPresentationPolicy.dismissesOnBackdropTap {
                                dismissStyleConfigurationModal()
                            }
                        }

                    styleConfigurationModalContent
                        .frame(maxHeight: modalMaxHeight)
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .shadow(color: .black.opacity(0.18), radius: 28, y: 12)
                        .padding(24)
                        .onTapGesture {}
                        .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .transition(.opacity)
                .zIndex(20)
                .onExitCommand {
                    if StyleConfigurationModalPresentationPolicy.dismissesOnEscapeKey {
                        dismissStyleConfigurationModal()
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var styleConfigurationModalContent: some View {
        if autoMatchSheetDraft != nil {
            autoMatchSheet
        } else if let fallbackDraft = outputFormatDraft {
            StyleOutputFormatSheet(
                draft: outputFormatSheetBinding(fallback: fallbackDraft),
                previewInput: StyleOutputFormatPreviewText.sampleInput,
                onCancel: { outputFormatDraft = nil },
                onSave: saveOutputFormatSheet
            )
        }
    }

    private func dismissSmartConfiguration() {
        if smartConfigurationViewModel.canCancel {
            smartConfigurationViewModel.cancel()
        }
        showingSmartConfiguration = false
    }

    private func dismissStyleConfigurationModal() {
        autoMatchSheetDraft = nil
        outputFormatDraft = nil
    }

    private var styleList: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(L10n.localize("style.view.title", comment: ""), systemImage: "slider.horizontal.3")
                .font(.system(size: 24, weight: .semibold))
                .padding(.horizontal, 18)
                .padding(.top, 22)

            ScrollView {
                VStack(spacing: 8) {
                    ForEach(viewModel.profiles, id: \.id) { profile in
                        Button {
                            select(profile)
                        } label: {
                            HStack(alignment: .top, spacing: 12) {
                                Image(systemName: profile.iconName)
                                    .foregroundStyle(AppTheme.ColorToken.accent)
                                    .frame(width: 24, height: 24)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(profile.name)
                                        .font(.system(size: 14, weight: .semibold))
                                    if let subtitle = profile.outputFormatListSubtitle ?? profile.subtitle {
                                        Text(subtitle)
                                            .font(.system(size: 12))
                                            .foregroundStyle(AppTheme.ColorToken.secondaryText)
                                            .lineLimit(2)
                                    }
                                }
                                Spacer(minLength: 0)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 11)
                            .frame(maxWidth: .infinity, minHeight: 58, alignment: .leading)
                            .background(viewModel.selectedProfile?.id == profile.id ? AppTheme.ColorToken.selectionBackground : Color.clear)
                            .overlay(
                                RoundedRectangle(cornerRadius: AppTheme.Radius.card, style: .continuous)
                                    .stroke(
                                        viewModel.selectedProfile?.id == profile.id
                                            ? AppTheme.ColorToken.selectionBorder
                                            : Color.clear,
                                        lineWidth: AppTheme.Border.selectedLineWidth
                                    )
                            )
                            .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.card, style: .continuous))
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.bottom, 18)
            }
        }
    }

    private var editor: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.section) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(viewModel.selectedProfile?.name ?? L10n.localize("style.view.title", comment: ""))
                        .font(.system(size: 26, weight: .semibold))
                    Text(L10n.localize("style.view.prompt_editor_hint", comment: ""))
                        .font(.system(size: 13))
                        .foregroundStyle(AppTheme.ColorToken.secondaryText)
                }
                Spacer()
                Button {
                    resetPrompt()
                } label: {
                    Label(
                        L10n.localize("style.action.restore_default", comment: ""),
                        systemImage: "arrow.counterclockwise"
                    )
                }
                .buttonStyle(.bordered)
                .disabled(viewModel.selectedProfile?.builtIn != true)
                Button(L10n.localize("style.action.confirm", comment: "")) {
                    savePrompt()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(viewModel.selectedProfile == nil)
            }
            appRoutingSection
            outputFormatSummarySection
            autoMatchSummarySection
            HSplitView {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Markdown", systemImage: "text.alignleft")
                        .font(.system(size: 13, weight: .semibold))
                    TextEditor(text: $prompt)
                        .font(.system(.body, design: .monospaced))
                        .scrollContentBackground(.hidden)
                        .padding(10)
                        .background(AppTheme.ColorToken.panelBackground)
                        .overlay(editorBorder)
                        .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.card))
                        .shadow(color: AppTheme.ColorToken.accent.opacity(0.03), radius: 6, y: 2)
                }
                .frame(
                    minWidth: StyleViewLayout.minimumEditorPaneWidth,
                    maxWidth: .infinity,
                    maxHeight: .infinity
                )

                VStack(alignment: .leading, spacing: 8) {
                    Label(L10n.localize("style.view.preview", comment: ""), systemImage: "eye")
                        .font(.system(size: 13, weight: .semibold))
                    ScrollView {
                        MarkdownPromptPreview(markdown: prompt)
                            .padding(14)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(AppTheme.ColorToken.panelBackground)
                    .overlay(editorBorder)
                    .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.card))
                    .shadow(color: AppTheme.ColorToken.accent.opacity(0.03), radius: 6, y: 2)
                }
                .frame(
                    minWidth: StyleViewLayout.minimumEditorPaneWidth,
                    maxWidth: .infinity,
                    maxHeight: .infinity
                )
            }
        }
        .padding(AppTheme.Spacing.page)
    }

    private var appRoutingSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 12) {
                Label(L10n.localize("style.app_routing.title", comment: ""), systemImage: "scope")
                    .font(.system(size: 18, weight: .semibold))
                Spacer()
                Button {
                    loadInstalledAppsIfNeeded()
                    showingAppSelector = true
                } label: {
                    Label(L10n.localize("style.action.manage_apps", comment: ""), systemImage: "magnifyingglass")
                }
                .buttonStyle(.borderless)
                Button {
                    guard viewModel.canLaunchSmartConfiguration else {
                        viewModel.reportSmartConfigurationConfigurationRequired()
                        return
                    }
                    smartConfigurationViewModel = viewModel.makeSmartConfigurationViewModel()
                    showingSmartConfiguration = true
                } label: {
                    Label(L10n.localize("style.action.smart_configuration", comment: ""), systemImage: "wand.and.stars")
                }
                .buttonStyle(.borderedProminent)
            }

            if displayedApplications.isEmpty {
                HStack(spacing: 10) {
                    Image(systemName: "app.badge")
                        .font(.system(size: 18))
                        .foregroundStyle(AppTheme.ColorToken.secondaryText)
                    Text(L10n.localize("style.app_routing.no_application_bindings", comment: ""))
                        .font(.system(size: 13))
                        .foregroundStyle(AppTheme.ColorToken.secondaryText)
                    Spacer()
                }
                .padding(12)
                .background(AppTheme.ColorToken.controlBackground)
                .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.card, style: .continuous))
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(displayedApplications) { app in
                            VStack(spacing: 6) {
                                ApplicationIconView(name: app.name, iconPath: app.iconPath, size: 46)
                                if !app.badges.isEmpty {
                                    HStack(spacing: 4) {
                                        ForEach(app.badges, id: \.self) { badge in
                                            Text(badge.title)
                                                .font(.system(size: 9, weight: .semibold))
                                                .foregroundStyle(badge.color)
                                                .lineLimit(1)
                                                .padding(.horizontal, 5)
                                                .padding(.vertical, 2)
                                                .background(badge.color.opacity(0.12))
                                                .clipShape(Capsule())
                                        }
                                    }
                                    .frame(width: 64, height: 14)
                                }
                                Text(app.name)
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(AppTheme.ColorToken.secondaryText)
                                    .lineLimit(1)
                                    .frame(width: 64)
                            }
                            .help(app.bundleID)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
        .padding(16)
        .appPanel(cornerRadius: AppTheme.Radius.card)
    }

    private var appSelectorSheet: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(L10n.localize("style.action.manage_apps", comment: ""))
                        .font(.system(size: 20, weight: .semibold))
                    Text(L10n.format("style.app_routing.select_app_for_style", comment: "", viewModel.selectedProfile?.name ?? L10n.localize("style.view.title", comment: "")))
                        .font(.system(size: 12))
                        .foregroundStyle(AppTheme.ColorToken.secondaryText)
                }
                Spacer()
                Button {
                    showingAppSelector = false
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .semibold))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 18)

            Divider()

            InstalledAppSelectorView(
                installedApps: installedApps,
                selectedBundleIDs: selectedBundleIDs,
                onSelect: addApplicationRule,
                onRemove: removeApplicationRule
            )
            .padding(20)

            Divider()

            HStack {
                Button {
                    loadInstalledApps(force: true)
                } label: {
                    Label(L10n.localize("style.app_routing.rescan", comment: ""), systemImage: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                Spacer()
                Button(L10n.localize("style.action.done", comment: "")) {
                    showingAppSelector = false
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 14)
        }
        .frame(width: 560)
        .frame(minHeight: 460)
        .background(AppTheme.ColorToken.pageBackground)
    }

    private var autoMatchSummarySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(StyleAutoMatchSummary.label(for: viewModel))
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(AppTheme.ColorToken.primaryText)
                    Text(L10n.localize("style.automatch.sheet.subtitle", comment: ""))
                        .font(.system(size: 12))
                        .foregroundStyle(AppTheme.ColorToken.secondaryText)
                        .lineLimit(2)
                }
                Spacer()
                Toggle(
                    L10n.localize("style.automatch.global.title", comment: ""),
                    isOn: Binding(
                        get: { viewModel.autoMatchSettings.globalEnabled },
                        set: { viewModel.saveGlobalAutoMatchEnabled($0) }
                    )
                )
                .toggleStyle(.switch)
                .labelsHidden()
                Button {
                    openAutoMatchSheet()
                } label: {
                    Label(L10n.localize("style.action.configure_auto_match", comment: ""), systemImage: "wand.and.stars")
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(16)
        .appPanel(cornerRadius: AppTheme.Radius.card)
    }

    private var outputFormatSummarySection: some View {
        let format = currentOutputFormat
        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 12) {
                Image(systemName: "textformat.alt")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(AppTheme.ColorToken.accent)
                    .frame(width: 26, height: 26)
                VStack(alignment: .leading, spacing: 4) {
                    Text(L10n.localize("style.output_format.card.title", comment: ""))
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(AppTheme.ColorToken.primaryText)
                    Text(format.summaryText)
                        .font(.system(size: 12))
                        .foregroundStyle(AppTheme.ColorToken.secondaryText)
                        .lineLimit(2)
                }
                Spacer()
                Button {
                    openOutputFormatSheet()
                } label: {
                    Label(L10n.localize("style.action.configure_output_format", comment: ""), systemImage: "slider.horizontal.3")
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(16)
        .appPanel(cornerRadius: AppTheme.Radius.card)
    }

    private var autoMatchSheet: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(L10n.localize("style.automatch.sheet.title", comment: ""))
                        .font(.system(size: 20, weight: .semibold))
                    Text(L10n.localize("style.automatch.sheet.subtitle", comment: ""))
                        .font(.system(size: 12))
                        .foregroundStyle(AppTheme.ColorToken.secondaryText)
                }
                Spacer()
                if StyleConfigurationModalPresentationPolicy.showsCloseButton {
                    Button {
                        autoMatchSheetDraft = nil
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .semibold))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 18)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    autoMatchDescriptionSection
                    autoMatchContextRoundsSection
                }
                .padding(22)
            }

            Divider()

            HStack {
                if viewModel.isGeneratingAutoMatchDescription {
                    ProgressView()
                        .controlSize(.small)
                        .padding(.leading, 4)
                }
                Spacer()
                Button(L10n.localize("style.automatch.action.cancel", comment: "")) {
                    autoMatchSheetDraft = nil
                }
                .buttonStyle(.borderless)
                .keyboardShortcut(.cancelAction)
                Button(L10n.localize("style.automatch.action.save", comment: "")) {
                    saveAutoMatchSheet()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 14)
        }
        .frame(width: 560)
        .frame(minHeight: 520)
        .background(AppTheme.ColorToken.pageBackground)
    }

    private var autoMatchDescriptionSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(L10n.localize("style.automatch.description.title", comment: ""))
                    .font(.system(size: 14, weight: .semibold))
                Spacer()
                Button {
                    Task { await generateAutoMatchDescription() }
                } label: {
                    Label(L10n.localize("style.action.generate_auto_match_description", comment: ""), systemImage: "sparkles")
                }
                .buttonStyle(.borderless)
                .disabled(viewModel.selectedProfile == nil || viewModel.isGeneratingAutoMatchDescription)
            }
            TextEditor(text: autoMatchDescriptionBinding)
                .font(.system(.body))
                .scrollContentBackground(.hidden)
                .padding(8)
                .background(AppTheme.ColorToken.panelBackground)
                .overlay(editorBorder)
                .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.card))
                .frame(minHeight: 76)
            Text(L10n.localize("style.automatch.description.hint", comment: ""))
                .font(.system(size: 11))
                .foregroundStyle(AppTheme.ColorToken.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var autoMatchContextRoundsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle(isOn: autoMatchContextEnabledBinding) {
                Text(L10n.localize("style.automatch.context.title", comment: ""))
                    .font(.system(size: 14, weight: .semibold))
            }
            Text(L10n.localize("style.automatch.context.description", comment: ""))
                .font(.system(size: 12))
                .foregroundStyle(AppTheme.ColorToken.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            VStack(spacing: 18) {
                autoMatchSliderField(
                    title: L10n.localize("style.automatch.context.rounds_title", comment: ""),
                    suffix: L10n.localize("style.automatch.context.rounds_suffix", comment: ""),
                    value: autoMatchContextRoundsBinding,
                    range: 0...5
                )
                autoMatchSliderField(
                    title: L10n.localize("style.automatch.context.ttl_title", comment: ""),
                    suffix: L10n.localize("style.automatch.context.ttl_suffix", comment: ""),
                    value: autoMatchContextTTLHoursBinding,
                    range: 1...24,
                    step: 1
                )
            }
            .padding(.top, 4)
            .disabled(!autoMatchContextEnabledBinding.wrappedValue)
            .opacity(autoMatchContextEnabledBinding.wrappedValue ? 1.0 : 0.6)
        }
    }

    private func autoMatchSliderField(
        title: String,
        suffix: String,
        value: Binding<Int>,
        range: ClosedRange<Int>,
        step: Double = 1
    ) -> some View {
        let doubleValue = Binding<Double>(
            get: { Double(value.wrappedValue) },
            set: { value.wrappedValue = min(max(Int($0.rounded()), range.lowerBound), range.upperBound) }
        )
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(AppTheme.ColorToken.secondaryText)
                Spacer()
                Text("\(value.wrappedValue) \(suffix)")
                    .font(.system(size: 13, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(AppTheme.ColorToken.primaryText)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(AppTheme.ColorToken.panelBackground)
                    .overlay(
                        RoundedRectangle(cornerRadius: AppTheme.Radius.card, style: .continuous)
                            .stroke(AppTheme.ColorToken.panelStroke, lineWidth: AppTheme.Border.panelLineWidth)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.card, style: .continuous))
            }
            Slider(
                value: doubleValue,
                in: Double(range.lowerBound)...Double(range.upperBound),
                step: step
            )
            .tint(AppTheme.ColorToken.accent)
        }
    }

    private func saveAutoMatchSheet() {
        guard let id = viewModel.selectedProfile?.id,
              let draft = autoMatchSheetDraft else {
            autoMatchSheetDraft = nil
            return
        }
        do {
            try viewModel.updateAutoMatchConfiguration(
                profileID: id,
                contextRounds: ContextRoundsSettings(
                    enabled: draft.contextRoundsEnabled,
                    maxRounds: draft.contextRounds,
                    ttlHours: draft.contextTTLHours
                ),
                autoMatchDescription: draft.description
            )
            autoMatchSheetDraft = nil
        } catch {
            viewModel.report(error: error)
        }
    }

    private func saveOutputFormatSheet() {
        guard let id = viewModel.selectedProfile?.id,
              let draft = outputFormatDraft else {
            outputFormatDraft = nil
            return
        }
        do {
            try viewModel.updateOutputFormat(id: id, outputFormat: draft.format)
            outputFormatDraft = nil
        } catch {
            viewModel.report(error: error)
        }
    }

    private func generateAutoMatchDescription() async {
        guard let id = viewModel.selectedProfile?.id else { return }
        await viewModel.generateAutoMatchDescription(forProfileID: id)
        if let updated = viewModel.selectedProfile,
           let description = updated.autoMatchDescription {
            autoMatchSheetDraft?.description = description
        }
    }

    private func openAutoMatchSheet() {
        outputFormatDraft = nil
        autoMatchSheetDraft = StyleAutoMatchSheetPresentation.makeDraft(
            from: viewModel.selectedProfile,
            settings: viewModel.autoMatchSettings
        )
    }

    private func openOutputFormatSheet() {
        autoMatchSheetDraft = nil
        outputFormatDraft = StyleOutputFormatSheetDraft(format: currentOutputFormat)
    }

    private func outputFormatSheetBinding(fallback: StyleOutputFormatSheetDraft) -> Binding<StyleOutputFormatSheetDraft> {
        Binding(
            get: { outputFormatDraft ?? fallback },
            set: { outputFormatDraft = $0 }
        )
    }

    private var currentOutputFormat: StyleOutputFormat {
        if let profile = viewModel.selectedProfile {
            return profile.outputFormat
                ?? StyleOutputFormat.builtInDefault(for: profile.id)
                ?? StyleOutputFormat.systemDefault
        }
        return StyleOutputFormat.systemDefault
    }

    private var autoMatchDescriptionBinding: Binding<String> {
        Binding(
            get: { autoMatchSheetDraft?.description ?? "" },
            set: { autoMatchSheetDraft?.description = $0 }
        )
    }

    private var autoMatchContextEnabledBinding: Binding<Bool> {
        Binding(
            get: { autoMatchSheetDraft?.contextRoundsEnabled ?? true },
            set: { autoMatchSheetDraft?.contextRoundsEnabled = $0 }
        )
    }

    private var autoMatchContextRoundsBinding: Binding<Int> {
        Binding(
            get: { autoMatchSheetDraft?.contextRounds ?? 3 },
            set: { autoMatchSheetDraft?.contextRounds = $0 }
        )
    }

    private var autoMatchContextTTLHoursBinding: Binding<Int> {
        Binding(
            get: { autoMatchSheetDraft?.contextTTLHours ?? 6 },
            set: { autoMatchSheetDraft?.contextTTLHours = $0 }
        )
    }

    private var editorBorder: some View {
        RoundedRectangle(cornerRadius: AppTheme.Radius.card, style: .continuous)
            .stroke(AppTheme.ColorToken.panelStroke, lineWidth: AppTheme.Border.panelLineWidth)
    }

    private var selectedRules: [AppStyleRule] {
        guard let styleID = viewModel.selectedProfile?.id else { return [] }
        return viewModel.appStyleRules.filter { $0.styleID == styleID }
    }

    private var selectedBundleIDs: Set<String> {
        Set(selectedRules.map(\.bundleID))
    }

    private var displayedApplications: [StyleApplicationDisplay] {
        guard let styleID = viewModel.selectedProfile?.id else { return [] }
        return StyleApplicationPresentation.displayedApplications(
            selectedStyleID: styleID,
            selectedRules: selectedRules,
            allRules: viewModel.appStyleRules,
            installedApps: installedApps,
            autoMatchSettings: viewModel.autoMatchSettings
        )
    }

    private func select(_ profile: StyleProfileRecord) {
        do {
            try viewModel.selectProfile(id: profile.id)
            prompt = viewModel.selectedProfile?.prompt ?? profile.prompt
        } catch {
            viewModel.report(error: error)
        }
    }

    private func savePrompt() {
        guard let profile = viewModel.selectedProfile else { return }
        do {
            try viewModel.updateProfile(id: profile.id, prompt: prompt)
            prompt = viewModel.selectedProfile?.prompt ?? prompt
        } catch {
            viewModel.report(error: error)
        }
    }

    private func resetPrompt() {
        guard let profile = viewModel.selectedProfile else { return }
        do {
            try viewModel.resetBuiltInPrompt(id: profile.id)
            prompt = viewModel.selectedProfile?.prompt ?? prompt
        } catch {
            viewModel.report(error: error)
        }
    }

    private func addApplicationRule(_ app: InstalledApplication) {
        guard let styleID = viewModel.selectedProfile?.id,
              let bundleID = app.bundleID else { return }
        do {
            try viewModel.saveAppStyleRule(
                id: nil,
                bundleID: bundleID,
                appName: app.name,
                styleID: styleID
            )
        } catch {
            viewModel.report(error: error)
        }
    }

    private func removeApplicationRule(bundleID: String) {
        guard let rule = viewModel.appStyleRules.first(where: { $0.bundleID == bundleID }) else {
            return
        }
        viewModel.deleteAppStyleRule(id: rule.id)
    }

    private func loadInstalledAppsIfNeeded() {
        guard installedApps.isEmpty else { return }
        loadInstalledApps(force: false)
    }

    private func loadInstalledApps(force: Bool) {
        guard force || installedApps.isEmpty else { return }
        Task {
            let apps = await Task.detached {
                FileSystemInstalledApplicationProvider().scanInstalledApplications()
            }.value
            installedApps = apps.sorted {
                $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
        }
    }
}

struct StyleApplicationDisplay: Identifiable {
    let bundleID: String
    let name: String
    let iconPath: String?
    let source: StyleApplicationDisplaySource
    let badges: [StyleApplicationDisplayBadge]

    var id: String { bundleID }
}

enum StyleApplicationDisplaySource: Equatable {
    case manual
    case aiAutoMatch
}

enum StyleApplicationDisplayBadge: Equatable, Hashable {
    case temporary

    var title: String {
        switch self {
        case .temporary:
            return L10n.localize("style.app_routing.source_temporary", comment: "")
        }
    }

    var color: Color {
        switch self {
        case .temporary:
            return AppTheme.ColorToken.accent
        }
    }
}

enum StyleApplicationPresentation {
    static func displayedApplications(
        selectedStyleID: String,
        selectedRules: [AppStyleRule],
        allRules: [AppStyleRule],
        installedApps: [InstalledApplication],
        autoMatchSettings: StyleAutoMatchSettings = .init(),
        registry: KnownApplicationRegistry = .builtIn(),
        limit: Int = 8
    ) -> [StyleApplicationDisplay] {
        let appsByBundleID = Dictionary(
            installedApps.compactMap { app -> (String, InstalledApplication)? in
                guard let bundleID = normalizedBundleID(app.bundleID) else { return nil }
                return (bundleID, app)
            },
            uniquingKeysWith: { first, _ in first }
        )

        let explicit = selectedRules.compactMap { rule -> StyleApplicationDisplay? in
            guard let bundleID = normalizedBundleID(rule.bundleID) else { return nil }
            let installedApp = appsByBundleID[bundleID]
            return StyleApplicationDisplay(
                bundleID: rule.bundleID,
                name: installedApp?.name ?? rule.appName,
                iconPath: installedApp?.iconPath,
                source: .manual,
                badges: []
            )
        }
        let explicitBundleIDs = Set(allRules.compactMap { normalizedBundleID($0.bundleID) })
        let automatic = aiRouteCacheDisplays(
            selectedStyleID: selectedStyleID,
            autoMatchSettings: autoMatchSettings,
            appsByBundleID: appsByBundleID,
            excludingBundleIDs: explicitBundleIDs
        )
        return explicit + automatic
    }

    private static func aiRouteCacheDisplays(
        selectedStyleID: String,
        autoMatchSettings: StyleAutoMatchSettings,
        appsByBundleID: [String: InstalledApplication],
        excludingBundleIDs explicitBundleIDs: Set<String>
    ) -> [StyleApplicationDisplay] {
        guard autoMatchSettings.globalEnabled else { return [] }
        return autoMatchSettings.routeCache
            .sorted { lhs, rhs in
                lhs.value.lastUsedAt > rhs.value.lastUsedAt
            }
            .compactMap { key, entry -> StyleApplicationDisplay? in
                guard entry.styleID == selectedStyleID,
                      !entry.isExpired,
                      let identity = routeCacheIdentity(key),
                      !explicitBundleIDs.contains(identity.bundleID) else {
                    return nil
                }
                let installedApp = appsByBundleID[identity.bundleID]
                return StyleApplicationDisplay(
                    bundleID: identity.bundleID,
                    name: installedApp?.name ?? identity.displayName,
                    iconPath: installedApp?.iconPath,
                    source: .aiAutoMatch,
                    badges: [.temporary]
                )
            }
    }

    private static func normalizedBundleID(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let trimmed, !trimmed.isEmpty else { return nil }
        return trimmed.lowercased()
    }

    private static func routeCacheIdentity(_ key: String) -> (bundleID: String, displayName: String)? {
        if key.hasPrefix("bundle:") {
            let raw = String(key.dropFirst("bundle:".count))
            guard let bundleID = normalizedBundleID(raw) else { return nil }
            return (bundleID, raw)
        }
        if key.hasPrefix("app:") {
            let raw = String(key.dropFirst("app:".count))
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }
            return ("app:\(trimmed.lowercased())", trimmed)
        }
        return nil
    }
}

/// Sheet-local editable draft of a style's auto-match settings.
/// Keeps the SwiftUI state independent from repository round-trips until the
/// user explicitly saves the sheet.
struct StyleAutoMatchSheetDraft: Identifiable {
    let id = UUID()
    var description: String = ""
    var contextRoundsEnabled: Bool = true
    var contextRounds: Int = 3
    var contextTTLHours: Int = 6

    init() {}

    init(from profile: StyleProfileRecord?, settings: StyleAutoMatchSettings) {
        self.description = profile?.autoMatchDescription ?? ""
        self.contextRoundsEnabled = settings.contextRounds.enabled
        self.contextRounds = settings.contextRounds.maxRounds
        self.contextTTLHours = settings.contextRounds.ttlHours
    }
}

enum StyleAutoMatchSheetPresentation {
    static func makeDraft(
        from profile: StyleProfileRecord?,
        settings: StyleAutoMatchSettings
    ) -> StyleAutoMatchSheetDraft {
        StyleAutoMatchSheetDraft(from: profile, settings: settings)
    }
}

/// Pure presentation helper that turns the ViewModel state into the single
/// localized summary line shown on the style page (OpenSpec §4.5). Kept as a
/// standalone enum so it can be unit-tested without instantiating SwiftUI.
@MainActor
enum StyleAutoMatchSummary {
    static func label(for viewModel: StyleViewModel) -> String {
        let profile = viewModel.selectedProfile
        let globalEnabled = viewModel.autoMatchSettings.globalEnabled
        if !globalEnabled {
            return L10n.localize("style.app_routing.auto_match_summary.global_off", comment: "")
        }
        guard let profile else {
            return L10n.localize("style.app_routing.auto_match_summary.style_excluded", comment: "")
        }
        if !profile.allowAutoMatch {
            return L10n.localize("style.app_routing.auto_match_summary.style_excluded", comment: "")
        }
        let trimmedDescription = profile.autoMatchDescription?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if trimmedDescription.isEmpty {
            return L10n.localize("style.app_routing.auto_match_summary.no_description", comment: "")
        }
        return L10n.localize("style.app_routing.auto_match_summary.eligible", comment: "")
    }
}

private struct MarkdownPromptPreview: View {
    let markdown: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Self.blocks(from: markdown)) { block in
                blockView(block)
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .textSelection(.enabled)
    }

    @ViewBuilder
    private func blockView(_ block: MarkdownPreviewBlock) -> some View {
        switch block.kind {
        case .heading:
            Text(block.text)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(AppTheme.ColorToken.primaryText)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, block.index == 0 ? 0 : 4)
        case .bullet:
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("•")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(AppTheme.ColorToken.accent)
                inlineText(block.text)
                    .font(.system(size: 13))
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        case .paragraph:
            inlineText(block.text)
                .font(.system(size: 13))
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func inlineText(_ text: String) -> Text {
        var remaining = text[...]
        var output = Text("")
        while let start = remaining.range(of: "**"),
              let end = remaining[start.upperBound...].range(of: "**") {
            let prefix = String(remaining[..<start.lowerBound])
            let emphasized = String(remaining[start.upperBound..<end.lowerBound])
            output = output + Text(prefix) + Text(emphasized).bold()
            remaining = remaining[end.upperBound...]
        }
        return output + Text(String(remaining))
    }

    private static func blocks(from markdown: String) -> [MarkdownPreviewBlock] {
        let lines = markdown.components(separatedBy: .newlines)
        var blocks: [MarkdownPreviewBlock] = []
        var paragraph: [String] = []

        func flushParagraph() {
            let text = paragraph.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else {
                paragraph.removeAll()
                return
            }
            blocks.append(MarkdownPreviewBlock(index: blocks.count, kind: .paragraph, text: text))
            paragraph.removeAll()
        }

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty {
                flushParagraph()
            } else if trimmed.hasPrefix("## ") {
                flushParagraph()
                blocks.append(MarkdownPreviewBlock(index: blocks.count, kind: .heading, text: String(trimmed.dropFirst(3))))
            } else if trimmed.hasPrefix("- ") || trimmed.hasPrefix("– ") {
                flushParagraph()
                blocks.append(MarkdownPreviewBlock(index: blocks.count, kind: .bullet, text: String(trimmed.dropFirst(2))))
            } else {
                paragraph.append(trimmed)
            }
        }
        flushParagraph()
        return blocks
    }
}

private struct MarkdownPreviewBlock: Identifiable {
    enum Kind {
        case heading
        case paragraph
        case bullet
    }

    let index: Int
    let kind: Kind
    let text: String

    var id: Int { index }
}

private extension StyleProfileRecord {
    var iconName: String {
        switch id {
        case "builtin.original": return "text.alignleft"
        case "builtin.formal": return "doc.text"
        case "builtin.casual": return "bubble.left.and.bubble.right"
        case "builtin.energetic": return "sparkles"
        case "builtin.coding": return "chevron.left.forwardslash.chevron.right"
        case "builtin.email": return "envelope"
        default: return "slider.horizontal.3"
        }
    }
}
