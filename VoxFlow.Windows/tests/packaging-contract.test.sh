#!/usr/bin/env bash

set -euo pipefail

windows_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
installer="${windows_root}/installer/VoxFlow.iss"
profile="${windows_root}/src/VoxFlow.Windows.App/Properties/PublishProfiles/WindowsX64.pubxml"
layout_check="${windows_root}/scripts/check-release-layout.ps1"
release_check="${windows_root}/scripts/windows-release-check.ps1"
ffmpeg_stage="${windows_root}/scripts/stage-ffmpeg-runtime.ps1"
tesseract_stage="${windows_root}/scripts/stage-tesseract-runtime.ps1"
agent_stage="${windows_root}/scripts/stage-builtin-agent-runtime.ps1"
tesseract_build="${windows_root}/scripts/build-tesseract-runtime.ps1"
qwen_build="${windows_root}/scripts/build-qwen-production-bridge.ps1"
qwen_bridge_test="${windows_root}/tests/qwen-native-bridge.test.ps1"
process_helper_test="${windows_root}/tests/process-helpers.test.ps1"
process_helpers="${windows_root}/scripts/ProcessHelpers.ps1"
qwen_runtime_manifest="${windows_root}/scripts/QwenRuntimeManifest.ps1"
installer_contract="${windows_root}/src/VoxFlow.Windows.Infrastructure/Runtime/InstallerLayoutContract.cs"
openssl_nasm_patch="${windows_root}/scripts/patches/openssl-nasm-env.patch"

test -f "${installer}"
test -f "${profile}"
test -f "${layout_check}"
test -f "${release_check}"
test -f "${ffmpeg_stage}"
test -f "${tesseract_stage}"
test -f "${agent_stage}"
test -f "${tesseract_build}"
test -f "${qwen_build}"
test -f "${qwen_bridge_test}"
test -f "${process_helper_test}"
test -f "${process_helpers}"
test -f "${qwen_runtime_manifest}"
test -f "${installer_contract}"
test -f "${openssl_nasm_patch}"

for expected in \
  'PrivilegesRequired=lowest' \
  'ArchitecturesAllowed=x64compatible and not arm64' \
  'MinVersion=10.0.17763' \
  'DefaultDirName={localappdata}\Programs\VoxFlow' \
  'deleteuserdata' \
  'qwen_asr.dll' \
  'Qwen\QWEN_NATIVE_RUNTIME_MANIFEST.json' \
  'Qwen\MODEL_PROVENANCE.json' \
  'Qwen\readiness-canary.wav' \
  'ScreenCapture.NET.DX11.dll' \
  'ScreenCapture.NET.dll' \
  'HPPH.dll' \
  'runtime\ffmpeg\ffmpeg.exe' \
  'runtime\ffmpeg\FFMPEG_RUNTIME_MANIFEST.json' \
  'runtime\ffmpeg\THIRD_PARTY_NOTICES.md' \
  'runtime\agent\voxflow-agent.exe' \
  'runtime\agent\VOXFLOW_AGENT_RUNTIME_MANIFEST.json' \
  'runtime\ocr\tesseract.exe' \
  'runtime\ocr\TESSERACT_RUNTIME_MANIFEST.json' \
  'runtime\ocr\tessdata\eng.traineddata' \
  'runtime\ocr\licenses\libarchive.txt' \
  'runtime\ocr\licenses\openssl.txt' \
  'LICENSE-GPL-3.0-or-later.txt' \
  'LICENSE-qwen-asr-MIT.txt' \
  'LICENSE-LGPL-2.1-only.txt' \
  'LICENSE-Unicode-3.0.txt' \
  'THIRD-PARTY-NOTICES.md'; do
  grep -Fq -- "${expected}" "${installer}" || {
    printf 'Installer contract is missing: %s\n' "${expected}" >&2
    exit 1
  }
done

grep -Fq "'runtime/ffmpeg/THIRD_PARTY_NOTICES.md'" "${layout_check}"
if grep -Fq 'runtime/ffmpeg/LICENSE.txt' "${layout_check}"; then
  printf '%s\n' 'FFmpeg release layout must follow the manifest notice file, not the retired LICENSE.txt path.' >&2
  exit 1
