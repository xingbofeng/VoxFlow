[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string] $PublishRoot
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

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

$root = (Resolve-Path -LiteralPath $PublishRoot).Path
$requiredFiles = @(
    'VoxFlow.exe',
    'VoxFlow.deps.json',
    'VoxFlow.runtimeconfig.json',
    'coreclr.dll',
    'hostfxr.dll',
    'qwen_asr.dll',
    'licenses/LICENSE-GPL-3.0-or-later.txt',
    'licenses/LICENSE-qwen-asr-MIT.txt',
    'licenses/LICENSE-MIT-dependencies.txt',
    'licenses/LICENSE-Apache-2.0.txt',
    'licenses/LICENSE-SQLite-blessing.txt',
    'licenses/THIRD-PARTY-NOTICES.md'
)
foreach ($relativePath in $requiredFiles) {
    $path = Join-Path $root $relativePath
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        Fail "Required release file is missing: $relativePath"
    }
}

$ffmpegRoot = Join-Path $root 'runtime/ffmpeg'
$ffmpegManifestPath = Join-Path $ffmpegRoot 'FFMPEG_RUNTIME_MANIFEST.json'
if (-not (Test-Path -LiteralPath $ffmpegManifestPath -PathType Leaf)) {
    Fail 'The controlled FFmpeg runtime manifest is missing.'
}
$ffmpegManifest = Get-Content -LiteralPath $ffmpegManifestPath -Raw | ConvertFrom-Json
if ($ffmpegManifest.runtimeId -ne 'ffmpeg-n8.1.2-22-g94138f6973-20260710-win64-lgpl-shared' -or
    $ffmpegManifest.architecture -ne 'x64') {
    Fail 'The published FFmpeg runtime identity or architecture changed.'
}
$expectedFfmpegFiles = @('FFMPEG_RUNTIME_MANIFEST.json', 'LICENSE.txt') + @(
    $ffmpegManifest.files | ForEach-Object { $_.path })
$actualFfmpegFiles = @(Get-ChildItem -LiteralPath $ffmpegRoot -File | ForEach-Object { $_.Name })
$inventoryDifference = @(Compare-Object $expectedFfmpegFiles $actualFfmpegFiles)
if ($inventoryDifference.Count -gt 0) {
    Fail "The published FFmpeg runtime contains missing or extra files: $($inventoryDifference[0].InputObject)."
}
foreach ($entry in $ffmpegManifest.files) {
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

$nativeBinaries = @((Join-Path $root 'qwen_asr.dll')) + @(
    $ffmpegManifest.files |
        Where-Object { $_.path -match '(?i)\.(dll|exe)$' } |
        ForEach-Object { Join-Path $ffmpegRoot $_.path })
foreach ($nativeBinary in $nativeBinaries) {
    $stdout = Join-Path $env:TEMP ('voxflow-dumpbin-' + [Guid]::NewGuid().ToString('N') + '.txt')
    $stderr = "$stdout.stderr"
    try {
        $process = Start-Process -FilePath $dumpbin.FullName `
            -ArgumentList @('/nologo', '/dependents', $nativeBinary) `
            -RedirectStandardOutput $stdout -RedirectStandardError $stderr `
            -NoNewWindow -Wait -PassThru
        if ($process.ExitCode -ne 0) {
            Fail "dumpbin dependency audit failed with exit code $($process.ExitCode)."
        }
        $dependencyText = Get-Content -LiteralPath $stdout -Raw
        if ($dependencyText -match '(?i)(python[^\s]*|cudart[^\s]*|nvcuda|mlx[^\s]*|libwinpthread[^\s]*|vcruntime[^\s]*|msvcp[^\s]*)\.dll') {
            Fail "Native runtime imports a forbidden external dependency: $([IO.Path]::GetFileName($nativeBinary))."
        }
    }
    finally {
        Remove-Item -LiteralPath $stdout, $stderr -Force -ErrorAction SilentlyContinue
    }
}

Write-Output 'PASS: release layout is self-contained Windows x64, license-complete, and native dependency-audited.'
