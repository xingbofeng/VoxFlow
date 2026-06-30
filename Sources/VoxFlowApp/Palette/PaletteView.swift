import AppKit
import FuzzyMatch
import SwiftUI

struct PaletteView: View {
    @ObservedObject var viewModel: PaletteViewModel
    @FocusState private var isSearchFocused: Bool
    var onCommand: (PaletteCommand) -> Void = { _ in }
    var onDefaultAction: (PaletteDefaultAction) -> Void = { _ in }
    var onAssetAction: (AssetAction, AssetItem) -> Void = { _, _ in }
    var onFileAction: (PaletteFileAction, PaletteFileItem) -> Void = { _, _ in }
    var onOpenApplication: (String, PaletteRootItemID) -> Void = { _, _ in }
    var onAskAI: (String) -> Void = { _ in }
    var onTranslate: (String) -> Void = { _ in }
    var onActivateQuicklink: (PaletteQuicklink, String) -> Void = { _, _ in }
    var onOpenURL: (String) -> Void = { _ in }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            VStack(spacing: 0) {
                searchHeader
                Divider()
                content
                Divider()
                footer
            }

            if viewModel.isActionPanelPresented {
                actionMenu
                    .padding(.trailing, 14)
                    .padding(.bottom, 48)
                    .transition(.opacity)
            }

