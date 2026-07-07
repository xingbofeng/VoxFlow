// DictusKeyboard/Views/EmojiPickerView.swift
import SwiftUI
import AudioToolbox
import Shared

/// Shared model for category bar items (recents + standard categories).
struct CategoryInfo: Identifiable {
    let id: String
    let name: String
    let icon: String
    let representativeEmoji: String?  // nil for recents (uses SF Symbol clock icon)
}

enum EmojiSearchMode: Equatable {
    case unicodeNames
}

enum EmojiSearchModeResolver {
    static func activeMode(defaults: UserDefaults = AppGroup.preferences) -> EmojiSearchMode {
        mode(forLanguage: defaults.string(forKey: SharedKeys.language))
    }

    static func mode(forLanguage _: String?) -> EmojiSearchMode {
        .unicodeNames
    }
}

/// Full emoji picker matching Apple/SuperWhisper style:
/// - Search bar at top (pill shape)
/// - Single continuous horizontal LazyHGrid (4 rows, swipe left/right)
/// - Category bar at bottom as bookmarks into the grid
struct EmojiPickerView: View {
    let onEmojiInsert: (String) -> Void
    let onDelete: () -> Void
    let onDismiss: () -> Void
    /// Actual available width passed from the parent GeometryReader.
    /// WHY a parameter: In keyboard extensions, UIHostingController may not give
    /// SwiftUI content the full screen width due to safe area or layout margins.
    /// Using the measured parent width guarantees the grid fits without clipping.
    let availableWidth: CGFloat
    /// Actual available height for the picker (excludes the toolbar).
    let availableHeight: CGFloat

    @State private var recentEmojis: [String] = []
    @State private var selectedCategoryID: String = "smileys"
    @State private var isSearchActive: Bool = false
    @State private var searchText: String = ""
    @State private var showCursor: Bool = true
    @State private var filteredEmojis: [String] = []
    @State private var searchTask: Task<Void, Never>? = nil

    private let categories = EmojiStore.categories

    // Grid sizing constants
    private let headerHeight: CGFloat = 20
    private let categoryBarHeight: CGFloat = 36
    private let rowSpacing: CGFloat = 1

    /// Number of rows that fit in available height after subtracting header + category bar.
    private var rowCount: Int {
        let gridSpace = availableHeight - headerHeight - categoryBarHeight
        let rowWithSpacing: CGFloat = rowHeight + rowSpacing
        return max(3, Int(gridSpace / rowWithSpacing))
    }

    /// Height per emoji row, computed to fill available space evenly.
    private var rowHeight: CGFloat { 42 }

    private var gridRows: [GridItem] {
        Array(repeating: GridItem(.fixed(rowHeight), spacing: rowSpacing), count: rowCount)
    }

    /// Columns for vertical grid: 8 emojis per row filling the full width.
    private var gridColumns: [GridItem] {
        Array(repeating: GridItem(.fixed(emojiCellWidth), spacing: 0), count: 8)
    }

    /// Dynamic cell width: exactly 8 emojis per row based on actual available width.
    private var emojiCellWidth: CGFloat {
        (availableWidth - 4) / 8
    }

    // MARK: - Computed data

    /// Returns only the emojis for the currently selected category.
    /// WHY category pagination: The previous flat grid rendered ALL ~1800 emojis at once,
    /// causing CoreText to cache every glyph (~65KB each) = 139 MiB. By showing only one
    /// category at a time (max ~230 emojis), peak memory stays under ~15 MiB.
    private var currentCategoryEmojis: [EmojiGridItem] {
        if selectedCategoryID == "recents" {
            return recentEmojis.enumerated().map { i, emoji in
                EmojiGridItem(id: "recents_\(i)", emoji: emoji, categoryID: "recents")
            }
        }
        guard let cat = categories.first(where: { $0.id == selectedCategoryID }) else {
            return []
        }
        return cat.emojis.enumerated().map { i, emoji in
            EmojiGridItem(id: "\(cat.id)_\(i)", emoji: emoji, categoryID: cat.id)
        }
    }

    private var sectionInfos: [CategoryInfo] {
        var infos: [CategoryInfo] = []
        if !recentEmojis.isEmpty {
            infos.append(CategoryInfo(id: "recents", name: NSLocalizedString("emoji.recents", comment: ""), icon: "clock", representativeEmoji: nil))
        }
        for cat in categories {
            infos.append(CategoryInfo(id: cat.id, name: cat.name, icon: cat.icon, representativeEmoji: cat.representativeEmoji))
        }
        return infos
    }

