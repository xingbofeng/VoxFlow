// DictusApp/Views/ModelCardView.swift
// Individual model card with gauges, engine badge, and tap-to-select/download interaction.
import SwiftUI
import Shared

/// Displays a single model's metadata and state-dependent controls inside a glass card.
///
/// WHY a separate view (not inline in ForEach):
/// Each model card has complex layout (4 rows) and interaction logic (download, select,
/// delete, progress, error states). Extracting keeps ModelManagerView's body clean and
/// makes each card independently previewable.
///
/// INTERACTION MODEL (v2 — tap-to-act):
/// The entire card is a single tappable surface. Behavior depends on model state:
/// - .ready + not active -> select as active model
/// - .notDownloaded -> start download
/// - .error -> cleanup and retry
/// - .downloading / .prewarming -> card disabled (no tap)
///
/// WHY no separate buttons:
/// Removing "Choisir", download arrow, and trash buttons simplifies the UI.
/// Cards behave like native radio buttons — tap to select. Deletion uses
/// swipe-to-delete in the parent ModelManagerView (like iOS Mail).
///
/// LAYOUT (top to bottom):
/// Row 1: displayName + engine badge ("WK"/"PK") + optional "Recommended" badge
/// Row 2: Short localized description
/// Row 3: Two gauge bars side-by-side (Accuracy in blue, Speed in blue highlight)
/// Row 4: Size label + state-dependent status indicator
struct ModelCardView: View {
    let model: ModelInfo
    @ObservedObject var modelManager: ModelManager
    let onDownloadError: (String) -> Void

    /// The current state for this model, with a safe default.
    private var state: ModelState {
        modelManager.modelStates[model.identifier] ?? .notDownloaded
    }

    /// Whether this model is the currently active one.
    private var isActive: Bool {
        modelManager.activeModel == model.identifier
    }

    /// Whether the card should be tappable (disabled during download/prewarming).
    private var isCardDisabled: Bool {
        switch state {
        case .downloading, .prewarming, .unavailable:
            return true
        default:
            return false
        }
    }

    private var isUnavailable: Bool {
        if case .unavailable = state {
            return true
        }
        return false
    }

    var body: some View {
        Button {
            handleCardTap()
        } label: {
            cardContent
                .contentShape(Rectangle())
        }
        .buttonStyle(GlassPressStyle(pressedScale: 0.95))
        .disabled(isCardDisabled)
    }

    // MARK: - Card content

    private var cardContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Row 1: Name + engine badge + recommended badge
            HStack(spacing: 6) {
                Text(model.displayName)
                    .font(.dictusSubheading)

                // Engine badge pill (e.g. "WK" or "PK")
                Text(model.engine.rawValue)
                    .font(.caption2.bold())
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.dictusAccent)
                    .foregroundColor(.white)
                    .cornerRadius(4)

                if modelManager.isRecommended(model.identifier) {
                    Text(L10n.t("services.recommended"))
                        .font(.caption2.bold())
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.dictusAccent.opacity(0.15))
                        .foregroundColor(.dictusAccent)
                        .cornerRadius(4)
                }
            }

            // Row 2: Localized description
            Text(model.localizedDescription)
                .font(.dictusCaption)
                .foregroundStyle(.secondary)

            // Row 3: Gauge bars OR full-width progress during download/prewarming
            if case .downloading = state, let progress = modelManager.downloadProgress[model.identifier] {
                // Full-width progress bar replaces gauges during download
                VStack(spacing: 4) {
                    ProgressView(value: progress, total: 1.0)
                        .tint(.dictusAccent)
                    Text("\(Int(progress * 100))%")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
            } else if case .prewarming = state {
                // Full-width indeterminate progress during CoreML compilation
                VStack(spacing: 4) {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                    Text(L10n.t("services.optimizing"))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            } else {
                // Normal gauge bars (Accuracy + Speed) — both blue palette
                HStack(spacing: 16) {
                    GaugeBarView(
                        value: model.accuracyScore,
                        label: L10n.t("services.gauge.accuracy"),
                        color: .dictusAccent
                    )

                    GaugeBarView(
                        value: model.speedScore,
                        label: L10n.t("services.gauge.speed"),
                        color: .dictusAccentHighlight
                    )
                }
            }

            // Row 4: Size + state-dependent status indicator
            HStack {
                Label(model.sizeLabel, systemImage: "internaldrive")
                    .font(.dictusCaption)
                    .foregroundStyle(.secondary)

                Spacer()

                trailingContent
            }
        }
        .padding(16)
        .background(
            Group {
                if isActive {
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color.dictusAccent.opacity(0.10))
                }
            }
        )
        .dictusGlass()
        .overlay(
            // Active model gets a dark blue border stroke on top of glass
            Group {
                if isActive {
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(
                            isUnavailable ? Color(.systemGray3) : Color.dictusAccent.opacity(0.6),
                            lineWidth: 2
                        )
                }
            }
        )
        .opacity(isUnavailable ? 0.55 : 1)
        .saturation(isUnavailable ? 0.2 : 1)
    }

    // MARK: - Tap handler

    /// Routes card tap based on current model state.
    ///
    /// WHY a function instead of inline closure:
    /// Multiple state branches with different async/sync behavior.
    /// A named function keeps the Button action clean and testable.
    private func handleCardTap() {
        switch state {
        case .ready:
            if !isActive {
                modelManager.selectModel(model.identifier)
            }
        case .notDownloaded:
            Task {
                do {
                    try await modelManager.downloadModel(model.identifier)
                } catch {
                    onDownloadError(error.localizedDescription)
                }
            }
        case .error:
            modelManager.cleanupFailedModel(model.identifier)
        case .downloading, .prewarming, .unavailable:
            // Card is disabled in these states — this shouldn't fire
            break
        }
    }

    // MARK: - State-dependent trailing content

    /// The trailing content changes based on the model's current state.
    /// Now shows status indicators only (no action buttons — the card itself is the button).
    @ViewBuilder
    private var trailingContent: some View {
        switch state {
        case .notDownloaded:
            // Subtle download hint icon
            Image(systemName: "arrow.down.circle")
                .font(.title2)
                .foregroundColor(.dictusAccent)

        case .downloading:
            // Progress is shown full-width in card body (Row 3)
            EmptyView()

        case .prewarming:
            // Progress is shown full-width in card body (Row 3)
            EmptyView()

        case .ready:
            // No checkmark, no button — active state shown via background tint + border
            EmptyView()

        case .unavailable(let message):
            Image(systemName: "lock.circle")
                .font(.title3)
                .foregroundStyle(.secondary)
                .help(message)

        case .error(let message):
            VStack(spacing: 2) {
                Image(systemName: "arrow.clockwise.circle")
                    .font(.title3)
                    .foregroundColor(.orange)
                Text(L10n.t("common.retry"))
                    .font(.caption2)
                    .foregroundColor(.orange)
            }
            .help(message)
        }
    }
}

#Preview {
    ScrollView {
        VStack(spacing: 12) {
            ModelCardView(
                model: ModelInfo.all[0],
                modelManager: ModelManager(),
                onDownloadError: { _ in }
            )
        }
        .padding()
    }
    .background(Color.dictusBackground)
}
