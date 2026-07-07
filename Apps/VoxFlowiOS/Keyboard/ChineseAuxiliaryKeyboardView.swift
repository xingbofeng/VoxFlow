// Mashangxie Chinese auxiliary symbol/number panels.
import SwiftUI

enum ChineseAuxiliaryPanelMode: Equatable {
    case symbols
    case numbers
}

@MainActor
final class ChineseAuxiliaryPanelState: ObservableObject {
    static let shared = ChineseAuxiliaryPanelState()

    @Published var mode: ChineseAuxiliaryPanelMode?

    private init() {}

    func show(_ mode: ChineseAuxiliaryPanelMode) {
        self.mode = mode
    }

    func dismiss() {
        mode = nil
    }
}

struct ChineseAuxiliaryKeyboardView: View {
    let mode: ChineseAuxiliaryPanelMode
    let returnTitle: String
    let onInsert: (String) -> Void
    let onDelete: () -> Void
    let onSpace: () -> Void
    let onSend: () -> Void
    let onReturn: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            switch mode {
            case .symbols:
                ChineseSymbolKeyboardView(
                    returnTitle: returnTitle,
                    onInsert: onInsert,
                    onReturn: onReturn
                )
            case .numbers:
                ChineseNumberKeyboardView(
                    returnTitle: returnTitle,
                    onInsert: onInsert,
                    onDelete: onDelete,
                    onSpace: onSpace,
                    onSend: onSend,
                    onReturn: onReturn
                )
            }
        }
        .background(Self.panelBackground)
    }

    fileprivate static let panelBackground = Color(UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(white: 0.12, alpha: 1)
            : UIColor(red: 0.80, green: 0.82, blue: 0.86, alpha: 1)
    })
}

private enum ChineseSymbolCategory: String, CaseIterable, Identifiable {
    case common
    case chinese
    case english
    case emoji

    var id: String { rawValue }

    var title: String {
        switch self {
        case .common: return "常用"
        case .chinese: return "中文"
        case .english: return "英文"
        case .emoji: return "表情"
        }
    }

    var symbols: [String] {
        switch self {
        case .common:
            return [
                "，", "。", "？", "！", "、", "：", "；", "…", "……", "@", "#", "%", "&", "*", "+", "-",
                "=", "/", "\\", "|", "_", "~", "^", "·", "(", ")", "[", "]", "{", "}", "<", ">", "$", "¥",
                "€", "£", "℃", "°", "©", "®", "™", "✓", "×", "÷", "←", "→", "↑", "↓"
            ]
        case .chinese:
            return [
                "，", "。", "？", "！", "、", "；", "：", "“", "”", "‘", "’", "（", "）", "《", "》", "〈",
                "〉", "【", "】", "「", "」", "『", "』", "—", "——", "…", "·", "￥", "％", "℃", "～", "＋",
                "－", "＝", "×", "÷", "｜", "〔", "〕", "〖", "〗"
            ]
        case .english:
            return [
                ",", ".", "?", "!", "'", "\"", ":", ";", "/", "\\", "-", "_", "@", "#", "$", "%", "&", "*",
                "+", "=", "(", ")", "[", "]", "{", "}", "<", ">", "`", "~", "|", "^"
            ]
        case .emoji:
            return [
                "😂", "👍", "😭", "🙏", "😍", "😊", "🥰", "😘", "😅", "🤣", "😄", "😎", "🤔", "👌", "👏", "🔥",
                "🎉", "❤️", "💔", "💕", "✨", "⭐", "💯", "💪", "🤝", "🙌", "😢", "😡", "😳", "😴", "🤯", "😇",
                "😋", "😆", "😉", "😜", "😤", "😱", "👀", "💡", "✅", "❌", "⚠️", "📌", "🚀", "🌹", "🍻", "☕️"
            ]
        }
    }
}

private struct ChineseSymbolKeyboardView: View {
    let returnTitle: String
    let onInsert: (String) -> Void
    let onReturn: () -> Void

