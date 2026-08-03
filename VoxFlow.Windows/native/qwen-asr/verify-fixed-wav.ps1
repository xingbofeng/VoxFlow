[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string] $ExecutablePath,

    [Parameter(Mandatory = $true)]
    [string] $ModelRoot,

    [Parameter(Mandatory = $true)]
    [string] $WavPath,

    [Parameter(Mandatory = $true)]
    [string] $OutputRoot
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

function Fail {
    param([string] $Message)
    Write-Error $Message
    exit 1
}

function Assert-FileRecord {
    param(
        [Parameter(Mandatory = $true)]
        [string] $Root,

        [Parameter(Mandatory = $true)]
        [object] $Record
    )

    $path = Join-Path $Root $Record.name
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        Fail "Pinned model file is missing: $($Record.name)"
    }

    $file = Get-Item -LiteralPath $path
    if ($file.Length -ne [Int64] $Record.bytes) {
        Fail "Pinned model file has the wrong byte count: $($Record.name)"
    }

    $actualHash = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($actualHash -ne $Record.sha256) {
        Fail "Pinned model file has the wrong SHA-256: $($Record.name)"
    }
}

$executable = (Resolve-Path -LiteralPath $ExecutablePath).Path
$modelPath = (Resolve-Path -LiteralPath $ModelRoot).Path
$wav = (Resolve-Path -LiteralPath $WavPath).Path
$outputPath = [System.IO.Path]::GetFullPath($OutputRoot)

if (-not (Test-Path -LiteralPath $executable -PathType Leaf)) {
    Fail 'ExecutablePath must name the qwen_asr.exe produced by verify-upstream-msvc.ps1.'
}
if (-not (Test-Path -LiteralPath $modelPath -PathType Container)) {
    Fail 'ModelRoot must be an existing directory.'
}
if (-not (Test-Path -LiteralPath $wav -PathType Leaf)) {
    Fail 'WavPath must be an existing file.'
}

$manifestPath = Join-Path $PSScriptRoot 'MODEL_PROVENANCE.json'
$manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
$model = @($manifest.models | Where-Object { $_.id -eq 'qwen3-asr-0.6b' })
if ($model.Count -ne 1) {
    Fail 'MODEL_PROVENANCE.json must contain exactly one qwen3-asr-0.6b record.'
}
foreach ($file in $model[0].files) {
    Assert-FileRecord -Root $modelPath -Record $file
}

$fixedWav = $manifest.runtime.windowsValidation.fixedWav
$wavInfo = Get-Item -LiteralPath $wav
if ($wavInfo.Length -ne [Int64] $fixedWav.bytes) {
    Fail 'The fixed WAV byte count does not match MODEL_PROVENANCE.json.'
}
$wavHash = (Get-FileHash -LiteralPath $wav -Algorithm SHA256).Hash.ToLowerInvariant()
if ($wavHash -ne $fixedWav.sha256) {
    Fail 'The fixed WAV SHA-256 does not match MODEL_PROVENANCE.json.'
}

if (Test-Path -LiteralPath $outputPath) {
    if ($null -ne (Get-ChildItem -LiteralPath $outputPath -Force | Select-Object -First 1)) {
        Fail 'OutputRoot must be empty so stale inference output cannot satisfy the check.'
    }
} else {
    New-Item -ItemType Directory -Path $outputPath | Out-Null
}

$transcriptPath = Join-Path $outputPath 'transcript.txt'
$diagnosticsPath = Join-Path $outputPath 'diagnostics.txt'
$stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
$process = Start-Process -FilePath $executable `
    -ArgumentList @('-d', "`"$modelPath`"", '--stdin', '--stream', '-t', '6') `
    -RedirectStandardInput $wav `
    -RedirectStandardOutput $transcriptPath `
    -RedirectStandardError $diagnosticsPath `
    -NoNewWindow `
    -Wait `
    -PassThru
$stopwatch.Stop()

if ($process.ExitCode -ne 0) {
    Fail "Fixed-WAV inference failed with exit code $($process.ExitCode). See $diagnosticsPath"
}

$strictUtf8 = [System.Text.UTF8Encoding]::new($false, $true)
try {
    $transcript = [System.IO.File]::ReadAllText($transcriptPath, $strictUtf8)
}
catch {
    Fail 'The fixed-WAV transcript is not valid UTF-8.'
}
if ([string]::IsNullOrWhiteSpace($transcript)) {
    Fail 'Fixed-WAV inference returned an empty transcript.'
}

$diagnostics = [System.IO.File]::ReadAllText($diagnosticsPath)
if ($diagnostics -notmatch 'Model loaded\.' -or
    $diagnostics -notmatch 'Inference:\s+\d+\s+ms' -or
    $diagnostics -notmatch 'Audio:\s+[0-9.]+\s+s processed') {
    Fail 'Fixed-WAV inference did not emit the expected model and timing diagnostics.'
}

$transcriptInfo = Get-Item -LiteralPath $transcriptPath
$transcriptHash = (Get-FileHash -LiteralPath $transcriptPath -Algorithm SHA256).Hash.ToLowerInvariant()
Write-Output ('PASS: immutable Qwen 0.6B model and fixed WAV verified; exit=0; transcriptBytes={0}; transcriptSha256={1}; elapsedSeconds={2:N1}' -f `
    $transcriptInfo.Length,
    $transcriptHash,
    $stopwatch.Elapsed.TotalSeconds)
