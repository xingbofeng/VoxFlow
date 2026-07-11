[CmdletBinding()]
param(
    [string]$SolutionPath,
    [string]$DotnetPath = "dotnet"
)

$ErrorActionPreference = "Stop"
$windowsRoot = Split-Path $PSScriptRoot -Parent
if ([string]::IsNullOrWhiteSpace($SolutionPath)) {
    $SolutionPath = Join-Path $windowsRoot "VoxFlow.Windows.sln"
}
$RequiredAuditSource = "https://api.nuget.org/v3/index.json"
$LegacyTestDeprecationAllowlist = @{
    # xUnit.net v2 packages are test-only and require a coordinated runner
    # migration. This exact, expiring exception must not grow implicitly.
    "xunit|2.9.3" = [DateTime]"2026-12-31"
    "xunit.assert|2.9.3" = [DateTime]"2026-12-31"
    "xunit.core|2.9.3" = [DateTime]"2026-12-31"
    "xunit.extensibility.core|2.9.3" = [DateTime]"2026-12-31"
    "xunit.extensibility.execution|2.9.3" = [DateTime]"2026-12-31"
}

function Invoke-Dotnet {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Arguments
    )

    $startInfo = New-Object System.Diagnostics.ProcessStartInfo
    $startInfo.FileName = $DotnetPath
    $startInfo.Arguments = $Arguments
    $startInfo.WorkingDirectory = Split-Path $SolutionPath -Parent
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true

    $process = New-Object System.Diagnostics.Process
    $process.StartInfo = $startInfo
    if (-not $process.Start()) {
        throw "Could not start dotnet."
    }

    $standardOutput = $process.StandardOutput.ReadToEndAsync()
    $standardError = $process.StandardError.ReadToEndAsync()
    $process.WaitForExit()
    $result = [PSCustomObject]@{
        ExitCode = $process.ExitCode
        StandardOutput = $standardOutput.Result
        StandardError = $standardError.Result
    }
    $process.Dispose()
    return $result
}