            if viewModel.isTypeFilterPresented {
                typeFilterPanel
                    .padding(.trailing, 24)
                    .padding(.top, 64)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    .transition(.opacity)
            }
        }
        .frame(width: 760, height: 470)
        .onAppear {
            focusSearchField()
        }
        .onChange(of: viewModel.searchFocusRequestID) { _, _ in
            focusSearchField()
        }
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(nsColor: .windowBackgroundColor))
        )
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var searchHeader: some View {
        HStack(spacing: 12) {
            if viewModel.mode != .home {
                Button {
                    viewModel.goBack()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 17, weight: .semibold))
                }
                .buttonStyle(.borderless)
                .frame(width: 34, height: 34)
                .background(Color(nsColor: .controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }

            TextField(
                viewModel.searchPlaceholder,
                text: Binding(
                    get: { viewModel.searchText },
                    set: { text in
                        try? viewModel.updateSearchText(text)
                    }
                )
            )
            .textFieldStyle(.plain)
            .font(.system(size: 23, weight: .regular))
            .focused($isSearchFocused)
            .onSubmit {
                performPrimaryAction()
            }

            if viewModel.mode == .recentAssets {
                typeFilterMenu
            }
        }
        .padding(.horizontal, 20)
        .frame(height: 58)
    }

    private func focusSearchField() {
        isSearchFocused = false
        DispatchQueue.main.async {
            isSearchFocused = true
        }
        Task { @MainActor in
            await Task.yield()
            isSearchFocused = true
            try? await Task.sleep(nanoseconds: 50_000_000)
            isSearchFocused = true
        }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.mode {
        case .home:
            homeResultList
        case .recentAssets:
            assetBrowser
        case .fileSearch:
            fileBrowser
        }
    }

    private var homeResultList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(viewModel.rootSections.enumerated()), id: \.offset) { _, section in
                        SectionHeader(title(for: section.kind))
                        if section.kind == .favoriteHint {
                            favoriteHintRow
                        } else {
                            ForEach(section.items) { item in
                                let index = rootItemIndex(for: item)
                                rootResultButton(item, index: index)
                                    .id(item.id)
                            }
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 14)
                .id(viewModel.homeResultListIdentity)
            }
            .onChange(of: viewModel.selectedHomeResultIndex) { _, _ in
                scrollHomeSelectionIntoView(proxy)
            }
        }
    }

    private func rootResultButton(_ item: PaletteRootItem, index: Int) -> some View {
        let isSelected = viewModel.selectedRootItemID == item.id
        return Button {
            viewModel.selectHomeResult(at: index)
            performPrimaryAction()
        } label: {
            HStack(spacing: 13) {
                rootIcon(for: item)
                PaletteHighlightedText(text: item.title, query: viewModel.searchText, size: 16, weight: .medium)
                    .lineLimit(1)
                PaletteHighlightedText(
                    text: item.subtitle,
                    query: viewModel.searchText,
                    size: 14,
                    weight: .regular,
                    color: .secondary
                )
                    .lineLimit(1)
                Spacer()
                Text(kindTitle(for: item.kind))
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 15)
            .frame(height: 45)
            .contentShape(Rectangle())
        }
        .buttonStyle(PaletteRowButtonStyle())
        .focusable(false)
        .background {
            PaletteRowSelectionHighlight(isSelected: isSelected)
        }
    }

    private var favoriteHintRow: some View {
        HStack(spacing: 13) {
            Image(systemName: "star")
                .font(.system(size: 17, weight: .medium))
                .frame(width: 28, height: 28)
                .foregroundStyle(.secondary)
            Text(L10n.localize("palette.assets.empty_pinned_title", comment: ""))
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(.secondary)
            Text(L10n.localize("palette.assets.empty_pinned_subtitle", comment: ""))
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.horizontal, 15)
        .frame(height: 45)
    }

    private var assetBrowser: some View {
        HStack(spacing: 0) {
            assetList
                .frame(width: 300)
            Divider()
            assetPreviewPane
        }
    }

    private var assetList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 6) {
                    SectionHeader(L10n.localize("palette.section.today", comment: ""))
                    ForEach(Array(viewModel.assets.enumerated()), id: \.element.id) { index, asset in
                        let isSelected = viewModel.selectedAssetIndex == index
                        Button {
                            viewModel.selectAsset(at: index)
                        } label: {
                            HStack(spacing: 12) {
                                assetIcon(asset)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(asset.title)
                                        .font(.system(size: 16, weight: .medium))
                                        .lineLimit(1)
                                    Text(assetSubtitle(asset))
                                        .font(.system(size: 12))
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                                Spacer()
                            }
                            .padding(.horizontal, 14)
                            .frame(height: 48)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(PaletteRowButtonStyle())
                        .focusable(false)
                        .background {
                            PaletteRowSelectionHighlight(isSelected: isSelected)
                        }
                        .id(asset.id)
                        .simultaneousGesture(
                            TapGesture(count: 2).onEnded {
                                viewModel.selectAsset(at: index)
                                viewModel.presentActionPanel()
                            }
                        )
                        .overlay {
                            RightClickActionView {
                                viewModel.selectAsset(at: index)
                                viewModel.presentActionPanel()
                            }
                        }
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 14)
            }
            .onChange(of: viewModel.selectedAssetIndex) { _, _ in
                scrollAssetSelectionIntoView(proxy)
            }
        }
    }

    private func scrollHomeSelectionIntoView(_ proxy: ScrollViewProxy) {
        guard let item = viewModel.selectedRootItem else { return }
        withAnimation(.easeOut(duration: 0.12)) {
            proxy.scrollTo(
                item.id,
                anchor: paletteScrollAnchor(
                    index: viewModel.selectedHomeResultIndex,
                    count: viewModel.visibleRootItems.count
                )
            )
        }
    }

    private func scrollAssetSelectionIntoView(_ proxy: ScrollViewProxy) {
        guard viewModel.assets.indices.contains(viewModel.selectedAssetIndex) else { return }
        let asset = viewModel.assets[viewModel.selectedAssetIndex]
        withAnimation(.easeOut(duration: 0.12)) {
            proxy.scrollTo(
                asset.id,
                anchor: paletteScrollAnchor(
                    index: viewModel.selectedAssetIndex,
                    count: viewModel.assets.count
                )
            )
        }
    }

    private func scrollFileSelectionIntoView(_ proxy: ScrollViewProxy) {
        guard viewModel.fileResults.indices.contains(viewModel.selectedFileIndex) else { return }
        let file = viewModel.fileResults[viewModel.selectedFileIndex]
        withAnimation(.easeOut(duration: 0.12)) {
            proxy.scrollTo(
                file.id,
                anchor: paletteScrollAnchor(
                    index: viewModel.selectedFileIndex,
                    count: viewModel.fileResults.count
                )
            )
        }
    }

    private func paletteScrollAnchor(index: Int, count: Int) -> UnitPoint {
        if index == 0 {
            return .top
        }
        if index == count - 1 {
            return .bottom
        }
        return .center
    }

    private var assetPreviewPane: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let asset = viewModel.selectedAsset {
                previewContent(for: asset)
                Divider()
                assetInformation(for: asset)
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "tray")
                        .font(.system(size: 40))
                        .foregroundStyle(.secondary)
                    Text(L10n.localize("palette.assets.empty", comment: ""))
                        .font(.system(size: 16))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var fileBrowser: some View {
        HStack(spacing: 0) {
            fileList
                .frame(width: 340)
            Divider()
            filePreviewPane
        }
    }

    private var fileList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 6) {
                    fileSectionHeader
                    ForEach(Array(viewModel.fileResults.enumerated()), id: \.element.id) { index, file in
                        let isSelected = viewModel.selectedFileIndex == index
                        Button {
                            viewModel.selectFile(at: index)
                        } label: {
                            HStack(spacing: 12) {
                                fileIcon(file)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(file.name)
                                        .font(.system(size: 16, weight: .medium))
                                        .lineLimit(1)
                                    Text(file.displayPath)
                                        .font(.system(size: 12))
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                                Spacer()
                            }
                            .padding(.horizontal, 14)
                            .frame(height: 50)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(PaletteRowButtonStyle())
                        .focusable(false)
                        .background {
                            PaletteRowSelectionHighlight(isSelected: isSelected)
                        }
                        .id(file.id)
                        .simultaneousGesture(
                            TapGesture(count: 2).onEnded {
                                viewModel.selectFile(at: index)
                                onFileAction(.open, file)
                            }
                        )
                        .overlay {
                            RightClickActionView {
                                viewModel.selectFile(at: index)
                                viewModel.presentActionPanel()
                            }
                        }
                    }

                    if viewModel.fileResults.isEmpty {
                        if viewModel.fileSearchState == .searching {
                            fileSearchingRow
                        } else {
                            fileEmptyRow
                        }
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 14)
            }
            .onChange(of: viewModel.selectedFileIndex) { _, _ in
                scrollFileSelectionIntoView(proxy)
            }
            .onChange(of: viewModel.fileResults.map(\.id).joined(separator: "|")) { _, _ in
                scrollFileSelectionIntoView(proxy)
            }
        }
    }

    private var filePreviewPane: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let file = viewModel.selectedFile {
                VStack(alignment: .leading, spacing: 18) {
                    HStack(spacing: 14) {
                        filePreviewIcon(file)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(file.name)
                                .font(.system(size: 20, weight: .semibold))
                                .lineLimit(2)
                            Text(file.displayPath)
                                .font(.system(size: 13))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }

                    Divider()

                    if let metadata = viewModel.selectedFileMetadata {
                        fileMetadataRows(metadata)
                    } else {
                        Text(L10n.localize("palette.files.metadata.loading", comment: ""))
                            .font(.system(size: 14))
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(22)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            } else if viewModel.fileSearchState == .searching {
                VStack(spacing: 12) {
                    ProgressView()
                        .controlSize(.regular)
                    Text(L10n.localize("palette.files.section.searching", comment: ""))
                        .font(.system(size: 16))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.system(size: 40))
                        .foregroundStyle(.secondary)
                    Text(L10n.localize("palette.files.empty", comment: ""))
                        .font(.system(size: 16))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private func fileMetadataRows(_ metadata: PaletteFileMetadata) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            fileMetadataRow(
                label: L10n.localize("palette.files.metadata.name", comment: ""),
                value: metadata.name
            )
            fileMetadataRow(
                label: L10n.localize("palette.files.metadata.where", comment: ""),
                value: metadata.path
            )
            if let kind = metadata.kind {
                fileMetadataRow(
                    label: L10n.localize("palette.files.metadata.kind", comment: ""),
                    value: kind
                )
            }
            if let size = metadata.sizeDescription {
                fileMetadataRow(
                    label: L10n.localize("palette.files.metadata.size", comment: ""),
                    value: size
                )
            }
            if let createdAt = metadata.createdAt {
                fileMetadataRow(
                    label: L10n.localize("palette.files.metadata.created", comment: ""),
                    value: fileMetadataDateFormatter.string(from: createdAt)
                )
            }
            if let modifiedAt = metadata.modifiedAt {
                fileMetadataRow(
                    label: L10n.localize("palette.files.metadata.modified", comment: ""),
                    value: fileMetadataDateFormatter.string(from: modifiedAt)
                )
            }
        }
    }

    private func fileMetadataRow(label: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(label)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 72, alignment: .leading)
            Text(value)
                .font(.system(size: 13))
                .lineLimit(2)
                .textSelection(.enabled)
        }
    }

    private var fileSectionHeader: some View {
        HStack(spacing: 8) {
            Text(fileSectionTitle)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.secondary)
            if viewModel.fileSearchState == .searching {
                ProgressView()
                    .controlSize(.small)
            }
        }
        .padding(.horizontal, 10)
        .padding(.top, 4)
    }

    private var fileSectionTitle: String {
        switch viewModel.fileSearchState {
        case .showingRecent:
            return L10n.localize("palette.files.section.recent", comment: "")
        case .searching:
            return L10n.localize("palette.files.section.searching", comment: "")
        case .timedOut:
            return L10n.localize("palette.files.section.partial", comment: "")
        case .idle, .completed, .failed:
            return L10n.localize("palette.files.section.results", comment: "")
        }
    }

    private var fileSearchingRow: some View {
        HStack(spacing: 13) {
            ProgressView()
                .controlSize(.small)
                .frame(width: 28, height: 28)
            Text(L10n.localize("palette.files.section.searching", comment: ""))
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.horizontal, 15)
        .frame(height: 50)
    }

    private var fileEmptyRow: some View {
        HStack(spacing: 13) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 17, weight: .medium))
                .frame(width: 28, height: 28)
                .foregroundStyle(.secondary)
            Text(L10n.localize("palette.files.empty", comment: ""))
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.horizontal, 15)
        .frame(height: 50)
    }

    private var footer: some View {
        HStack(spacing: 12) {
            footerSelectionLabel
            Spacer()
            Button(viewModel.footerPrimaryActionTitle) {
                performPrimaryAction()
            }
            .buttonStyle(.borderless)
            .font(.system(size: 15, weight: .semibold))

            Text("↩")
                .keyboardBadge()

            Divider()
                .frame(height: 24)

            Button(L10n.localize("palette.action.menu", comment: "")) {
                viewModel.toggleActionPanel()
            }
            .buttonStyle(.borderless)
            .keyboardShortcut("k", modifiers: .command)
            .font(.system(size: 15, weight: .semibold))
            .accessibilityLabel(L10n.localize("palette.action.menu", comment: ""))
            Text("⌘")
                .keyboardBadge()
            Text("K")
                .keyboardBadge()
        }
        .padding(.horizontal, 18)
        .frame(height: 44)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.65))
    }

    private var footerSelectionLabel: some View {
        HStack(spacing: 8) {
            footerSelectionIcon
                .frame(width: 20, height: 20)
            Text(viewModel.footerSelectionTitle)
                .lineLimit(1)
        }
        .font(.system(size: 14, weight: .medium))
        .foregroundStyle(.secondary)
    }

    @ViewBuilder
    private var footerSelectionIcon: some View {
        if viewModel.mode == .home, let item = viewModel.selectedRootItem {
            rootIcon(for: item)
                .scaleEffect(0.72)
        } else if viewModel.mode == .recentAssets, let asset = viewModel.selectedAsset {
            assetIcon(asset)
                .scaleEffect(0.67)
        } else if viewModel.mode == .fileSearch, let file = viewModel.selectedFile {
            fileIcon(file)
                .scaleEffect(0.67)
        } else {
            Image(systemName: "tray.full")
        }
    }

    private var typeFilterMenu: some View {
        Button {
            viewModel.toggleTypeFilter()
        } label: {
            HStack(spacing: 10) {
                Text(viewModel.selectedTypeFilter.title)
                Image(systemName: viewModel.isTypeFilterPresented ? "chevron.up" : "chevron.down")
            }
            .font(.system(size: 15, weight: .medium))
            .frame(width: 170, height: 38)
        }
        .buttonStyle(.plain)
        .keyboardShortcut("p", modifiers: .command)
    }

    private var typeFilterPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(L10n.localize("palette.search.filter_placeholder", comment: ""))
                .font(.system(size: 18))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 18)
                .frame(height: 54)
            Divider()
            ForEach(viewModel.typeFilters, id: \.self) { filter in
                Button {
                    try? viewModel.selectTypeFilter(filter)
                } label: {
                    Text(filter.title)
                        .font(.system(size: 18, weight: .medium))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 18)
                        .frame(height: 44)
                        .background(
                            RoundedRectangle(cornerRadius: 14)
                                .fill(filter == viewModel.selectedTypeFilter ? Color(nsColor: .separatorColor).opacity(0.52) : .clear)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 10)
        .frame(width: 250)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color(nsColor: .windowBackgroundColor))
                .shadow(color: .black.opacity(0.14), radius: 22, x: 0, y: 12)
        )
    }

    private var actionMenu: some View {
        VStack(alignment: .leading, spacing: 0) {
            if viewModel.mode == .home {
                ForEach(Array(viewModel.rootActionPanelActionsForSelectedRootItem().enumerated()), id: \.element.rawValue) { index, action in
                    rootActionMenuRow(action: action) {
                        performKeyboardAction(viewModel.performRootAction(action))
                    }
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(index == viewModel.selectedActionIndex ? Color(nsColor: .separatorColor).opacity(0.52) : .clear)
                    )
                }
            } else if viewModel.mode == .recentAssets,
               let asset = viewModel.selectedAsset,
               let actions = try? viewModel.actionPanelActionsForSelectedAsset() {
                ForEach(Array(actions.enumerated()), id: \.element.rawValue) { index, action in
                    actionMenuRow(action: action) {
                        onAssetAction(action, asset)
                        if action == .delete {
                            try? viewModel.reloadAssets()
                        }
                        viewModel.isActionPanelPresented = false
                    }
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(index == viewModel.selectedActionIndex ? Color(nsColor: .separatorColor).opacity(0.52) : .clear)
                    )
                }
            } else if viewModel.mode == .fileSearch, let file = viewModel.selectedFile {
                ForEach(Array(viewModel.fileActionPanelActionsForSelectedFile().enumerated()), id: \.element.rawValue) { index, action in
                    fileActionMenuRow(action: action) {
                        onFileAction(action, file)
                        viewModel.isActionPanelPresented = false
                    }
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(index == viewModel.selectedActionIndex ? Color(nsColor: .separatorColor).opacity(0.52) : .clear)
                    )
                }
            }
        }
        .padding(.vertical, 10)
        .frame(width: 360, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color(nsColor: .windowBackgroundColor))
                .shadow(color: .black.opacity(0.14), radius: 22, x: 0, y: 12)
        )
    }

    private func rootActionMenuRow(action: PaletteRootAction, perform: @escaping () -> Void) -> some View {
        Button(action: perform) {
            HStack(spacing: 12) {
                Image(systemName: action.systemImageName)
                    .font(.system(size: 17, weight: .medium))
                    .frame(width: 24)
                Text(action.displayTitle)
                    .font(.system(size: 16, weight: .medium))
                Spacer()
                ForEach(action.shortcutBadges, id: \.self) { badge in
                    Text(badge)
                        .keyboardBadge()
                }
            }
            .foregroundStyle(action == .removeFavorite ? .red : .primary)
            .padding(.horizontal, 18)
            .frame(height: 42)
            .contentShape(Rectangle())
        }
        .buttonStyle(PaletteActionMenuButtonStyle(isDestructive: action == .removeFavorite))
    }

    private func actionMenuRow(action: AssetAction, perform: @escaping () -> Void) -> some View {
        Button(action: perform) {
            HStack(spacing: 12) {
                Image(systemName: action.systemImageName)
                    .font(.system(size: 17, weight: .medium))
                    .frame(width: 24)
                Text(action.displayTitle)
                    .font(.system(size: 16, weight: .medium))
                Spacer()
                ForEach(action.shortcutBadges, id: \.self) { badge in
                    Text(badge)
                        .keyboardBadge()
                }
            }
            .foregroundStyle(action == .delete ? .red : .primary)
            .padding(.horizontal, 18)
            .frame(height: 42)
            .contentShape(Rectangle())
        }
        .buttonStyle(PaletteActionMenuButtonStyle(isDestructive: action == .delete))
    }

    private func fileActionMenuRow(action: PaletteFileAction, perform: @escaping () -> Void) -> some View {
        Button(action: perform) {
            HStack(spacing: 12) {
                Image(systemName: action.systemImageName)
                    .font(.system(size: 17, weight: .medium))
                    .frame(width: 24)
                Text(action.displayTitle)
                    .font(.system(size: 16, weight: .medium))
                Spacer()
                ForEach(action.shortcutBadges, id: \.self) { badge in
                    Text(badge)
                        .keyboardBadge()
                }
            }
            .padding(.horizontal, 18)
            .frame(height: 42)
            .contentShape(Rectangle())
        }
        .buttonStyle(PaletteActionMenuButtonStyle())
    }

    private func activate(_ command: PaletteCommand) {
        do {
            try viewModel.activate(command)
        } catch {
            onCommand(command)
        }
    }

    private func performPrimaryAction() {
        switch viewModel.mode {
        case .home:
            performKeyboardAction(viewModel.primaryKeyboardAction())
            return
        case .fileSearch:
            guard let file = viewModel.selectedFile else { return }
            onFileAction(.open, file)
            return
        case .recentAssets:
            break
        }
        guard let asset = viewModel.selectedAsset else {
            if let command = viewModel.selectedHomeResult?.command {
                activate(command)
            }
            return
        }
        let action = viewModel.defaultAction(for: asset)
        onDefaultAction(action)
        if case let .assetAction(assetAction) = action {
            onAssetAction(assetAction, asset)
        }
    }

    private func performKeyboardAction(_ action: PaletteKeyboardAction) {
        switch action {
        case .none:
            break
        case let .activateCommand(command):
            activate(command)
        case let .openApplication(path, itemID):
            onOpenApplication(path, itemID)
        case let .performAssetAction(defaultAction, assetID):
            guard let asset = viewModel.assets.first(where: { $0.id == assetID }) else { return }
            onDefaultAction(defaultAction)
            if case let .assetAction(assetAction) = defaultAction {
                onAssetAction(assetAction, asset)
            }
        case let .performFileAction(action, fileID):
            guard let file = viewModel.fileResults.first(where: { $0.id == fileID }) else { return }
            onFileAction(action, file)
        case let .askAI(prompt):
            onAskAI(prompt)
        case let .translate(text):
            onTranslate(text)
        case let .activateQuicklink(link, query):
            onActivateQuicklink(link, query)
        case let .openURL(urlString):
            onOpenURL(urlString)
        }
    }

    private func commandIcon(for command: PaletteCommand) -> some View {
        let systemName: String
        switch command {
        case .recentAssets, .assetHistory:
            systemName = "tray.full"
        case .searchFiles:
            systemName = "doc.text.magnifyingglass"
        case .screenshotOCR:
            systemName = "text.viewfinder"
        case .startAgentCompose:
            systemName = "quote.bubble"
        case .startAgentDispatch:
            systemName = "terminal"
        case .startDictation:
            systemName = "mic"
        }
        return Image(systemName: systemName)
            .font(.system(size: 17, weight: .medium))
            .frame(width: 28, height: 28)
            .foregroundStyle(Color(red: 0.03, green: 0.46, blue: 0.38))
    }

    @ViewBuilder
    private func rootIcon(for item: PaletteRootItem) -> some View {
        switch item.icon {
        case let .systemImage(systemName):
            Image(systemName: systemName)
                .font(.system(size: 17, weight: .medium))
                .frame(width: 28, height: 28)
                .foregroundStyle(Color(red: 0.03, green: 0.46, blue: 0.38))
        case let .quicklinkImage(name):
            if let url = quicklinkIconURL(named: name),
            let image = NSImage(contentsOf: url) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 24, height: 24)
                    .frame(width: 28, height: 28)
            } else {
                Image(systemName: "globe")
                    .font(.system(size: 17, weight: .medium))
                    .frame(width: 28, height: 28)
                    .foregroundStyle(Color(red: 0.03, green: 0.46, blue: 0.38))
            }
        case let .websiteIcon(pageURL):
            AsyncImage(url: faviconURL(for: pageURL)) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFit()
                        .frame(width: 22, height: 22)
                        .frame(width: 28, height: 28)
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                case .empty, .failure:
                    websiteIconPlaceholder(for: pageURL)
                @unknown default:
                    websiteIconPlaceholder(for: pageURL)
                }
            }
        case let .applicationIcon(path):
            if let image = NSImage(contentsOfFile: path) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 28, height: 28)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            } else {
                Image(systemName: "app")
                    .font(.system(size: 17, weight: .medium))
                    .frame(width: 28, height: 28)
                    .foregroundStyle(Color(red: 0.03, green: 0.46, blue: 0.38))
            }
        }
    }

    private func quicklinkIconURL(named name: String) -> URL? {
        VoxFlowAppResourceBundle.url(
            forResource: name,
            withExtension: "png",
            subdirectory: "QuicklinkIcons"
        ) ?? VoxFlowAppResourceBundle.url(
            forResource: name,
            withExtension: "png"
        )
    }

    private func faviconURL(for pageURL: String) -> URL? {
        guard let url = URL(string: pageURL),
              let host = url.host else {
            return nil
        }
        let encodedHost = host.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? host
        return URL(string: "https://www.google.com/s2/favicons?domain=\(encodedHost)&sz=64")
    }

    private func websiteIconPlaceholder(for pageURL: String) -> some View {
        let host = URL(string: pageURL)?.host ?? pageURL
        let initial = host
            .replacingOccurrences(of: "www.", with: "")
            .prefix(1)
            .uppercased()
        return ZStack {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color(red: 0.03, green: 0.46, blue: 0.38).opacity(0.11))
            Text(initial.isEmpty ? "?" : initial)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color(red: 0.03, green: 0.46, blue: 0.38))
        }
        .frame(width: 22, height: 22)
        .frame(width: 28, height: 28)
    }

    private func rootItemIndex(for item: PaletteRootItem) -> Int {
        viewModel.visibleRootItems.firstIndex { $0.id == item.id } ?? 0
    }

    private func title(for sectionKind: PaletteRootSectionKind) -> String {
        switch sectionKind {
        case .favorites, .favoriteHint:
            return L10n.localize("palette.section.favorites", comment: "")
        case .suggestions:
            return L10n.localize("palette.section.suggestions", comment: "")
        case .searchResults:
            return L10n.localize("palette.section.results", comment: "")
        }
    }

    private func kindTitle(for kind: PaletteRootItemKind) -> String {
        switch kind {
        case .command:
            return L10n.localize("palette.item_kind.command", comment: "")
        case .application:
            return L10n.localize("palette.item_kind.application", comment: "")
        case .ai:
            return "AI"
        case .quicklink:
            return L10n.localize("palette.item_kind.quicklink", comment: "")
        case .link:
            return L10n.localize("palette.item_kind.link", comment: "")
        }
    }

    private func assetIcon(_ asset: AssetItem) -> some View {
        Group {
            switch asset.contentType {
            case .text:
                Image(systemName: asset.source == .dictation ? "waveform" : "doc.text")
            case .image:
                if let imagePath = asset.imagePath,
                   let image = NSImage(contentsOfFile: imagePath) {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFill()
                } else {
                    Image(systemName: "photo")
                }
            case .file:
                Image(systemName: "doc")
            case .link:
                Image(systemName: "link")
            case .color:
                Image(systemName: "paintpalette")
            }
        }
        .font(.system(size: 18, weight: .medium))
        .frame(width: 30, height: 30)
        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
        .foregroundStyle(Color(red: 0.03, green: 0.46, blue: 0.38))
    }

    private func fileIcon(_ file: PaletteFileItem) -> some View {
        Group {
            if FileManager.default.fileExists(atPath: file.url.path) {
                Image(nsImage: NSWorkspace.shared.icon(forFile: file.url.path))
                    .resizable()
                    .scaledToFit()
            } else {
                Image(systemName: file.isDirectory ? "folder" : "doc")
            }
        }
        .font(.system(size: 18, weight: .medium))
        .frame(width: 30, height: 30)
        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
        .foregroundStyle(Color(red: 0.03, green: 0.46, blue: 0.38))
    }

    @ViewBuilder
    private func filePreviewIcon(_ file: PaletteFileItem) -> some View {
        if case let .image(url) = viewModel.selectedFileMetadata?.previewKind,
           let image = NSImage(contentsOf: url) {
            Image(nsImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: 54, height: 54)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        } else if FileManager.default.fileExists(atPath: file.url.path) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: file.url.path))
                .resizable()
                .scaledToFit()
                .frame(width: 54, height: 54)
        } else {
            Image(systemName: file.isDirectory ? "folder" : "doc")
                .font(.system(size: 38, weight: .medium))
                .frame(width: 54, height: 54)
                .foregroundStyle(Color(red: 0.03, green: 0.46, blue: 0.38))
        }
    }

    private var fileMetadataDateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }

    private func assetSubtitle(_ asset: AssetItem) -> String {
        switch asset.source {
        case .dictation:
            return L10n.localize("palette.asset.source.dictation", comment: "")
        case .screenshot:
            return L10n.localize("palette.asset.source.screenshot", comment: "")
        case .clipboard:
            return L10n.localize("palette.asset.source.clipboard", comment: "")
        }
    }

    @ViewBuilder
    private func previewContent(for asset: AssetItem) -> some View {
        if asset.contentType == .image,
           let imagePath = asset.imagePath,
           let image = NSImage(contentsOfFile: imagePath) {
            Image(nsImage: image)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: .infinity, maxHeight: 210)
                .padding(16)
        } else {
            ScrollView(.vertical) {
                Text(asset.previewText ?? asset.text ?? asset.url ?? asset.filePath ?? asset.colorValue ?? asset.title)
                    .font(.system(size: 14))
                    .lineSpacing(4)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .padding(18)
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .frame(height: 210, alignment: .topLeading)
        }
    }

    private func assetInformation(for asset: AssetItem) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L10n.localize("palette.asset.info_title", comment: ""))
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.secondary)
            infoRow(L10n.localize("palette.asset.info_source_label", comment: ""), assetSubtitle(asset))
            infoRow(L10n.localize("palette.asset.info_content_type_label", comment: ""), contentTypeTitle(asset.contentType))
            if let imagePath = asset.imagePath {
                infoRow(L10n.localize("palette.asset.info_image_path_label", comment: ""), imagePath)
            }
            if let filePath = asset.filePath {
                infoRow(L10n.localize("palette.asset.info_file_path_label", comment: ""), filePath)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func infoRow(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .lineLimit(1)
        }
        .font(.system(size: 14))
    }

    private func contentTypeTitle(_ contentType: AssetContentType) -> String {
        switch contentType {
        case .text:
            return L10n.localize("palette.content_type.text", comment: "")
        case .image:
            return L10n.localize("palette.content_type.image", comment: "")
        case .file:
            return L10n.localize("palette.content_type.file", comment: "")
        case .link:
            return L10n.localize("palette.content_type.link", comment: "")
        case .color:
            return L10n.localize("palette.content_type.color", comment: "")
        }
    }

}