    @State private var category: ChineseSymbolCategory = .common

    var body: some View {
        GeometryReader { geometry in
            let metrics = PanelLayoutMetrics(geometry: geometry, leftRows: 5)

            HStack(spacing: KeyMetrics.keySpacing) {
                VStack(spacing: KeyMetrics.keySpacing) {
                    ChinesePanelKey(title: returnTitle, background: Self.specialKeyColor, action: onReturn)
                        .frame(width: metrics.leftColumnWidth, height: metrics.leftKeyHeight)
                    ForEach(Self.categories) { item in
                        ChinesePanelKey(
                            title: item.title,
                            background: category == item ? Self.selectedCategoryColor : Self.specialKeyColor
                        ) {
                            category = item
                        }
                        .frame(width: metrics.leftColumnWidth, height: metrics.leftKeyHeight)
                    }
                }

                ScrollView(.vertical, showsIndicators: false) {
                    LazyVGrid(
                        columns: Array(repeating: GridItem(.flexible(), spacing: KeyMetrics.keySpacing), count: 4),
                        spacing: KeyMetrics.keySpacing
                    ) {
                        ForEach(category.symbols, id: \.self) { symbol in
                            ChinesePanelKey(title: symbol) {
                                onInsert(normalized(symbol))
                                onReturn()
                            }
                            .frame(height: metrics.rightKeyHeight)
                        }
                    }
                    .frame(width: metrics.rightGridWidth)
                }
                .frame(width: metrics.rightGridWidth, height: metrics.availableHeight)
            }
            .padding(.horizontal, KeyMetrics.rowSidePadding)
            .padding(.vertical, 4)
            .frame(width: geometry.size.width, height: geometry.size.height, alignment: .topLeading)
        }
    }

    private static let categories: [ChineseSymbolCategory] = [.common, .english, .chinese, .emoji]

    private static let specialKeyColor = Color(UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(white: 0.24, alpha: 1)
            : UIColor(red: 0.68, green: 0.71, blue: 0.76, alpha: 1)
    })

    private static let selectedCategoryColor = Color(UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(white: 0.32, alpha: 1)
            : UIColor(red: 0.58, green: 0.62, blue: 0.68, alpha: 1)
    })

    private func normalized(_ symbol: String) -> String {
        symbol
    }
}

private struct ChineseNumberKeyboardView: View {
    let returnTitle: String
    let onInsert: (String) -> Void
    let onDelete: () -> Void
    let onSpace: () -> Void
    let onSend: () -> Void
    let onReturn: () -> Void

    private let leftColumn: [NumberPanelKey] = [
        .input("+", special: true),
        .input("-", special: true),
        .input("*", special: true),
        .input("/", special: true),
        .input("=", special: true),
    ]

    private let rows: [[NumberPanelKey]] = [
        [.input("1", special: false), .input("2", special: false), .input("3", special: false), .delete],
        [.input("4", special: false), .input("5", special: false), .input("6", special: false), .space],
        [.input("7", special: false), .input("8", special: false), .input("9", special: false), .input("@", special: true)],
        [.returnPanel, .input("0", special: false), .input(".", special: true), .send],
    ]

