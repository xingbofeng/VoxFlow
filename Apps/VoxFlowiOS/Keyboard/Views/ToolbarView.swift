// DictusKeyboard/Views/ToolbarView.swift
import SwiftUI
import Shared
import ChineseInput

struct ToolbarDisplayPolicy {
    static func showsChineseModeToggle(
        suggestions: [String],
        suggestionMode: SuggestionMode,
        statusMessage: String?
    ) -> Bool {
        statusMessage == nil && suggestions.isEmpty && suggestionMode != .chineseCandidates
    }
}

/// Toolbar displayed above the keyboard with app shortcut and AnimatedMicButton.
/// Inspired by Wispr Flow -- the mic button is the primary dictation trigger.
///
/// WHY AnimatedMicButton replaces inline micIcon:
/// AnimatedMicButton provides 4 visual states (idle glow, recording pulse,
/// transcribing shimmer, success flash) that give the user clear feedback
/// about the dictation lifecycle. The inline micIcon only had basic color changes.
///
/// ClipboardBridge pending state (add-ios-keyboard-clipboard-fallback Phase 5):
/// When `pendingClipboard.hasPreview` is true, the toolbar swaps:
/// - Left: Chinese mode pill → middle-truncated preview pill (tappable to insert)
/// - Right: Mic button → X close button (tappable to dismiss without inserting)
/// Normal typing remains available underneath. The system pasteboard is NOT
/// cleared on either action.
struct ToolbarView: View {
    let hasFullAccess: Bool
    let dictationStatus: DictationStatus
    var onMicTap: () -> Void

    // Suggestion bar integration parameters (default to idle/empty)
    var statusMessage: String? = nil
    var suggestions: [String] = []
    var suggestionMode: SuggestionMode = .idle
    var onSuggestionTap: ((Int) -> Void)? = nil
    var suggestionsExpanded: Bool = false
    var onSuggestionExpand: (() -> Void)? = nil
    /// Total Chinese candidate count for the current composition; forwarded to
    /// the suggestion bar's expand button badge.
    var candidateCount: Int? = nil
    var chinesePreedit: String? = nil

    /// Callback when the user cycles the language via the toolbar switcher.
    var onLanguageChanged: ((SupportedLanguage) -> Void)? = nil
    var chineseInputMode: ChineseInputMode = ChineseKeyboardModeStore.active
    var onChineseModeToggle: ((ChineseInputMode) -> Void)? = nil
    var leadingActionTitle: String? = nil
    var onLeadingAction: (() -> Void)? = nil

    /// ClipboardBridge pending state. When non-empty, the toolbar shows a
    /// preview pill on the left and an X close button on the right instead
    /// of the normal Chinese mode toggle + mic.
    var pendingClipboard: PendingClipboardDictation = .none
    var onPendingInsert: (() -> Void)? = nil
    var onPendingDismiss: (() -> Void)? = nil
    var onPendingRetry: (() -> Void)? = nil

    private var hasPendingClipboard: Bool {
        pendingClipboard.launched && !pendingClipboard.dismissed
    }

    private var showsChineseModeToggle: Bool {
        ToolbarDisplayPolicy.showsChineseModeToggle(
            suggestions: suggestions,
            suggestionMode: suggestionMode,
            statusMessage: statusMessage
        )
    }

    var body: some View {
        // WHY ZStack: ensures the banner text is centered horizontally across the
        // full toolbar width, independent of the mic pill position on the right.
        // Both layers are vertically centered by the ZStack's default alignment.
        ZStack {
            if hasFullAccess {
                // Normal mode: gear left (when idle), suggestion bar (when typing), mic right.
                // WHY hide gear when suggestions showing:
                // The suggestion bar needs horizontal space to display 3 slots legibly.
                // The gear icon is rarely needed during active typing, and users can
                // access settings between typing sessions when the bar reverts to idle.
                HStack {
                    if let message = statusMessage {
                        Text(message)
                            .font(.caption)
                            .foregroundColor(.red)
                            .lineLimit(1)
                            .frame(maxWidth: .infinity)
                    } else if let leadingActionTitle {
                        ToolbarLeadingActionButton(title: leadingActionTitle, action: onLeadingAction)

                        Spacer()
                    } else if pendingClipboard.hasPreview {
                        // ClipboardBridge pending: show middle-truncated preview.
                        // Tapping inserts the full pending text (not the truncated preview).
                        ClipboardPreviewPill(
                            previewText: pendingClipboard.previewText ?? "",
                            onTap: { onPendingInsert?() }
                        )
                        .frame(maxWidth: .infinity, alignment: .leading)
                        Spacer()
                    } else if let failureReason = pendingClipboard.readFailureReason {
                        ClipboardFailurePill(
                            reason: failureReason,
                            onTap: { onPendingRetry?() }
                        )
                        .frame(maxWidth: .infinity, alignment: .leading)
                        Spacer()
                    } else if hasPendingClipboard {
                        ClipboardWaitingPill()
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Spacer()
                    } else if showsChineseModeToggle {
                        ChineseModeToggleButton(mode: chineseInputMode, onToggle: onChineseModeToggle)

                        Spacer()
                    } else {
                        SuggestionBarView(
                            suggestions: suggestions,
                            mode: suggestionMode,
                            onTap: { index in onSuggestionTap?(index) },
                            isExpanded: suggestionsExpanded,
                            onExpand: onSuggestionExpand,
                            candidateCount: candidateCount,
                            preedit: chinesePreedit
                        )
                    }

                    if hasPendingClipboard {
                        // Pending state: X close button instead of mic.
                        // Tapping dismisses the preview without inserting and
                        // WITHOUT clearing UIPasteboard.
                        ClipboardDismissButton(onTap: { onPendingDismiss?() })
                    } else {
                        AnimatedMicButton(status: dictationStatus, isPill: true, onTap: onMicTap)
                    }
                }
            } else {
                // No Full Access: centered banner text + disabled mic on the right
                HStack(spacing: 6) {
                    Image(systemName: "keyboard")
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                    Text(keyboardString("keyboard.full_access_required"))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                HStack {
                    Spacer()

                    AnimatedMicButton(status: .idle, isPill: true, onTap: {})
                        .disabled(true)
                        .opacity(0.4)
                }
            }
        }
        .padding(.horizontal, hasPendingClipboard ? 12 : 12)
        // Push content down so the mic ring/glow doesn't get clipped by the
        // iOS keyboard container's native top border (~2pt separator).
        .padding(.top, 4)
        // WHY 52pt: The AnimatedMicButton pill (36pt tall) has ring/glow effects
        // extending to 46pt. With 4pt top padding, 52pt total provides enough
        // breathing room above and below the pill without clipping.
        .frame(height: 52)
    }
}

private func keyboardString(_ key: String) -> String {
    NSLocalizedString(key, bundle: .main, comment: "")
}

/// ClipboardBridge preview pill: shows middle-truncated text on the left side
/// of the toolbar. Tapping inserts the FULL pending text (not the truncated
/// preview) via `textDocumentProxy.insertText`.
private struct ClipboardPreviewPill: View {
    let previewText: String
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 10) {
                Image(systemName: "doc.on.clipboard")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Color.dictusAccent)
                    .frame(width: 20, height: 20)