private struct PaletteHighlightedText: View {
    private static let matcher = FuzzyMatcher()
    private static let highlightColor = Color(red: 0.03, green: 0.46, blue: 0.38)

    let text: String
    let query: String
    let size: CGFloat
    let weight: Font.Weight
    var color: Color = .primary

    var body: some View {
        Text(attributedText)
    }

    static func matchesVisibleText(_ text: String, query: String) -> Bool {
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedQuery.isEmpty else { return false }
        return matcher.highlight(text, against: normalizedQuery) != nil
    }

    private var attributedText: AttributedString {
        var result = AttributedString(text)
        result.foregroundColor = color
        result.font = .system(size: size, weight: weight)

        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedQuery.isEmpty,
              let ranges = Self.matcher.highlight(text, against: normalizedQuery)
        else {
            return result
        }

        var highlightAttributes = AttributeContainer()
        highlightAttributes.foregroundColor = Self.highlightColor
        highlightAttributes.font = .system(size: size, weight: .semibold)
        for range in ranges {
            guard let lower = AttributedString.Index(range.lowerBound, within: result),
                  let upper = AttributedString.Index(range.upperBound, within: result) else {
                continue
            }
            result[lower..<upper].mergeAttributes(highlightAttributes)
        }
        return result
    }
}

private struct SectionHeader: View {
    let title: String

