import Foundation
import Shared
import UIKit

/// Phase state for the ClipboardDictationHandoffView.
///
/// Lifecycle:
/// 1. `preparing` — view appeared, about to request mic permission
/// 2. `requestingPermission` — `AVAudioApplication.requestRecordPermission` in flight
/// 3. `recording` — streaming ASR running, live partial displayed
/// 4. `finalizing` — user tapped "Finish & Copy", waiting for final text (max 8s)
/// 5. `copied` — final or fallback partial copied to UIPasteboard
/// 6. `empty` — no partial or final text, pasteboard NOT overwritten
/// 7. `failed` — ASR or mic permission error
/// 8. `cancelled` — user cancelled before completion
enum ClipboardDictationHandoffPhase: String, Equatable, Sendable {
    case preparing
    case requestingPermission
    case recording
    case finalizing
    case copied
    case empty
    case failed
    case cancelled
}

/// Snapshot of the handoff presentation state — what the view binds to.
struct ClipboardDictationHandoffSnapshot: Equatable {
    let phase: ClipboardDictationHandoffPhase
    let providerDisplayName: String
    let partialText: String
    let finalText: String?
    let copiedText: String?
    let copiedTextPreview: String?
    let copiedWasFallbackPartial: Bool
    let errorMessage: String?

    static let initial = ClipboardDictationHandoffSnapshot(
        phase: .preparing,
        providerDisplayName: "",
        partialText: "",
        finalText: nil,
        copiedText: nil,
        copiedTextPreview: nil,
        copiedWasFallbackPartial: false,
        errorMessage: nil
    )
}

/// Pure state machine for the clipboard dictation handoff page.
///
/// WHY a separate state object: the existing `DictationCoordinator` is
/// AppGroupBridge-shaped — it writes results to AppGroup defaults and posts
/// Darwin notifications so the keyboard can insert. The ClipboardBridge path
/// is different: it writes results to UIPasteboard and the keyboard reads
/// them on its next appearance. Keeping the state machine separate avoids
/// tangling the two paths and lets us unit-test the phase transitions
/// (partial → finalizing → copied; finalizing timeout → fallback partial;
/// empty result → no overwrite; cancel; background).
///
/// The state machine itself is MainActor-isolated and owns no I/O — it just
/// transitions state and emits intents that the view / coordinator executes.
@MainActor
final class ClipboardDictationHandoffState: ObservableObject {
    @Published private(set) var snapshot: ClipboardDictationHandoffSnapshot

    /// How long to wait for a final result after the user taps "Finish &
    /// Copy" before falling back to the latest partial. Per spec: 8 seconds.
    static let finalizingTimeoutSeconds: TimeInterval = 8.0

    /// When the user taps "Finish & Copy" while in `.recording`, we transition
    /// to `.finalizing`. If no final arrives within `finalizingTimeoutSeconds`:
    ///   - non-empty partial → `.copied` with `copiedWasFallbackPartial=true`
    ///   - empty partial → `.empty` (no pasteboard write)
    private var finalizingTimer: Timer?
    private var finalizingStartTime: Date?

    init(providerDisplayName: String) {
        self.snapshot = .initial
        self.snapshot = ClipboardDictationHandoffSnapshot(
            phase: .preparing,
            providerDisplayName: providerDisplayName,
            partialText: "",
            finalText: nil,
            copiedText: nil,
            copiedTextPreview: nil,
            copiedWasFallbackPartial: false,
            errorMessage: nil
        )
    }

    // MARK: - Transitions (called by the view / coordinator)

    func transitionToRequestingPermission() {
        guard snapshot.phase == .preparing else { return }
        update(phase: .requestingPermission)
    }

    func transitionToRecording() {
        guard snapshot.phase == .preparing || snapshot.phase == .requestingPermission else { return }
        update(phase: .recording)
    }

    /// Update the partial text shown live during `.recording` or `.finalizing`.
    func updatePartial(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        switch snapshot.phase {
        case .recording, .finalizing, .preparing, .requestingPermission:
            snapshot = ClipboardDictationHandoffSnapshot(
                phase: snapshot.phase,
                providerDisplayName: snapshot.providerDisplayName,
                partialText: trimmed,
                finalText: snapshot.finalText,
                copiedText: snapshot.copiedText,
                copiedTextPreview: snapshot.copiedTextPreview,
                copiedWasFallbackPartial: snapshot.copiedWasFallbackPartial,
                errorMessage: snapshot.errorMessage
            )
        default:
            break
        }
    }

    /// Handle a final transcription result.
    /// - If we're in `.recording`: copy final, transition to `.copied`.
    /// - If we're in `.finalizing`: copy final, transition to `.copied` and
    ///   cancel the finalizing timer.
    /// - If the final is empty/whitespace and there's no partial: transition
    ///   to `.empty` (no pasteboard write).
    /// - If the final is empty but there's a partial: copy the partial as
    ///   fallback (treat it as a timeout-fallback result).
    func handleFinal(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        switch snapshot.phase {
        case .recording, .finalizing:
            finalizingTimer?.invalidate()
            finalizingTimer = nil
            if trimmed.isEmpty {
                if snapshot.partialText.isEmpty {
                    // No final, no partial — don't overwrite pasteboard.
                    update(phase: .empty, finalText: nil, copiedTextPreview: nil)
                } else {
                    // Empty final but non-empty partial — fall back to partial.
                    copyAndMarkCopied(
                        text: snapshot.partialText,
                        wasFallbackPartial: true,
                        finalText: nil
                    )
                }
            } else {
                copyAndMarkCopied(
                    text: trimmed,
                    wasFallbackPartial: false,
                    finalText: trimmed
                )
            }
        default:
            break
        }
    }

