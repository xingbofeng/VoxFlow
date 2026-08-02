#!/usr/bin/env bash

set -euo pipefail

if [[ "$#" -ne 1 || ! -f "$1" ]]; then
  printf '%s\n' 'Usage: check-traceability.sh <traceability.md>' >&2
  exit 2
fi

traceability_file="$1"
row_count=0

trim_value() {
  local value="$1"
  value="${value#"${value%%[![:space:]]*}"}"
  value="${value%"${value##*[![:space:]]}"}"
  printf '%s' "${value}"
}

while IFS='|' read -r _ requirement_id requirement tasks evidence _; do
  requirement_id="$(trim_value "${requirement_id}")"
  [[ "${requirement_id}" =~ ^[A-Z]{3}-[0-9]{2}$ ]] || continue

  row_count=$((row_count + 1))
  requirement="$(trim_value "${requirement}")"
  tasks="$(trim_value "${tasks}")"
  evidence="$(trim_value "${evidence}")"

  if [[ -z "${requirement}" || -z "${tasks}" || -z "${evidence}" ]]; then
    printf 'Incomplete traceability row: %s.\n' "${requirement_id}" >&2
    exit 1
  fi
done < "${traceability_file}"

if [[ "${row_count}" -eq 0 ]]; then
  printf '%s\n' 'Traceability matrix contains no requirement rows.' >&2
  exit 1
fi

printf 'PASS: %s traceability rows include requirement, task, and evidence values.\n' "${row_count}"
