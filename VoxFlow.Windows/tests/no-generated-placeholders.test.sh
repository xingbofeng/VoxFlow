#!/usr/bin/env bash

set -euo pipefail

windows_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
placeholder_files="$(
  rg --files "${windows_root}/src" "${windows_root}/tests" \
    | rg '(^|/)(Class1|UnitTest1)\.cs$' \
    || true
)"

if [[ -n "${placeholder_files}" ]]; then
  printf '%s\n' 'Generated placeholder source and tests are forbidden:' >&2
  printf '%s\n' "${placeholder_files}" >&2
  exit 1
fi

printf '%s\n' 'PASS: no generated Class1 or UnitTest1 placeholders remain.'
