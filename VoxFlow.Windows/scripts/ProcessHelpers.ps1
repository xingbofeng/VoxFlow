Set-StrictMode -Version Latest

function ConvertTo-VoxFlowProcessArguments {
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string[]] $Arguments
    )

    $encoded = @($Arguments | ForEach-Object {
        $argument = [string] $_
        if ($argument.Length -gt 0 -and $argument -notmatch '[\s"]') {
            $argument
            return
        }

        $builder = New-Object System.Text.StringBuilder
        [void]$builder.Append('"')
        $backslashes = 0
        foreach ($character in $argument.ToCharArray()) {
            if ($character -eq [char]92) {
                $backslashes++
                continue
            }
            if ($character -eq [char]34) {
                [void]$builder.Append((('\' * (($backslashes * 2) + 1)) -join ''))
                [void]$builder.Append('"')
                $backslashes = 0
                continue
            }
            if ($backslashes -gt 0) {
                [void]$builder.Append((('\' * $backslashes) -join ''))
                $backslashes = 0
            }
            [void]$builder.Append($character)
        }
        if ($backslashes -gt 0) {
            [void]$builder.Append((('\' * ($backslashes * 2)) -join ''))
        }
        [void]$builder.Append('"')
        $builder.ToString()
    })
    return $encoded -join ' '
}

function Stop-VoxFlowProcessTree {
    param(
        [Parameter(Mandatory = $true)]
        [System.Diagnostics.Process] $Process
    )

    if ($Process.HasExited) {
        return
    }

    $taskkillSucceeded = $false
    try {
        & taskkill.exe /PID $Process.Id /T /F 2>$null | Out-Null
        $taskkillSucceeded = $LASTEXITCODE -eq 0
    } catch { }
    if ($taskkillSucceeded) {
        try {
            if ($Process.WaitForExit(5000)) {
                return
            }
        } catch { }
    }

    try {
        $Process.Kill()
        [void]$Process.WaitForExit(5000)
    } catch { }
}

function Protect-VoxFlowProcessOutput {
    param([AllowEmptyString()][string] $Value)

    $credentialName = '(?:api[_-]?key|secret[_-]?(?:id|key)|access[_-]?token|authorization(?:[_-]?token)?|bearer[_-]?token)'
    $protected = $Value `
        -replace 'sk-[A-Za-z0-9._-]{16,}', '[REDACTED]' `
        -replace 'AKID[A-Za-z0-9]{16,}', '[REDACTED]' `
        -replace '(?i)(Bearer\s+)[A-Za-z0-9._-]{8,}', '$1[REDACTED]'
    $protected = $protected -replace `
        "(?i)((?:`"?$credentialName`"?)\s*[:=]\s*)(?:`"[^`"]*`"|'[^']*'|[^\s,;}\]]+)", `
        '$1[REDACTED]'
    $protected = $protected -replace `
        "(?i)((?:--?)$credentialName(?:=|\s+))(?:`"[^`"]*`"|'[^']*'|[^\s]+)", `
        '$1[REDACTED]'
    return $protected
}

function Invoke-VoxFlowProcess {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string] $FilePath,

        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string[]] $Arguments,

        [Parameter(Mandatory = $true)]
        [string] $Description,

        [string] $WorkingDirectory,

        [ValidateRange(1, 86400)]
        [int] $TimeoutSeconds = 3600,

        [switch] $CaptureOutput
    )

    $startInfo = New-Object System.Diagnostics.ProcessStartInfo
    $startInfo.FileName = $FilePath
    $startInfo.Arguments = ConvertTo-VoxFlowProcessArguments $Arguments
    if (-not [string]::IsNullOrWhiteSpace($WorkingDirectory)) {
        $startInfo.WorkingDirectory = $WorkingDirectory
    }
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
            throw "$Description could not start."
        }

        $outputTask = $process.StandardOutput.ReadToEndAsync()
        $errorTask = $process.StandardError.ReadToEndAsync()
        if (-not $process.WaitForExit($TimeoutSeconds * 1000)) {
            Stop-VoxFlowProcessTree $process
            throw "$Description timed out after $TimeoutSeconds seconds."
        }
        $process.WaitForExit()

        $output = $outputTask.GetAwaiter().GetResult()
        $errorOutput = $errorTask.GetAwaiter().GetResult()
        if ($process.ExitCode -ne 0) {
            $diagnostic = Protect-VoxFlowProcessOutput ($output + [Environment]::NewLine + $errorOutput)
            if ($diagnostic.Length -gt 12000) {
                $diagnostic = $diagnostic.Substring($diagnostic.Length - 12000)
            }
            if (-not [string]::IsNullOrWhiteSpace($diagnostic)) {
                Write-Host $diagnostic.TrimEnd()
            }
            throw "$Description failed with exit code $($process.ExitCode)."
        }

        if ($CaptureOutput) {
            return $output.Trim()
        }

        if (-not [string]::IsNullOrWhiteSpace($output)) {
            Write-Host (Protect-VoxFlowProcessOutput $output.TrimEnd())
        }
        if (-not [string]::IsNullOrWhiteSpace($errorOutput)) {
            Write-Host (Protect-VoxFlowProcessOutput $errorOutput.TrimEnd())
        }
    }
    finally {
        if ($started -and -not $process.HasExited) {
            Stop-VoxFlowProcessTree $process
        }
        $process.Dispose()
    }
}

function Resolve-VoxFlowDotnetPath {
    [CmdletBinding()]
    param(
        [string] $RequestedPath = 'dotnet.exe'
    )

    if (-not [string]::IsNullOrWhiteSpace($RequestedPath)) {
        if (Test-Path -LiteralPath $RequestedPath -PathType Leaf) {
            return (Resolve-Path -LiteralPath $RequestedPath).Path
        }

        $command = Get-Command $RequestedPath -CommandType Application -ErrorAction SilentlyContinue
        if ($null -ne $command) {
            return $command.Source
        }
    }

    $programFilesRoots = @(
        $env:ProgramW6432,
        $env:ProgramFiles
    ) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Unique
    foreach ($root in $programFilesRoots) {
        $candidate = Join-Path $root 'dotnet/dotnet.exe'
        if (Test-Path -LiteralPath $candidate -PathType Leaf) {
            return (Resolve-Path -LiteralPath $candidate).Path
        }
    }

    throw 'The .NET SDK executable was not found on PATH or under Program Files\dotnet.'
}
