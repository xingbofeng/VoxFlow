# Modifications

This package adapts TypeWhisper-inspired correction ideas to VoxFlow's architecture.

Implemented and planned differences:

- Use VoxFlow naming: `VoxFlowVoiceCorrection`, not TypeWhisper runtime naming.
- Apply correction only to ordinary dictation final transcripts after optional LLM refinement.
- Keep Agent Compose, command, translation, interim transcripts, and secure fields outside Phase 1 correction.
- Match against immutable raw input, resolve conflicts once, and apply replacements from the end to avoid cascading replacements.
- Persist rules through VoxFlow SQLite repositories while keeping the matcher on immutable snapshots.
- Test focused text observation with fake observers and fake clocks so CI does not require Accessibility permission.
- Keep UI implementation VoxFlow-specific; do not copy TypeWhisper UI layout or naming.

## Core model implementation

- Split the rule model into VoxFlow-specific `Core` value types with `Codable`, `Equatable`, and strict `Sendable` boundaries.
- Added explicit global/application scope, lifecycle, rule source, provider/model/language metadata, counters, immutable snapshots, correction events, and fail-open warnings.
- Added validation for empty or self-replacing rules, size and confidence limits, and conservative automatic-learning restrictions.

## Deterministic matching implementation

- Replaced TypeWhisper's service-owned mutation flow with stateless matcher, resolver, and applier value types.
- Collect all matches from immutable raw text and apply resolved replacements from the end, preventing same-pass cascades.
- Represent spans as UTF-16 offsets so AppKit, Accessibility, SQLite events, and benchmark reports share one range convention.
- Resolve overlaps deterministically using source, scope, policy, confidence, length, position, and rule ID.
- Added a VoxFlow-specific `ContextGate` so Phase 1 correction only applies to ordinary dictation final transcripts and fails open for unsupported modes or privacy-sensitive fields.

## Focused text observation implementation

- Replaced direct `AXUIElement` coupling with a Foundation-only observation contract using opaque element identities.
- Kept Accessibility reads in the App adapter and prevented secure-field value reads.
- Added a fake observer and fake clock boundary so unit tests do not require Accessibility permission or wall-clock delays.
- Added a conservative learning coordinator that polls at TypeWhisper's 2 / 5 / 10 second offsets, stores app-scoped learned rules, respects the auto-learning and direct-apply settings, and rejects feedback loops from already-applied corrections.
- Added a pure high-confidence extractor so rewrite, insertion-only, deletion-only, ambiguous, out-of-range, and overlap cases are rejected before persistence.
- Added learning lifecycle policy for manual rules, active/candidate automatic rules, 30-day suppression, undo actions, confidence reduction, and suspension after repeated user reverts.
