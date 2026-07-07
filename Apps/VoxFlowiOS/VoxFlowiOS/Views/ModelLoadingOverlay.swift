// DictusApp/Views/ModelLoadingOverlay.swift
// Full-screen blocking overlay shown while a model is downloading, compiling
// for the Neural Engine, or being loaded into RAM. Issue #144.
import SwiftUI
import Shared

/// Full-screen cover that surfaces long-running model preparation work to the user.
///
/// Why this exists:
/// Whisper turbo (~954 MB) takes ~2 min of one-off Core ML compilation on a 15 Pro Max
/// and a couple of seconds to load into RAM after each cold start. Without a blocking UI
/// the user could mistake the wait for a frozen app, tap the keyboard mic mid-load,
/// and trigger a `Swift.CancellationError` cascade (issue #144). The overlay refuses
/// any further model interaction until `modelLoadState == .ready`.
///
/// The overlay observes two signals to decide which copy to show:
/// 1. `ModelManager.modelStates[id]` — `.downloading`, `.prewarming`, `.ready`
/// 2. `ModelManager.modelLoadState` (mirrored from the App Group via Combine) —
///    `.loading` once `DictationCoordinator.preloadActiveModel` is in flight.
struct ModelLoadingOverlay: View {
    @ObservedObject var modelManager: ModelManager

    /// Identifier of the model the user just acted on (download or select).
    /// Drives the phase logic and which copy is shown.
    let modelIdentifier: String

    /// Two-way binding controlled by the parent. The overlay flips it to false
    /// once the model becomes ready so the cover dismisses itself.
    @Binding var isPresented: Bool

    @State private var showCompletion = false

    /// Tracks whether we have ever observed an active prep phase (downloading,
    /// compiling, or loading). Without this, the overlay would auto-dismiss
    /// when presented synchronously by the parent before `downloadModel`
    /// has had a chance to flip `modelStates[id]` from `.notDownloaded` to
    /// `.downloading` — the onboarding race that surfaced after f5ba7ab.
    @State private var hasSeenWorkPhase = false

    private enum Phase {
        case downloading
        case compiling
        case loading
        case ready
    }

    var body: some View {
        ZStack {
            // Adaptive brand background — auto switches between light/dark
            // (#F2F2F7 in light, #0A1628 in dark).
            Color.dictusBackground.ignoresSafeArea()

            // Waveform sits behind the central column. Same height/opacity as the
            // onboarding welcome screen so the visual identity is consistent. Full
            // edge-to-edge width — no horizontal padding.
            BrandWaveform(maxHeight: 100, isProcessing: true)
                .opacity(0.55)
                .allowsHitTesting(false)

            VStack(spacing: 0) {
                Spacer(minLength: 24)

                modelTitleHeader
                    .padding(.top, 24)

                Spacer()

                // Fixed-height swap area so toggling between active and completion
                // states doesn't reflow the surrounding layout (and shift the
                // background waveform).
                ZStack {
                    if showCompletion {
                        completionView
                            .transition(.opacity.combined(with: .scale(scale: 0.94)))
                    } else {
                        activeView
                            .transition(.opacity)
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 140)

                Spacer()

                stayOnPageNotice
                    .padding(.bottom, 40)
            }
        }
        .interactiveDismissDisabled(true)
        .onReceive(NotificationCenter.default.publisher(for: .dictusModelLoadStateChanged)) { _ in
            checkForCompletion()
        }
        .onChange(of: currentModelState) { _, _ in
            checkForCompletion()
        }
        .onAppear {
            checkForCompletion()
        }
    }

    // MARK: - Sub-views

    private var modelTitleHeader: some View {
        // Tracking value used on the phase label. Pulled out so the leading
        // compensation padding stays in sync — `.tracking()` adds half its width
        // of trailing space after the last character, which shifts the optical
        // center off relative to the un-tracked model name above. We add the
        // same width as a leading offset to push the label back to true center.
        let labelTracking: CGFloat = 1.4

        return VStack(spacing: 8) {
            if let info = ModelInfo.forIdentifier(modelIdentifier) {
                Text(info.displayName)
                    .font(.dictusSubheading)
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity)
                    .multilineTextAlignment(.center)
            }
            Text(phaseLabel)
                .font(.caption.weight(.semibold))
                .textCase(.uppercase)
                .foregroundStyle(Color.dictusAccent)
                .tracking(labelTracking)
                .padding(.leading, labelTracking)
                .frame(maxWidth: .infinity)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }

    @ViewBuilder
    private var activeView: some View {
        VStack(spacing: 24) {
            if currentPhase == .downloading,
               let progress = modelManager.downloadProgress[modelIdentifier] {
                VStack(spacing: 6) {
                    ProgressView(value: Double(progress), total: 1.0)
                        .progressViewStyle(.linear)
                        .tint(.dictusAccent)
                        .frame(maxWidth: 240)
                    Text("\(Int(progress * 100)) %")
                        .font(.dictusCaption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            CyclingLoadingText(phrases: phrases(for: currentPhase))
        }
    }

    private var completionView: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 48, weight: .semibold))
                .foregroundStyle(Color.dictusAccent)
            Text(L10n.t("model_loading.ready"))
                .font(.dictusSubheading)
                .foregroundStyle(.primary)
        }
    }

