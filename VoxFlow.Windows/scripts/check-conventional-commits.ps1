[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string] $BaseRef,

    [string] $HeadRef = "HEAD",

    [string] $FallbackBaseRef = ""
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot 'ProcessHelpers.ps1')
$conventionalCommitPattern = "^(feat|fix|docs|style|refactor|perf|test|build|ci|chore|revert)(\([a-z0-9][a-z0-9._/-]*\))?(!)?: .+"
$range = "$BaseRef..$HeadRef"

foreach ($ref in @($BaseRef, $HeadRef, $FallbackBaseRef) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }) {
    if ($ref -notmatch "^[0-9A-Za-z._/^-]+$") {
        throw "Git refs contain unsupported characters."
    }
}

$gitCommand = Get-Command git.exe -ErrorAction SilentlyContinue
if ($null -eq $gitCommand) {
    $fallbackGit = Join-Path $env:ProgramFiles "Git\cmd\git.exe"
    if (-not (Test-Path $fallbackGit)) {
        throw "Git is required for the Conventional Commit check."
    }
    $gitExecutable = $fallbackGit
}
else {
    $gitExecutable = $gitCommand.Source
}

function Invoke-GitLog {
    param([string] $CommitRange)

    $startInfo = New-Object System.Diagnostics.ProcessStartInfo
    $startInfo.FileName = $gitExecutable
    $startInfo.Arguments = ConvertTo-VoxFlowProcessArguments @(
        'log', '--format=%H%x09%s', $CommitRange)
    $startInfo.WorkingDirectory = (Get-Location).ProviderPath
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    $process = New-Object System.Diagnostics.Process
    $process.StartInfo = $startInfo
    $started = $false
    try {
        $started = $process.Start()
        if (-not $started) {
            throw 'Git could not start for the Conventional Commit check.'
        }
        $standardOutput = $process.StandardOutput.ReadToEndAsync()
        $standardError = $process.StandardError.ReadToEndAsync()
        if (-not $process.WaitForExit(120000)) {
            Stop-VoxFlowProcessTree $process
            throw 'Git log timed out after 120 seconds.'
        }
        $process.WaitForExit()
        return [PSCustomObject]@{
            ExitCode = $process.ExitCode
            StandardOutput = $standardOutput.GetAwaiter().GetResult()
            StandardError = Protect-VoxFlowProcessOutput $standardError.GetAwaiter().GetResult()
        }
    }
    finally {
        if ($started -and -not $process.HasExited) {
            Stop-VoxFlowProcessTree $process
        }
        $process.Dispose()
    }
}

$result = Invoke-GitLog -CommitRange $range
if ($result.ExitCode -ne 0 -and -not [string]::IsNullOrWhiteSpace($FallbackBaseRef)) {
    $fallbackRange = "$FallbackBaseRef..$HeadRef"
    $fallbackResult = Invoke-GitLog -CommitRange $fallbackRange
    if ($fallbackResult.ExitCode -eq 0) {
        Write-Warning "The push base $BaseRef is unavailable locally; validating the branch range $fallbackRange instead."
        $range = $fallbackRange
        $result = $fallbackResult
    }
}

if ($result.ExitCode -ne 0) {
    $details = $result.StandardError.Trim()
    if ([string]::IsNullOrWhiteSpace($details)) {
        throw "Unable to inspect Conventional Commit range $range."
    }

    throw "Unable to inspect Conventional Commit range ${range}: $details"
}

$commitLines = @($result.StandardOutput -split "`r?`n" | Where-Object { $_.Length -gt 0 })

$invalidCommits = @()
foreach ($commitLine in $commitLines) {
    $parts = $commitLine -split "`t", 2
    if ($parts.Count -ne 2) {
        $invalidCommits += $parts[0]
        continue
    }
    # Strip BOM / zero-width prefixes that editors or encodings may inject.
    $subject = $parts[1].Trim()
    $subject = $subject -replace "^[\uFEFF\u200B\u200C\u200D\u2060]+", ""
    # If a UTF-8 BOM was mis-decoded, drop leading junk until a known type token.
    if ($subject -notmatch $conventionalCommitPattern -and
        $subject -match '(feat|fix|docs|style|refactor|perf|test|build|ci|chore|revert)(\(|:)') {
        $subject = $subject.Substring($subject.IndexOf($Matches[1]))
    }
    if ($subject -notmatch $conventionalCommitPattern) {
        $invalidCommits += $parts[0]
    }
}

if ($invalidCommits.Count -gt 0) {
    foreach ($commitHash in $invalidCommits) {
        [Console]::Error.WriteLine("Non-conventional commit subject detected at $commitHash.")
    }
    exit 1
}

Write-Output "PASS: all inspected commit subjects follow the Conventional Commit format."
