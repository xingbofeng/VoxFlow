// DictusKeyboard/Views/SuggestionBarView.swift
// Displays word, correction, prediction, and Chinese composition candidates.
import SwiftUI

struct SuggestionDisplayPolicy: Equatable {
    let lineLimit: Int
    let truncationMode: Text.TruncationMode
    let minimumScaleFactor: CGFloat
    let usesHorizontalScroll: Bool
    let fontSize: CGFloat
    let minTouchHeight: CGFloat
    let minItemWidth: CGFloat
    let expandButtonWidth: CGFloat

    static func policy(for mode: SuggestionMode) -> SuggestionDisplayPolicy {
        switch mode {
        case .chineseCandidates:
            return SuggestionDisplayPolicy(
                lineLimit: 1,
                truncationMode: .tail,
                minimumScaleFactor: 0.9,
                usesHorizontalScroll: true,
                fontSize: 21,
                minTouchHeight: 48,
                minItemWidth: 60,
                expandButtonWidth: 76
            )
        default:
            return SuggestionDisplayPolicy(
                lineLimit: 1,
                truncationMode: .tail,
                minimumScaleFactor: 0.75,
                usesHorizontalScroll: false,
                fontSize: 15,
                minTouchHeight: 36,
                minItemWidth: 0,
                expandButtonWidth: 0
            )
        }
    }
}

/// Suggestion strip rendered above the key grid.
///
/// Chinese candidates intentionally use a horizontally scrollable chip strip:
/// the video repro showed a cramped 15pt row with a tiny disclosure affordance,
/// making later/earlier candidates hard to browse and tap. Each Chinese
/// candidate now gets a 44pt touch target, matching iOS touch guidance.
struct SuggestionBarView: View {
    let suggestions: [String]
    let mode: SuggestionMode
    let onTap: (Int) -> Void
    var isExpanded: Bool = false
    var onExpand: (() -> Void)? = nil
    /// Total number of candidates for the current composition. When it exceeds
    /// the readable strip width, a small count badge is shown on the expand
    /// button so users know more candidates are reachable. Defaults to the
    /// visible list length when omitted.
    var candidateCount: Int? = nil

    private var totalCandidateCount: Int {
        candidateCount ?? suggestions.count
    }

    private var showsCandidateCount: Bool {
        mode == .chineseCandidates && totalCandidateCount > suggestions.count && onExpand != nil
    }

    private var displayPolicy: SuggestionDisplayPolicy {
        SuggestionDisplayPolicy.policy(for: mode)
    }

    var body: some View {
        if suggestions.isEmpty {
            EmptyView()
        } else if mode == .chineseCandidates {
            chineseCandidateStrip
        } else {
            standardSuggestionStrip
        }
    }

