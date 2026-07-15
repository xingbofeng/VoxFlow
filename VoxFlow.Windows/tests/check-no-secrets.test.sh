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

mkdir -p "${fixture_root}/agent" "${fixture_root}/migrations" "${fixture_root}/snapshots" "${fixture_root}/diagnostics"
fixture_api_token="${credential_prefix}jsonl-fixture-1234567890"
fixture_bearer="Bearer"' trace-token-1234567890'
printf '{"event":"request","apiKey":"%s"}\n' "${fixture_api_token}" > "${fixture_root}/agent/sidecar.jsonl"
printf '{"trace":{"authorization":"%s"}}\n' "${fixture_bearer}" > "${fixture_root}/agent/trace.ndjson"
printf "INSERT INTO workflow_tasks(trace_json) VALUES ('%s');\n" "${credential_prefix}sql-fixture-1234567890" > "${fixture_root}/migrations/agent.sql"
printf '{"snapshot":"settings","accessToken":"snapshot-token-1234567890"}\n' > "${fixture_root}/snapshots/ui-snapshot.json"
touch "${fixture_root}/snapshots/ui-screenshot.png"
printf 'new ProcessStartInfo { Arguments = "%s" };\n' "${credential_prefix}argv-fixture-1234567890" > "${fixture_root}/agent/process.cs"
printf 'startup failed: %s\n' "Bearer"' crash-token-1234567890' > "${fixture_root}/diagnostics/startup.log"

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

if "${scanner}" "${fixture_root}/snapshots/ui-screenshot.png" > "${temporary_directory}/screenshot-output.txt" 2>&1; then
  printf '%s\n' 'Expected the release scanner to reject a UI screenshot artifact.' >&2
  exit 1
fi
grep -Fq 'Sensitive user-data artifact detected' "${temporary_directory}/screenshot-output.txt"

canary_publish_root="${temporary_directory}/canary-publish"
mkdir -p "${canary_publish_root}/Qwen"
cp "${windows_root}/../TestResources/ASRSmoke/Audio/zh_short.wav" \
  "${canary_publish_root}/Qwen/readiness-canary.wav"
cp "${windows_root}/native/qwen-asr/MODEL_PROVENANCE.json" \
  "${canary_publish_root}/Qwen/MODEL_PROVENANCE.json"
canary_bytes="$(wc -c < "${canary_publish_root}/Qwen/readiness-canary.wav" | tr -d '[:space:]')"
canary_sha256="$(sha256sum "${canary_publish_root}/Qwen/readiness-canary.wav" | awk '{print $1}')"
"${scanner}" "${canary_publish_root}"

cat > "${canary_publish_root}/Qwen/MODEL_PROVENANCE.json" <<EOF
{"runtime":{"sourceArchive":{"fixedWav":{"bytes":${canary_bytes},"sha256":"${canary_sha256}"}}}}
EOF
if "${scanner}" "${canary_publish_root}" > "${temporary_directory}/misplaced-canary-output.txt" 2>&1; then
  printf '%s\n' 'Expected a fixedWav object outside runtime.windowsValidation to be rejected.' >&2
  exit 1
fi
grep -Fq 'Sensitive user-data artifact detected' "${temporary_directory}/misplaced-canary-output.txt"

incorrect_canary_bytes=$((canary_bytes + 1))
incorrect_canary_sha256='0000000000000000000000000000000000000000000000000000000000000000'
cat > "${canary_publish_root}/Qwen/MODEL_PROVENANCE.json" <<EOF
{"runtime":{"sourceArchive":{"bytes":${canary_bytes},"sha256":"${canary_sha256}"},"windowsValidation":{"fixedWav":{"bytes":${incorrect_canary_bytes},"sha256":"${incorrect_canary_sha256}"}}}}
EOF
if "${scanner}" "${canary_publish_root}" > "${temporary_directory}/misleading-canary-output.txt" 2>&1; then
  printf '%s\n' 'Expected canary provenance values from unrelated manifest objects to be rejected.' >&2
  exit 1
fi
grep -Fq 'Sensitive user-data artifact detected' "${temporary_directory}/misleading-canary-output.txt"

cp "${windows_root}/native/qwen-asr/MODEL_PROVENANCE.json" \
  "${canary_publish_root}/Qwen/MODEL_PROVENANCE.json"
printf 'tampered' >> "${canary_publish_root}/Qwen/readiness-canary.wav"
if "${scanner}" "${canary_publish_root}" > "${temporary_directory}/tampered-canary-output.txt" 2>&1; then
  printf '%s\n' 'Expected a canary that no longer matches provenance to be rejected.' >&2
  exit 1
fi
grep -Fq 'Sensitive user-data artifact detected' "${temporary_directory}/tampered-canary-output.txt"

for sensitive_file in \
  "${fixture_root}/agent/sidecar.jsonl" \
  "${fixture_root}/agent/trace.ndjson" \
  "${fixture_root}/migrations/agent.sql" \
  "${fixture_root}/snapshots/ui-snapshot.json" \
  "${fixture_root}/agent/process.cs" \
  "${fixture_root}/diagnostics/startup.log"; do
  if "${scanner}" "${sensitive_file}" > "${temporary_directory}/single-output.txt" 2>&1; then
    printf 'Expected scanner to reject sensitive fixture: %s\n' "${sensitive_file}" >&2
    exit 1
  fi
  grep -Fq 'Potential credential detected' "${temporary_directory}/single-output.txt"
done

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
mkdir -p "${default_fixture_root}/scripts" "${default_fixture_root}/artifacts"
cp "${scanner}" "${default_fixture_root}/scripts/check-no-secrets.sh"
chmod +x "${default_fixture_root}/scripts/check-no-secrets.sh"
printf '%s=%s\n' "${credential_name}" 'synthetic-local-only-value' > "${default_fixture_root}/.env.live"
printf '%s=\n' "${credential_name}" > "${default_fixture_root}/.env.live.example"
printf '%s=%s\n' "${credential_name}" 'synthetic-generated-artifact-value' > "${default_fixture_root}/artifacts/generated.env"
"${default_fixture_root}/scripts/check-no-secrets.sh"
if "${default_fixture_root}/scripts/check-no-secrets.sh" "${default_fixture_root}/artifacts" > "${temporary_directory}/explicit-artifacts-output.txt" 2>&1; then
  printf '%s\n' 'Expected an explicitly scanned artifacts directory to reject credentials.' >&2
  exit 1
fi
grep -Fq 'non-empty secret environment assignment' "${temporary_directory}/explicit-artifacts-output.txt"

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
mkdir -p "${safe_root}/tests"
printf '%s=\n' "${credential_name}" > "${safe_root}/safe.env"
printf '{\"accessToken\":\"\"}\n' > "${safe_root}/safe.json"
cat > "${safe_root}/tests/synthetic-credential-redaction.cs" <<'EOF'
const string FakeApiKey = "sk-" + "synthetic-test-token-1234567890";
const string FakeBearer = "Bearer" + " synthetic-test-token-1234567890";
EOF
"${scanner}" "${safe_root}"
"${scanner}"

printf '%s\n' 'PASS: credential scanner rejects synthetic credentials and accepts committed samples.'
