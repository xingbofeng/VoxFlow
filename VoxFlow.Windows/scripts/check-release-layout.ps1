[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string] $PublishRoot
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot 'ProcessHelpers.ps1')
. (Join-Path $PSScriptRoot 'QwenRuntimeManifest.ps1')

function Fail {
    param([string] $Message)
    throw $Message
}

function Assert-X64Pe {
    param([string] $Path)

    $bytes = [System.IO.File]::ReadAllBytes($Path)
    if ($bytes.Length -lt 0x100 -or $bytes[0] -ne 0x4d -or $bytes[1] -ne 0x5a) {
        Fail "Release binary is not a PE image: $Path"
    }
    $peOffset = [BitConverter]::ToInt32($bytes, 0x3c)
    if ($peOffset -lt 0 -or ($peOffset + 6) -gt $bytes.Length) {
        Fail "Release binary has an invalid PE header: $Path"
    }
    $machine = [BitConverter]::ToUInt16($bytes, $peOffset + 4)
    if ($machine -ne 0x8664) {
        Fail "Release binary is not Windows x64: $Path"
    }
}

$windowsRoot = Split-Path -Parent $PSScriptRoot
$root = (Resolve-Path -LiteralPath $PublishRoot).Path
$requiredFiles = @(
    'VoxFlow.exe',
    'VoxFlow.deps.json',
    'VoxFlow.runtimeconfig.json',
    'coreclr.dll',
    'hostfxr.dll',
    'qwen_asr.dll',
    'Qwen/QWEN_NATIVE_RUNTIME_MANIFEST.json',
    'Qwen/MODEL_PROVENANCE.json',
    'Qwen/readiness-canary.wav',
    'runtime/agent/VOXFLOW_AGENT_RUNTIME_MANIFEST.json',
    'runtime/agent/voxflow-agent.exe',
    'runtime/ffmpeg/FFMPEG_RUNTIME_MANIFEST.json',
    'runtime/ffmpeg/LICENSE.txt',
    'runtime/ffmpeg/ffmpeg.exe',
    'runtime/ffmpeg/ffprobe.exe',
    'runtime/ocr/TESSERACT_RUNTIME_MANIFEST.json',
    'runtime/ocr/LICENSE.txt',
    'runtime/ocr/tesseract.exe',
    'runtime/ocr/tessdata/eng.traineddata',
    'ScreenCapture.NET.dll',
    'ScreenCapture.NET.DX11.dll',
    'HPPH.dll',
    'Vortice.Direct3D11.dll',
    'Vortice.DXGI.dll',
    'Vortice.DirectX.dll',
    'Vortice.Mathematics.dll',
    'SharpGen.Runtime.dll',
    'SharpGen.Runtime.COM.dll',
    'licenses/LICENSE-GPL-3.0-or-later.txt',
    'licenses/LICENSE-qwen-asr-MIT.txt',
    'licenses/LICENSE-LGPL-2.1-only.txt',
    'licenses/LICENSE-MIT-dependencies.txt',
    'licenses/LICENSE-Apache-2.0.txt',
    'licenses/LICENSE-Unicode-3.0.txt',
    'licenses/LICENSE-SQLite-blessing.txt',
    'licenses/THIRD-PARTY-NOTICES.md'
)
foreach ($relativePath in $requiredFiles) {
    $path = Join-Path $root $relativePath
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        Fail "Required release file is missing: $relativePath"
    }
}

