# Source Attribution

## Current Implementation

No TypeWhisper implementation has been copied verbatim. The Phase 1 core models materially adapt the domain concepts documented by TypeWhisper, while using VoxFlow-specific names, fields, validation rules, and persistence boundaries.

## Approved TypeWhisper References

- `TypeWhisper/Models/DictionaryEntry.swift`
  - Adapted VoxFlow files: `Core/CorrectionRule.swift`, `Core/MatchPolicy.swift`, `Core/RuleScope.swift`, `Core/RuleLifecycle.swift`.
  - Adapted concepts: original/replacement pair, enabled state, case sensitivity, source metadata, confidence and usage counters.
- `TypeWhisper/Services/DictionaryService.swift`
  - Adapted VoxFlow files: `Matching/BoundaryClassifier.swift`, `Matching/LinearRuleMatcher.swift`, `Matching/ReplacementApplier.swift`, `Core/CorrectionEvent.swift`.
  - Adapted concepts: case-sensitive or case-insensitive deterministic matching, boundary-safe corrections, empty manual replacements, and correction event metadata.
  - VoxFlow-specific additions: immutable raw-text match collection, UTF-16 spans, deterministic overlap resolution, end-to-start application, and non-cascading engine composition.
  - VoxFlow-specific safety additions: `Matching/ContextGate.swift` keeps command, translation, interim transcript, secure field, disabled rules, inactive lifecycle, and mismatched app/provider/model/language scope out of runtime correction.
- `TypeWhisper/Services/PostProcessingPipeline.swift`
  - Adapted VoxFlow file: `Processing/VoiceCorrectionEngine.swift`.
  - Adapted concept: one deterministic post-processing stage for dictionary corrections.
- `TypeWhisper/Services/TextDiffService.swift`
  - Adapted VoxFlow file: `Learning/HighConfidenceCorrectionExtractor.swift`.
  - Adapted concepts: high-confidence substitution extraction and rejection of rewrite, insertion-only, deletion-only, ambiguity, casing-only, punctuation-only, out-of-inserted-range, and applied-correction-overlap feedback.
- `TypeWhisper/Services/TargetAppCorrectionLearningService.swift`
  - Adapted VoxFlow files: `Learning/FocusedTextObservation.swift`, App-layer `CorrectionObservationCoordinator.swift`.
  - Adapted concepts: capture a baseline focused element, recapture only the same element after insertion, poll at 2 / 5 / 10 seconds, and learn only conservative corrections.
- `TypeWhisper/Services/TextInsertionService.swift`
  - Adapted VoxFlow file: App-layer `AccessibilityFocusedTextObserver.swift`.
  - Adapted concepts: AX focused element, readable value, selected range, secure-field guard, and same-element verification; VoxFlow keeps its existing text insertion contract.

## Non-TypeWhisper References

- FlashText: data model and replacement behavior ideas only, no runtime source copied.
- JiWER: benchmark cross-check tool only, no production source copied.
- OpenAI Evals / LanguageTool style fixtures: benchmark structure inspiration only, no runtime source copied.
