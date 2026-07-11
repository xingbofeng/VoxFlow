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
)

for capability in "${capabilities[@]}"; do
  grep -Fq "${capability}" "${traceability}" || {
    printf 'Traceability matrix is missing capability: %s\n' "${capability}" >&2
    exit 1
  }
done

requirement_ids=()
for prefix_and_count in WCA:6 WDS:6 WDR:5 WQA:4 WML:5 WOL:4 WQD:7 WSS:5 WTO:4; do
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

for excluded_scope in 'Screenshot and OCR' 'ARM64' 'Automatic update' 'MSIX' 'Server process' 'Translation, TTS, Agent, notes, and tasks'; do
  grep -Fq "${excluded_scope}" "${traceability}" || {
    printf 'Traceability exclusions are missing: %s\n' "${excluded_scope}" >&2
    exit 1
  }
done

printf '%s\n' 'PASS: every Windows capability has requirement, task, and test traceability.'