fi

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

grep -Fq 'replaceableScreenshotAssemblies' "${layout_check}"
grep -Fq 'LICENSE-LGPL-2.1-only.txt' "${layout_check}"

if grep -Eqi 'msix|appx|auto.?update|update.?service' "${installer}" "${profile}"; then
  printf '%s\n' 'Windows V1 packaging must not introduce MSIX or automatic update machinery.' >&2
  exit 1
fi

grep -Fq 'check-no-secrets.sh' "${release_check}"
grep -Fq 'qwen-native-bridge.test.ps1' "${release_check}"
grep -Fq 'check-release-layout.ps1' "${release_check}"
grep -Fq 'stage-ffmpeg-runtime.ps1' "${windows_root}/scripts/prepare-windows-release.ps1"
grep -Fq 'build-tesseract-runtime.ps1' "${windows_root}/scripts/prepare-windows-release.ps1"
grep -Fq 'External Tesseract staging inputs are not accepted for a release' \
  "${windows_root}/scripts/prepare-windows-release.ps1"
grep -Fq 'stage-tesseract-runtime.ps1' "${tesseract_build}"
grep -Fq 'Invoke-VoxFlowProcess' "${tesseract_stage}"
grep -Fq 'Assert-FixedFile $dependencyLicense $dependency.bytes $dependency.sha256' \
  "${tesseract_stage}"
grep -Fq 'The controlled Tesseract dependency notice is invalid' "${layout_check}"
ocr_dependency_notice_hashes=(
  c6dbbf828498be844a89eaa3b84adbab3199e342eb5cb2ed2f0d4ba7ec0f38a3
  543457a53893d439ac029f115c15940c0921ce1b919db501bbad266e2a4d1059
  ed5d90cb4a041bddad679470a071302ab05ae5d0ec2cf8f9c97ad7b2708751e6
  87829abb5bbb00b55a107365da89e9a33f86c4250169e5a1e5588505be7d5806
  30e556b3959e3985d66efefec5eaac51d4995053caa1d3cffe6eb916f146f229
  ba6bceebcba0fdd35488477c2cca8c4632ce82c74dbfbc87d886ce6fc4433579
  616a3ad264ce29b8f1cb97e53037b139d406899ca8d1f799651e17bfa09830b8
  bdb0a645ea18c60507d0368379b1ac5474b92255fcc2d115e07486a7672ba526
  050b5ba2c8eb0bd3b996e12ef79312a1c62237f2de1b3c609843f00bb74744f3
  8b58c446121a109ccf32edc094bba3010a3d85e4ee3702950db55e4d3e87736c
  a6af136f3e15038a666b61f376612a07d9a4e48cb7c01adbf3e33b3f14ab49b6
  7d5450cb2d142651b8afa315b5f238efc805dad827d91ba367d8516bc9d49e7a
  0e27c2382d7b8147972bbb746e04059a1152c8d0fda9d03ef1399d1a433c4ade
  e32ff4e00d9d94930537635291da39e7e612703334bf6fde8c7f1686fe8a45a2
  434dca949c6da7c500413aef694539fe37f867dd1a94d83d4ed1d260194e2660
)
for notice_hash in "${ocr_dependency_notice_hashes[@]}"; do
  grep -Fq "${notice_hash}" "${tesseract_stage}"
  grep -Fq "${notice_hash}" "${layout_check}"
done
grep -Fq 'TimeoutSec 1800' "${ffmpeg_stage}"
grep -Fq 'TimeoutSec 600' "${tesseract_build}"
grep -Fq "'status', '--porcelain', '--untracked-files=no'" "${tesseract_build}"
grep -Fq 'clean reviewed baseline' "${tesseract_build}"
openssl_nasm_patch_hash='7dd0697985022e385f2c7d6e88709b4be891f8e69223fe96f6f283a03416c0f5'
test "$(sha256sum "${openssl_nasm_patch}" | awk '{print $1}')" = "${openssl_nasm_patch_hash}"
grep -Fq "${openssl_nasm_patch_hash}" \
  "${tesseract_build}"
