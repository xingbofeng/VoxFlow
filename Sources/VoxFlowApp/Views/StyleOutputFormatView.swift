import SwiftUI
import VoxFlowTextProcessing

struct StyleOutputFormatSheet: View {
    @Binding var draft: StyleOutputFormatSheetDraft
    let previewInput: String
    let onCancel: () -> Void
    let onSave: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    optionsSection
                    previewSection
                    rulesSection
                }
                .padding(22)
            }
            Divider()
            footer
        }
        .frame(width: 560)
        .frame(minHeight: 560)
        .background(AppTheme.ColorToken.pageBackground)
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(L10n.localize("style.output_format.sheet.title", comment: ""))
                    .font(.system(size: 20, weight: .semibold))
                Text(L10n.localize("style.output_format.sheet.subtitle", comment: ""))
                    .font(.system(size: 12))
                    .foregroundStyle(AppTheme.ColorToken.secondaryText)
            }
            Spacer()
            Button(action: onCancel) {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .semibold))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 18)
    }

    private var optionsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(L10n.localize("style.output_format.options.title", comment: ""))
                .font(.system(size: 14, weight: .semibold))
            outputFormatPicker(
                title: L10n.localize("style.output_format.punctuation.title", comment: ""),
                selection: $draft.punctuation,
                values: StyleOutputPunctuation.allCases,
                label: outputPunctuationLabel
            )
            outputFormatPicker(
                title: L10n.localize("style.output_format.capitalization.title", comment: ""),
                selection: $draft.capitalization,
                values: StyleOutputCapitalization.allCases,
                label: outputCapitalizationLabel
            )
            outputFormatPicker(
                title: L10n.localize("style.output_format.tone.title", comment: ""),
                selection: $draft.tone,
                values: StyleOutputTone.allCases,
                label: outputToneLabel
            )
            outputFormatPicker(
                title: L10n.localize("style.output_format.emoji.title", comment: ""),
                selection: $draft.emoji,
                values: StyleOutputEmoji.allCases,
                label: outputEmojiLabel
            )
        }
    }

    private func outputFormatPicker<Value: CaseIterable & Hashable & Identifiable>(
        title: String,
        selection: Binding<Value>,
        values: [Value],
        label: @escaping (Value) -> String
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(AppTheme.ColorToken.secondaryText)
            Picker(title, selection: selection) {
                ForEach(values, id: \.self) { value in
                    Text(label(value)).tag(value)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
        }
    }

    private var previewSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L10n.localize("style.output_format.preview.title", comment: ""))
                .font(.system(size: 14, weight: .semibold))
            VStack(alignment: .leading, spacing: 10) {
                Text(L10n.localize("style.output_format.preview.input", comment: ""))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(AppTheme.ColorToken.secondaryText)
                Text(previewInput)
                    .font(.system(size: 13))
                    .foregroundStyle(AppTheme.ColorToken.primaryText)
                Divider()
                Text(L10n.localize("style.output_format.preview.output", comment: ""))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(AppTheme.ColorToken.secondaryText)
                Text(outputPreviewText)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(AppTheme.ColorToken.primaryText)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AppTheme.ColorToken.panelBackground)
            .overlay(editorBorder)
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.card, style: .continuous))
        }
    }

    private var outputPreviewText: String {
        StyleOutputFormatPreviewText.output(for: draft.format)
    }

    private var rulesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L10n.localize("style.output_format.rules.title", comment: ""))
                .font(.system(size: 14, weight: .semibold))
            Text(L10n.localize("style.output_format.rules.description", comment: ""))
                .font(.system(size: 12))
                .foregroundStyle(AppTheme.ColorToken.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var footer: some View {
        HStack {
            Spacer()
            Button(L10n.localize("style.output_format.action.cancel", comment: ""), action: onCancel)
                .buttonStyle(.borderless)
                .keyboardShortcut(.cancelAction)
            Button(L10n.localize("style.output_format.action.save", comment: ""), action: onSave)
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 14)
    }

    private var editorBorder: some View {
        RoundedRectangle(cornerRadius: AppTheme.Radius.card, style: .continuous)
            .stroke(AppTheme.ColorToken.panelStroke, lineWidth: AppTheme.Border.panelLineWidth)
    }
}

