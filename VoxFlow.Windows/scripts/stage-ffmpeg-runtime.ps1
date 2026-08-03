[CmdletBinding()]
param(
    [string] $Destination,
    [string] $ArchivePath
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$windowsRoot = Split-Path -Parent $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($Destination)) {
    $Destination = Join-Path $windowsRoot 'runtime/ffmpeg'
}
$destinationPath = [System.IO.Path]::GetFullPath($Destination)
$manifestPath = Join-Path $windowsRoot 'runtime/ffmpeg/FFMPEG_RUNTIME_MANIFEST.json'
$manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
$stagedLicense = Join-Path $destinationPath $manifest.licenseFile.path
$staged = Test-Path -LiteralPath $stagedLicense -PathType Leaf
if ($staged) {
    $licenseInfo = Get-Item -LiteralPath $stagedLicense
    $licenseHash = (Get-FileHash -LiteralPath $stagedLicense -Algorithm SHA256).Hash.ToLowerInvariant()
    $staged = $licenseInfo.Length -eq [long]$manifest.licenseFile.size -and
        $licenseHash -eq $manifest.licenseFile.sha256
}
foreach ($entry in $manifest.files) {
    $candidate = Join-Path $destinationPath $entry.path
    if (-not (Test-Path -LiteralPath $candidate -PathType Leaf)) {
        $staged = $false
        break
    }
    $info = Get-Item -LiteralPath $candidate
    $hash = (Get-FileHash -LiteralPath $candidate -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($info.Length -ne [long]$entry.size -or $hash -ne $entry.sha256) {
        $staged = $false
        break
    }
}
if ($staged) {
    Write-Output "PASS: verified FFmpeg runtime is already staged at $destinationPath"
    return
}
$temporaryRoot = Join-Path $env:TEMP ('VoxFlow-FFmpeg-' + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $temporaryRoot -Force | Out-Null

try {
    if ([string]::IsNullOrWhiteSpace($ArchivePath)) {
        $ArchivePath = Join-Path $temporaryRoot $manifest.archive.fileName
        Invoke-WebRequest -Uri $manifest.archive.downloadUrl -OutFile $ArchivePath -UseBasicParsing -TimeoutSec 1800
    }
    $resolvedArchive = (Resolve-Path -LiteralPath $ArchivePath).Path
    $archiveInfo = Get-Item -LiteralPath $resolvedArchive
    if ($archiveInfo.Length -ne [long]$manifest.archive.size) {
        throw "FFmpeg archive size mismatch: $($archiveInfo.Length)."
    }
    $archiveHash = (Get-FileHash -LiteralPath $resolvedArchive -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($archiveHash -ne $manifest.archive.sha256) {
        throw "FFmpeg archive SHA-256 mismatch: $archiveHash."
    }

    $expanded = Join-Path $temporaryRoot 'expanded'
    $expandableArchive = Join-Path $temporaryRoot 'ffmpeg-package.zip'
    Copy-Item -LiteralPath $resolvedArchive -Destination $expandableArchive -Force
    Expand-Archive -LiteralPath $expandableArchive -DestinationPath $expanded
    $bin = Join-Path $expanded $manifest.archive.runtimePath
    $license = Join-Path $expanded $manifest.archive.noticePath
    if (-not (Test-Path -LiteralPath $bin -PathType Container) -or
        -not (Test-Path -LiteralPath $license -PathType Leaf)) {
        throw 'The reviewed FFmpeg archive layout changed.'
    }
    $licenseInfo = Get-Item -LiteralPath $license
    $licenseHash = (Get-FileHash -LiteralPath $license -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($licenseInfo.Length -ne [long]$manifest.licenseFile.size -or
        $licenseHash -ne $manifest.licenseFile.sha256) {
        throw 'The FFmpeg license file does not match the reviewed archive.'
    }

    New-Item -ItemType Directory -Path $destinationPath -Force | Out-Null
    foreach ($entry in $manifest.files) {
        $source = Join-Path $bin $entry.path
        if (-not (Test-Path -LiteralPath $source -PathType Leaf)) {
            throw "FFmpeg runtime file is missing from the archive: $($entry.path)."
        }
        $info = Get-Item -LiteralPath $source
        $hash = (Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash.ToLowerInvariant()
        if ($info.Length -ne [long]$entry.size -or $hash -ne $entry.sha256) {
            throw "FFmpeg runtime file verification failed: $($entry.path)."
        }
        Copy-Item -LiteralPath $source -Destination (Join-Path $destinationPath $entry.path) -Force
    }
    Copy-Item -LiteralPath $license -Destination $stagedLicense -Force
    if ((Resolve-Path -LiteralPath $manifestPath).Path -ne (Join-Path $destinationPath 'FFMPEG_RUNTIME_MANIFEST.json')) {
        Copy-Item -LiteralPath $manifestPath -Destination (Join-Path $destinationPath 'FFMPEG_RUNTIME_MANIFEST.json') -Force
    }
    Write-Output "PASS: staged verified FFmpeg runtime $($manifest.runtimeId) at $destinationPath"
}
finally {
    Remove-Item -LiteralPath $temporaryRoot -Recurse -Force -ErrorAction SilentlyContinue
}
