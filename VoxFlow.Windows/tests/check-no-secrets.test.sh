#!/usr/bin/env bash

set -euo pipefail

windows_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
scanner="${windows_root}/scripts/check-no-secrets.sh"
temporary_directory="$(mktemp -d)"
trap 'rm -rf "${temporary_directory}"' EXIT

fixture_root="${temporary_directory}/fixture-root"
mkdir -p "${fixture_root}/src" "${fixture_root}/publish"
credential_name="VOXFLOW_LIVE_OPENAI_API"'_KEY'
credential_prefix='sk-'
credential_value="${credential_prefix}synthetic-fixture-not-real-1234567890"
printf '%s=%s\n' "${credential_name}" "${credential_value}" > "${fixture_root}/src/leaked.env"
printf '$env:%s = %s\n' 'VOXFLOW_LIVE_TENCENT_ASR_SECRET_KEY' "'synthetic-powershell-value'" > "${fixture_root}/src/leaked.ps1"
printf '{\"accessToken\":\"synthetic-json-value\"}\n' > "${fixture_root}/publish/leaked.json"
printf '<SecretId>synthetic-xml-value</SecretId>\n' > "${fixture_root}/publish/leaked.config"
touch "${fixture_root}/publish/private-recording.wav"

if "${scanner}" "${fixture_root}" > "${temporary_directory}/leaked-output.txt" 2>&1; then
  printf '%s\n' 'Expected the credential scanner to reject the synthetic leaked fixture.' >&2
  exit 1
fi

if ! grep -Fq 'Potential credential detected' "${temporary_directory}/leaked-output.txt"; then
  printf '%s\n' 'Expected a credential-detection diagnostic from the scanner.' >&2
  exit 1
fi

for rule in 'API key token pattern' 'PowerShell secret assignment' 'structured secret assignment' 'XML secret element'; do
  grep -Fq "${rule}" "${temporary_directory}/leaked-output.txt" || {
    printf 'Expected scanner rule did not fire: %s\n' "${rule}" >&2
    exit 1
  }
done
grep -Fq 'Sensitive user-data artifact detected' "${temporary_directory}/leaked-output.txt"

if grep -Fq "${credential_value}" "${temporary_directory}/leaked-output.txt"; then
  printf '%s\n' 'Credential scanner diagnostics must not echo the matching value.' >&2
  exit 1
fi

explicit_publish_root="${temporary_directory}/explicit-publish"
mkdir -p "${explicit_publish_root}/publish"
printf '%s=%s\n' "${credential_name}" 'synthetic-publish-value' > "${explicit_publish_root}/publish/.env.live"

if "${scanner}" "${explicit_publish_root}/publish" > "${temporary_directory}/publish-output.txt" 2>&1; then
  printf '%s\n' 'Expected an explicitly scanned publish directory to reject .env.live.' >&2
  exit 1
fi

if ! grep -Fq 'non-empty secret environment assignment' "${temporary_directory}/publish-output.txt"; then
  printf '%s\n' 'Expected the publish .env.live fixture to trigger the environment-assignment rule.' >&2
  exit 1
fi

default_fixture_root="${temporary_directory}/default-source-root"
mkdir -p "${default_fixture_root}/scripts"
cp "${scanner}" "${default_fixture_root}/scripts/check-no-secrets.sh"
chmod +x "${default_fixture_root}/scripts/check-no-secrets.sh"
printf '%s=%s\n' "${credential_name}" 'synthetic-local-only-value' > "${default_fixture_root}/.env.live"
printf '%s=\n' "${credential_name}" > "${default_fixture_root}/.env.live.example"
"${default_fixture_root}/scripts/check-no-secrets.sh"

printf '%s=%s\n' "${credential_name}" 'synthetic-example-leak-value' > "${default_fixture_root}/.env.live.example"
if "${default_fixture_root}/scripts/check-no-secrets.sh" > "${temporary_directory}/example-output.txt" 2>&1; then
  printf '%s\n' 'Expected the default source scan to reject a leaked .env.live.example value.' >&2
  exit 1
fi

if ! grep -Fq 'non-empty secret environment assignment' "${temporary_directory}/example-output.txt"; then
  printf '%s\n' 'Expected .env.live.example to remain inside the default source scan.' >&2
  exit 1
fi

safe_root="${temporary_directory}/safe-root"
mkdir -p "${safe_root}"
printf '%s=\n' "${credential_name}" > "${safe_root}/safe.env"
printf '{\"accessToken\":\"\"}\n' > "${safe_root}/safe.json"
"${scanner}" "${safe_root}"
"${scanner}"

printf '%s\n' 'PASS: credential scanner rejects synthetic credentials and accepts committed samples.'
