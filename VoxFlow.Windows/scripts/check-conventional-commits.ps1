[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string] $BaseRef,

    [string] $HeadRef = "HEAD"
)

$ErrorActionPreference = "Stop"
$conventionalCommitPattern = "^(feat|fix|docs|style|refactor|perf|test|build|ci|chore|revert)(\([a-z0-9][a-z0-9._/-]*\))?(!)?: .+"
$range = "$BaseRef..$HeadRef"

foreach ($ref in @($BaseRef, $HeadRef)) {
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

$processStart = [System.Diagnostics.ProcessStartInfo]::new()
$processStart.FileName = $gitExecutable
$processStart.Arguments = "log --format=`"%H%x09%s`" `"$range`""
$processStart.WorkingDirectory = (Get-Location).ProviderPath
$processStart.UseShellExecute = $false
$processStart.RedirectStandardOutput = $true
$processStart.RedirectStandardError = $true
$processStart.CreateNoWindow = $true
$process = [System.Diagnostics.Process]::new()
$process.StartInfo = $processStart
[void] $process.Start()
$standardOutput = $process.StandardOutput.ReadToEnd()
$standardError = $process.StandardError.ReadToEnd()
$process.WaitForExit()

if ($process.ExitCode -ne 0) {
    throw "Unable to inspect Conventional Commit range $range."
}

$commitLines = @($standardOutput -split "`r?`n" | Where-Object { $_.Length -gt 0 })

$invalidCommits = @()
foreach ($commitLine in $commitLines) {
    $parts = $commitLine -split "`t", 2
    if ($parts.Count -ne 2 -or $parts[1] -notmatch $conventionalCommitPattern) {
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
