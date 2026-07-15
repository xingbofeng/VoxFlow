$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$windowsRoot = Split-Path -Parent $PSScriptRoot
. (Join-Path $windowsRoot 'scripts/ProcessHelpers.ps1')
. (Join-Path $windowsRoot 'scripts/QwenRuntimeManifest.ps1')

function Assert-True {
    param(
        [Parameter(Mandatory = $true)]
        [bool] $Condition,

        [Parameter(Mandatory = $true)]
        [string] $Message
    )

    if (-not $Condition) {
        throw $Message
    }
}

function Invoke-CheckedProcess {
    param(
        [Parameter(Mandatory = $true)]
        [string] $FilePath,

        [Parameter(Mandatory = $true)]
        [string[]] $Arguments,

        [Parameter(Mandatory = $true)]
        [string] $FailureMessage
    )

    Invoke-VoxFlowProcess -FilePath $FilePath -Arguments $Arguments `
        -Description $FailureMessage -TimeoutSeconds 900
}

$sourceRoot = Join-Path $windowsRoot 'native/qwen-asr-bridge'
$buildRoot = Join-Path $env:TEMP ('voxflow-qwen-bridge-' + [Guid]::NewGuid().ToString('N'))
$cmakeCommand = Get-Command cmake.exe -ErrorAction SilentlyContinue
$ctestCommand = Get-Command ctest.exe -ErrorAction SilentlyContinue
$cmakeExecutable = if ($null -eq $cmakeCommand) { '' } else { $cmakeCommand.Source }
$ctestExecutable = if ($null -eq $ctestCommand) { '' } else { $ctestCommand.Source }
if ([string]::IsNullOrWhiteSpace($cmakeExecutable) -or [string]::IsNullOrWhiteSpace($ctestExecutable)) {
    $standaloneCmake = Join-Path $env:ProgramFiles 'CMake/bin/cmake.exe'
    $standaloneCtest = Join-Path $env:ProgramFiles 'CMake/bin/ctest.exe'
    if ((Test-Path -LiteralPath $standaloneCmake -PathType Leaf) -and
        (Test-Path -LiteralPath $standaloneCtest -PathType Leaf)) {
        $cmakeExecutable = $standaloneCmake
        $ctestExecutable = $standaloneCtest
    }
}
if ([string]::IsNullOrWhiteSpace($cmakeExecutable) -or [string]::IsNullOrWhiteSpace($ctestExecutable)) {
    $vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio/Installer/vswhere.exe'
    Assert-True (Test-Path -LiteralPath $vswhere -PathType Leaf) 'Visual Studio vswhere.exe is required to locate CMake.'
    $installationPath = (& $vswhere -latest -products '*' -property installationPath | Select-Object -First 1)
    $installationPath = if ($null -eq $installationPath) { '' } else { $installationPath.Trim() }
    Assert-True (-not [string]::IsNullOrWhiteSpace($installationPath)) 'Visual Studio installation could not be located.'
    $cmakePath = Join-Path $installationPath 'Common7/IDE/CommonExtensions/Microsoft/CMake/CMake/bin/cmake.exe'
    $ctestPath = Join-Path $installationPath 'Common7/IDE/CommonExtensions/Microsoft/CMake/CMake/bin/ctest.exe'
    Assert-True (Test-Path -LiteralPath $cmakePath -PathType Leaf) 'Visual Studio CMake was not found.'
    Assert-True (Test-Path -LiteralPath $ctestPath -PathType Leaf) 'Visual Studio CTest was not found.'
    $cmakeExecutable = $cmakePath
    $ctestExecutable = $ctestPath
}

try {
    Invoke-CheckedProcess $cmakeExecutable @('-S', $sourceRoot, '-B', $buildRoot, '-A', 'x64', '-DVF_QWEN_TEST_BACKEND=ON') 'qwen-asr bridge configure failed.'
    Invoke-CheckedProcess $cmakeExecutable @('--build', $buildRoot, '--config', 'Release', '--target', 'vf_qwen_native_contract') 'qwen-asr bridge build failed.'
    Invoke-CheckedProcess $ctestExecutable @('--test-dir', $buildRoot, '-C', 'Release', '--output-on-failure') 'qwen-asr bridge native contract failed.'

    $dll = Join-Path $buildRoot 'Release/qwen_asr.dll'
    Assert-True (Test-Path -LiteralPath $dll -PathType Leaf) 'The native contract build did not produce qwen_asr.dll.'

    $bytes = [System.IO.File]::ReadAllBytes($dll)
    Assert-True ($bytes.Length -gt 0x100) 'The native DLL is unexpectedly small.'
    Assert-True ($bytes[0] -eq 0x4d -and $bytes[1] -eq 0x5a) 'The native output is not a PE image.'
    $peOffset = [BitConverter]::ToInt32($bytes, 0x3c)
    $machine = [BitConverter]::ToUInt16($bytes, $peOffset + 4)
    Assert-True ($machine -eq 0x8664) 'The native bridge is not Windows x64.'

    $testBackendRejected = $false
    try {
        Assert-VoxFlowQwenNativeAbi -Path $dll
    }
    catch {
        $testBackendRejected = $_.Exception.Message -like '*not the production backend*'
    }
    Assert-True $testBackendRejected `
        'The deterministic test backend could masquerade as the production Qwen runtime.'

    Write-Output 'PASS: Qwen C ABI, x64 PE, and production-backend discrimination passed.'
}
finally {
    Remove-Item -LiteralPath $buildRoot -Recurse -Force -ErrorAction SilentlyContinue
}
