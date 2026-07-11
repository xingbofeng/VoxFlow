#!/usr/bin/env bash

set -euo pipefail

windows_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
installer="${windows_root}/installer/VoxFlow.iss"
profile="${windows_root}/src/VoxFlow.Windows.App/Properties/PublishProfiles/WindowsX64.pubxml"
layout_check="${windows_root}/scripts/check-release-layout.ps1"
release_check="${windows_root}/scripts/windows-release-check.ps1"
ffmpeg_stage="${windows_root}/scripts/stage-ffmpeg-runtime.ps1"
qwen_build="${windows_root}/scripts/build-qwen-production-bridge.ps1"

test -f "${installer}"
test -f "${profile}"
test -f "${layout_check}"
test -f "${release_check}"
test -f "${ffmpeg_stage}"
test -f "${qwen_build}"

for expected in \
  'PrivilegesRequired=lowest' \
  'ArchitecturesAllowed=x64compatible and not arm64' \
  'MinVersion=10.0.17763' \
  'DefaultDirName={localappdata}\Programs\VoxFlow' \
  'deleteuserdata' \
  'qwen_asr.dll' \
  'runtime\ffmpeg\ffmpeg.exe' \
  'runtime\ffmpeg\FFMPEG_RUNTIME_MANIFEST.json' \
  'LICENSE-GPL-3.0-or-later.txt' \
  'LICENSE-qwen-asr-MIT.txt' \
  'THIRD-PARTY-NOTICES.md'; do
  grep -Fq -- "${expected}" "${installer}" || {
    printf 'Installer contract is missing: %s\n' "${expected}" >&2
    exit 1
  }
done

for expected in \
  '<RuntimeIdentifier>win-x64</RuntimeIdentifier>' \
  '<SelfContained>true</SelfContained>' \
  '<PublishSingleFile>false</PublishSingleFile>' \
  '<PublishTrimmed>false</PublishTrimmed>'; do
  grep -Fq -- "${expected}" "${profile}" || {
    printf 'Publish profile contract is missing: %s\n' "${expected}" >&2
    exit 1
  }
done

if grep -Eqi 'msix|appx|auto.?update|update.?service' "${installer}" "${profile}"; then
  printf '%s\n' 'Windows V1 packaging must not introduce MSIX or automatic update machinery.' >&2
  exit 1
fi

grep -Fq 'check-no-secrets.sh' "${release_check}"
grep -Fq 'qwen-native-bridge.test.ps1' "${release_check}"
grep -Fq 'check-release-layout.ps1' "${release_check}"
grep -Fq 'stage-ffmpeg-runtime.ps1' "${windows_root}/scripts/prepare-windows-release.ps1"
grep -Fq 'VoxFlow-$Version-windows-x64-portable.zip' "${windows_root}/scripts/prepare-windows-release.ps1"
grep -Fq 'b00b789b17051aea61e9717458171100662318a4' "${qwen_build}"
grep -Fq 'cd39114d50ad2d17d892571d896f67fbe8b25333958682430f095eeffbb58598' \
  "${windows_root}/runtime/ffmpeg/FFMPEG_RUNTIME_MANIFEST.json"

printf '%s\n' 'PASS: Windows packaging source contract is per-user, x64-only, self-contained, license-complete, and has explicit data deletion.'
