[CmdletBinding()]
param(
    [string]$TestProject = "VoxFlow.Windows/tests/VoxFlow.Windows.App.Tests/VoxFlow.Windows.App.Tests.csproj",
    [string]$DotnetPath = "dotnet.exe"
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot 'ProcessHelpers.ps1')

$repositoryRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
if (-not [System.IO.Path]::IsPathRooted($TestProject)) {
    $TestProject = Join-Path $repositoryRoot $TestProject
}
$resolvedDotnet = Resolve-VoxFlowDotnetPath $DotnetPath
Invoke-VoxFlowProcess -FilePath $resolvedDotnet -TimeoutSeconds 1800 `
    -Description 'Localization resource parity tests' -Arguments @(
        'test', $TestProject,
        '--filter', 'FullyQualifiedName~LocalizationResourceParityTests'
    )