$qwenRoot = Join-Path $root 'Qwen'
$qwenNativeManifestPath = Join-Path $qwenRoot 'QWEN_NATIVE_RUNTIME_MANIFEST.json'
$qwenBinary = Join-Path $root 'qwen_asr.dll'
Assert-VoxFlowQwenRuntimeManifest `
    -BinaryPath $qwenBinary -ManifestPath $qwenNativeManifestPath | Out-Null

$qwenProvenancePath = Join-Path $qwenRoot 'MODEL_PROVENANCE.json'
$expectedQwenProvenancePath = Join-Path $windowsRoot 'native/qwen-asr/MODEL_PROVENANCE.json'
$publishedProvenanceHash = (Get-FileHash -LiteralPath $qwenProvenancePath -Algorithm SHA256).Hash
$expectedProvenanceHash = (Get-FileHash -LiteralPath $expectedQwenProvenancePath -Algorithm SHA256).Hash
if ($publishedProvenanceHash -ne $expectedProvenanceHash) {
    Fail 'The published Qwen model provenance does not match the reviewed source record.'
}
$qwenProvenance = Get-Content -LiteralPath $qwenProvenancePath -Raw | ConvertFrom-Json
$qwenValidation = $qwenProvenance.runtime.windowsValidation
$qwenFixedWav = $qwenValidation.fixedWav
if ($qwenProvenance.schemaVersion -ne 1 -or $qwenProvenance.publishable -ne $true -or
    $null -ne $qwenProvenance.publicationBlocker -or
    $qwenProvenance.runtime.repository -ne 'https://github.com/antirez/qwen-asr' -or
    $qwenProvenance.runtime.upstreamRevision -ne 'b00b789b17051aea61e9717458171100662318a4' -or
    $qwenValidation.status -ne 'passed' -or $qwenValidation.targetArchitecture -ne 'x64' -or
    $qwenValidation.portabilityOverlay.cleanupPatchSha256 -ne
        '519fd8434a4e5f9ffd4a067686c552905eca0a5e1387ac2f467ea9007f2965a8' -or
    $qwenValidation.dependencyAudit.status -ne 'passed' -or
    $qwenValidation.dependencyAudit.externalRuntimeRequired -ne $false -or
    $qwenValidation.fixedWavExecuted -ne $true -or
    [long]$qwenFixedWav.bytes -le 0 -or
    $qwenFixedWav.sha256 -notmatch '^[0-9a-f]{64}$') {
    Fail 'The published Qwen model provenance is invalid.'
}
$qwenCanaryPath = Join-Path $qwenRoot 'readiness-canary.wav'
$qwenCanary = Get-Item -LiteralPath $qwenCanaryPath
$qwenCanaryHash = (Get-FileHash -LiteralPath $qwenCanaryPath -Algorithm SHA256).Hash.ToLowerInvariant()
if ($qwenCanary.Length -ne [long]$qwenFixedWav.bytes -or
    $qwenCanaryHash -ne $qwenFixedWav.sha256) {
    Fail 'The published Qwen readiness canary does not match its reviewed provenance.'
}
$expectedQwenFiles = @(
    'MODEL_PROVENANCE.json',
    'QWEN_NATIVE_RUNTIME_MANIFEST.json',
    'readiness-canary.wav'
)
$actualQwenFiles = @(Get-ChildItem -LiteralPath $qwenRoot -Recurse -File | ForEach-Object {
    $_.FullName.Substring($qwenRoot.Length).TrimStart('\').Replace('\', '/')
})
if (@(Compare-Object ($expectedQwenFiles | Sort-Object) ($actualQwenFiles | Sort-Object)).Count -ne 0) {
    Fail 'The controlled Qwen runtime metadata contains missing or extra files.'
}

$ffmpegRoot = Join-Path $root 'runtime/ffmpeg'
$ocrRoot = Join-Path $root 'runtime/ocr'
$agentRoot = Join-Path $root 'runtime/agent'
$agentManifestPath = Join-Path $agentRoot 'VOXFLOW_AGENT_RUNTIME_MANIFEST.json'
if (-not (Test-Path -LiteralPath $agentManifestPath -PathType Leaf)) { Fail 'The controlled built-in Agent manifest is missing.' }
$agentManifest = Get-Content -LiteralPath $agentManifestPath -Raw | ConvertFrom-Json
if ($agentManifest.schemaVersion -ne 1 -or $agentManifest.runtimeId -ne 'voxflow-agent' -or
    $agentManifest.architecture -ne 'x64' -or
    $agentManifest.target -ne 'x86_64-pc-windows-msvc' -or
    $agentManifest.binary -ne 'voxflow-agent.exe' -or
    [long]$agentManifest.size -le 0 -or
    $agentManifest.license -ne 'MIT' -or
    $agentManifest.source.repository -ne 'https://github.com/xingbofeng/VoxFlow' -or
    $agentManifest.source.path -ne 'agent-cli' -or
    $agentManifest.source.revision -notmatch '^[0-9a-f]{40}$' -or
    $agentManifest.build.profile -ne 'release' -or
    @($agentManifest.build.features).Count -ne 1 -or
    $agentManifest.build.features[0] -ne 'builtin-agent' -or
    $agentManifest.build.defaultFeatures -ne $false -or
    $agentManifest.build.locked -ne $true -or
    $agentManifest.build.binary -ne 'voxflow-agent' -or
    $agentManifest.build.crtLinkage -ne 'static' -or
    $agentManifest.build.targetFeature -ne '+crt-static' -or
    $agentManifest.sha256 -notmatch '^[0-9a-fA-F]{64}$') {
    Fail 'The built-in Agent manifest is invalid.'
}
$agentBinary = Join-Path $agentRoot $agentManifest.binary
if (-not (Test-Path -LiteralPath $agentBinary -PathType Leaf) -or
    (Get-Item -LiteralPath $agentBinary).Length -ne [long]$agentManifest.size -or
    (Get-FileHash -LiteralPath $agentBinary -Algorithm SHA256).Hash -ne $agentManifest.sha256) {
    Fail 'The bundled built-in Agent binary is missing or has been modified.'
}
$expectedAgentFiles = @('VOXFLOW_AGENT_RUNTIME_MANIFEST.json', 'voxflow-agent.exe')
$actualAgentFiles = @(Get-ChildItem -LiteralPath $agentRoot -Recurse -File | ForEach-Object {
    $_.FullName.Substring($agentRoot.Length).TrimStart('\').Replace('\', '/')
})
if (@(Compare-Object ($expectedAgentFiles | Sort-Object) ($actualAgentFiles | Sort-Object)).Count -ne 0) {
    Fail 'The controlled built-in Agent runtime contains missing or extra files.'
}
Assert-X64Pe $agentBinary

$ocrManifestPath = Join-Path $ocrRoot 'TESSERACT_RUNTIME_MANIFEST.json'
if (-not (Test-Path -LiteralPath $ocrManifestPath -PathType Leaf)) {
    Fail 'The controlled Tesseract runtime manifest is missing.'
}
$ocrManifest = Get-Content -LiteralPath $ocrManifestPath -Raw | ConvertFrom-Json
if ($ocrManifest.schemaVersion -ne 1 -or
    $ocrManifest.runtimeId -ne 'tesseract-5.5.2-vcpkg-03e366fb-x64-static' -or
    $ocrManifest.version -ne '5.5.2' -or $ocrManifest.architecture -ne 'x64' -or
    $ocrManifest.binary -ne 'tesseract.exe' -or
    $ocrManifest.license -ne 'Apache-2.0' -or
    $ocrManifest.source.repository -ne 'https://github.com/tesseract-ocr/tesseract' -or
    $ocrManifest.source.tag -ne '5.5.2' -or
    $ocrManifest.build.packageManager -ne 'vcpkg' -or
    $ocrManifest.build.baseline -ne '03e366fb91e38b9432ebd5f8cc79f7c8f55e96ab' -or
    $ocrManifest.build.triplet -ne 'x64-windows-static' -or
    $ocrManifest.build.buildType -ne 'release' -or
    $ocrManifest.build.nasm -ne '3.01' -or
    $ocrManifest.build.opensslNasmPatchSha256 -ne
        '7dd0697985022e385f2c7d6e88709b4be891f8e69223fe96f6f283a03416c0f5' -or
    $ocrManifest.tessdata.repository -ne 'https://github.com/tesseract-ocr/tessdata_fast' -or
    $ocrManifest.tessdata.revision -ne '87416418657359cb625c412a48b6e1d6d41c29bd' -or
    $ocrManifest.tessdata.license -ne 'Apache-2.0') {
    Fail 'The controlled Tesseract runtime manifest is invalid.'
}
$ocrModels = [ordered]@{
    eng = @{ path = 'tessdata/eng.traineddata'; size = 4113088; sha256 = '7d4322bd2a7749724879683fc3912cb542f19906c83bcc1a52132556427170b2' }
    chi_sim = @{ path = 'tessdata/chi_sim.traineddata'; size = 2469156; sha256 = 'a5fcb6f0db1e1d6d8522f39db4e848f05984669172e584e8d76b6b3141e1f730' }
    chi_tra = @{ path = 'tessdata/chi_tra.traineddata'; size = 2366642; sha256 = '529c5b5797d64b126065cd55f2bb4c7fd7b15790798091b1ff259941a829330b' }
    jpn = @{ path = 'tessdata/jpn.traineddata'; size = 2471260; sha256 = '1f5de9236d2e85f5fdf4b3c500f2d4926f8d9449f28f5394472d9e8d83b91b4d' }
    kor = @{ path = 'tessdata/kor.traineddata'; size = 1677415; sha256 = '6b85e11d9bbf07863b97b3523b1b112844c43e713df8b66418a081fd1060b3b2' }
}
$ocrNativeDependencies = [ordered]@{
    bzip2 = @{ version = '1.0.8#6'; license = 'bzip2-1.0.6'; source = 'https://sourceware.org/bzip2/'; size = 1896; sha256 = 'c6dbbf828498be844a89eaa3b84adbab3199e342eb5cb2ed2f0d4ba7ec0f38a3' }
    curl = @{ version = '8.21.0#1'; license = 'curl AND ISC AND BSD-3-Clause'; source = 'https://github.com/curl/curl'; size = 2055; sha256 = '543457a53893d439ac029f115c15940c0921ce1b919db501bbad266e2a4d1059' }
    giflib = @{ version = '6.1.3'; license = 'MIT'; source = 'https://sourceforge.net/projects/giflib/'; size = 1039; sha256 = 'ed5d90cb4a041bddad679470a071302ab05ae5d0ec2cf8f9c97ad7b2708751e6' }
    leptonica = @{ version = '1.87.0'; license = 'BSD-2-Clause'; source = 'https://github.com/DanBloomberg/leptonica'; size = 1521; sha256 = '87829abb5bbb00b55a107365da89e9a33f86c4250169e5a1e5588505be7d5806' }
    libarchive = @{ version = '3.8.7'; license = 'BSD-2-Clause'; source = 'https://github.com/libarchive/libarchive'; size = 3089; sha256 = '30e556b3959e3985d66efefec5eaac51d4995053caa1d3cffe6eb916f146f229' }
    'libjpeg-turbo' = @{ version = '3.2.0'; license = 'BSD-3-Clause AND IJG'; source = 'https://github.com/libjpeg-turbo/libjpeg-turbo'; size = 6077; sha256 = 'ba6bceebcba0fdd35488477c2cca8c4632ce82c74dbfbc87d886ce6fc4433579' }
    liblzma = @{ version = '5.8.3'; license = '0BSD'; source = 'https://github.com/tukaani-project/xz'; size = 3119; sha256 = '616a3ad264ce29b8f1cb97e53037b139d406899ca8d1f799651e17bfa09830b8' }
    libpng = @{ version = '1.6.58'; license = 'libpng-2.0'; source = 'https://github.com/pnggroup/libpng'; size = 5345; sha256 = 'bdb0a645ea18c60507d0368379b1ac5474b92255fcc2d115e07486a7672ba526' }
    libwebp = @{ version = '1.6.0#2'; license = 'BSD-3-Clause'; source = 'https://github.com/webmproject/libwebp'; size = 3017; sha256 = '050b5ba2c8eb0bd3b996e12ef79312a1c62237f2de1b3c609843f00bb74744f3' }
    lz4 = @{ version = '1.10.0'; license = 'BSD-2-Clause'; source = 'https://github.com/lz4/lz4'; size = 1311; sha256 = '8b58c446121a109ccf32edc094bba3010a3d85e4ee3702950db55e4d3e87736c' }
    openjpeg = @{ version = '2.5.4'; license = 'BSD-2-Clause'; source = 'https://github.com/uclouvain/openjpeg'; size = 2112; sha256 = 'a6af136f3e15038a666b61f376612a07d9a4e48cb7c01adbf3e33b3f14ab49b6' }
    openssl = @{ version = '3.6.3'; license = 'Apache-2.0'; source = 'https://github.com/openssl/openssl'; size = 10175; sha256 = '7d5450cb2d142651b8afa315b5f238efc805dad827d91ba367d8516bc9d49e7a' }
    tiff = @{ version = '4.7.2'; license = 'libtiff'; source = 'https://gitlab.com/libtiff/libtiff'; size = 2416; sha256 = '0e27c2382d7b8147972bbb746e04059a1152c8d0fda9d03ef1399d1a433c4ade' }
    zlib = @{ version = '1.3.2#1'; license = 'Zlib'; source = 'https://github.com/madler/zlib'; size = 1002; sha256 = 'e32ff4e00d9d94930537635291da39e7e612703334bf6fde8c7f1686fe8a45a2' }
    zstd = @{ version = '1.5.7'; license = 'BSD-3-Clause'; source = 'https://github.com/facebook/zstd'; size = 20086; sha256 = '434dca949c6da7c500413aef694539fe37f867dd1a94d83d4ed1d260194e2660' }
}
if ($null -eq $ocrManifest.files -or $null -eq $ocrManifest.languages -or
    $null -eq $ocrManifest.nativeDependencies -or
    @($ocrManifest.files).Count -ne 22 -or @($ocrManifest.languages).Count -ne 5 -or
    @($ocrManifest.nativeDependencies).Count -ne $ocrNativeDependencies.Count) {
    Fail 'The controlled Tesseract runtime inventory is incomplete.'
}
$expectedOcrManifestPaths = @('tesseract.exe', 'LICENSE.txt') + @(
    $ocrModels.Values | ForEach-Object { $_.path }) + @(
    $ocrNativeDependencies.Keys | ForEach-Object { "licenses/$_.txt" })
$manifestOcrPaths = @($ocrManifest.files | ForEach-Object { $_.path })
if ($manifestOcrPaths.Count -ne $expectedOcrManifestPaths.Count -or
    @(Compare-Object ($manifestOcrPaths | Sort-Object) ($expectedOcrManifestPaths | Sort-Object)).Count -ne 0) {
    Fail 'The controlled Tesseract runtime file paths changed.'
}
$ocrLanguageNames = @($ocrManifest.languages | ForEach-Object { $_.language } | Sort-Object)
if (@(Compare-Object $ocrLanguageNames @($ocrModels.Keys | Sort-Object)).Count -ne 0) {
    Fail 'The controlled Tesseract runtime language inventory changed.'
}
foreach ($language in $ocrManifest.languages) {
    $expected = $ocrModels[$language.language]
    if ($null -eq $expected -or $language.path -ne $expected.path -or
        [long]$language.size -ne [long]$expected.size -or
        $language.sha256 -ne $expected.sha256) {
        Fail "The controlled Tesseract language manifest is invalid: $($language.language)"
    }
}
foreach ($dependency in $ocrManifest.nativeDependencies) {
    $expected = $ocrNativeDependencies[$dependency.port]
    $notice = "licenses/$($dependency.port).txt"
    if ($null -eq $expected -or $dependency.version -ne $expected.version -or
        $dependency.license -ne $expected.license -or $dependency.source -ne $expected.source -or
        $dependency.notice -ne $notice) {
        Fail "The controlled Tesseract native dependency inventory is invalid: $($dependency.port)"
    }
}
$ocrDependencyNames = @($ocrManifest.nativeDependencies | ForEach-Object { $_.port } | Sort-Object)
if (@(Compare-Object $ocrDependencyNames @($ocrNativeDependencies.Keys | Sort-Object)).Count -ne 0) {
    Fail 'The controlled Tesseract native dependency set changed.'
}
$expectedOcrFiles = @('TESSERACT_RUNTIME_MANIFEST.json') + @(
    $ocrManifest.files | ForEach-Object { $_.path })
$actualOcrFiles = @(Get-ChildItem -LiteralPath $ocrRoot -Recurse -File | ForEach-Object {
    $_.FullName.Substring($ocrRoot.Length).TrimStart('\').Replace('\', '/')
})
if (@(Compare-Object ($expectedOcrFiles | Sort-Object) ($actualOcrFiles | Sort-Object)).Count -ne 0) {
    Fail 'The controlled Tesseract runtime contains missing or extra files.'
}
$ocrFiles = @{}
foreach ($file in $ocrManifest.files) {
    $normalizedPath = if ($null -eq $file.path) { '' } else { $file.path.Replace('\', '/') }
    if ([string]::IsNullOrWhiteSpace($file.path) -or $file.path -ne $normalizedPath -or
        [System.IO.Path]::IsPathRooted($file.path) -or $normalizedPath -match '(^|/)\.\.(/|$)' -or
        $normalizedPath.Contains(':') -or $ocrFiles.ContainsKey($file.path)) {
        Fail 'The controlled Tesseract runtime manifest contains unsafe duplicate paths.'
    }
    $ocrFiles[$file.path] = $file
    $path = Join-Path $ocrRoot $file.path.Replace('/', '\')
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        Fail "The controlled Tesseract runtime file is missing: $($file.path)"
    }
    $item = Get-Item -LiteralPath $path
    $hash = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($item.Length -ne [long]$file.size -or $hash -ne $file.sha256) {
        Fail "The controlled Tesseract runtime file hash is invalid: $($file.path)"
    }
}
if (-not $ocrFiles.ContainsKey('tesseract.exe') -or -not $ocrFiles.ContainsKey('LICENSE.txt')) {
    Fail 'The controlled Tesseract runtime must include its binary and license.'
}
$ocrLicense = $ocrFiles['LICENSE.txt']
if ([long]$ocrLicense.size -ne 11358 -or
    $ocrLicense.sha256 -ne 'cfc7749b96f63bd31c3c42b5c471bf756814053e847c10f3eb003417bc523d30') {
    Fail 'The controlled Tesseract license does not match the reviewed source.'
}
foreach ($model in $ocrModels.Values) {
    $modelFile = $ocrFiles[$model.path]
    if ($null -eq $modelFile -or [long]$modelFile.size -ne [long]$model.size -or
        $modelFile.sha256 -ne $model.sha256) {
        Fail "The controlled Tesseract model file is invalid: $($model.path)"
    }
}
foreach ($dependencyName in $ocrNativeDependencies.Keys) {
    $dependency = $ocrNativeDependencies[$dependencyName]
    $noticePath = "licenses/$dependencyName.txt"
    $noticeFile = $ocrFiles[$noticePath]
    if ($null -eq $noticeFile -or [long]$noticeFile.size -ne [long]$dependency.size -or
        $noticeFile.sha256 -ne $dependency.sha256) {
        Fail "The controlled Tesseract dependency notice is invalid: $dependencyName"
    }
}
$ocrBinary = Join-Path $ocrRoot 'tesseract.exe'
Assert-X64Pe $ocrBinary

$ffmpegManifestPath = Join-Path $ffmpegRoot 'FFMPEG_RUNTIME_MANIFEST.json'
if (-not (Test-Path -LiteralPath $ffmpegManifestPath -PathType Leaf)) {
    Fail 'The controlled FFmpeg runtime manifest is missing.'
}
$reviewedFfmpegManifestPath = Join-Path $windowsRoot 'runtime/ffmpeg/FFMPEG_RUNTIME_MANIFEST.json'
$reviewedFfmpegManifestHash = (Get-FileHash -LiteralPath $reviewedFfmpegManifestPath -Algorithm SHA256).Hash.ToLowerInvariant()
$publishedFfmpegManifestHash = (Get-FileHash -LiteralPath $ffmpegManifestPath -Algorithm SHA256).Hash.ToLowerInvariant()
if ($reviewedFfmpegManifestHash -ne
        '957ee658b3acbc8683c40131db499147c48e4d11cff745b15e332443798e1038' -or
    $publishedFfmpegManifestHash -ne $reviewedFfmpegManifestHash) {
    Fail 'The published FFmpeg manifest does not match the reviewed source manifest.'
}
$ffmpegManifest = Get-Content -LiteralPath $ffmpegManifestPath -Raw | ConvertFrom-Json
if ($ffmpegManifest.schemaVersion -ne 1 -or
    $ffmpegManifest.runtimeId -ne 'ffmpeg-n8.1.2-22-g94138f6973-20260710-win64-lgpl-shared' -or
    $ffmpegManifest.architecture -ne 'x64' -or
    $ffmpegManifest.license -ne 'LGPL-3.0-or-later' -or
    $ffmpegManifest.archive.fileName -ne 'ffmpeg-n8.1.2-22-g94138f6973-win64-lgpl-shared-8.1.zip' -or
    [long]$ffmpegManifest.archive.size -ne 70508421 -or
    $ffmpegManifest.archive.sha256 -ne
        'cd39114d50ad2d17d892571d896f67fbe8b25333958682430f095eeffbb58598' -or
    [long]$ffmpegManifest.archive.assetId -ne 472524907 -or
    $ffmpegManifest.archive.releaseTag -ne 'autobuild-2026-07-10-13-44' -or
    $ffmpegManifest.licenseFile.path -ne 'LICENSE.txt' -or
    [long]$ffmpegManifest.licenseFile.size -ne 7651 -or
    $ffmpegManifest.licenseFile.sha256 -ne
        'da7eabb7bafdf7d3ae5e9f223aa5bdc1eece45ac569dc21b3b037520b4464768') {
    Fail 'The published FFmpeg runtime identity or architecture changed.'
}
$reviewedFfmpegFilePaths = @(
    'avcodec-62.dll',
    'avdevice-62.dll',
    'avfilter-11.dll',
    'avformat-62.dll',
    'avutil-60.dll',
    'ffmpeg.exe',
    'ffprobe.exe',
    'swresample-6.dll',
    'swscale-9.dll'
)
$manifestFfmpegFilePaths = @($ffmpegManifest.files | ForEach-Object { $_.path })
if (@($ffmpegManifest.files).Count -ne $reviewedFfmpegFilePaths.Count -or
    @(Compare-Object ($manifestFfmpegFilePaths | Sort-Object) ($reviewedFfmpegFilePaths | Sort-Object)).Count -ne 0) {
    Fail 'The published FFmpeg runtime file inventory changed.'
}
$expectedFfmpegFiles = @('FFMPEG_RUNTIME_MANIFEST.json', $ffmpegManifest.licenseFile.path) + @(
    $ffmpegManifest.files | ForEach-Object { $_.path })
$actualFfmpegFiles = @(Get-ChildItem -LiteralPath $ffmpegRoot -Recurse -File | ForEach-Object {
    $_.FullName.Substring($ffmpegRoot.Length).TrimStart('\').Replace('\', '/')
})
$inventoryDifference = @(Compare-Object ($expectedFfmpegFiles | Sort-Object) ($actualFfmpegFiles | Sort-Object))
if ($inventoryDifference.Count -gt 0) {
    Fail "The published FFmpeg runtime contains missing or extra files: $($inventoryDifference[0].InputObject)."
}
$ffmpegLicensePath = Join-Path $ffmpegRoot $ffmpegManifest.licenseFile.path
$ffmpegLicenseInfo = Get-Item -LiteralPath $ffmpegLicensePath
$ffmpegLicenseHash = (Get-FileHash -LiteralPath $ffmpegLicensePath -Algorithm SHA256).Hash.ToLowerInvariant()
if ($ffmpegLicenseInfo.Length -ne [long]$ffmpegManifest.licenseFile.size -or
    $ffmpegLicenseHash -ne $ffmpegManifest.licenseFile.sha256) {
    Fail 'The published FFmpeg license file does not match the reviewed archive.'
}
foreach ($entry in $ffmpegManifest.files) {
    $normalizedPath = if ($null -eq $entry.path) { '' } else { $entry.path.Replace('\', '/') }
    if ([string]::IsNullOrWhiteSpace($entry.path) -or $entry.path -ne $normalizedPath -or
        [System.IO.Path]::IsPathRooted($entry.path) -or $normalizedPath -match '(^|/)\.\.(/|$)' -or
        $normalizedPath.Contains(':')) {
        Fail 'The published FFmpeg manifest contains an unsafe path.'
    }
    $path = Join-Path $ffmpegRoot $entry.path
    $info = Get-Item -LiteralPath $path
    $hash = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($info.Length -ne [long]$entry.size -or $hash -ne $entry.sha256) {
        Fail "Published FFmpeg runtime verification failed: $($entry.path)."
    }
    Assert-X64Pe $path
}

Assert-X64Pe (Join-Path $root 'VoxFlow.exe')
Assert-X64Pe (Join-Path $root 'qwen_asr.dll')

$replaceableScreenshotAssemblies = @(
    'ScreenCapture.NET.dll',
    'ScreenCapture.NET.DX11.dll',
    'HPPH.dll'
)
foreach ($assembly in $replaceableScreenshotAssemblies) {
    $assemblyPath = Join-Path $root $assembly
    if (-not (Test-Path -LiteralPath $assemblyPath -PathType Leaf)) {
        Fail "Replaceable LGPL screenshot assembly is missing: $assembly"
    }
}

$forbiddenNames = '(?i)(^|[._-])(python|cuda|cudart|nvcuda|mlx|wsl)([._-]|$)|\.py[co]?$|\.msix$|\.appx$'
$forbidden = @(Get-ChildItem -LiteralPath $root -Recurse -File |
    Where-Object { $_.Name -match $forbiddenNames })
if ($forbidden.Count -gt 0) {
    Fail "Forbidden release dependency detected: $($forbidden[0].Name)"
}

$dumpbin = Get-ChildItem -Path 'C:\BuildTools\VC\Tools\MSVC' -Filter dumpbin.exe -Recurse -File -ErrorAction SilentlyContinue |
    Where-Object { $_.FullName -match 'Hostx64\\x64\\dumpbin\.exe$' } |
    Sort-Object FullName -Descending |
    Select-Object -First 1
if ($null -eq $dumpbin) {
    $visualStudioRoots = @(
        (Join-Path ${env:ProgramFiles} 'Microsoft Visual Studio'),
        (Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio')
    )
    $dumpbin = Get-ChildItem -Path $visualStudioRoots -Filter dumpbin.exe -Recurse -File -ErrorAction SilentlyContinue |
        Where-Object { $_.FullName -match 'Hostx64\\x64\\dumpbin\.exe$' } |
        Sort-Object FullName -Descending |
        Select-Object -First 1
}
if ($null -eq $dumpbin) {
    Fail 'dumpbin.exe is required to audit native runtime imports.'
}

$qwenExportText = Invoke-VoxFlowProcess -FilePath $dumpbin.FullName `
    -Arguments @('/nologo', '/exports', $qwenBinary) `
    -Description 'Qwen native export audit' -TimeoutSeconds 120 -CaptureOutput
$expectedQwenExports = @(
    'vf_qwen_abi_version',
    'vf_qwen_backend_kind',
    'vf_qwen_runtime_create',
    'vf_qwen_runtime_destroy',
    'vf_qwen_session_create',
    'vf_qwen_session_start',
    'vf_qwen_session_push_pcm16',
    'vf_qwen_session_poll',
    'vf_qwen_session_finish',
    'vf_qwen_session_cancel',
    'vf_qwen_session_last_error',
    'vf_qwen_session_destroy'
)
foreach ($qwenExport in $expectedQwenExports) {
    if ($qwenExportText -notmatch "(?m)\b$([regex]::Escape($qwenExport))\b") {
        Fail "The Qwen production bridge is missing its required export: $qwenExport"
    }
}

$nativeBinaries = @((Join-Path $root 'qwen_asr.dll'), $agentBinary, $ocrBinary) + @(
    $ffmpegManifest.files |
        Where-Object { $_.path -match '(?i)\.(dll|exe)$' } |
        ForEach-Object { Join-Path $ffmpegRoot $_.path })
foreach ($nativeBinary in $nativeBinaries) {
    $dependencyText = Invoke-VoxFlowProcess -FilePath $dumpbin.FullName `
        -Arguments @('/nologo', '/dependents', $nativeBinary) `
        -Description 'dumpbin dependency audit' -TimeoutSeconds 120 -CaptureOutput
    if ($dependencyText -match '(?i)(python[^\s]*|cudart[^\s]*|nvcuda|mlx[^\s]*|libwinpthread[^\s]*|vcruntime[^\s]*|msvcp[^\s]*)\.dll') {
        Fail "Native runtime imports a forbidden external dependency: $([IO.Path]::GetFileName($nativeBinary))."
    }
    $dependencies = @([regex]::Matches(
        $dependencyText,
        '(?im)^\s+(?<name>[a-z0-9_.-]+\.dll)\s*$') |
        ForEach-Object { $_.Groups['name'].Value } |
        Sort-Object -Unique)
    if ($dependencies.Count -eq 0) {
        Fail "dumpbin returned no dependency inventory for $([IO.Path]::GetFileName($nativeBinary))."
    }
    foreach ($dependency in $dependencies) {
        $normalized = $dependency.ToLowerInvariant()
        $nativeDirectory = Split-Path -Parent $nativeBinary
        $nativeBinaryIsAtPublishRoot = [System.IO.Path]::GetFullPath($nativeDirectory).TrimEnd('\') -eq
            [System.IO.Path]::GetFullPath($root).TrimEnd('\')
        if ((Test-Path -LiteralPath (Join-Path $nativeDirectory $dependency) -PathType Leaf) -or
            ($nativeBinaryIsAtPublishRoot -and
                (Test-Path -LiteralPath (Join-Path $root $dependency) -PathType Leaf)) -or
            $normalized -match '^(api|ext)-ms-win-' -or
            (Test-Path -LiteralPath (Join-Path $env:SystemRoot "System32/$dependency") -PathType Leaf)) {
            continue
        }
        Fail "Native runtime imports an unpackaged non-system dependency: $dependency from $([IO.Path]::GetFileName($nativeBinary))."
    }
}

Write-Output 'PASS: release layout is self-contained Windows x64, license-complete, and native dependency-audited.'
