#!/usr/bin/env bash

set -euo pipefail

windows_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
repository_root="$(cd "${windows_root}/.." && pwd)"
workflow="${repository_root}/.github/workflows/windows-ci.yml"
commit_check="${windows_root}/scripts/check-conventional-commits.ps1"

test -f "${workflow}" || {
  printf '%s\n' 'Missing Windows CI workflow.' >&2
  exit 1
}
test -f "${commit_check}" || {
  printf '%s\n' 'Missing Conventional Commit checker.' >&2
  exit 1
}

for expected in \
  'runs-on: windows-latest' \
  'dotnet test' \
  '--configuration Debug' \
  '--configuration Release' \
  '-p:Platform=x64' \
  'check-conventional-commits.ps1' \
  'check-no-secrets.sh' \
  'governance.test.sh' \
  'traceability.test.sh' \
  'traceability-validator.test.sh' \
  'windows-ci-contract.test.sh' \
  'dependency-governance.test.sh' \
  'screenshot-architecture.test.sh' \
  'check-no-secrets.test.sh' \
  'check-nuget-security.ps1' \
  'check-license-inventory.ps1' \
  'check-cargo-license-inventory.ps1' \
  'rustup toolchain install 1.97.0' \
  'agent-cli/**' \
  'stage-ffmpeg-runtime.ps1' \
  'FfmpegRealMediaFixtureTests' \
  'build-qwen-production-bridge.ps1' \
  'prepare-windows-release.ps1' \
  'Upload Windows x64 packages' \
  "github.event_name == 'push'" \
  'github.event.before' \
  'github.sha'; do
  grep -Fq -- "${expected}" "${workflow}" || {
    printf 'Windows CI workflow is missing contract text: %s\n' "${expected}" >&2
    exit 1
  }
done

if grep -Eq '\$\{\{[[:space:]]*secrets\.|VOXFLOW_LIVE_[A-Z_]+[[:space:]]*:' "${workflow}"; then
  printf '%s\n' 'Windows offline CI must not read live credentials.' >&2
  exit 1
fi

grep -Eq '^permissions:[[:space:]]*$' "${workflow}"
grep -Eq '^[[:space:]]+contents:[[:space:]]+read[[:space:]]*$' "${workflow}"
grep -Fq 'Conventional Commit' "${commit_check}"

printf '%s\n' 'PASS: Windows CI is x64-only, offline, security-gated, and commit-convention aware.'
