#!/usr/bin/env bash

set -euo pipefail

script_directory="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
windows_root="$(cd "${script_directory}/.." && pwd)"
repository_root="$(cd "${windows_root}/.." && pwd)"

has_detection=0
has_input_error=0

trim_value() {
  local value="$1"
  value="${value#"${value%%[![:space:]]*}"}"
  value="${value%"${value##*[![:space:]]}"}"
  printf '%s' "${value}"
}

has_nonempty_assignment_value() {
  local value
  value="$(trim_value "$1")"
  value="${value%%#*}"
  value="$(trim_value "${value}")"
  value="${value%;}"
  value="${value%,}"
  value="${value%\}}"
  value="$(trim_value "${value}")"

  case "${value,,}" in
    ''|'""'|"''"|null|todo)
      return 1
      ;;
  esac

  return 0
}

is_scannable_text_file() {
  local path="$1"
  local name="${path##*/}"

  case "${name}" in
    .gitignore|.gitattributes|.editorconfig|.env.live|.env.live.*|*.cs|*.csproj|*.sln|*.slnx|*.props|*.targets|*.xaml|*.xml|*.json|*.jsonc|*.yml|*.yaml|*.md|*.txt|*.sh|*.ps1|*.psm1|*.bat|*.cmd|*.iss|*.ini|*.config|*.toml|*.env|*.example)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

scan_file() {
  local candidate="$1"
  local extension="${candidate##*.}"
  local line
  local line_number=0
  local rule
  local value

  is_scannable_text_file "${candidate}" || return 0

  shopt -s nocasematch
  while IFS= read -r line || [[ -n "${line}" ]]; do
    line_number=$((line_number + 1))
    rule=""

    if [[ "${line}" =~ sk-[A-Za-z0-9._-]{16,} ]]; then
      rule="API key token pattern"
    elif [[ "${line}" =~ AKID[A-Za-z0-9]{16,} ]]; then
      rule="cloud secret identifier pattern"
    elif [[ "${line}" =~ [Bb]earer[[:space:]]+[A-Za-z0-9._-]{16,} ]]; then
      rule="Authorization bearer token"
    elif [[ "${line}" =~ ^[[:space:]]*(export[[:space:]]+)?[A-Za-z_][A-Za-z0-9_]*(API_KEY|SECRET_ID|SECRET_KEY|ACCESS_TOKEN|AUTHORIZATION_TOKEN|BEARER_TOKEN)[A-Za-z0-9_]*[[:space:]]*= ]]; then
      value="${line#*=}"
      if has_nonempty_assignment_value "${value}"; then
        rule="non-empty secret environment assignment"
      fi
    elif [[ "${extension,,}" =~ ^ps(m)?1$ ]] && [[ "${line}" =~ ^[[:space:]]*\$(env:)?[A-Za-z_][A-Za-z0-9_]*(API_KEY|SECRET_ID|SECRET_KEY|ACCESS_TOKEN|AUTHORIZATION_TOKEN|BEARER_TOKEN)[A-Za-z0-9_]*[[:space:]]*= ]]; then
      value="${line#*=}"
      if has_nonempty_assignment_value "${value}"; then
        rule="PowerShell secret assignment"
      fi
    elif [[ "${extension,,}" =~ ^(json|jsonc|ya?ml|config)$ ]] && [[ "${line}" =~ (api[_-]?key|secret[_-]?(id|key)|access[_-]?token|authorization|bearer[_-]?token)[A-Za-z0-9_.-]*[\"\']?[[:space:]]*: ]]; then
      value="${line#*:}"
      if has_nonempty_assignment_value "${value}"; then
        rule="structured secret assignment"
      fi
    elif [[ "${extension,,}" =~ ^(xml|config|csproj|props|targets|xaml)$ ]] && [[ "${line}" =~ \<(ApiKey|SecretId|SecretKey|AccessToken|Authorization|BearerToken)\>[[:space:]]*[^\<[:space:]] ]]; then
      rule="XML secret element"
    elif [[ "${line}" =~ (ApiKey|SecretId|SecretKey|AccessToken|AuthorizationToken|BearerToken)[[:space:]]*=[[:space:]]*[\"\'][^\"\']{8,}[\"\'] ]]; then
      rule="source-code secret literal"
    elif [[ "${extension,,}" == cs ]] && [[ "${line}" =~ (Console|Debug|Trace|Logger?|Log(Trace|Debug|Information|Warning|Error|Critical)?)[^\n]*(SourcePath|RawText|FinalText|TranslatedText|Authorization) ]]; then
      rule="sensitive transcription logging"
    fi

    if [[ -n "${rule}" ]]; then
      printf 'Potential credential detected in %s:%s (%s).\n' "${candidate}" "${line_number}" "${rule}" >&2
      has_detection=1
    fi
  done < "${candidate}"
  shopt -u nocasematch
}

scan_path() {
  local candidate="$1"
  local allow_source_live_skip="${2:-0}"
  local discovered

  if [[ -f "${candidate}" ]]; then
    scan_file "${candidate}"
    return
  fi

  if [[ ! -d "${candidate}" ]]; then
    printf 'Cannot scan missing path: %s\n' "${candidate}" >&2
    has_input_error=1
    return
  fi

  while IFS= read -r -d '' discovered; do
    if [[ "${allow_source_live_skip}" -eq 1 ]]; then
      case "${discovered##*/}" in
        .env.live|.env.live.*)
          [[ "${discovered##*/}" == '.env.live.example' ]] || continue
          ;;
      esac
    fi
    if [[ "${allow_source_live_skip}" -eq 0 ]]; then
      case "${discovered,,}" in
        *.wav|*.mp3|*.m4a|*.aac|*.mp4|*.mov|*.db|*.sqlite|*.sqlite3|*.log)
          printf 'Sensitive user-data artifact detected in release inputs: %s.\n' "${discovered}" >&2
          has_detection=1
          continue
          ;;
      esac
    fi
    scan_file "${discovered}"
  done < <(
    find "${candidate}" \
      -type d \( -name .git -o -name .vs -o -name bin -o -name obj -o -name TestResults -o -name models -o -name logs \) -prune \
      -o -type f -print0
  )
}

if [[ "$#" -eq 0 ]]; then
  scan_path "${windows_root}" 1
  windows_workflow="${repository_root}/.github/workflows/windows-ci.yml"
  [[ ! -f "${windows_workflow}" ]] || scan_file "${windows_workflow}"
else
  for candidate in "$@"; do
    scan_path "${candidate}" 0
  done
fi

if [[ "${has_input_error}" -ne 0 ]]; then
  exit 2
fi

if [[ "${has_detection}" -ne 0 ]]; then
  exit 1
fi

printf '%s\n' 'PASS: no credential-like values found in the scanned release inputs.'