struct StyleOutputFormatSheetDraft: Identifiable {
    let id = UUID()
    var punctuation: StyleOutputPunctuation
    var capitalization: StyleOutputCapitalization
    var tone: StyleOutputTone
    var emoji: StyleOutputEmoji

    var format: StyleOutputFormat {
        StyleOutputFormat(
            punctuation: punctuation,
            capitalization: capitalization,
            tone: tone,
            emoji: emoji
        )
    }

    init(format: StyleOutputFormat) {
        self.punctuation = format.punctuation
        self.capitalization = format.capitalization
        self.tone = format.tone
        self.emoji = format.emoji
    }
}

enum StyleOutputFormatPreviewText {
    static var sampleInput: String {
        L10n.localize("style.output_format.preview.sample", comment: "")
    }

    static func output(for format: StyleOutputFormat) -> String {
        let toneKey = "style.output_format.preview.output.\(format.tone.rawValue)"
        let toneText = L10n.format(toneKey, comment: "", englishClause(for: format.capitalization))
        let withEmoji = toneText + emojiSuffix(for: format.emoji)
        return applyPunctuation(format.punctuation, to: withEmoji)
    }

    private static func englishClause(for capitalization: StyleOutputCapitalization) -> String {
        switch capitalization {
        case .normal:
            return L10n.localize("style.output_format.preview.english.normal", comment: "")
        case .relaxed:
            return L10n.localize("style.output_format.preview.english.relaxed", comment: "")
        case .preserve:
            return L10n.localize("style.output_format.preview.english.preserve", comment: "")
        }
    }

    private static func emojiSuffix(for emoji: StyleOutputEmoji) -> String {
        switch emoji {
        case .none:
            return ""
        case .natural:
            return L10n.localize("style.output_format.preview.emoji.natural", comment: "")
        case .required:
            return L10n.localize("style.output_format.preview.emoji.required", comment: "")
        }
    }

    private static func applyPunctuation(
        _ punctuation: StyleOutputPunctuation,
        to text: String
    ) -> String {
        switch punctuation {
        case .complete:
            return text + L10n.localize("style.output_format.preview.period", comment: "")
        case .less, .preserve:
            return StyleOutputFormatter.process(
                text,
                policy: StyleOutputFormatPolicy(punctuation: .noEnding)
            )
        }
    }
}

extension StyleProfileRecord {
    var outputFormatListSubtitle: String? {
        (outputFormat ?? StyleOutputFormat.builtInDefault(for: id))?.summaryText
    }
}

extension StyleOutputFormat {
    var summaryText: String {
        [
            outputPunctuationLabel(punctuation),
            outputCapitalizationLabel(capitalization),
            outputToneLabel(tone),
            outputEmojiLabel(emoji),
        ].joined(separator: " · ")
    }
}

func outputPunctuationLabel(_ value: StyleOutputPunctuation) -> String {
    switch value {
    case .complete:
        return L10n.localize("style.output_format.punctuation.complete", comment: "")
    case .less:
        return L10n.localize("style.output_format.punctuation.less", comment: "")
    case .preserve:
        return L10n.localize("style.output_format.punctuation.preserve", comment: "")
    }
}

func outputCapitalizationLabel(_ value: StyleOutputCapitalization) -> String {
    switch value {
    case .normal:
        return L10n.localize("style.output_format.capitalization.normal", comment: "")
    case .relaxed:
        return L10n.localize("style.output_format.capitalization.relaxed", comment: "")
    case .preserve:
        return L10n.localize("style.output_format.capitalization.preserve", comment: "")
    }
}

func outputToneLabel(_ value: StyleOutputTone) -> String {
    switch value {
    case .restrained:
        return L10n.localize("style.output_format.tone.restrained", comment: "")
    case .natural:
        return L10n.localize("style.output_format.tone.natural", comment: "")
    case .energetic:
        return L10n.localize("style.output_format.tone.energetic", comment: "")
    }
}

func outputEmojiLabel(_ value: StyleOutputEmoji) -> String {
    switch value {
    case .none:
        return L10n.localize("style.output_format.emoji.none", comment: "")
    case .natural:
        return L10n.localize("style.output_format.emoji.natural", comment: "")
    case .required:
        return L10n.localize("style.output_format.emoji.required", comment: "")
    }
}
