#!/usr/bin/env bash

set -euo pipefail

windows_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
traceability="${windows_root}/docs/traceability.md"

test -f "${traceability}" || {
  printf '%s\n' 'Missing docs/traceability.md.' >&2
  exit 1
}

capabilities=(
  windows-cloud-asr
  windows-desktop-shell
  windows-dictation-runtime
  windows-local-qwen-asr
  windows-model-lifecycle
  windows-openai-llm
  windows-quality-and-distribution
  windows-settings-and-state
  windows-text-output
  windows-screenshot-capture-selection
  windows-screenshot-annotation-export
  windows-screenshot-ocr-transform
  windows-screenshot-media-history
)

for capability in "${capabilities[@]}"; do
  grep -Fq "${capability}" "${traceability}" || {
    printf 'Traceability matrix is missing capability: %s\n' "${capability}" >&2
    exit 1
  }
done

requirement_ids=()
for prefix_and_count in WCA:6 WDS:6 WDR:5 WQA:4 WML:5 WOL:4 WQD:7 WSS:5 WTO:4 WSC:4 WSA:3 WSO:3 WSM:3; do
  prefix="${prefix_and_count%%:*}"
  count="${prefix_and_count##*:}"
  for number in $(seq 1 "${count}"); do
    requirement_ids+=("$(printf '%s-%02d' "${prefix}" "${number}")")
  done
done

for requirement_id in "${requirement_ids[@]}"; do
  matches="$(grep -Ec "^\\| ${requirement_id} \\|" "${traceability}")"
  [[ "${matches}" -eq 1 ]] || {
    printf 'Expected exactly one traceability row for %s; found %s.\n' "${requirement_id}" "${matches}" >&2
    exit 1
  }
done

for excluded_scope in 'Scrolling capture and screen recording' 'ARM64' 'Automatic update' 'MSIX' 'Server process' 'Notes and task management'; do
  grep -Fq "${excluded_scope}" "${traceability}" || {
    printf 'Traceability exclusions are missing: %s\n' "${excluded_scope}" >&2
    exit 1
  }
done

screenshot_evidence=(
  'VoxFlow.Windows.App.Tests/WindowsScreenshotControllerTests:tests/VoxFlow.Windows.App.Tests/WindowsScreenshotControllerTests.cs'
  'VoxFlow.Windows.Platform.Tests/InteractiveHotkeyRouteTests:tests/VoxFlow.Windows.Platform.Tests/InteractiveHotkeyRouteTests.cs'
  'VoxFlow.Windows.Platform.Tests/Dx11ScreenshotFrameSourceTests:tests/VoxFlow.Windows.Platform.Tests/Dx11ScreenshotFrameSourceTests.cs'
  'VoxFlow.Windows.Domain.Tests/ScreenshotGeometryTests:tests/VoxFlow.Windows.Domain.Tests/ScreenshotGeometryTests.cs'
  'VoxFlow.Windows.Platform.Tests/ScreenshotCaptureGeometryTests:tests/VoxFlow.Windows.Platform.Tests/ScreenshotCaptureGeometryTests.cs'
  'VoxFlow.Windows.Domain.Tests/ScreenshotSelectionTests:tests/VoxFlow.Windows.Domain.Tests/ScreenshotSelectionTests.cs'
  'VoxFlow.Windows.App.Tests/ScreenshotOverlayInputTests:tests/VoxFlow.Windows.App.Tests/ScreenshotOverlayInputTests.cs'
  'VoxFlow.Windows.Domain.Tests/ScreenshotAnnotationTests:tests/VoxFlow.Windows.Domain.Tests/ScreenshotAnnotationTests.cs'
  'VoxFlow.Windows.App.Tests/ScreenshotToolbarTests:tests/VoxFlow.Windows.App.Tests/ScreenshotToolbarTests.cs'
  'VoxFlow.Windows.App.Tests/ScreenshotSourceRendererTests:tests/VoxFlow.Windows.App.Tests/ScreenshotSourceRendererTests.cs'
  'VoxFlow.Windows.App.Tests/ScreenshotClipboardExportTests:tests/VoxFlow.Windows.App.Tests/ScreenshotClipboardExportTests.cs'
  'VoxFlow.Windows.Infrastructure.Tests/TesseractScreenshotOcrAdapterTests:tests/VoxFlow.Windows.Infrastructure.Tests/TesseractScreenshotOcrAdapterTests.cs'
  'VoxFlow.Windows.Application.Tests/ScreenshotOcrOrchestratorTests:tests/VoxFlow.Windows.Application.Tests/Screenshot/ScreenshotOcrOrchestratorTests.cs'
  'VoxFlow.Windows.Application.Tests/ScreenshotTransformServiceTests:tests/VoxFlow.Windows.Application.Tests/Screenshot/ScreenshotTransformServiceTests.cs'
  'VoxFlow.Windows.App.Tests/ScreenshotInlineTranslationTests:tests/VoxFlow.Windows.App.Tests/ScreenshotInlineTranslationTests.cs'
  'VoxFlow.Windows.App.Tests/ScreenshotResultPresentationTests:tests/VoxFlow.Windows.App.Tests/ScreenshotResultPresentationTests.cs'
  'VoxFlow.Windows.App.Tests/ScreenshotResultViewModelTests:tests/VoxFlow.Windows.App.Tests/ScreenshotResultViewModelTests.cs'
  'VoxFlow.Windows.Infrastructure.Tests/ScreenshotRecordRepositoryTests:tests/VoxFlow.Windows.Infrastructure.Tests/Persistence/ScreenshotRecordRepositoryTests.cs'
  'VoxFlow.Windows.Infrastructure.Tests/FileScreenshotAssetStoreTests:tests/VoxFlow.Windows.Infrastructure.Tests/Screenshots/FileScreenshotAssetStoreTests.cs'
  'VoxFlow.Windows.Infrastructure.Tests/ScreenshotSchemaMigrationTests:tests/VoxFlow.Windows.Infrastructure.Tests/Persistence/ScreenshotSchemaMigrationTests.cs'
  'VoxFlow.Windows.App.Tests/ScreenshotMediaPageViewModelTests:tests/VoxFlow.Windows.App.Tests/ScreenshotMediaPageViewModelTests.cs'
  'VoxFlow.Windows.App.Tests/ScreenshotDetailViewModelTests:tests/VoxFlow.Windows.App.Tests/ScreenshotDetailViewModelTests.cs'
)

for evidence in "${screenshot_evidence[@]}"; do
  evidence_id="${evidence%%:*}"
  test_path="${windows_root}/${evidence#*:}"
  project="${evidence_id%%/*}"
  test_class="${evidence_id##*/}"

  test -f "${test_path}" || {
    printf 'Traceability evidence file is missing: %s\n' "${test_path#"${windows_root}/"}" >&2
    exit 1
  }
  grep -Eq "class[[:space:]]+${test_class}([^[:alnum:]_]|$)" "${test_path}" || {
    printf 'Traceability names a missing screenshot test class: %s/%s\n' "${project}" "${test_class}" >&2
    exit 1
  }
  grep -Fq "\`${project}/${test_class}\`" "${traceability}" || {
    printf 'Screenshot traceability is missing executable evidence: %s/%s\n' "${project}" "${test_class}" >&2
    exit 1
  }
done

printf '%s\n' 'PASS: every Windows capability has requirement, task, and test traceability.'