    init(_ title: String) {
        self.title = title
    }

    var body: some View {
        Text(title)
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 10)
            .padding(.top, 4)
    }
}

private struct PaletteRowButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(
                        configuration.isPressed
                            ? Color(nsColor: .separatorColor).opacity(0.45)
                            : .clear
                    )
            )
    }
}

private struct PaletteRowSelectionHighlight: View {
    let isSelected: Bool

    var body: some View {
        RoundedRectangle(cornerRadius: 12)
            .fill(isSelected ? Color.accentColor.opacity(0.18) : .clear)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(
                        isSelected ? Color.accentColor.opacity(0.26) : .clear,
                        lineWidth: isSelected ? 1 : 0
                    )
            )
    }
}

private struct PaletteActionMenuButtonStyle: ButtonStyle {
    var isDestructive = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(configuration.isPressed ? Color(nsColor: .separatorColor).opacity(0.45) : .clear)
            )
    }
}

private struct RightClickActionView: NSViewRepresentable {
    var onRightClick: () -> Void

    func makeNSView(context: Context) -> CaptureView {
        let view = CaptureView()
        view.onRightClick = onRightClick
        return view
    }

    func updateNSView(_ nsView: CaptureView, context: Context) {
        nsView.onRightClick = onRightClick
    }

