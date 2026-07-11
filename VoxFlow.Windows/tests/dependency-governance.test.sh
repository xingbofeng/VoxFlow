#!/usr/bin/env bash

set -euo pipefail

windows_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
repository_root="$(cd "${windows_root}/.." && pwd)"
infrastructure_project="${windows_root}/src/VoxFlow.Windows.Infrastructure/VoxFlow.Windows.Infrastructure.csproj"
notices="${windows_root}/THIRD-PARTY-NOTICES.md"
security_audit="${windows_root}/scripts/check-nuget-security.ps1"
license_audit="${windows_root}/scripts/check-license-inventory.ps1"
workflow="${repository_root}/.github/workflows/windows-ci.yml"

grep -Eq '<PackageReference Include="SQLitePCLRaw\.bundle_e_sqlite3" Version="3\.0\.3"[[:space:]]*/>' "${infrastructure_project}" || {
  printf '%s\n' 'Infrastructure must directly pin the audited SQLitePCLRaw bundle.' >&2
  exit 1
}

for script in "${security_audit}" "${license_audit}"; do
  test -f "${script}" || {
    printf 'Missing dependency governance script: %s\n' "${script}" >&2
    exit 1
  }
done

grep -Fq -- '--output-version 1' "${security_audit}"
grep -Fq -- '--output-version 1' "${license_audit}"
grep -Fq 'NU1905' "${security_audit}"
grep -Fq 'https://api.nuget.org/v3/index.json' "${security_audit}"
grep -Fq 'xunit.extensibility.execution|2.9.3' "${security_audit}"
grep -Fq '2026-12-31' "${security_audit}"
grep -Fq 'Get-VerifiedPackageLicense' "${license_audit}"
grep -Fq '.nupkg.metadata' "${license_audit}"
grep -Fq 'https://api.nuget.org/v3/index.json' "${license_audit}"
grep -Fq 'Get-FileHash' "${license_audit}"
grep -Fq '99464c3a88df7b708ce59e462cdcb85f72dfc9b1335b4fcc68be56131b634b95' "${license_audit}"
grep -Fq 'Source mismatch' "${license_audit}"

for expected in \
  'check-nuget-security.ps1' \
  'check-license-inventory.ps1' \
  'dependency-governance.test.sh'; do
  grep -Fq "${expected}" "${workflow}" || {
    printf 'Windows CI is missing dependency governance gate: %s\n' "${expected}" >&2
    exit 1
  }
done

for inventory_entry in \
  'Microsoft.Data.Sqlite | 10.0.9 | MIT' \
  'Microsoft.Data.Sqlite.Core | 10.0.9 | MIT' \
  'System.Security.Cryptography.ProtectedData | 10.0.9 | MIT' \
  'SQLitePCLRaw.bundle_e_sqlite3 | 3.0.3 | Apache-2.0' \
  'SQLitePCLRaw.core | 3.0.3 | Apache-2.0' \
  'SQLitePCLRaw.config.e_sqlite3 | 3.0.3 | Apache-2.0' \
  'SQLitePCLRaw.provider.e_sqlite3 | 3.0.3 | Apache-2.0' \
  'SourceGear.sqlite3 | 3.50.4.5 | blessing'; do
  grep -Fq "${inventory_entry}" "${notices}" || {
    printf 'Third-party inventory is missing: %s\n' "${inventory_entry}" >&2
    exit 1
  }
done

printf '%s\n' 'PASS: NuGet security and license inventory gates are wired into Windows CI.'
