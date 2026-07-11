[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string] $OutputPath
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$expectedRevision = 'b00b789b17051aea61e9717458171100662318a4'
$expectedPatchHash = '519fd8434a4e5f9ffd4a067686c552905eca0a5e1387ac2f467ea9007f2965a8'
$windowsRoot = Split-Path -Parent $PSScriptRoot
$bridgeRoot = Join-Path $windowsRoot 'native/qwen-asr-bridge'
$patchPath = Join-Path $windowsRoot 'native/qwen-asr/windows-port/patches/0001-msvc-c11-cleanups.patch'
$output = [System.IO.Path]::GetFullPath($OutputPath)
$temporaryRoot = Join-Path $env:TEMP ('VoxFlow-Qwen-Production-' + [Guid]::NewGuid().ToString('N'))

function Invoke-Checked {
    param([string] $FilePath, [string[]] $Arguments, [string] $Description)
    & $FilePath @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "$Description failed with exit code $LASTEXITCODE."
    }
}

function Find-CMake {
    $command = Get-Command cmake.exe -ErrorAction SilentlyContinue
    if ($null -ne $command) { return $command.Source }
    $standalone = Join-Path $env:ProgramFiles 'CMake/bin/cmake.exe'
    if (Test-Path -LiteralPath $standalone -PathType Leaf) { return $standalone }
    $vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio/Installer/vswhere.exe'
    if (-not (Test-Path -LiteralPath $vswhere -PathType Leaf)) {
        throw 'Visual Studio vswhere.exe is required to locate CMake.'
    }
    $installation = (& $vswhere -latest -products '*' -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath | Select-Object -First 1).Trim()
    $bundled = Join-Path $installation 'Common7/IDE/CommonExtensions/Microsoft/CMake/CMake/bin/cmake.exe'
    if (-not (Test-Path -LiteralPath $bundled -PathType Leaf)) {
        throw 'Visual Studio CMake is not installed.'
    }
    return $bundled
}

New-Item -ItemType Directory -Path $temporaryRoot -Force | Out-Null
try {
    $actualPatchHash = (Get-FileHash -LiteralPath $patchPath -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($actualPatchHash -ne $expectedPatchHash) {
        throw 'The audited Qwen Windows patch hash changed.'
    }

    $checkout = Join-Path $temporaryRoot 'checkout'
    Invoke-Checked 'git.exe' @(
        'clone', '--filter=blob:none', '--no-checkout',
        'https://github.com/antirez/qwen-asr.git', $checkout
    ) 'Pinned Qwen clone'
    Invoke-Checked 'git.exe' @('-C', $checkout, 'fetch', '--depth=1', 'origin', $expectedRevision) 'Pinned Qwen fetch'
    Invoke-Checked 'git.exe' @('-C', $checkout, 'checkout', '--detach', $expectedRevision) 'Pinned Qwen checkout'
    $actualRevision = (& git.exe -C $checkout rev-parse HEAD).Trim()
    if ($actualRevision -ne $expectedRevision -or
        -not [string]::IsNullOrWhiteSpace((& git.exe -C $checkout status --porcelain --untracked-files=no | Out-String))) {
        throw 'The Qwen production source revision is not clean and pinned.'
    }

    $archive = Join-Path $temporaryRoot 'upstream.zip'
    Invoke-Checked 'git.exe' @('-C', $checkout, 'archive', '--format=zip', "--output=$archive", $expectedRevision) 'Pinned Qwen archive'
    $upstream = Join-Path $temporaryRoot 'upstream'
    Expand-Archive -LiteralPath $archive -DestinationPath $upstream
    Push-Location $upstream
    try {
        Invoke-Checked 'git.exe' @('apply', '--check', $patchPath) 'Audited Qwen patch check'
        Invoke-Checked 'git.exe' @('apply', $patchPath) 'Audited Qwen patch application'
    }
    finally {
        Pop-Location
    }

    $cmake = Find-CMake
    $build = Join-Path $temporaryRoot 'build'
    Invoke-Checked $cmake @(
        '-S', $bridgeRoot, '-B', $build, '-A', 'x64',
        '-DVF_QWEN_TEST_BACKEND=OFF',
        "-DVF_QWEN_UPSTREAM_DIR=$upstream"
    ) 'Qwen production bridge configure'
    Invoke-Checked $cmake @('--build', $build, '--config', 'Release', '--target', 'qwen_asr') 'Qwen production bridge build'

    $dll = Join-Path $build 'Release/qwen_asr.dll'
    if (-not (Test-Path -LiteralPath $dll -PathType Leaf)) {
        throw 'The production Qwen bridge DLL was not produced.'
    }
    $bytes = [System.IO.File]::ReadAllBytes($dll)
    $peOffset = [BitConverter]::ToInt32($bytes, 0x3c)
    if ($bytes[0] -ne 0x4d -or $bytes[1] -ne 0x5a -or
        [BitConverter]::ToUInt16($bytes, $peOffset + 4) -ne 0x8664) {
        throw 'The production Qwen bridge is not Windows x64.'
    }
    New-Item -ItemType Directory -Path (Split-Path -Parent $output) -Force | Out-Null
    Copy-Item -LiteralPath $dll -Destination $output -Force
    Write-Output "PASS: built production qwen_asr.dll from pinned revision $expectedRevision at $output"
}
finally {
    Remove-Item -LiteralPath $temporaryRoot -Recurse -Force -ErrorAction SilentlyContinue
}
