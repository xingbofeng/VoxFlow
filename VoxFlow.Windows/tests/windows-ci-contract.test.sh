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

powershell_executable="${POWERSHELL_EXECUTABLE:-powershell.exe}"
if command -v "${powershell_executable}" >/dev/null 2>&1; then
  temporary_directory="$(mktemp -d)"
  trap 'rm -rf "${temporary_directory}"' EXIT
  fixture_repository="${temporary_directory}/conventional-commit-fixture"
  mkdir -p "${fixture_repository}"

  git -C "${fixture_repository}" init --quiet
  git -C "${fixture_repository}" config user.email 'fixture@example.invalid'
  git -C "${fixture_repository}" config user.name 'VoxFlow CI Fixture'
  printf '%s\n' 'base' > "${fixture_repository}/base.txt"
  git -C "${fixture_repository}" add base.txt
  git -C "${fixture_repository}" commit --quiet -m 'feat: create Conventional Commit fixture'
  base_ref="$(git -C "${fixture_repository}" rev-parse HEAD)"

  git -C "${fixture_repository}" checkout --quiet -b merge-source "${base_ref}"
  printf '%s\n' 'source' > "${fixture_repository}/source.txt"
  git -C "${fixture_repository}" add source.txt
  git -C "${fixture_repository}" commit --quiet -m 'fix: add merge source change'

  git -C "${fixture_repository}" checkout --quiet -b merge-target "${base_ref}"
  printf '%s\n' 'target' > "${fixture_repository}/target.txt"
  git -C "${fixture_repository}" add target.txt
  git -C "${fixture_repository}" commit --quiet -m 'docs: add merge target change'
  git -C "${fixture_repository}" merge --quiet --no-ff --no-edit \
    -m 'Merge pull request #42 from fixture/merge-source' merge-source
  merge_ref="$(git -C "${fixture_repository}" rev-parse HEAD)"
  git -C "${fixture_repository}" rev-parse "${merge_ref}^2" >/dev/null

  run_commit_check() {
    local range_base="$1"
    local range_head="$2"
    (
      cd "${fixture_repository}"
      "${powershell_executable}" -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass \
        -File "${commit_check}" -BaseRef "${range_base}" -HeadRef "${range_head}"
    )
  }

  if ! run_commit_check "${base_ref}" "${merge_ref}"; then
    printf '%s\n' 'Expected the checker to accept a GitHub-style merge commit with a nonconventional subject.' >&2
    exit 1
  fi

  printf '%s\n' 'authored nonconventional change' > "${fixture_repository}/authored.txt"
  git -C "${fixture_repository}" add authored.txt
  git -C "${fixture_repository}" commit --quiet -m 'authored change without convention'
  authored_ref="$(git -C "${fixture_repository}" rev-parse HEAD)"
  authored_hash="$(git -C "${fixture_repository}" rev-parse "${authored_ref}")"

  if run_commit_check "${base_ref}" "${authored_ref}" > "${temporary_directory}/authored-output.txt" 2>&1; then
    printf '%s\n' 'Expected the checker to reject a nonconventional authored non-merge commit.' >&2
    exit 1
  fi
  grep -Fq "${authored_hash}" "${temporary_directory}/authored-output.txt" || {
    printf '%s\n' 'Expected the checker diagnostic to identify the nonconventional authored commit.' >&2
    exit 1
  }
else
  printf '%s\n' 'SKIP: executable Conventional Commit fixture requires PowerShell and runs in Windows CI.'
fi

printf '%s\n' 'PASS: Windows CI is x64-only, offline, security-gated, and commit-convention aware.'
