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

struct StyleView: View {
    @ObservedObject var viewModel: StyleViewModel
    @State private var prompt = ""
    @State private var installedApps: [InstalledApplication] = []
    @State private var showingAppSelector = false
    @State private var showingSmartConfiguration = false
    @State private var smartConfigurationViewModel: SmartConfigurationViewModel

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
        }
        .background(AppTheme.ColorToken.pageBackground)
        .tint(AppTheme.ColorToken.accent)
        .actionFeedbackOverlay(
            message: viewModel.lastActionMessage,
            error: viewModel.lastError,
            onDismiss: viewModel.clearFeedback
        )
        .onAppear {
            viewModel.loadIfNeeded()
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
                onClose: dismissSmartConfiguration
            )
            .frame(width: 760, height: 640)
            .background(AppTheme.ColorToken.pageBackground)
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .shadow(color: .black.opacity(0.18), radius: 28, y: 12)
            .padding(24)
        }
        .transition(.opacity)
    }

    private func dismissSmartConfiguration() {
        if smartConfigurationViewModel.canCancel {
            smartConfigurationViewModel.cancel()
        }
        showingSmartConfiguration = false
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
                                    if let subtitle = profile.subtitle {
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
                    Text(String(format: L10n.localize("style.app_routing.select_app_for_style", comment: ""), viewModel.selectedProfile?.name ?? L10n.localize("style.view.title", comment: "")))
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
        .frame(minHeight: 520)
        .background(AppTheme.ColorToken.pageBackground)
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
        let appsByBundleID = Dictionary(
            installedApps.compactMap { app -> (String, InstalledApplication)? in
                guard let bundleID = app.bundleID else { return nil }
                return (bundleID, app)
            },
            uniquingKeysWith: { first, _ in first }
        )

        let explicit = selectedRules.map { rule -> StyleApplicationDisplay in
            let installedApp = appsByBundleID[rule.bundleID]
            return StyleApplicationDisplay(
                bundleID: rule.bundleID,
                name: installedApp?.name ?? rule.appName,
                iconPath: installedApp?.iconPath
            )
        }

        if !explicit.isEmpty {
            return explicit
        }

        guard let styleID = viewModel.selectedProfile?.id else { return [] }
        let existingBundleIDs = Set(viewModel.appStyleRules.map { $0.bundleID.lowercased() })
        return KnownApplicationRegistry.builtIn().entries
            .filter { $0.suggestedStyleID == styleID }
            .filter { !existingBundleIDs.contains($0.bundleID.lowercased()) }
            .prefix(8)
            .map { entry in
                let installedApp = installedApps.first {
                    $0.bundleID?.caseInsensitiveCompare(entry.bundleID) == .orderedSame
                }
                return StyleApplicationDisplay(
                    bundleID: entry.bundleID,
                    name: installedApp?.name ?? entry.displayName,
                    iconPath: installedApp?.iconPath
                )
            }
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

private struct StyleApplicationDisplay: Identifiable {
    let bundleID: String
    let name: String
    let iconPath: String?

    var id: String { bundleID }
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
