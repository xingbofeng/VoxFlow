[CmdletBinding()]
param(
    [string] $CargoRoot,
    [string] $NoticesPath,
    [string] $CargoPath = 'cargo.exe'
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot 'ProcessHelpers.ps1')

function Invoke-Captured {
    param(
        [Parameter(Mandatory = $true)]
        [string] $FilePath,
        [Parameter(Mandatory = $true)]
        [string[]] $Arguments,
        [Parameter(Mandatory = $true)]
        [string] $WorkingDirectory
    )

    return Invoke-VoxFlowProcess -FilePath $FilePath -Arguments $Arguments `
        -WorkingDirectory $WorkingDirectory -Description 'Cargo metadata' `
        -TimeoutSeconds 600 -CaptureOutput
}

$windowsRoot = Split-Path -Parent $PSScriptRoot
$repositoryRoot = Split-Path -Parent $windowsRoot
if ([string]::IsNullOrWhiteSpace($CargoRoot)) {
    $CargoRoot = Join-Path $repositoryRoot 'agent-cli'
}
if ([string]::IsNullOrWhiteSpace($NoticesPath)) {
    $NoticesPath = Join-Path $windowsRoot 'THIRD-PARTY-NOTICES.md'
}
$CargoRoot = [System.IO.Path]::GetFullPath($CargoRoot)
$NoticesPath = [System.IO.Path]::GetFullPath($NoticesPath)
if (-not (Test-Path -LiteralPath (Join-Path $CargoRoot 'Cargo.lock') -PathType Leaf)) {
    throw 'The locked Agent Cargo graph is missing.'
}

$metadata = Invoke-Captured -FilePath $CargoPath -WorkingDirectory $CargoRoot -Arguments @(
    'metadata', '--format-version', '1', '--filter-platform', 'x86_64-pc-windows-msvc',
    '--no-default-features', '--features', 'builtin-agent', '--locked'
) | ConvertFrom-Json
$nodes = @{}
foreach ($node in @($metadata.resolve.nodes)) { $nodes[[string]$node.id] = $node }
$packages = @{}
foreach ($package in @($metadata.packages)) { $packages[[string]$package.id] = $package }

$resolved = @{}
$pending = New-Object System.Collections.Generic.Stack[string]
$pending.Push([string]$metadata.resolve.root)
$visited = @{}
while ($pending.Count -gt 0) {
    $id = $pending.Pop()
    if ($visited.ContainsKey($id)) { continue }
    $visited[$id] = $true
    $package = $packages[$id]
    if ($id -ne [string]$metadata.resolve.root) {
        if ([string]$package.source -notmatch '^registry\+https://github\.com/rust-lang/crates\.io-index$') {
            throw "Agent runtime dependency is not from the reviewed crates.io registry: $($package.name)."
        }
        if ([string]::IsNullOrWhiteSpace([string]$package.license)) {
            throw "Agent runtime dependency has no SPDX license expression: $($package.name)."
        }
        $key = "$(([string]$package.name).ToLowerInvariant())|$([string]$package.version)"
        $resolved[$key] = [PSCustomObject]@{
            Name = [string]$package.name
            Version = [string]$package.version
            License = [string]$package.license
        }
    }
    foreach ($dependency in @($nodes[$id].deps)) {
        $isNormal = @($dependency.dep_kinds | Where-Object { $null -eq $_.kind }).Count -gt 0
        if ($isNormal) { $pending.Push([string]$dependency.pkg) }
    }
}

$notices = Get-Content -LiteralPath $NoticesPath -Raw
$startMarker = '<!-- cargo-runtime-inventory:start -->'
$endMarker = '<!-- cargo-runtime-inventory:end -->'
$start = $notices.IndexOf($startMarker)
$end = $notices.IndexOf($endMarker)
if ($start -lt 0 -or $end -le $start) {
    throw 'THIRD-PARTY-NOTICES.md is missing Cargo runtime inventory markers.'
}
$block = $notices.Substring($start + $startMarker.Length, $end - $start - $startMarker.Length)
$declared = @{}
foreach ($row in [regex]::Matches($block, '(?m)^\|\s*(?<license>[^|]+?)\s*\|\s*(?<crates>[^|]+?)\s*\|\s*$')) {
    $license = $row.Groups['license'].Value.Trim()
    if ($license -eq 'License expression' -or $license -match '^-+$') { continue }
    foreach ($crate in [regex]::Matches($row.Groups['crates'].Value, '`(?<name>[^@`]+)@(?<version>[^`]+)`')) {
        $name = $crate.Groups['name'].Value
        $version = $crate.Groups['version'].Value
        $key = "$($name.ToLowerInvariant())|$version"
        if ($declared.ContainsKey($key)) { throw "Duplicate Cargo inventory row: $name $version" }
        $declared[$key] = [PSCustomObject]@{ Name = $name; Version = $version; License = $license }
    }
}

$problems = New-Object System.Collections.Generic.List[string]
foreach ($key in $resolved.Keys) {
    if (-not $declared.ContainsKey($key)) {
        $problems.Add("Missing Cargo inventory entry: $($resolved[$key].Name) $($resolved[$key].Version)")
    }
    elseif ($declared[$key].License -ne $resolved[$key].License) {
        $problems.Add("Cargo license mismatch: $($resolved[$key].Name) $($resolved[$key].Version)")
    }
}
foreach ($key in $declared.Keys) {
    if (-not $resolved.ContainsKey($key)) {
        $problems.Add("Stale Cargo inventory entry: $($declared[$key].Name) $($declared[$key].Version)")
    }
}
if ($problems.Count -gt 0) {
    $problems | Sort-Object | ForEach-Object { [Console]::Error.WriteLine($_) }
    exit 1
}
if (-not (Test-Path -LiteralPath (Join-Path $windowsRoot 'installer/licenses/LICENSE-Unicode-3.0.txt') -PathType Leaf)) {
    throw 'The Cargo runtime uses Unicode-3.0 but its installer license text is missing.'
}
Write-Output "PASS: $($resolved.Count) locked Agent runtime crates have reviewed SPDX inventory entries."