    private var chineseCandidateStrip: some View {
        HStack(spacing: 6) {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color(.systemBackground).opacity(0.58))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(Color(.separator).opacity(0.18), lineWidth: 0.5)
                    )
                    .contentShape(Rectangle())

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(Array(suggestions.enumerated()), id: \.offset) { index, suggestion in
                            Button {
                                onTap(index)
                            } label: {
                                Text(displayText(suggestion, at: index))
                                    .font(.system(size: displayPolicy.fontSize, weight: fontWeight(at: index)))
                                    .foregroundColor(Color(.label))
                                    .lineLimit(displayPolicy.lineLimit)
                                    .truncationMode(displayPolicy.truncationMode)
                                    .minimumScaleFactor(displayPolicy.minimumScaleFactor)
                                    .fixedSize(horizontal: true, vertical: false)
                                    .padding(.horizontal, 16)
                                    .frame(minWidth: displayPolicy.minItemWidth)
                                    .frame(minHeight: displayPolicy.minTouchHeight)
                                    .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            }
                            .buttonStyle(.plain)
                            .background(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(index == 0 ? Color(.systemBackground).opacity(0.96) : Color(.systemBackground).opacity(0.28))
                            )
                        }
                    }
                    .padding(.leading, 10)
                    .padding(.trailing, 12)
                    .frame(maxWidth: .infinity, minHeight: displayPolicy.minTouchHeight, alignment: .leading)
                }
                .frame(height: displayPolicy.minTouchHeight)
                .contentShape(Rectangle())

                HStack {
                    edgeFade(from: Color(.systemGray5), to: Color(.systemGray5).opacity(0))
                        .frame(width: 10)

                    Spacer()

                    edgeFade(from: Color(.systemGray5).opacity(0), to: Color(.systemGray5))
                        .frame(width: 16)
                }
                .allowsHitTesting(false)
            }
            .frame(maxWidth: .infinity, minHeight: displayPolicy.minTouchHeight)
            .contentShape(Rectangle())

            Button {
                onExpand?()
            } label: {
                HStack(spacing: 4) {
                    if showsCandidateCount {
                        Text("\(totalCandidateCount)")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 6)
                            .frame(minHeight: 20)
                            .background(
                                Capsule()
                                    .fill(Color(.systemGray4).opacity(0.5))
                            )
                    }
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(.secondary)
                }
                .frame(width: displayPolicy.expandButtonWidth + (showsCandidateCount ? 24 : 0), height: displayPolicy.minTouchHeight)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color(.systemBackground).opacity(0.88))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(Color(.separator).opacity(0.22), lineWidth: 0.5)
                )
                .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(onExpand == nil)
            .opacity(onExpand == nil ? 0.35 : 1)
        }
        .frame(maxWidth: .infinity, minHeight: displayPolicy.minTouchHeight)
        .contentShape(Rectangle())
        .accessibilityLabel("中文候选")
        .transition(.opacity)
        .animation(.easeInOut(duration: 0.15), value: suggestions)
    }

    private var standardSuggestionStrip: some View {
        HStack(spacing: 0) {
            ForEach(Array(suggestions.enumerated()), id: \.offset) { index, suggestion in
                if index > 0 {
                    Rectangle()
                        .fill(Color(.systemGray3))
                        .frame(width: 0.5)
                        .padding(.vertical, 8)
                }

                Button {
                    onTap(index)
                } label: {
                    Text(displayText(suggestion, at: index))
                        .font(.system(size: displayPolicy.fontSize))
                        .fontWeight(fontWeight(at: index))
                        .foregroundColor(Color(.label))
                        .lineLimit(displayPolicy.lineLimit)
                        .truncationMode(displayPolicy.truncationMode)
                        .minimumScaleFactor(displayPolicy.minimumScaleFactor)
                        .allowsTightening(true)
                        .frame(maxWidth: .infinity)
                        .frame(height: displayPolicy.minTouchHeight)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .transition(.opacity)
        .animation(.easeInOut(duration: 0.15), value: suggestions)
    }

    private func edgeFade(from leading: Color, to trailing: Color) -> some View {
        LinearGradient(
            colors: [leading, trailing],
            startPoint: .leading,
            endPoint: .trailing
        )
    }

    /// In correction mode, the original word (index 0) is shown in quotes
    /// to indicate it's the "as-typed" option. Matches iOS native behavior
    /// where the unquoted bold center word is the one that gets auto-applied.
    private func fontWeight(at index: Int) -> Font.Weight {
        switch mode {
        case .chineseCandidates:
            return index == 0 ? .semibold : .regular
        case .predictions:
            return .regular
        case .undoAvailable:
            return index == 0 ? .semibold : .regular
        default:
            return index == 1 ? .semibold : .regular
        }
    }

    private func displayText(_ suggestion: String, at index: Int) -> String {
        if mode == .corrections && index == 0 {
            return "\u{201C}\(suggestion)\u{201D}"
        }
        if mode == .undoAvailable && index == 0 {
            return suggestion + " \u{21A9}"
        }
        return suggestion
    }
}
