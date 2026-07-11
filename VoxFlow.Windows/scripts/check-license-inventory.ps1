[CmdletBinding()]
param(
    [string]$SolutionPath,
    [string]$NoticesPath,
    [string]$DotnetPath = "dotnet"
)

$ErrorActionPreference = "Stop"
$windowsRoot = Split-Path $PSScriptRoot -Parent
if ([string]::IsNullOrWhiteSpace($SolutionPath)) {
    $SolutionPath = Join-Path $windowsRoot "VoxFlow.Windows.sln"
}
if ([string]::IsNullOrWhiteSpace($NoticesPath)) {
    $NoticesPath = Join-Path $windowsRoot "THIRD-PARTY-NOTICES.md"
}
$RequiredPackageSource = "https://api.nuget.org/v3/index.json"
$FileLicenseOverrides = @{
    # SourceGear ships the SQLite public-domain blessing as a package file.
    # Pinning its hash makes the normalized SPDX mapping reviewable and fail-closed.
    "sourcegear.sqlite3|3.50.4.5" = [PSCustomObject]@{
        File = "LICENSE.txt"
        Sha256 = "99464c3a88df7b708ce59e462cdcb85f72dfc9b1335b4fcc68be56131b634b95"
        License = "blessing"
    }
}
$LegacyLicenseUrlOverrides = @{
    # This legacy package predates NuGet license expressions. Its exact URL is
    # locked until the xUnit v3 migration removes the dependency.
    "xunit.abstractions|2.0.3" = [PSCustomObject]@{
        Url = "https://raw.githubusercontent.com/xunit/xunit/master/license.txt"
        License = "Apache-2.0"
    }
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

function Invoke-ResolvedPackageReport {
    $escapedSolution = $SolutionPath.Replace('"', '\"')
    $result = Invoke-Dotnet -Arguments "list `"$escapedSolution`" package --include-transitive --format json --output-version 1 --no-restore"
    if ($result.ExitCode -ne 0) {
        throw "dotnet could not enumerate the restored NuGet graph."
    }

    $output = $result.StandardOutput
    $jsonStart = $output.IndexOf("{")
    $jsonEnd = $output.LastIndexOf("}")
    if ($jsonStart -lt 0 -or $jsonEnd -lt $jsonStart) {
        throw "dotnet package list did not return a JSON report."
    }

    $report = $output.Substring($jsonStart, $jsonEnd - $jsonStart + 1) | ConvertFrom-Json
    if ([int]$report.version -ne 1) {
        throw "Unexpected NuGet package-list JSON version."
    }
    if (@($report.projects).Count -eq 0) {
        throw "NuGet package list returned no projects."
    }
    if ([string]$report.parameters -notmatch "(^|\s)--include-transitive(\s|$)") {
        throw "NuGet package-list report omitted the transitive graph."
    }

    return $report
}

function Get-GlobalPackagesFolder {
    if (-not [string]::IsNullOrWhiteSpace($env:NUGET_PACKAGES)) {
        return $env:NUGET_PACKAGES
    }

    $result = Invoke-Dotnet -Arguments "nuget locals global-packages --list --force-english-output"
    if ($result.ExitCode -ne 0) {
        throw "dotnet could not locate the NuGet global-packages folder."
    }

    $match = [regex]::Match($result.StandardOutput, "(?im)^global-packages:\s*(?<path>.+?)\s*$")
    if (-not $match.Success) {
        throw "dotnet returned an unrecognized global-packages location."
    }

    return $match.Groups["path"].Value.Trim()
}

function Get-VerifiedPackageLicense {
    param(
        [Parameter(Mandatory = $true)]
        [object]$Package,
        [Parameter(Mandatory = $true)]
        [string]$GlobalPackagesFolder
    )

    $key = "$(([string]$Package.Id).ToLowerInvariant())|$([string]$Package.Version)"
    $packageIdFolder = ([string]$Package.Id).ToLowerInvariant()
    $packageVersionFolder = ([string]$Package.Version).ToLowerInvariant()
    $packageRoot = Join-Path (Join-Path $GlobalPackagesFolder $packageIdFolder) $packageVersionFolder
    if (-not (Test-Path -LiteralPath $packageRoot -PathType Container)) {
        throw "Restored package folder is missing: $($Package.Id) $($Package.Version)"
    }

    $packageMetadataPath = Join-Path $packageRoot ".nupkg.metadata"
    if (-not (Test-Path -LiteralPath $packageMetadataPath -PathType Leaf)) {
        throw "NuGet restore metadata is missing for $($Package.Id) $($Package.Version)."
    }
    $packageMetadata = Get-Content -LiteralPath $packageMetadataPath -Raw | ConvertFrom-Json
    if (-not [string]::Equals([string]$packageMetadata.source, $RequiredPackageSource, [StringComparison]::OrdinalIgnoreCase) -or
        [string]::IsNullOrWhiteSpace([string]$packageMetadata.contentHash)) {
        throw "Unverified restore source or content hash for $($Package.Id) $($Package.Version)."
    }

    $nuspecFiles = @(Get-ChildItem -LiteralPath $packageRoot -Filter "*.nuspec" -File)
    if ($nuspecFiles.Count -ne 1) {
        throw "Expected exactly one nuspec for $($Package.Id) $($Package.Version)."
    }

    [xml]$nuspec = Get-Content -LiteralPath $nuspecFiles[0].FullName -Raw
    $metadata = $nuspec.SelectSingleNode("/*[local-name()='package']/*[local-name()='metadata']")
    $idNode = $metadata.SelectSingleNode("*[local-name()='id']")
    $versionNode = $metadata.SelectSingleNode("*[local-name()='version']")
    if (-not [string]::Equals($idNode.InnerText.Trim(), [string]$Package.Id, [StringComparison]::OrdinalIgnoreCase) -or
        -not [string]::Equals($versionNode.InnerText.Trim(), [string]$Package.Version, [StringComparison]::OrdinalIgnoreCase)) {
        throw "Nuspec identity mismatch for $($Package.Id) $($Package.Version)."
    }

    $licenseNode = $metadata.SelectSingleNode("*[local-name()='license']")
    if ($null -ne $licenseNode) {
        $licenseType = $licenseNode.Attributes["type"].Value
        $licenseValue = $licenseNode.InnerText.Trim()
        if ($licenseType -eq "expression") {
            if ([string]::IsNullOrWhiteSpace($licenseValue)) {
                throw "Empty NuGet license expression for $($Package.Id) $($Package.Version)."
            }
            return $licenseValue
        }

        if ($licenseType -eq "file") {
            if (-not $FileLicenseOverrides.ContainsKey($key)) {
                throw "Unreviewed package-file license for $($Package.Id) $($Package.Version)."
            }

            $override = $FileLicenseOverrides[$key]
            if (-not [string]::Equals($licenseValue, $override.File, [StringComparison]::OrdinalIgnoreCase)) {
                throw "Package license filename changed for $($Package.Id) $($Package.Version)."
            }

            $licensePath = Join-Path $packageRoot $licenseValue
            if (-not (Test-Path -LiteralPath $licensePath -PathType Leaf)) {
                throw "Package license file is missing for $($Package.Id) $($Package.Version)."
            }
            $actualHash = (Get-FileHash -LiteralPath $licensePath -Algorithm SHA256).Hash.ToLowerInvariant()
            if ($actualHash -ne $override.Sha256) {
                throw "Package license file hash changed for $($Package.Id) $($Package.Version)."
            }
            return $override.License
        }

        throw "Unsupported NuGet license metadata type for $($Package.Id) $($Package.Version)."
    }

    $licenseUrlNode = $metadata.SelectSingleNode("*[local-name()='licenseUrl']")
    if ($null -eq $licenseUrlNode -or -not $LegacyLicenseUrlOverrides.ContainsKey($key)) {
        throw "Package has no reviewable NuGet license metadata: $($Package.Id) $($Package.Version)."
    }

    $legacyOverride = $LegacyLicenseUrlOverrides[$key]
    if (-not [string]::Equals($licenseUrlNode.InnerText.Trim(), $legacyOverride.Url, [StringComparison]::Ordinal)) {
        throw "Legacy package license URL changed for $($Package.Id) $($Package.Version)."
    }
    return $legacyOverride.License
}

function Get-ResolvedPackageInventory {
    param(
        [Parameter(Mandatory = $true)]
        [object]$Report
    )

    $resolved = @{}
    foreach ($project in @($Report.projects)) {
        $normalizedPath = ([string]$project.path).Replace("\", "/")
        $projectScope = if ($normalizedPath -match "/src/") { "Runtime" } else { "Development/test" }

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

                    $id = [string]$package.id
                    $version = [string]$package.resolvedVersion
                    $key = "$($id.ToLowerInvariant())|$version"
                    if (-not $resolved.ContainsKey($key)) {
                        $resolved[$key] = [PSCustomObject]@{
                            Id = $id
                            Version = $version
                            Scope = $projectScope
                        }
                    }
                    elseif ($projectScope -eq "Runtime") {
                        $resolved[$key].Scope = "Runtime"
                    }
                }
            }
        }
    }

    return $resolved
}

function Get-DeclaredPackageInventory {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Notices
    )

    $startMarker = "<!-- nuget-inventory:start -->"
    $endMarker = "<!-- nuget-inventory:end -->"
    $start = $Notices.IndexOf($startMarker)
    $end = $Notices.IndexOf($endMarker)
    if ($start -lt 0 -or $end -le $start) {
        throw "THIRD-PARTY-NOTICES.md is missing NuGet inventory markers."
    }

    $block = $Notices.Substring($start + $startMarker.Length, $end - $start - $startMarker.Length)
    $rows = [regex]::Matches(
        $block,
        "(?m)^\|\s*(?<id>[^|]+?)\s*\|\s*(?<version>[^|]+?)\s*\|\s*(?<license>[^|]+?)\s*\|\s*(?<scope>[^|]+?)\s*\|\s*(?<source>[^|]+?)\s*\|\s*$")

    $declared = @{}
    foreach ($row in $rows) {
        $id = $row.Groups["id"].Value.Trim()
        if ($id -eq "Package" -or $id -match "^-+$") {
            continue
        }

        $version = $row.Groups["version"].Value.Trim()
        $license = $row.Groups["license"].Value.Trim()
        $scope = $row.Groups["scope"].Value.Trim()
        $source = $row.Groups["source"].Value.Trim()
        $key = "$($id.ToLowerInvariant())|$version"

        if ($declared.ContainsKey($key)) {
            throw "Duplicate NuGet inventory row: $id $version"
        }
        if ($license -match "^(UNKNOWN|NOASSERTION|TBD)$") {
            throw "NuGet inventory has an unresolved license: $id $version"
        }
        if ($scope -ne "Runtime" -and $scope -ne "Development/test") {
            throw "NuGet inventory has an invalid scope for $id $version."
        }

        $sourceUri = $null
        if (-not [Uri]::TryCreate($source, [UriKind]::Absolute, [ref]$sourceUri) -or $sourceUri.Scheme -ne "https") {
            throw "NuGet inventory source must be HTTPS for $id $version."
        }

        $declared[$key] = [PSCustomObject]@{
            Id = $id
            Version = $version
            License = $license
            Scope = $scope
            Source = $source
        }
    }

    return $declared
}

try {
    if (-not (Test-Path -LiteralPath $SolutionPath -PathType Leaf)) {
        throw "Solution not found: $SolutionPath"
    }
    if (-not (Test-Path -LiteralPath $NoticesPath -PathType Leaf)) {
        throw "Notices file not found: $NoticesPath"
    }

    $resolved = Get-ResolvedPackageInventory -Report (Invoke-ResolvedPackageReport)
    $declared = Get-DeclaredPackageInventory -Notices (Get-Content -LiteralPath $NoticesPath -Raw)
    $globalPackagesFolder = Get-GlobalPackagesFolder
    if (-not (Test-Path -LiteralPath $globalPackagesFolder -PathType Container)) {
        throw "NuGet global-packages folder does not exist: $globalPackagesFolder"
    }
    $problems = New-Object System.Collections.Generic.List[string]

    foreach ($key in $resolved.Keys) {
        if (-not $declared.ContainsKey($key)) {
            $package = $resolved[$key]
            $problems.Add("Missing inventory row: $($package.Id) $($package.Version)")
            continue
        }

        if ($declared[$key].Scope -ne $resolved[$key].Scope) {
            $problems.Add("Scope mismatch for $($resolved[$key].Id) $($resolved[$key].Version): expected $($resolved[$key].Scope)")
        }

        $verifiedLicense = Get-VerifiedPackageLicense -Package $resolved[$key] -GlobalPackagesFolder $globalPackagesFolder
        if (-not [string]::Equals($declared[$key].License, $verifiedLicense, [StringComparison]::Ordinal)) {
            $problems.Add("License mismatch for $($resolved[$key].Id) $($resolved[$key].Version): expected $verifiedLicense")
        }

        $expectedSource = "https://www.nuget.org/packages/$($resolved[$key].Id)/$($resolved[$key].Version)"
        if (-not [string]::Equals($declared[$key].Source.TrimEnd('/'), $expectedSource, [StringComparison]::OrdinalIgnoreCase)) {
            $problems.Add("Source mismatch for $($resolved[$key].Id) $($resolved[$key].Version): expected $expectedSource")
        }
    }

    foreach ($key in $declared.Keys) {
        if (-not $resolved.ContainsKey($key)) {
            $package = $declared[$key]
            $problems.Add("Stale inventory row: $($package.Id) $($package.Version)")
        }
    }

    if ($problems.Count -gt 0) {
        foreach ($problem in $problems | Sort-Object) {
            [Console]::Error.WriteLine($problem)
        }
        exit 1
    }

    Write-Output "PASS: THIRD-PARTY-NOTICES.md matches package, version, scope, license, and source for all $($resolved.Count) restored NuGet entries."
}
catch {
    [Console]::Error.WriteLine($_.Exception.Message)
    [Console]::Error.WriteLine($_.ScriptStackTrace)
    exit 1
}