grep -Fq "${openssl_nasm_patch_hash}" \
  "${tesseract_stage}"
grep -Fq "${openssl_nasm_patch_hash}" \
  "${layout_check}"
grep -Fq 'target-feature=+crt-static' "${agent_stage}"
grep -Fq 'RequireVerifiedTesseractRuntimeForRelease' "${windows_root}/src/VoxFlow.Windows.App/VoxFlow.Windows.App.csproj"
grep -Fq 'IncludeStagedTesseractRuntime' "${windows_root}/src/VoxFlow.Windows.App/VoxFlow.Windows.App.csproj"
grep -Fq 'IncludeStagedTesseractRuntimeOnPublish' "${windows_root}/src/VoxFlow.Windows.App/VoxFlow.Windows.App.csproj"
grep -Fq 'StagedTesseractRuntimeRoot' "${windows_root}/src/VoxFlow.Windows.App/VoxFlow.Windows.App.csproj"
grep -Fq 'AfterTargets="Build"' "${windows_root}/src/VoxFlow.Windows.App/VoxFlow.Windows.App.csproj"
grep -Fq 'AfterTargets="Publish"' "${windows_root}/src/VoxFlow.Windows.App/VoxFlow.Windows.App.csproj"
# Debug/dev must copy a staged OCR tree on every Build, not only via load-time Content.
if grep -Eq 'Content Include=.*runtime\\ocr' \
  "${windows_root}/src/VoxFlow.Windows.App/VoxFlow.Windows.App.csproj"; then
  printf '%s\n' 'OCR runtime packaging must use explicit Build/Publish Copy targets.' >&2
  exit 1
fi
grep -Fq 'VoxFlow-$Version-windows-x64-portable.zip' "${windows_root}/scripts/prepare-windows-release.ps1"
grep -Fq 'b00b789b17051aea61e9717458171100662318a4' "${qwen_build}"
grep -Fq 'New-VoxFlowQwenRuntimeManifest' "${qwen_build}"
grep -Fq 'source.bridge.dirty' "${qwen_runtime_manifest}"
grep -Fq 'local validation build is marked dirty' "${qwen_build}"
grep -Fq 'vf_qwen_backend_kind' "${qwen_runtime_manifest}"
grep -Fq 'src/windows_compat.c' "${windows_root}/native/qwen-asr-bridge/CMakeLists.txt"
if grep -Fq 'file(GLOB' "${windows_root}/native/qwen-asr-bridge/CMakeLists.txt"; then
  printf '%s\n' 'Qwen production sources must be explicitly enumerated.' >&2
  exit 1