function Invoke-PackageAudit {
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet("--vulnerable", "--deprecated")]
        [string]$AuditSwitch
    )

    $escapedSolution = $SolutionPath.Replace('"', '\"')
    $result = Invoke-Dotnet -Arguments "list `"$escapedSolution`" package $AuditSwitch --include-transitive --format json --output-version 1 --no-restore"
    if ($result.ExitCode -ne 0) {
        throw "dotnet package audit failed for $AuditSwitch."
    }

    $combinedOutput = $result.StandardOutput + [Environment]::NewLine + $result.StandardError
    if ($combinedOutput -match "(?im)\bNU1900\b|\bNU1905\b") {
        throw "NuGet vulnerability metadata could not be verified for $AuditSwitch."
    }

    $output = $result.StandardOutput
    $jsonStart = $output.IndexOf("{")
    $jsonEnd = $output.LastIndexOf("}")
    if ($jsonStart -lt 0 -or $jsonEnd -lt $jsonStart) {
        throw "dotnet package audit did not return a JSON report for $AuditSwitch."
    }

    $report = $output.Substring($jsonStart, $jsonEnd - $jsonStart + 1) | ConvertFrom-Json
    if ([int]$report.version -ne 1) {
        throw "Unexpected NuGet audit JSON version for $AuditSwitch."
    }
    if (@($report.projects).Count -eq 0) {
        throw "NuGet audit returned no projects for $AuditSwitch."
    }

    $reportedSources = @($report.sources | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })
    if ($reportedSources.Count -eq 0 -or -not ($reportedSources -contains $RequiredAuditSource)) {
        throw "NuGet audit did not confirm the required vulnerability source for $AuditSwitch."
    }

    $expectedParameter = $AuditSwitch.TrimStart("-")
    if ([string]$report.parameters -notmatch "(^|\s)--?$expectedParameter(\s|$)") {
        throw "NuGet audit report parameters do not match $AuditSwitch."
    }

    return $report
}

function Get-ReportedPackages {
    param(
        [Parameter(Mandatory = $true)]
        [object]$Report
    )

    foreach ($project in @($Report.projects)) {
        foreach ($framework in @($project.frameworks)) {
            if ($null -eq $framework) {
                continue
            }

            foreach ($propertyName in @("topLevelPackages", "transitivePackages")) {
                $property = $framework.PSObject.Properties[$propertyName]
                if ($null -eq $property) {
                    continue
                }

                foreach ($package in @($property.Value)) {
                    if ($null -eq $package) {
                        continue
                    }

                    [PSCustomObject]@{
                        ProjectPath = [string]$project.path
                        Id = [string]$package.id
                        Version = [string]$package.resolvedVersion
                        Vulnerabilities = @($package.vulnerabilities)
                        DeprecationReasons = @($package.deprecationReasons)
                    }
                }
            }
        }
    }
}

try {
    if (-not (Test-Path -LiteralPath $SolutionPath -PathType Leaf)) {
        throw "Solution not found: $SolutionPath"
    }

    $vulnerablePackages = @(Get-ReportedPackages -Report (Invoke-PackageAudit -AuditSwitch "--vulnerable") |
        Where-Object { $_.Vulnerabilities.Count -gt 0 })

    if ($vulnerablePackages.Count -gt 0) {
        [Console]::Error.WriteLine("NuGet vulnerability audit found $($vulnerablePackages.Count) blocking package occurrence(s).")
        foreach ($finding in $vulnerablePackages | Sort-Object ProjectPath, Id, Version -Unique) {
            foreach ($vulnerability in $finding.Vulnerabilities) {
                [Console]::Error.WriteLine(("{0} {1}: {2} {3}" -f
                    $finding.Id,
                    $finding.Version,
                    [string]$vulnerability.severity,
                    [string]$vulnerability.advisoryurl))
            }
        }
        exit 1
    }

    $deprecatedPackages = @(Get-ReportedPackages -Report (Invoke-PackageAudit -AuditSwitch "--deprecated") |
        Where-Object { $_.DeprecationReasons.Count -gt 0 })

    # Test-only packages marked solely as Legacy are allowed only when their
    # exact id/version pair is explicitly listed above and has not expired.
    $blockingDeprecations = New-Object System.Collections.Generic.List[object]
    $seenAllowedPairs = New-Object System.Collections.Generic.HashSet[string]
    foreach ($deprecatedPackage in $deprecatedPackages) {
        $normalizedPath = ([string]$deprecatedPackage.ProjectPath).Replace("\", "/")
        $isProductionProject = $normalizedPath -match "/src/"
        $hasNonLegacyReason = @($deprecatedPackage.DeprecationReasons | Where-Object { [string]$_ -ne "Legacy" }).Count -gt 0
        $key = "$(([string]$deprecatedPackage.Id).ToLowerInvariant())|$([string]$deprecatedPackage.Version)"
        $isAllowlisted = $LegacyTestDeprecationAllowlist.ContainsKey($key)
        $allowlistExpired = $isAllowlisted -and [DateTime]::UtcNow.Date -gt $LegacyTestDeprecationAllowlist[$key].Date

        if ($isProductionProject -or $hasNonLegacyReason -or -not $isAllowlisted -or $allowlistExpired) {
            $blockingDeprecations.Add($deprecatedPackage)
            continue
        }

        [void]$seenAllowedPairs.Add($key)
    }

    $staleAllowlistEntries = @($LegacyTestDeprecationAllowlist.Keys | Where-Object { -not $seenAllowedPairs.Contains($_) })
    if ($staleAllowlistEntries.Count -gt 0) {
        throw "NuGet deprecation allowlist has stale entries: $([string]::Join(',', [string[]]$staleAllowlistEntries))"
    }

    if ($blockingDeprecations.Count -gt 0) {
        [Console]::Error.WriteLine("NuGet deprecation audit found $($blockingDeprecations.Count) blocking package occurrence(s).")
        foreach ($finding in $blockingDeprecations | Sort-Object ProjectPath, Id, Version -Unique) {
            [Console]::Error.WriteLine(("{0} {1}: {2}" -f
                $finding.Id,
                $finding.Version,
                ([string]::Join(",", [string[]]$finding.DeprecationReasons))))
        }
        exit 1
    }

    if ($seenAllowedPairs.Count -gt 0) {
        Write-Warning "$($seenAllowedPairs.Count) exact test-only Legacy package/version exception(s) are active through 2026-12-31."
    }

    Write-Output "PASS: no vulnerable, production-deprecated, or non-Legacy test NuGet packages are resolved."
}
catch {
    [Console]::Error.WriteLine($_.Exception.Message)
    [Console]::Error.WriteLine($_.ScriptStackTrace)
    exit 1
}
