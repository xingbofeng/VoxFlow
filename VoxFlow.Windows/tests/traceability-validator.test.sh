#!/usr/bin/env bash

set -euo pipefail

windows_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
validator="${windows_root}/scripts/check-traceability.sh"
temporary_directory="$(mktemp -d)"
trap 'rm -rf "${temporary_directory}"' EXIT

printf '%s\n' \
  '| ID | Requirement | OpenSpec tasks | Automated evidence |' \
  '| --- | --- | --- | --- |' \
  '| WCA-01 | | | |' \
  > "${temporary_directory}/invalid.md"

if "${validator}" "${temporary_directory}/invalid.md" >/dev/null 2>&1; then
  printf '%s\n' 'Expected an incomplete traceability row to be rejected.' >&2
  exit 1
fi

printf '%s\n' \
  '| ID | Requirement | OpenSpec tasks | Automated evidence |' \
  '| --- | --- | --- | --- |' \
  '| WCA-01 | Streaming session contract | 3.5, 7.5 | `StreamingAsrContractTests` |' \
  > "${temporary_directory}/valid.md"

"${validator}" "${temporary_directory}/valid.md"
"${validator}" "${windows_root}/docs/traceability.md"

printf '%s\n' 'PASS: traceability rows require requirement, task, and evidence values.'
