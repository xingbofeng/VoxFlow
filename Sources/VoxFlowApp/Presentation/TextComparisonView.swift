import SwiftUI

/// Configuration passed into `TextComparisonView`.
///
/// The input carries the source/processed titles (which differ between the
/// top result area and a deterministic phase), the source/processed text, an
/// empty-placeholder, and an optional `initialMode`. Comparison-mode label is
/// always sourced from `L10n` by the view itself to stay consistent.
struct TextComparisonInput: Sendable, Equatable {
    let sourceTitle: String
    let processedTitle: String
    let sourceText: String
    let processedText: String
    let emptyPlaceholder: String
    let initialMode: TextComparisonMode?

    init(
        sourceTitle: String,
        processedTitle: String,
        sourceText: String,
        processedText: String,
        emptyPlaceholder: String,
        initialMode: TextComparisonMode? = nil
    ) {
        self.sourceTitle = sourceTitle
        self.processedTitle = processedTitle
        self.sourceText = sourceText
        self.processedText = processedText
        self.emptyPlaceholder = emptyPlaceholder
        self.initialMode = initialMode
    }
}

/// Reusable inline text comparison view.
///
/// Renders a segmented control with `source / processed / comparison` modes
/// (labels supplied by the caller for source/processed, and localized
/// `home.detail.comparison.mode.comparison` for comparison). In comparison
/// mode, the view shows inline diff highlighting: deleted segments use a
/// light-red background with strikethrough, inserted segments use a
/// light-green background, and unchanged segments use the body style. A
/// similarity badge is shown to the right of the segmented control.
///
/// The view does not own a `ScrollView`; text wraps naturally and is
/// constrained by `lineLimit` and the surrounding modal layout, so it never
/// introduces a nested vertical scrollbar.
struct TextComparisonView: View {
    let input: TextComparisonInput
    private let renderer = TextDiffingComparisonRenderer()
    @State private var selectedMode: TextComparisonMode

    init(input: TextComparisonInput) {
        self.input = input
        let presentation = TextComparisonPresentation(
            source: input.sourceText,
            processed: input.processedText
        )
        _selectedMode = State(initialValue: input.initialMode ?? presentation.defaultMode)
    }

    var body: some View {
        let presentation = TextComparisonPresentation(
            source: input.sourceText,
            processed: input.processedText
        )
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Picker("", selection: $selectedMode) {
                    Text(input.sourceTitle).tag(TextComparisonMode.source)
                    Text(input.processedTitle).tag(TextComparisonMode.processed)
                    Text(L10n.localize(
                        "home.detail.comparison.mode.comparison",
                        comment: "Comparison mode label"
                    )).tag(TextComparisonMode.comparison)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                if selectedMode == .comparison {
                    Text(L10n.format("home.detail.comparison.similarity_format", comment: "Similarity percentage format",
                        presentation.similarityPercent
                    ))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(similarityColor(for: presentation))
                    .padding(.horizontal, 10)
                    .frame(height: 24)
                    .background(similarityColor(for: presentation).opacity(0.12))
                    .clipShape(Capsule())
                    .accessibilityLabel(L10n.format("home.detail.comparison.similarity_format", comment: "Similarity percentage format",
                        presentation.similarityPercent
                    ))
                }
            }
            bodyContent(presentation: presentation)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppTheme.ColorToken.panelBackground.opacity(0.82))
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.Radius.card, style: .continuous)
                .stroke(AppTheme.ColorToken.subtleStroke, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.card, style: .continuous))
    }

    // MARK: - Body

    @ViewBuilder
    private func bodyContent(presentation: TextComparisonPresentation) -> some View {
        if input.sourceText.isEmpty && input.processedText.isEmpty {
            Text(input.emptyPlaceholder)
                .font(.system(size: 13))
                .foregroundStyle(AppTheme.ColorToken.secondaryText)
                .frame(maxWidth: .infinity, minHeight: 56, alignment: .topLeading)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            switch selectedMode {
            case .source:
                Text(input.sourceText)
                    .font(.system(size: 14))
                    .foregroundStyle(AppTheme.ColorToken.primaryText)
                    .textSelection(.enabled)
                    .lineLimit(12)
                    .frame(maxWidth: .infinity, minHeight: 56, alignment: .topLeading)
                    .fixedSize(horizontal: false, vertical: true)
            case .processed:
                Text(input.processedText)
                    .font(.system(size: 14))
                    .foregroundStyle(AppTheme.ColorToken.primaryText)
                    .textSelection(.enabled)
                    .lineLimit(12)
                    .frame(maxWidth: .infinity, minHeight: 56, alignment: .topLeading)
                    .fixedSize(horizontal: false, vertical: true)
            case .comparison:
                comparisonBody(presentation: presentation)
            }
        }
    }

    @ViewBuilder
    private func comparisonBody(presentation: TextComparisonPresentation) -> some View {
        if presentation.segments.isEmpty {
            Text(input.emptyPlaceholder)
                .font(.system(size: 14))
                .foregroundStyle(AppTheme.ColorToken.secondaryText)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, minHeight: 56, alignment: .topLeading)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            Text(comparisonAttributed(presentation: presentation))
                .font(.system(size: 14))
                .foregroundStyle(AppTheme.ColorToken.primaryText)
                .textSelection(.enabled)
                .lineLimit(12)
                .frame(maxWidth: .infinity, minHeight: 56, alignment: .topLeading)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityLabel(comparisonAccessibilityLabel(presentation: presentation))
        }
    }

    // MARK: - Attribution

    private func comparisonAttributed(presentation: TextComparisonPresentation) -> AttributedString {
        renderer.attributedString(
            source: presentation.sourceText,
            processed: presentation.processedText
        )
    }

    private func comparisonAccessibilityLabel(presentation: TextComparisonPresentation) -> String {
        presentation.segments.map { segment -> String in
            switch segment {
            case .equal(let text):
                return text
            case .inserted(let text):
                return L10n.format("home.detail.comparison.accessibility.inserted_format", comment: "Inserted segment accessibility label",
                    text
                )
            case .deleted(let text):
                return L10n.format("home.detail.comparison.accessibility.deleted_format", comment: "Deleted segment accessibility label",
                    text
                )
            }
        }.joined(separator: " ")
    }

    private func similarityColor(for presentation: TextComparisonPresentation) -> Color {
        if presentation.similarityPercent >= 80 {
            return AppTheme.ColorToken.secondaryText
        }
        return AppTheme.ColorToken.accent
    }

}
