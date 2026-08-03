[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string] $OutputPath
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot 'ProcessHelpers.ps1')
. (Join-Path $PSScriptRoot 'QwenRuntimeManifest.ps1')

$expectedRevision = 'b00b789b17051aea61e9717458171100662318a4'
$expectedPatchHash = '519fd8434a4e5f9ffd4a067686c552905eca0a5e1387ac2f467ea9007f2965a8'
$windowsRoot = Split-Path -Parent $PSScriptRoot
$bridgeRoot = Join-Path $windowsRoot 'native/qwen-asr-bridge'
$patchPath = Join-Path $windowsRoot 'native/qwen-asr/windows-port/patches/0001-msvc-c11-cleanups.patch'
$output = [System.IO.Path]::GetFullPath($OutputPath)
$temporaryRoot = Join-Path $env:TEMP ('VoxFlow-Qwen-Production-' + [Guid]::NewGuid().ToString('N'))

function Invoke-Checked {
    param([string] $FilePath, [string[]] $Arguments, [string] $Description)
    Invoke-VoxFlowProcess -FilePath $FilePath -Arguments $Arguments `
        -Description $Description -TimeoutSeconds 3600
}

function Invoke-Captured {
    param([string] $FilePath, [string[]] $Arguments, [string] $Description)
    return Invoke-VoxFlowProcess -FilePath $FilePath -Arguments $Arguments `
        -Description $Description -TimeoutSeconds 600 -CaptureOutput
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
    $installation = (Invoke-Captured $vswhere @(
        '-latest', '-products', '*', '-requires',
        'Microsoft.VisualStudio.Component.VC.Tools.x86.x64',
        '-property', 'installationPath'
    ) 'Visual Studio discovery').Split([Environment]::NewLine)[0].Trim()
    $bundled = Join-Path $installation 'Common7/IDE/CommonExtensions/Microsoft/CMake/CMake/bin/cmake.exe'
    if (-not (Test-Path -LiteralPath $bundled -PathType Leaf)) {
        throw 'Visual Studio CMake is not installed.'
    }
    return $bundled
}

$repositoryState = Get-VoxFlowQwenBridgeRepositoryState
if ($env:GITHUB_SHA -match '^[0-9a-fA-F]{40}$' -and
    $env:GITHUB_SHA.ToLowerInvariant() -ne $repositoryState.Revision) {
    throw 'GITHUB_SHA does not match the Qwen bridge source checkout.'
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
    $actualRevision = Invoke-Captured 'git.exe' @('-C', $checkout, 'rev-parse', 'HEAD') 'Pinned Qwen revision check'
    $workingTreeStatus = Invoke-Captured 'git.exe' @(
        '-C', $checkout, 'status', '--porcelain', '--untracked-files=no'
    ) 'Pinned Qwen worktree check'
    if ($actualRevision -ne $expectedRevision -or
        -not [string]::IsNullOrWhiteSpace($workingTreeStatus)) {
        throw 'The Qwen production source revision is not clean and pinned.'
    }

    $archive = Join-Path $temporaryRoot 'upstream.zip'
    Invoke-Checked 'git.exe' @('-C', $checkout, 'archive', '--format=zip', "--output=$archive", $expectedRevision) 'Pinned Qwen archive'
    $upstream = Join-Path $temporaryRoot 'upstream'
    Expand-Archive -LiteralPath $archive -DestinationPath $upstream
    Invoke-Checked 'git.exe' @('-C', $upstream, 'apply', '--check', $patchPath) 'Audited Qwen patch check'
    Invoke-Checked 'git.exe' @('-C', $upstream, 'apply', $patchPath) 'Audited Qwen patch application'

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
    $manifestOutput = New-VoxFlowQwenRuntimeManifest `
        -BinaryPath $output -ManifestPath "$output.manifest.json" `
        -SourceRevision $repositoryState.Revision -SourceDirty $repositoryState.Dirty
    Write-Output "PASS: built production qwen_asr.dll and audited manifest from pinned revision $expectedRevision at $output"
    if ($repositoryState.Dirty) {
        Write-Output 'PASS: local validation build is marked dirty and cannot enter a release package.'
    }
    Write-Output "PASS: Qwen native runtime manifest written to $manifestOutput"
}
finally {
    Remove-Item -LiteralPath $temporaryRoot -Recurse -Force -ErrorAction SilentlyContinue
}