    /// Display name for the currently selected category.
    private var selectedCategoryName: String {
        sectionInfos.first(where: { $0.id == selectedCategoryID })?.name.uppercased() ?? ""
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            if isSearchActive {
                searchMode
            } else {
                normalMode
            }
        }
        .frame(width: availableWidth, height: availableHeight)
        .clipped()
        .onAppear {
            recentEmojis = RecentEmojis.load()
            if !recentEmojis.isEmpty {
                selectedCategoryID = "recents"
            }
        }
    }

    // MARK: - Normal mode

    @ViewBuilder
    private var normalMode: some View {
        // Category name label (e.g. "SMILEYS & PEOPLE")
        HStack {
            Text(selectedCategoryName)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.secondary)
            Spacer()
        }
        .padding(.horizontal, 8)
        .padding(.top, 4)
        .padding(.bottom, 1)

        // Vertical emoji grid — fills width first, scrolls down for more.
        // .id(selectedCategoryID) forces SwiftUI to destroy and recreate the grid when
        // the user switches categories, which releases the old Text views and their
        // CoreText glyph caches -- this is the key to keeping memory under 50 MiB.
        ScrollView(.vertical, showsIndicators: false) {
            LazyVGrid(columns: gridColumns, spacing: 0) {
                ForEach(currentCategoryEmojis) { item in
                    Button {
                        HapticFeedback.keyTapped()
                        onEmojiInsert(item.emoji)
                        RecentEmojis.add(item.emoji)
                        recentEmojis = RecentEmojis.load()
                    } label: {
                        Text(item.emoji)
                            .font(.system(size: 32))
                            .frame(width: emojiCellWidth, height: rowHeight)
                    }
                    .id(item.id)
                }
            }
            .padding(.horizontal, 2)
            .id(selectedCategoryID)
        }

        EmojiCategoryBar(
            sections: sectionInfos,
            selectedCategoryID: selectedCategoryID,
            onSelectCategory: { id in
                selectedCategoryID = id
            },
            onSearch: { isSearchActive = true },
            onDelete: onDelete,
            onDismiss: onDismiss
        )
    }

    // MARK: - Search mode

    @ViewBuilder
    private var searchMode: some View {
        // Search input bar
        searchInputBar
            .padding(.horizontal, 8)
            .padding(.top, 2)
            .padding(.bottom, 1)

        // Emoji row: recents when empty, results when searching.
        let emojiRow = searchModeEmojis
        if emojiRow.isEmpty {
            Text("emoji.no_results")
                .foregroundColor(.secondary)
                .font(.system(size: 14))
                .frame(height: 38)
        } else {
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 2) {
                    ForEach(Array(emojiRow.enumerated()), id: \.offset) { _, emoji in
                        Button {
                            HapticFeedback.keyTapped()
                            onEmojiInsert(emoji)
                            RecentEmojis.add(emoji)
                        } label: {
                            Text(emoji)
                                .font(.system(size: 30))
                                .frame(width: emojiCellWidth, height: 38)
                        }
                    }
                }
                .padding(.horizontal, 4)
            }
            .frame(height: 38)
        }

        Spacer(minLength: 0)

        EquatableView(content: MiniSearchKeyboard(
            onCharacter: { searchText.append($0) },
            onDelete: { if !searchText.isEmpty { searchText.removeLast() } },
            onSpace: { searchText.append(" ") }
        ))
        .onChange(of: searchText) { _, newValue in
            searchTask?.cancel()
            if newValue.isEmpty {
                filteredEmojis = []
                return
            }
            searchTask = Task {
                try? await Task.sleep(nanoseconds: 100_000_000) // 100ms debounce
                guard !Task.isCancelled else { return }
                let results = performSearch(query: newValue)
                guard !Task.isCancelled else { return }
                filteredEmojis = results
            }
        }
    }

    /// Search bar for search mode with cursor.
    private var searchInputBar: some View {
        let barWidth = availableWidth - 16 // 8pt margin each side
        return HStack(spacing: 0) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.secondary)
                .padding(.trailing, 6)

            // Cursor at the start, then text or placeholder
            if searchText.isEmpty {
                blinkingCursor
                Text("emoji.search")
                    .foregroundColor(.secondary)
            } else {
                Text(searchText)
                    .foregroundColor(.primary)
                blinkingCursor
            }

            Spacer(minLength: 0)

            // × button: clears text if any, closes search if empty
            Button {
                if searchText.isEmpty {
                    isSearchActive = false
                } else {
                    searchText = ""
                }
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.secondary)
            }
        }
        .lineLimit(1)
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
        .frame(width: barWidth)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(.systemGray6))
        )
    }

    private var blinkingCursor: some View {
        Rectangle()
            .fill(Color.accentColor)
            .frame(width: 2, height: 18)
            .opacity(showCursor ? 1 : 0)
            .animation(.easeInOut(duration: 0.5).repeatForever(autoreverses: true), value: showCursor)
            .onAppear { showCursor.toggle() }
    }

    /// Emojis to show in search mode row.
    /// When nothing typed: recents (or first emojis from catalog if no recents).
    /// When searching: debounced filtered results.
    private var searchModeEmojis: [String] {
        if searchText.isEmpty {
            if recentEmojis.isEmpty {
                return Array(EmojiStore.allEmojis.prefix(30))
            }
            return recentEmojis
        }
        return filteredEmojis
    }

    // MARK: - Search logic (debounced, pre-computed names)

    private func performSearch(query: String) -> [String] {
        let q = query.lowercased()
        return searchUnicodeName(query: q)
    }

    private let maxSearchResults = 30

    private func searchUnicodeName(query: String) -> [String] {
        var results: [String] = []
        for entry in EmojiStore.allEmojiNames {
            if entry.name.contains(query) {
                results.append(entry.emoji)
                if results.count >= maxSearchResults { return results }
            }
        }
        return results
    }
}

