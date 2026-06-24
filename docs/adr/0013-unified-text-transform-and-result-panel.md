# Unify Text Transform and Result Panel

VoxFlow will use a shared Text Transform service and a shared Text Result Panel presentation layer for screenshot OCR text, selected text, translation, and summary results. Screenshot OCR and Selection Actions keep separate entry points and ViewModels because their source state and output recovery rules differ, but sharing the transform stream and result UI prevents three parallel translation implementations and makes long-text progress, cancellation, partial output, copy, replacement, insertion, and speech playback behave consistently.

## Considered Options

- Keep screenshot OCR translation, screenshot overlay translation, and Selection Actions translation separate: rejected because it would preserve the current slow large-image translation path and create repeated streaming/cancellation logic.
- Reuse the existing screenshot result ViewModel for selected text: rejected because screenshot-specific state such as original image, translated overlay image, image copy, and OCR tabs would leak into selection-only flows.
- Share only the visual components and transform service: accepted because it keeps UI consistency while preserving clean business boundaries.
