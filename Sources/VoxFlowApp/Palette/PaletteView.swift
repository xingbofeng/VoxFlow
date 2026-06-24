import AppKit
import SwiftUI

struct PaletteView: View {
    @ObservedObject var viewModel: PaletteViewModel
    var onCommand: (PaletteCommand) -> Void = { _ in }
    var onDefaultAction: (PaletteDefaultAction) -> Void = { _ in }
    var onAssetAction: (AssetAction, AssetItem) -> Void = { _, _ in }

    private let homeSearchPlaceholder = "搜索应用、命令、资产..."
    private let assetSearchPlaceholder = "搜索资产..."

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
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(nsColor: .windowBackgroundColor))
        )
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var searchHeader: some View {
        HStack(spacing: 12) {
            if viewModel.mode == .recentAssets {
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
                viewModel.mode == .home ? homeSearchPlaceholder : assetSearchPlaceholder,
                text: Binding(
                    get: { viewModel.searchText },
                    set: { text in
                        try? viewModel.updateSearchText(text)
                    }
                )
            )
            .textFieldStyle(.plain)
            .font(.system(size: 23, weight: .regular))
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

    @ViewBuilder
    private var content: some View {
        switch viewModel.mode {
        case .home:
            homeResultList
        case .recentAssets:
            assetBrowser
        }
    }

    private var homeResultList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 8) {
                SectionHeader("常用")
                if let firstResult = viewModel.homeResults.first {
                    homeResultButton(firstResult, index: 0)
                }
                SectionHeader("建议")
                ForEach(Array(viewModel.homeResults.dropFirst().enumerated()), id: \.element.id) { offset, result in
                    homeResultButton(result, index: offset + 1)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 14)
        }
    }

    private func homeResultButton(_ result: PaletteHomeResult, index: Int) -> some View {
        Button {
            viewModel.selectHomeResult(at: index)
            activate(result.command)
        } label: {
            HStack(spacing: 13) {
                commandIcon(for: result.command)
                Text(result.title)
                    .font(.system(size: 16, weight: .medium))
                Text(result.subtitle)
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(result.command == .recentAssets ? "命令" : "")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 15)
            .frame(height: 45)
            .contentShape(Rectangle())
        }
        .buttonStyle(PaletteRowButtonStyle(isSelected: viewModel.selectedHomeResultIndex == index))
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
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 6) {
                SectionHeader("今天")
                ForEach(Array(viewModel.assets.enumerated()), id: \.element.id) { index, asset in
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
                    .buttonStyle(PaletteRowButtonStyle(isSelected: viewModel.selectedAssetIndex == index))
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
                    Text("暂无资产")
                        .font(.system(size: 16))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var footer: some View {
        HStack(spacing: 12) {
            Label("最近资产", systemImage: "tray.full")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.secondary)
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

            Button("动作") {
                viewModel.toggleActionPanel()
            }
            .buttonStyle(.borderless)
            .keyboardShortcut("k", modifiers: .command)
            .font(.system(size: 15, weight: .semibold))
            .accessibilityLabel("动作")
            Text("⌘")
                .keyboardBadge()
            Text("K")
                .keyboardBadge()
        }
        .padding(.horizontal, 18)
        .frame(height: 44)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.65))
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
            Text("搜索...")
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
            if let asset = viewModel.selectedAsset,
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

    private func activate(_ command: PaletteCommand) {
        do {
            try viewModel.activate(command)
        } catch {
            onCommand(command)
        }
    }

    private func performPrimaryAction() {
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

    private func commandIcon(for command: PaletteCommand) -> some View {
        let systemName: String
        switch command {
        case .recentAssets, .assetHistory:
            systemName = "tray.full"
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

    private func assetSubtitle(_ asset: AssetItem) -> String {
        switch asset.source {
        case .dictation:
            return "语音识别"
        case .screenshot:
            return "截图"
        case .clipboard:
            return "剪切板"
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
            Text(asset.previewText ?? asset.text ?? asset.url ?? asset.filePath ?? asset.colorValue ?? asset.title)
                .font(.system(size: 18))
                .lineSpacing(5)
                .padding(22)
                .frame(maxWidth: .infinity, maxHeight: 210, alignment: .topLeading)
        }
    }

    private func assetInformation(for asset: AssetItem) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("信息")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.secondary)
            infoRow("来源", assetSubtitle(asset))
            infoRow("内容类型", contentTypeTitle(asset.contentType))
            if let imagePath = asset.imagePath {
                infoRow("图片路径", imagePath)
            }
            if let filePath = asset.filePath {
                infoRow("文件路径", filePath)
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
            return "文本"
        case .image:
            return "图片"
        case .file:
            return "文件"
        case .link:
            return "链接"
        case .color:
            return "颜色"
        }
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
    var isSelected = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(rowColor(isPressed: configuration.isPressed))
            )
    }

    private func rowColor(isPressed: Bool) -> Color {
        if isPressed || isSelected {
            return Color(nsColor: .separatorColor).opacity(isPressed ? 0.68 : 0.52)
        }
        return .clear
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