// MARK: - Supporting types

private struct EmojiGridItem: Identifiable {
    let id: String
    let emoji: String
    let categoryID: String
}

/// Mini keyboard for emoji search with key popups and haptic feedback.
/// Uses 40pt key height to fit within the emoji picker without clipping.
/// Equatable to prevent re-renders when search text changes (layout is static).
private struct MiniSearchKeyboard: View, Equatable {
    let onCharacter: (String) -> Void
    let onDelete: () -> Void
    let onSpace: () -> Void

    static func == (lhs: MiniSearchKeyboard, rhs: MiniSearchKeyboard) -> Bool {
        true // Layout never changes, only closures differ
    }

    private let keyHeight: CGFloat = 34

    private let rows: [[String]] = [
        ["q", "w", "e", "r", "t", "y", "u", "i", "o", "p"],
        ["a", "s", "d", "f", "g", "h", "j", "k", "l"],
        ["z", "x", "c", "v", "b", "n", "m"]
    ]

    var body: some View {
        VStack(spacing: 3) {
            ForEach(Array(rows.enumerated()), id: \.offset) { rowIndex, row in
                HStack(spacing: 4) {
                    ForEach(row, id: \.self) { letter in
                        MiniKeyButton(label: letter, height: keyHeight) {
                            HapticFeedback.keyTapped()
                            AudioServicesPlaySystemSound(1104)
                            onCharacter(letter)
                        }
                    }
                    if rowIndex == 2 {
                        Button {
                            HapticFeedback.keyTapped()
                            AudioServicesPlaySystemSound(1155)
                            onDelete()
                        } label: {
                            Image(systemName: "delete.backward")
                                .font(.system(size: 18))
                                .frame(maxWidth: .infinity)
                                .frame(height: keyHeight)
                                .background(KeyMetrics.letterKeyColor)
                                .cornerRadius(KeyMetrics.keyCornerRadius)
                        }
                        .foregroundColor(Color(.label))
                    }
                }
            }
            Button {
                HapticFeedback.keyTapped()
                AudioServicesPlaySystemSound(1156)
                onSpace()
            } label: {
                Text("keyboard.space")
                    .font(.system(size: 16))
                    .frame(maxWidth: .infinity)
                    .frame(height: keyHeight)
                    .background(KeyMetrics.letterKeyColor)
                    .cornerRadius(KeyMetrics.keyCornerRadius)
            }
            .foregroundColor(Color(.label))
        }
        .padding(.horizontal, KeyMetrics.rowSidePadding)
        .padding(.bottom, 2)
    }
}

/// A single key in the mini search keyboard with press popup.
/// Uses a lightweight ButtonStyle instead of DragGesture for better performance.
private struct MiniKeyButton: View {
    let label: String
    let height: CGFloat
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 22))
                .foregroundColor(Color(.label))
                .frame(maxWidth: .infinity)
                .frame(height: height)
                .background(KeyMetrics.letterKeyColor)
                .cornerRadius(KeyMetrics.keyCornerRadius)
        }
        .buttonStyle(MiniKeyButtonStyle(label: label, height: height))
    }
}

private struct MiniKeyButtonStyle: ButtonStyle {
    let label: String
    let height: CGFloat

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .overlay(
                Group {
                    if configuration.isPressed {
                        KeyPopup(label: label)
                            .offset(y: -(height + 8))
                    }
                },
                alignment: .top
            )
    }
}
