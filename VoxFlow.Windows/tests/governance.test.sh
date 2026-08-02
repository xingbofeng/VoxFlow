#!/usr/bin/env bash

set -euo pipefail

windows_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

required_directories=(
  docs
  installer
  native/qwen-asr
  native/qwen-asr-bridge
  src/VoxFlow.Windows.Domain
  src/VoxFlow.Windows.Application
  src/VoxFlow.Windows.Infrastructure
  src/VoxFlow.Windows.Platform
  src/VoxFlow.Windows.Providers.Qwen
  src/VoxFlow.Windows.Providers.Cloud
  src/VoxFlow.Windows.App
  tests/VoxFlow.Windows.Domain.Tests
  tests/VoxFlow.Windows.Application.Tests
  tests/VoxFlow.Windows.Infrastructure.Tests
  tests/VoxFlow.Windows.Platform.Tests
  tests/VoxFlow.Windows.Providers.Qwen.Tests
  tests/VoxFlow.Windows.Providers.Cloud.Tests
  tests/VoxFlow.Windows.App.Tests
  tests/VoxFlow.Windows.IntegrationTests
)

for relative_path in "${required_directories[@]}"; do
  test -d "${windows_root}/${relative_path}" || {
    printf 'Missing required Windows project directory: %s\n' "${relative_path}" >&2
    exit 1
  }
  documented_name="${relative_path}"
  if [[ "${relative_path}" == src/* || "${relative_path}" == tests/* ]]; then
    documented_name="${relative_path##*/}"
  fi
  grep -Fq "${documented_name}" "${windows_root}/README.md" || {
    printf 'README does not document required directory: %s\n' "${relative_path}" >&2
    exit 1
  }
done

notices="${windows_root}/THIRD-PARTY-NOTICES.md"
test -f "${notices}"
grep -Fq 'GPL-3.0-or-later' "${notices}"
grep -Fq 'antirez/qwen-asr' "${notices}"
grep -Fq 'MIT' "${notices}"

upstream_record="${windows_root}/native/qwen-asr/UPSTREAM.md"
test -f "${upstream_record}"
for heading in 'Repository' 'Revision' 'License' 'Model format' 'Build parameters' 'Local patches' 'Validation evidence'; do
  grep -Fq "${heading}" "${upstream_record}" || {
    printf 'UPSTREAM.md is missing required field: %s\n' "${heading}" >&2
    exit 1
  }
done

secret_rules="${windows_root}/docs/secret-scanning.md"
test -f "${secret_rules}"
grep -Fq 'Source and configuration files' "${secret_rules}"
grep -Fq 'Installer and publish output' "${secret_rules}"
grep -Fq 'never prints the matching value' "${secret_rules}"

printf '%s\n' 'PASS: Windows governance layout and license-record scaffolds are present.'