    final class CaptureView: NSView {
        var onRightClick: () -> Void = {}

        override func hitTest(_ point: NSPoint) -> NSView? {
            guard let event = window?.currentEvent ?? NSApp.currentEvent,
                  event.type == .rightMouseDown || event.type == .rightMouseUp else {
                return nil
            }
            return super.hitTest(point)
        }

        override func rightMouseDown(with event: NSEvent) {
            onRightClick()
        }
    }
}

private extension AssetAction {
    var systemImageName: String {
        switch self {
        case .paste, .pasteAndKeepOpen, .pasteOCRText, .pasteFile, .pasteFilePath:
            return "arrow.turn.down.left"
        case .copy, .copyImage, .copyOCRText, .copyFile, .copyFilePath:
            return "doc.on.doc"
        case .quickLook:
            return "eye"
        case .saveAsFile:
            return "square.and.arrow.down"
        case .delete:
            return "trash"
        case .pin:
            return "pin"
        case .rerunOCR:
            return "text.viewfinder"
        case .attachToAIChat:
            return "sparkles"
        }
    }

    var shortcutBadges: [String] {
        switch self {
        case .paste:
            return ["↩"]
        case .copy:
            return ["⌘", "↩"]
        case .pasteAndKeepOpen:
            return ["⌥", "↩"]
        case .quickLook:
            return ["⌘", "Y"]
        case .saveAsFile:
            return ["⇧", "⌘", "S"]
        case .delete:
            return ["⌃", "X"]
        case .pasteFilePath:
            return ["↩"]
        case .copyFilePath:
            return ["⌘", "↩"]
        default:
            return []
        }
    }
}

private extension PaletteFileAction {
    var systemImageName: String {
        switch self {
        case .open:
            return "arrow.up.right.square"
        case .showInFinder:
            return "folder"
        case .quickLook:
            return "eye"
        case .copyPath, .copyName:
            return "doc.on.doc"
        }
    }

    var shortcutBadges: [String] {
        switch self {
        case .open:
            return ["↩"]
        case .copyPath:
            return ["⌘", "↩"]
        case .quickLook:
            return ["⌘", "Y"]
        default:
            return []
        }
    }
}

private extension View {
    func keyboardBadge() -> some View {
        self
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.secondary)
            .frame(minWidth: 28, minHeight: 26)
            .background(Color(nsColor: .separatorColor).opacity(0.25))
            .clipShape(RoundedRectangle(cornerRadius: 7))
    }
}
