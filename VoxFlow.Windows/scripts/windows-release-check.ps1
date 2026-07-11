[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string] $PublishRoot,

    [switch] $SkipManagedTests
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

function Invoke-Checked {
    param(
        [string] $FilePath,
        [string[]] $Arguments,
        [string] $Description
    )

    $process = Start-Process -FilePath $FilePath -ArgumentList $Arguments -NoNewWindow -Wait -PassThru
    if ($process.ExitCode -ne 0) {
        throw "$Description failed with exit code $($process.ExitCode)."
    }
}

$windowsRoot = Split-Path -Parent $PSScriptRoot
$solution = Join-Path $windowsRoot 'VoxFlow.Windows.sln'
$publishPath = (Resolve-Path -LiteralPath $PublishRoot).Path
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
Invoke-Checked 'powershell.exe' @('-NoLogo', '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', (Join-Path $windowsRoot 'tests/qwen-native-bridge.test.ps1')) 'Qwen native ABI contract'

if (-not $SkipManagedTests) {
    Invoke-Checked 'dotnet.exe' @('test', $solution, '--configuration', 'Release', '-p:Platform=x64', '--no-restore') 'Release offline tests'
    Invoke-Checked 'dotnet.exe' @('build', $solution, '--configuration', 'Release', '-p:Platform=x64', '--no-restore') 'Release x64 build'
}

& (Join-Path $windowsRoot 'scripts/check-release-layout.ps1') -PublishRoot $publishPath
Write-Output 'PASS: Windows release gates completed.'