    private var stayOnPageNotice: some View {
        Text(L10n.t("model_loading.stay_on_page"))
            .font(.dictusCaption)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 48)
    }

    // MARK: - Phase logic

    private var currentModelState: ModelState {
        modelManager.modelStates[modelIdentifier] ?? .notDownloaded
    }

    private var currentPhase: Phase {
        let raw = rawPhase
        // While we have not yet seen a real work phase, treat `.ready` as the
        // initial download phase so the copy doesn't briefly flash "ready"
        // before the parent's async download Task starts. This is the seam
        // that fixes the onboarding presentation race (commit f5ba7ab follow-up).
        if !hasSeenWorkPhase && raw == .ready {
            return .downloading
        }
        return raw
    }

    private var rawPhase: Phase {
        switch currentModelState {
        case .downloading:
            return .downloading
        case .prewarming:
            return .compiling
        case .ready:
            switch modelManager.modelLoadState {
            case .loading:
                return .loading
            case .ready:
                return .ready
            case .idle:
                // Defensive: model is ready on disk but no load is in flight.
                // Treat as ready so the overlay can dismiss.
                return .ready
            }
        case .notDownloaded, .unavailable, .error:
            return .ready
        }
    }

    private var phaseLabel: String {
        switch currentPhase {
        case .downloading: return L10n.t("model_loading.phase.downloading")
        case .compiling: return L10n.t("model_loading.phase.compiling")
        case .loading: return L10n.t("model_loading.phase.loading")
        case .ready: return L10n.t("model_loading.phase.ready")
        }
    }

    private func phrases(for phase: Phase) -> [String] {
        switch phase {
        case .downloading:
            return [
                L10n.t("model_loading.downloading.1"),
                L10n.t("model_loading.downloading.2"),
                L10n.t("model_loading.downloading.3"),
                L10n.t("model_loading.downloading.4"),
                L10n.t("model_loading.downloading.5")
            ]
        case .compiling:
            // Turbo's compile takes ~2 minutes — needs enough variety so the
            // copy doesn't visibly loop within that window.
            return [
                L10n.t("model_loading.compiling.1"),
                L10n.t("model_loading.compiling.2"),
                L10n.t("model_loading.compiling.3"),
                L10n.t("model_loading.compiling.4"),
                L10n.t("model_loading.compiling.5"),
                L10n.t("model_loading.compiling.6"),
                L10n.t("model_loading.compiling.7"),
                L10n.t("model_loading.compiling.8"),
                L10n.t("model_loading.compiling.9"),
                L10n.t("model_loading.compiling.10"),
                L10n.t("model_loading.compiling.11"),
                L10n.t("model_loading.compiling.12")
            ]
        case .loading:
            return [
                L10n.t("model_loading.loading.1"),
                L10n.t("model_loading.loading.2"),
                L10n.t("model_loading.loading.3"),
                L10n.t("model_loading.loading.4"),
                L10n.t("model_loading.loading.5")
            ]
        case .ready:
            return []
        }
    }

    private func checkForCompletion() {
        // Latch the work-phase flag the first time we observe real activity.
        // We read `rawPhase` here (not the user-facing `currentPhase`) because
        // the latter masquerades the initial `.ready` state as `.downloading`
        // until this flag flips, which would cause an infinite loop.
        if rawPhase != .ready {
            hasSeenWorkPhase = true
            return
        }
        // The model is ready, but if we have never seen any actual work happen
        // yet, the parent likely just opened the overlay and the state will
        // imminently flip to `.downloading`. Keep the cover up.
        guard hasSeenWorkPhase else { return }
        guard !showCompletion else { return }

        withAnimation(.easeInOut(duration: 0.35)) {
            showCompletion = true
        }

        // Brief celebration moment before the cover slides away.
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 900_000_000)
            withAnimation(.easeOut(duration: 0.4)) {
                isPresented = false
            }
        }
    }
}

#Preview("Downloading — light") {
    ModelLoadingOverlay(
        modelManager: {
            let m = ModelManager()
            m.modelStates["openai_whisper-large-v3_turbo_954MB"] = .downloading
            m.downloadProgress["openai_whisper-large-v3_turbo_954MB"] = 0.42
            return m
        }(),
        modelIdentifier: "openai_whisper-large-v3_turbo_954MB",
        isPresented: .constant(true)
    )
    .preferredColorScheme(.light)
}

#Preview("Compiling — dark") {
    ModelLoadingOverlay(
        modelManager: {
            let m = ModelManager()
            m.modelStates["openai_whisper-large-v3_turbo_954MB"] = .prewarming
            return m
        }(),
        modelIdentifier: "openai_whisper-large-v3_turbo_954MB",
        isPresented: .constant(true)
    )
    .preferredColorScheme(.dark)
}
