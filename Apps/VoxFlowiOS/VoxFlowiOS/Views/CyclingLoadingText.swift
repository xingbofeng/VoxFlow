// DictusApp/Views/CyclingLoadingText.swift
// Reusable text element that cycles through localized phrases with a fade
// transition. Used by ModelLoadingOverlay (issue #144) to reassure the user
// during long model download / compile / RAM-load operations.
import SwiftUI
import Shared

/// Cycles through a list of phrases on a fixed interval with a soft fade
/// transition between each phrase. Inspired by Claude Code's loading copy.
///
/// The driving timer is anchored to the SwiftUI `.task` modifier, so it stops
/// automatically when the view disappears (no manual invalidation needed).
struct CyclingLoadingText: View {
    /// Phrases to rotate through. Already-localized strings expected — the parent
    /// is responsible for picking the right set for the current load phase.
    let phrases: [String]

    /// Interval between phrase changes, in seconds.
    var interval: TimeInterval = 2.5

    @State private var index: Int = 0

    var body: some View {
        Text(currentPhrase)
            // Lighter weight + body size — softer and avoids visually shouting.
            .font(.system(.callout, design: .default, weight: .regular))
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .lineLimit(2, reservesSpace: true)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 32)
            // .id forces SwiftUI to treat each phrase as a distinct view so the
            // .transition runs on every change rather than animating in place.
            .id(currentPhrase)
            .transition(.opacity.combined(with: .scale(scale: 0.97)))
            .task(id: phrases) {
                guard !phrases.isEmpty else { return }
                index = 0
                while !Task.isCancelled {
                    do {
                        try await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
                    } catch {
                        return
                    }
                    if Task.isCancelled { return }
                    withAnimation(.easeInOut(duration: 0.45)) {
                        index = (index + 1) % phrases.count
                    }
                }
            }
    }

    private var currentPhrase: String {
        guard !phrases.isEmpty else { return "" }
        return phrases[index % phrases.count]
    }
}

#Preview {
    ZStack {
        Color.black.ignoresSafeArea()
        CyclingLoadingText(phrases: [
            "Téléchargement du modèle…",
            "Réception des poids neuronaux…",
            "Presque arrivé…"
        ], interval: 1.5)
    }
}