fi
grep -Fq 'Assert-VoxFlowQwenRuntimeManifest' "${windows_root}/scripts/prepare-windows-release.ps1"
grep -Fq 'QWEN_NATIVE_RUNTIME_MANIFEST.json' "${windows_root}/scripts/prepare-windows-release.ps1"
grep -Fq 'Assert-VoxFlowQwenRuntimeManifest' "${layout_check}"
grep -Fq 'published Qwen readiness canary' "${layout_check}"
grep -Fq 'Qwen native export audit' "${layout_check}"
grep -Fq 'ReadAbiVersion' "${qwen_runtime_manifest}"
grep -Fq 'qwen-asr-native-bridge' "${qwen_runtime_manifest}"
grep -Fq 'Get-FileHash -LiteralPath $binary -Algorithm SHA256' "${qwen_runtime_manifest}"
grep -Fq 'ApplicationExecutable = "VoxFlow.exe"' "${installer_contract}"
grep -Fq 'QWEN_NATIVE_RUNTIME_MANIFEST.json' "${installer_contract}"
grep -Fq 'runtime\ffmpeg\ffmpeg.exe' "${installer_contract}"
grep -Fq 'runtime\ffmpeg\THIRD_PARTY_NOTICES.md' "${installer_contract}"
grep -Fq 'runtime\ffmpeg\ffprobe.exe' "${installer_contract}"
grep -Fq 'runtime\agent\voxflow-agent.exe' "${installer_contract}"
grep -Fq 'runtime\ocr\tesseract.exe' "${installer_contract}"
grep -Fq 'runtime\ocr\tessdata\eng.traineddata' "${installer_contract}"
grep -Fq 'licenses\LICENSE-GPL-3.0-or-later.txt' "${installer_contract}"
grep -Fq 'licenses\THIRD-PARTY-NOTICES.md' "${installer_contract}"
grep -Fq 'Resolve-VoxFlowDotnetPath' "${process_helpers}"
grep -Fq "Program Files\\dotnet" "${process_helpers}"
grep -Fq 'WaitForExit($TimeoutSeconds * 1000)' "${process_helpers}"
grep -Fq 'Resolve-VoxFlowDotnetPath' "${windows_root}/scripts/check-localization.ps1"
grep -Fq 'Resolve-VoxFlowDotnetPath' "${release_check}"
grep -Fq 'Resolve-VoxFlowDotnetPath' "${windows_root}/scripts/prepare-windows-release.ps1"
for bounded_script in \
  "${release_check}" \
  "${windows_root}/scripts/prepare-windows-release.ps1" \
  "${tesseract_build}" \
  "${qwen_build}" \
  "${agent_stage}" \
  "${layout_check}"; do
  grep -Fq 'Invoke-VoxFlowProcess' "${bounded_script}"
  if grep -Fq 'Start-Process' "${bounded_script}"; then
    printf 'Release process must use the bounded process helper: %s\n' "${bounded_script}" >&2
    exit 1
  fi
done
grep -Fq 'Invoke-VoxFlowProcess' "${qwen_bridge_test}"
grep -Fq 'process-helpers.test.ps1' "${release_check}"
if grep -Fq 'Start-Process' "${qwen_bridge_test}"; then
  printf '%s\n' 'Qwen native contract processes must not inherit a WSL PTY through Start-Process.' >&2
  exit 1
fi
if grep -R -Fq --include='*.ps1' 'Start-Process' "${windows_root}/scripts"; then
  printf '%s\n' 'Release and governance scripts must not use unbounded Start-Process.' >&2
  exit 1
fi
grep -Fq 'https://api.nuget.org/v3-flatcontainer/devenvy.ffmpeg.binaries.lgpl/' \
  "${windows_root}/runtime/ffmpeg/FFMPEG_RUNTIME_MANIFEST.json"
grep -Fq '8.0.1.4' "${windows_root}/runtime/ffmpeg/FFMPEG_RUNTIME_MANIFEST.json"
ffmpeg_manifest_hash='edcea9157fcb9789645879111299739d9da1bb1e4656bba1c0352740d84f5110'
test "$(sha256sum "${windows_root}/runtime/ffmpeg/FFMPEG_RUNTIME_MANIFEST.json" | awk '{print $1}')" = \
  "${ffmpeg_manifest_hash}"
grep -Fq "${ffmpeg_manifest_hash}" "${layout_check}"
qwen_provenance_hash='180f3efcf0b91ff8074378891c5ca663458cd6f5e13d72f3334498c645002e01'
test "$(sha256sum "${windows_root}/native/qwen-asr/MODEL_PROVENANCE.json" | awk '{print $1}')" = \
  "${qwen_provenance_hash}"
grep -Fq "${qwen_provenance_hash}" "${windows_root}/scripts/check-no-secrets.sh"
for lf_path in \
  'native/qwen-asr/MODEL_PROVENANCE.json' \
  'runtime/ffmpeg/FFMPEG_RUNTIME_MANIFEST.json' \
  'scripts/patches/*.patch'; do
  grep -Fq "${lf_path} text eol=lf" "${windows_root}/.gitattributes"
done
grep -Fq '39d65c5952106502f000d66c41c3bd23d2c0550a8c3270bb224c7642b3cccf9e' \
  "${windows_root}/runtime/ffmpeg/FFMPEG_RUNTIME_MANIFEST.json"

printf '%s\n' 'PASS: Windows packaging source contract is per-user, x64-only, self-contained, license-complete, and has explicit data deletion.'
