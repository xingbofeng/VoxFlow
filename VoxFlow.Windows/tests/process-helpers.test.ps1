[CmdletBinding()]
param(
    [string] $DotnetPath
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$windowsRoot = Split-Path -Parent $PSScriptRoot
. (Join-Path $windowsRoot 'scripts/ProcessHelpers.ps1')

function Assert-True {
    param([bool] $Condition, [string] $Message)
    if (-not $Condition) { throw $Message }
}

$temporaryRoot = Join-Path $env:TEMP ('voxflow-process-helper-' + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $temporaryRoot -Force | Out-Null
try {
    $argumentEcho = Join-Path $temporaryRoot 'argument-echo.ps1'
    @'
[Console]::OutputEncoding = [Text.Encoding]::UTF8
@($args) | ConvertTo-Json -Compress
'@ | Set-Content -LiteralPath $argumentEcho -Encoding UTF8

    $expectedArguments = @(
        'plain',
        'space value',
        'C:\path with space\',
        'quote"inside',
        ''
    )
    $echoOutput = Invoke-VoxFlowProcess -FilePath 'powershell.exe' `
        -Arguments (@('-NoLogo', '-NoProfile', '-NonInteractive', '-File', $argumentEcho) + $expectedArguments) `
        -WorkingDirectory $temporaryRoot -Description 'Process argument round-trip' `
        -TimeoutSeconds 30 -CaptureOutput
    $actualArguments = [string[]](ConvertFrom-Json -InputObject $echoOutput)
    Assert-True ($actualArguments.Count -eq $expectedArguments.Count) `
        "The process helper changed the argument count (expected $($expectedArguments.Count), actual $($actualArguments.Count))."
    for ($index = 0; $index -lt $expectedArguments.Count; $index++) {
        Assert-True ($actualArguments[$index] -ceq $expectedArguments[$index]) `
            "The process helper changed argument $index."
    }

    $sampleOutput = '{"secretKey":"synthetic-json-value","accessToken":"synthetic-access-value"} ' +
        'secretKey: synthetic-yaml-value ' +
        '--secret-key synthetic-cli-value --authorization=synthetic-auth-value ' +
        ('Bearer' + ' synthetic-bearer-value')
    $protectedOutput = Protect-VoxFlowProcessOutput $sampleOutput
    foreach ($sensitiveValue in @(
        'synthetic-json-value',
        'synthetic-access-value',
        'synthetic-yaml-value',
        'synthetic-cli-value',
        'synthetic-auth-value',
        'synthetic-bearer-value')) {
        Assert-True (-not $protectedOutput.Contains($sensitiveValue)) `
            'The process helper did not redact a synthetic credential shape.'
    }

    $timedOut = $false
    try {
        Invoke-VoxFlowProcess -FilePath 'powershell.exe' `
            -Arguments @('-NoLogo', '-NoProfile', '-NonInteractive', '-Command', 'Start-Sleep -Seconds 30') `
            -WorkingDirectory $temporaryRoot -Description 'Bounded process probe' `
            -TimeoutSeconds 1
    }
    catch {
        $timedOut = $_.Exception.Message -like '*timed out*'
    }
    Assert-True $timedOut 'The process helper did not enforce its timeout.'

    $requestedDotnet = if ([string]::IsNullOrWhiteSpace($DotnetPath)) { 'dotnet.exe' } else { $DotnetPath }
    $dotnet = Resolve-VoxFlowDotnetPath $requestedDotnet
    Assert-True (Test-Path -LiteralPath $dotnet -PathType Leaf) `
        'The process helper did not resolve the requested dotnet executable.'
    $programFilesDotnet = @($env:ProgramW6432, $env:ProgramFiles) |
        Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
        ForEach-Object { Join-Path $_ 'dotnet/dotnet.exe' } |
        Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } |
        Select-Object -First 1
    if (-not [string]::IsNullOrWhiteSpace($programFilesDotnet)) {
        $fallbackDotnet = Resolve-VoxFlowDotnetPath 'voxflow-intentionally-missing-dotnet.exe'
        Assert-True ((Resolve-Path -LiteralPath $fallbackDotnet).Path -eq
            (Resolve-Path -LiteralPath $programFilesDotnet).Path) `
            'The process helper did not find dotnet under Program Files.'
    }

    Write-Output 'PASS: process arguments, timeout cleanup, redaction, and dotnet resolution are verified.'
}
finally {
    Remove-Item -LiteralPath $temporaryRoot -Recurse -Force -ErrorAction SilentlyContinue
}