    /// User tapped "Finish & Copy" while in `.recording`. Transitions to
    /// `.finalizing` and starts the 8s timer.
    func beginFinalizing() {
        guard snapshot.phase == .recording else { return }
        update(phase: .finalizing)
        finalizingStartTime = Date()
        finalizingTimer = Timer.scheduledTimer(
            withTimeInterval: Self.finalizingTimeoutSeconds,
            repeats: false
        ) { [weak self] _ in
            Task { @MainActor in
                self?.handleFinalizingTimeout()
            }
        }
    }

    /// Called when the finalizing timer fires (8s elapsed with no final).
    /// Internal access for unit tests to simulate timeout without waiting.
    func handleFinalizingTimeoutForTesting() {
        handleFinalizingTimeout()
    }

    /// Called when the finalizing timer fires (8s elapsed with no final).
    private func handleFinalizingTimeout() {
        guard snapshot.phase == .finalizing else { return }
        finalizingTimer = nil
        finalizingStartTime = nil
        if snapshot.partialText.isEmpty {
            // No final, no partial — don't overwrite pasteboard.
            update(phase: .empty, finalText: nil, copiedTextPreview: nil)
        } else {
            // Fallback: copy the latest partial.
            copyAndMarkCopied(
                text: snapshot.partialText,
                wasFallbackPartial: true,
                finalText: nil
            )
        }
    }

    /// User tapped "Cancel" while in `.recording` or `.finalizing`. Stops the
    /// timer and transitions to `.cancelled`. Does NOT write to the pasteboard.
    func cancel() {
        finalizingTimer?.invalidate()
        finalizingTimer = nil
        finalizingStartTime = nil
        switch snapshot.phase {
        case .recording, .finalizing, .preparing, .requestingPermission:
            update(phase: .cancelled)
        default:
            break
        }
    }

    /// Hard failure (ASR error, mic permission denied). Does NOT write to the
    /// pasteboard.
    func fail(_ message: String) {
        finalizingTimer?.invalidate()
        finalizingTimer = nil
        finalizingStartTime = nil
        update(phase: .failed, errorMessage: message)
    }

    /// Reset back to `.preparing` so the user can retry. Used by the "Dictate
    /// again" button on the `.empty` and `.failed` phases.
    func resetForRetry() {
        finalizingTimer?.invalidate()
        finalizingTimer = nil
        finalizingStartTime = nil
        snapshot = ClipboardDictationHandoffSnapshot(
            phase: .preparing,
            providerDisplayName: snapshot.providerDisplayName,
            partialText: "",
            finalText: nil,
            copiedText: nil,
            copiedTextPreview: nil,
            copiedWasFallbackPartial: false,
            errorMessage: nil
        )
    }

    /// Called by the view when it goes into the background. Per spec:
    /// - `.recording` → cancel immediately, no pasteboard write
    /// - `.finalizing` → allow up to 3s grace; the caller schedules the timer
    ///   and calls `handleFinalizingTimeout` if it elapses
    func handleBackgroundTransition() {
        switch snapshot.phase {
        case .recording, .preparing, .requestingPermission:
            // Recording interrupted by background — cancel, no copy.
            cancel()
        case .finalizing:
            // Allow up to 3s grace — caller is expected to schedule a timer
            // and call `handleFinalizingTimeout()` if it elapses. We invalidate
            // the original 8s timer here; the caller's 3s grace timer takes over.
            finalizingTimer?.invalidate()
            finalizingTimer = nil
        default:
            break
        }
    }

    /// Caller's grace timer fired while in `.finalizing` background state.
    func handleFinalizingBackgroundGraceTimeout() {
        handleFinalizingTimeout()
    }

    // MARK: - Internals

    private func copyAndMarkCopied(
        text: String,
        wasFallbackPartial: Bool,
        finalText: String?
    ) {
        // The actual UIPasteboard.string = ... write happens in the view /
        // coordinator — the state machine only records the intent. This keeps
        // the state machine testable without touching UIPasteboard.
        let preview: String
        if text.count > 60 {
            preview = String(text.prefix(30)) + "…" + String(text.suffix(30))
        } else {
            preview = text
        }
        snapshot = ClipboardDictationHandoffSnapshot(
            phase: .copied,
            providerDisplayName: snapshot.providerDisplayName,
            partialText: snapshot.partialText,
            finalText: finalText,
            copiedText: text,
            copiedTextPreview: preview,
            copiedWasFallbackPartial: wasFallbackPartial,
            errorMessage: nil
        )
    }

    private func update(
        phase: ClipboardDictationHandoffPhase,
        finalText: String? = nil,
        copiedText: String? = nil,
        copiedTextPreview: String? = nil,
        errorMessage: String? = nil
    ) {
        snapshot = ClipboardDictationHandoffSnapshot(
            phase: phase,
            providerDisplayName: snapshot.providerDisplayName,
            partialText: snapshot.partialText,
            finalText: finalText ?? snapshot.finalText,
            copiedText: copiedText ?? snapshot.copiedText,
            copiedTextPreview: copiedTextPreview ?? snapshot.copiedTextPreview,
            copiedWasFallbackPartial: snapshot.copiedWasFallbackPartial,
            errorMessage: errorMessage ?? snapshot.errorMessage
        )
    }
}
