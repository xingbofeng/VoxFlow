[CmdletBinding()]
param(
    [string] $CargoPath = 'cargo.exe',
    [string] $SourceRevision
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
        [string] $WorkingDirectory,
        [Parameter(Mandatory = $true)]
        [string] $Description
    )

    return Invoke-VoxFlowProcess -FilePath $FilePath -Arguments $Arguments `
        -WorkingDirectory $WorkingDirectory -Description $Description `
        -TimeoutSeconds 7200 -CaptureOutput
}

$windowsRoot = Split-Path -Parent $PSScriptRoot
$repositoryRoot = Split-Path -Parent $windowsRoot
$agentRoot = Join-Path $repositoryRoot 'agent-cli'
$runtimeRoot = Join-Path $windowsRoot 'runtime/agent'
$target = 'x86_64-pc-windows-msvc'

$revision = ''
$agentSourceStatus = ''
$useWslGit = $false
$gitMetadata = Join-Path $repositoryRoot '.git'
if (Test-Path -LiteralPath $gitMetadata -PathType Leaf) {
    $gitPointer = Get-Content -LiteralPath $gitMetadata -Raw
    $useWslGit = $gitPointer -match '(?m)^gitdir:\s*/'
}
if (-not $useWslGit) {
    try {
        $gitPath = (Get-Command git.exe -ErrorAction Stop).Source
        $revision = Invoke-Captured -FilePath $gitPath `
            -Arguments @('-C', $repositoryRoot, 'rev-parse', 'HEAD') `
            -WorkingDirectory $repositoryRoot -Description 'Repository revision probe'
        $agentSourceStatus = Invoke-Captured -FilePath $gitPath `
            -Arguments @('-C', $repositoryRoot, 'status', '--porcelain', '--untracked-files=all', '--', 'agent-cli') `
            -WorkingDirectory $repositoryRoot -Description 'Agent source cleanliness probe'
    }
    catch {
        $useWslGit = $true
    }
}
if ($useWslGit) {
    # A worktree created by WSL can contain a /mnt/... gitdir pointer that
    # Windows Git cannot resolve. Query that same checkout through WSL.
    $wsl = (Get-Command wsl.exe -ErrorAction Stop).Source
    $wslRepositoryRoot = Invoke-Captured -FilePath $wsl `
        -Arguments @('--exec', 'wslpath', '-a', $repositoryRoot) `
        -WorkingDirectory $repositoryRoot -Description 'WSL repository path probe'
    $revision = Invoke-Captured -FilePath $wsl `
        -Arguments @('--exec', 'git', '-C', $wslRepositoryRoot, 'rev-parse', 'HEAD') `
        -WorkingDirectory $repositoryRoot -Description 'WSL repository revision probe'
    $agentSourceStatus = Invoke-Captured -FilePath $wsl `
        -Arguments @('--exec', 'git', '-C', $wslRepositoryRoot, 'status', '--porcelain', '--untracked-files=all', '--', 'agent-cli') `
        -WorkingDirectory $repositoryRoot -Description 'WSL Agent source cleanliness probe'
}
if ($revision -notmatch '^[0-9a-f]{40}$') {
    throw 'Could not resolve the source revision for the Agent manifest.'
}
if (-not [string]::IsNullOrWhiteSpace($agentSourceStatus)) {
    throw 'The built-in Agent release source must be clean, including untracked files.'
}
if (-not [string]::IsNullOrWhiteSpace($SourceRevision) -and
    $SourceRevision.ToLowerInvariant() -ne $revision) {
    throw 'The requested Agent source revision does not match the checkout.'
}
if ($env:GITHUB_SHA -match '^[0-9a-fA-F]{40}$' -and
    $env:GITHUB_SHA.ToLowerInvariant() -ne $revision) {
    throw 'GITHUB_SHA does not match the Agent source checkout.'
}

# The final sidecar crate is linked with the static MSVC CRT. This keeps the
# clean Windows 10 install independent of a separately installed VC runtime.
Invoke-Captured -FilePath $CargoPath -WorkingDirectory $agentRoot `
    -Description 'Windows built-in Agent build' -Arguments @(
        'rustc', '--locked', '--release', '--target', $target,
        '--no-default-features', '--features', 'builtin-agent',
        '--bin', 'voxflow-agent', '--', '-C', 'target-feature=+crt-static'
    ) | Out-Null

$source = Join-Path $agentRoot "target/$target/release/voxflow-agent.exe"
if (-not (Test-Path -LiteralPath $source -PathType Leaf)) {
    throw 'Built-in Agent binary was not produced.'
}
New-Item -ItemType Directory -Path $runtimeRoot -Force | Out-Null
$destination = Join-Path $runtimeRoot 'voxflow-agent.exe'
Copy-Item -LiteralPath $source -Destination $destination -Force

$versionOutput = Invoke-Captured -FilePath $destination -Arguments @('--version') `
    -WorkingDirectory $runtimeRoot -Description 'Built-in Agent version probe'
if ($versionOutput -notmatch '^voxflow-agent\s+(?<version>\d+\.\d+\.\d+)$') {
    throw 'Built-in Agent returned an unexpected version string.'
}
$agentVersion = $Matches.version
$cargoVersion = Invoke-Captured -FilePath $CargoPath -Arguments @('--version') `
    -WorkingDirectory $agentRoot -Description 'Cargo version probe'
$file = Get-Item -LiteralPath $destination
$manifest = [ordered]@{
    schemaVersion = 1
    runtimeId = 'voxflow-agent'
    version = $agentVersion
    architecture = 'x64'
    target = $target
    binary = 'voxflow-agent.exe'
    size = [long]$file.Length
    sha256 = (Get-FileHash -LiteralPath $destination -Algorithm SHA256).Hash.ToLowerInvariant()
    license = 'MIT'
    source = [ordered]@{
        repository = 'https://github.com/xingbofeng/VoxFlow'
        path = 'agent-cli'
        revision = $revision
    }
    build = [ordered]@{
        profile = 'release'
        features = @('builtin-agent')
        defaultFeatures = $false
        locked = $true
        binary = 'voxflow-agent'
        crtLinkage = 'static'
        targetFeature = '+crt-static'
        cargo = $cargoVersion
    }
}
$manifest | ConvertTo-Json -Depth 5 | Set-Content `
    -LiteralPath (Join-Path $runtimeRoot 'VOXFLOW_AGENT_RUNTIME_MANIFEST.json') `
    -Encoding UTF8
Write-Output "PASS: staged verified built-in Agent runtime at $runtimeRoot"
