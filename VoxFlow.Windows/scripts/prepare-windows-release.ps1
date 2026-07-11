[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidatePattern('^\d+\.\d+\.\d+$')]
    [string] $Version,

    [Parameter(Mandatory = $true)]
    [string] $NativeDllPath,

    [string] $OutputRoot,

    [string] $IsccPath
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
$repositoryRoot = Split-Path -Parent $windowsRoot
$nativeDll = (Resolve-Path -LiteralPath $NativeDllPath).Path
if ([System.IO.Path]::GetFileName($nativeDll) -ne 'qwen_asr.dll') {
    throw 'NativeDllPath must identify the audited qwen_asr.dll.'
}

if ([string]::IsNullOrWhiteSpace($OutputRoot)) {
    $OutputRoot = Join-Path $windowsRoot 'artifacts/release'
}
$artifactRoot = [System.IO.Path]::GetFullPath($OutputRoot)
$stagingRoot = Join-Path $artifactRoot ("staging-$Version-" + [Guid]::NewGuid().ToString('N'))
$publishRoot = Join-Path $stagingRoot 'publish'
$installerOutput = Join-Path $artifactRoot 'installer'
New-Item -ItemType Directory -Path $publishRoot, $installerOutput -Force | Out-Null

$appProject = Join-Path $windowsRoot 'src/VoxFlow.Windows.App/VoxFlow.Windows.App.csproj'
& (Join-Path $windowsRoot 'scripts/stage-ffmpeg-runtime.ps1')
Invoke-Checked 'dotnet.exe' @(
    'publish', $appProject,
    '--configuration', 'Release',
    '-p:Platform=x64',
    '-p:PublishProfile=WindowsX64',
    "-p:Version=$Version",
    '--output', $publishRoot
) 'Self-contained win-x64 publish'

Copy-Item -LiteralPath $nativeDll -Destination (Join-Path $publishRoot 'qwen_asr.dll')
$licenseRoot = Join-Path $publishRoot 'licenses'
New-Item -ItemType Directory -Path $licenseRoot -Force | Out-Null
Copy-Item -LiteralPath (Join-Path $repositoryRoot 'LICENSE') -Destination (Join-Path $licenseRoot 'LICENSE-GPL-3.0-or-later.txt')
Copy-Item -LiteralPath (Join-Path $windowsRoot 'native/qwen-asr/LICENSE.upstream') -Destination (Join-Path $licenseRoot 'LICENSE-qwen-asr-MIT.txt')
Copy-Item -LiteralPath (Join-Path $windowsRoot 'THIRD-PARTY-NOTICES.md') -Destination (Join-Path $licenseRoot 'THIRD-PARTY-NOTICES.md')
Copy-Item -Path (Join-Path $windowsRoot 'installer/licenses/*') -Destination $licenseRoot

& (Join-Path $windowsRoot 'scripts/windows-release-check.ps1') -PublishRoot $publishRoot

if ([string]::IsNullOrWhiteSpace($IsccPath)) {
    $candidates = @(
        (Join-Path ${env:ProgramFiles} 'Inno Setup 7/ISCC.exe'),
        (Join-Path ${env:ProgramFiles(x86)} 'Inno Setup 6/ISCC.exe'),
        (Join-Path ${env:LOCALAPPDATA} 'Programs/Inno Setup 7/ISCC.exe'),
        (Join-Path ${env:LOCALAPPDATA} 'Programs/Inno Setup 6/ISCC.exe')
    )
    $IsccPath = $candidates | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } | Select-Object -First 1
}
if ([string]::IsNullOrWhiteSpace($IsccPath) -or -not (Test-Path -LiteralPath $IsccPath -PathType Leaf)) {
    throw 'Inno Setup ISCC.exe was not found. Install the official compiler or pass -IsccPath.'
}

$installerScript = Join-Path $windowsRoot 'installer/VoxFlow.iss'
Invoke-Checked $IsccPath @(
    "/DPublishDir=$publishRoot",
    "/DOutputDir=$installerOutput",
    "/DAppVersion=$Version",
    $installerScript
) 'Inno Setup compilation'

$installer = Join-Path $installerOutput "VoxFlow-$Version-windows-x64-setup.exe"
if (-not (Test-Path -LiteralPath $installer -PathType Leaf)) {
    throw "Expected installer was not produced: $installer"
}

$portable = Join-Path $artifactRoot "VoxFlow-$Version-windows-x64-portable.zip"
Compress-Archive -Path (Join-Path $publishRoot '*') -DestinationPath $portable -CompressionLevel Optimal -Force
if (-not (Test-Path -LiteralPath $portable -PathType Leaf)) {
    throw "Expected portable package was not produced: $portable"
}

Write-Output "PASS: Windows installer prepared at $installer"
Write-Output "PASS: Windows portable package prepared at $portable"