    var body: some View {
        GeometryReader { geometry in
            let metrics = PanelLayoutMetrics(geometry: geometry, leftRows: 5)

            HStack(spacing: KeyMetrics.keySpacing) {
                VStack(spacing: KeyMetrics.keySpacing) {
                    ForEach(leftColumn, id: \.self) { key in
                        keyView(for: key)
                            .frame(width: metrics.leftColumnWidth, height: metrics.leftKeyHeight)
                    }
                }

                VStack(spacing: KeyMetrics.keySpacing) {
                    ForEach(rows, id: \.self) { row in
                        HStack(spacing: KeyMetrics.keySpacing) {
                            ForEach(row, id: \.self) { key in
                                keyView(for: key)
                                    .frame(height: metrics.rightKeyHeight)
                            }
                        }
                    }
                }
                .frame(width: metrics.rightGridWidth, height: metrics.availableHeight, alignment: .top)
            }
            .padding(.horizontal, KeyMetrics.rowSidePadding)
            .padding(.vertical, 4)
            .frame(width: geometry.size.width, height: geometry.size.height, alignment: .topLeading)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("数字")
    }

    @ViewBuilder
    private func keyView(for key: NumberPanelKey) -> some View {
        switch key {
        case .input(let value, let special):
            ChinesePanelKey(title: value, background: special ? Self.specialKeyColor : KeyMetrics.letterKeyColor) {
                onInsert(value)
            }
        case .delete:
            ChinesePanelKey(systemName: "delete.left", background: Self.specialKeyColor, action: onDelete)
        case .space:
            ChinesePanelKey(title: "空格", background: Self.specialKeyColor, action: onSpace)
        case .returnPanel:
            ChinesePanelKey(title: returnTitle, action: onReturn)
        case .send:
            ChinesePanelKey(title: "发送", foreground: .white, background: Color.blue, action: onSend)
        }
    }

    private static let specialKeyColor = Color(UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(white: 0.24, alpha: 1)
            : UIColor(red: 0.68, green: 0.71, blue: 0.76, alpha: 1)
    })
}

private struct PanelLayoutMetrics {
    let availableHeight: CGFloat
    let leftColumnWidth: CGFloat
    let rightGridWidth: CGFloat
    let leftKeyHeight: CGFloat
    let rightKeyHeight: CGFloat

    init(geometry: GeometryProxy, leftRows: Int) {
        availableHeight = max(0, geometry.size.height - 8)
        leftColumnWidth = 64
        let contentWidth = max(0, geometry.size.width - (KeyMetrics.rowSidePadding * 2))
        rightGridWidth = max(0, contentWidth - leftColumnWidth - KeyMetrics.keySpacing)
        leftKeyHeight = max(
            34,
            (availableHeight - (KeyMetrics.keySpacing * CGFloat(max(0, leftRows - 1)))) / CGFloat(leftRows)
        )
        rightKeyHeight = max(
            40,
            (availableHeight - (KeyMetrics.keySpacing * 3)) / 4
        )
    }
}

private enum NumberPanelKey: Hashable {
    case input(String, special: Bool)
    case delete
    case space
    case returnPanel
    case send
}

private struct ChinesePanelKey: View {
    let title: String?
    let systemName: String?
    let foreground: Color
    let background: Color
    let action: () -> Void

    init(
        title: String,
        foreground: Color = .primary,
        background: Color = .white,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.systemName = nil
        self.foreground = foreground
        self.background = background
        self.action = action
    }

    init(
        systemName: String,
        foreground: Color = .primary,
        background: Color = .white,
        action: @escaping () -> Void
    ) {
        self.title = nil
        self.systemName = systemName
        self.foreground = foreground
        self.background = background
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            ZStack {
                if let systemName {
                    Image(systemName: systemName)
                        .font(.system(size: 24, weight: .regular))
                } else if let title {
                    Text(title)
                        .font(.system(size: title.count > 2 ? 20 : 26, weight: .regular))
                        .minimumScaleFactor(0.55)
                        .lineLimit(1)
                }
            }
            .foregroundColor(foreground)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(
                RoundedRectangle(cornerRadius: KeyMetrics.keyCornerRadius, style: .continuous)
            )
        }
        .buttonStyle(.plain)
        .background(
            RoundedRectangle(cornerRadius: KeyMetrics.keyCornerRadius, style: .continuous)
                .fill(background)
        )
        .overlay(
            RoundedRectangle(cornerRadius: KeyMetrics.keyCornerRadius, style: .continuous)
                .stroke(Color.black.opacity(0.08), lineWidth: 0.5)
        )
        .shadow(color: Color.black.opacity(0.18), radius: 0, x: 0, y: 1)
        .accessibilityLabel(title ?? systemName ?? "")
    }
}
