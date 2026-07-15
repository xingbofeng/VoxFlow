[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string] $PublishRoot,

    [switch] $SkipManagedTests,

    [string] $DotnetPath = 'dotnet.exe'
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot 'ProcessHelpers.ps1')

function Invoke-Checked {
    param(
        [string] $FilePath,
        [string[]] $Arguments,
        [string] $Description
    )

    Invoke-VoxFlowProcess -FilePath $FilePath -Arguments $Arguments `
        -Description $Description -TimeoutSeconds 3600
}

$windowsRoot = Split-Path -Parent $PSScriptRoot
$solution = Join-Path $windowsRoot 'VoxFlow.Windows.sln'
$publishPath = (Resolve-Path -LiteralPath $PublishRoot).Path
$resolvedDotnet = Resolve-VoxFlowDotnetPath $DotnetPath
$gitBash = Join-Path $env:ProgramFiles 'Git/bin/bash.exe'
if (-not (Test-Path -LiteralPath $gitBash -PathType Leaf)) {
    throw 'Git for Windows bash.exe is required for release governance checks.'
}

function Convert-ToGitBashPath {
    param([string] $WindowsPath)

    $fullPath = [System.IO.Path]::GetFullPath($WindowsPath)
    $drive = $fullPath.Substring(0, 1).ToLowerInvariant()
    return "/$drive/" + $fullPath.Substring(3).Replace('\', '/')
}

Invoke-Checked $gitBash @((Convert-ToGitBashPath (Join-Path $windowsRoot 'scripts/check-no-secrets.sh'))) 'Source secret scan'
Invoke-Checked $gitBash @(
    (Convert-ToGitBashPath (Join-Path $windowsRoot 'scripts/check-no-secrets.sh')),
    (Convert-ToGitBashPath $publishPath)
) 'Publish secret scan'
Invoke-Checked $gitBash @((Convert-ToGitBashPath (Join-Path $windowsRoot 'tests/packaging-contract.test.sh'))) 'Packaging source contract'
Invoke-Checked 'powershell.exe' @(
    '-NoLogo', '-NoProfile', '-ExecutionPolicy', 'Bypass',
    '-File', (Join-Path $windowsRoot 'tests/process-helpers.test.ps1'),
    '-DotnetPath', $resolvedDotnet
) 'Bounded process helper contract'
Invoke-Checked 'powershell.exe' @('-NoLogo', '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', (Join-Path $windowsRoot 'tests/qwen-native-bridge.test.ps1')) 'Qwen native ABI contract'
Invoke-Checked 'powershell.exe' @(
    '-NoLogo', '-NoProfile', '-ExecutionPolicy', 'Bypass',
    '-File', (Join-Path $windowsRoot 'scripts/check-localization.ps1'),
    '-DotnetPath', $resolvedDotnet
) 'Localization resource parity'
Invoke-Checked 'powershell.exe' @(
    '-NoLogo', '-NoProfile', '-ExecutionPolicy', 'Bypass',
    '-File', (Join-Path $windowsRoot 'scripts/check-license-inventory.ps1'),
    '-SolutionPath', $solution,
    '-NoticesPath', (Join-Path $windowsRoot 'THIRD-PARTY-NOTICES.md'),
    '-DotnetPath', $resolvedDotnet
) 'Resolved NuGet license inventory'
Invoke-Checked 'powershell.exe' @(
    '-NoLogo', '-NoProfile', '-ExecutionPolicy', 'Bypass',
    '-File', (Join-Path $windowsRoot 'scripts/check-cargo-license-inventory.ps1'),
    '-NoticesPath', (Join-Path $windowsRoot 'THIRD-PARTY-NOTICES.md')
) 'Locked Agent Cargo license inventory'

if (-not $SkipManagedTests) {
    Invoke-Checked $resolvedDotnet @('test', $solution, '--configuration', 'Release', '-p:Platform=x64', '--no-restore') 'Release offline tests'
    Invoke-Checked $resolvedDotnet @('build', $solution, '--configuration', 'Release', '-p:Platform=x64', '--no-restore') 'Release x64 build'
}

& (Join-Path $windowsRoot 'scripts/check-release-layout.ps1') -PublishRoot $publishPath
Write-Output 'PASS: Windows release gates completed.'