                Text(previewText)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .minimumScaleFactor(0.82)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 12)
            .frame(height: 36)
            .background(
                Capsule()
                    .fill(Color(.systemGray5).opacity(0.92))
            )
            .overlay(
                Capsule()
                    .strokeBorder(Color.dictusAccent.opacity(0.42), lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
    }
}

private struct ClipboardWaitingPill: View {
    var body: some View {
        HStack(spacing: 10) {
            ProgressView()
                .tint(Color.dictusAccent)
                .controlSize(.small)
                .frame(width: 20, height: 20)

            Text(keyboardString("keyboard.clipboard.reading"))
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.82)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 12)
        .frame(height: 36)
        .background(
            Capsule()
                .fill(Color(.systemGray5).opacity(0.92))
        )
        .overlay(
            Capsule()
                .strokeBorder(Color.dictusAccent.opacity(0.28), lineWidth: 1.5)
        )
    }
}

private struct ClipboardFailurePill: View {
    let reason: ClipboardReadFailureReason
    let onTap: () -> Void

    private var text: String {
        switch reason {
        case .fullAccessRequired:
            return keyboardString("keyboard.clipboard.full_access_required")
        case .pasteboardUnavailable:
            return keyboardString("keyboard.clipboard.read_failed")
        }
    }

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 10) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.orange)
                    .frame(width: 20, height: 20)

                Text(text)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 12)
            .frame(height: 36)
            .background(
                Capsule()
                    .fill(Color(.systemGray5).opacity(0.92))
            )
            .overlay(
                Capsule()
                    .strokeBorder(Color.orange.opacity(0.38), lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
    }
}

/// ClipboardBridge X close button: dismisses the preview without inserting
/// and WITHOUT clearing UIPasteboard.
private struct ClipboardDismissButton: View {
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            Image(systemName: "xmark")
                .font(.system(size: 18, weight: .regular))
                .foregroundStyle(.secondary)
                .frame(width: 56, height: 36)
                .background(
                    Capsule()
                        .fill(Color(.systemGray6).opacity(0.96))
                )
        }
        .buttonStyle(.plain)
    }
}

private struct ToolbarLeadingActionButton: View {
    let title: String
    let action: (() -> Void)?

    var body: some View {
        Button {
            action?()
        } label: {
            Text(title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(width: 44, height: 36)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color(.secondarySystemBackground))
                )
        }
        .buttonStyle(.plain)
        .disabled(action == nil)
    }
}

private struct ChineseModeToggleButton: View {
    let mode: ChineseInputMode
    let onToggle: ((ChineseInputMode) -> Void)?

    private var title: String {
        switch mode {
        case .chineseQwerty:
            return "九键"
        case .chineseNineGrid:
            return "26键"
        case .english:
            return "中文"
        case .symbols, .voice:
            return "中文"
        }
    }

    private var nextMode: ChineseInputMode {
        switch mode {
        case .chineseQwerty:
            return .chineseNineGrid
        case .chineseNineGrid, .symbols, .voice:
            return .chineseQwerty
        case .english:
            return .chineseQwerty
        }
    }

    var body: some View {
        Button {
            onToggle?(nextMode)
        } label: {
            Text(title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(width: 44, height: 36)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color(.secondarySystemBackground))
                )
        }
        .buttonStyle(.plain)
        .disabled(onToggle == nil)
    }
}
