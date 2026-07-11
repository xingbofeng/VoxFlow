#!/usr/bin/env bash

set -euo pipefail

windows_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
repository_root="$(cd "${windows_root}/.." && pwd)"
props="${windows_root}/Directory.Build.props"
solution="${windows_root}/VoxFlow.Windows.sln"
workflow="${repository_root}/.github/workflows/windows-ci.yml"

grep -Fq '<TargetFramework>net10.0-windows10.0.17763.0</TargetFramework>' "${props}"
grep -Fq '<SupportedOSPlatformVersion>10.0.17763.0</SupportedOSPlatformVersion>' "${props}"
grep -Fq '<PlatformTarget>x64</PlatformTarget>' "${props}"

grep -Fq $'\t\tDebug|x64 = Debug|x64' "${solution}"
grep -Fq $'\t\tRelease|x64 = Release|x64' "${solution}"

if grep -E '\|(Any CPU|x86)' "${solution}" >/dev/null; then
  printf '%s\n' 'The Windows solution must advertise x64 configurations only.' >&2
  exit 1
fi

project_count="$(grep -c '^Project("{FAE04EC0-301F-11D3-BF4B-00C04F79EFBC}")' "${solution}")"
debug_x64_count="$(grep -Ec '\.Debug[|]x64\.ActiveCfg = Debug[|]x64[[:space:]]*$' "${solution}")"
release_x64_count="$(grep -Ec '\.Release[|]x64\.ActiveCfg = Release[|]x64[[:space:]]*$' "${solution}")"

if [[ "${debug_x64_count}" -ne "${project_count}" || "${release_x64_count}" -ne "${project_count}" ]]; then
  printf '%s\n' 'Every project must map the solution x64 configurations to project x64.' >&2
  exit 1
fi

if grep -Fq '<RuntimeIdentifier>' "${props}"; then
  printf '%s\n' 'Solution-wide build properties must not set a project publish RID.' >&2
  exit 1
fi

if grep -E 'VoxFlow\.Windows\.sln.*--arch[[:space:]]+x64' "${workflow}" >/dev/null; then
  printf '%s\n' 'Solution commands must select x64 through Platform, not a solution-level RID.' >&2
  exit 1
fi

grep -Eq 'VoxFlow\.Windows\.sln.*-p:Platform=x64' "${workflow}"

printf '%s\n' 'PASS: solution builds use x64 Platform without an unsupported solution-level RID.'
