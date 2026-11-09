param(
    [string]$Solution = "AmdMobilePower.sln"
)

$ErrorActionPreference = "Stop"

$root = Split-Path -Parent $PSCommandPath

function Normalize-ProjectPath {
    param([string]$Path)

    return [IO.Path]::GetFullPath($Path).TrimEnd(
        [IO.Path]::DirectorySeparatorChar,
        [IO.Path]::AltDirectorySeparatorChar)
}

function Invoke-NuGetPackageReport {
    param(
        [string]$SolutionPath,
        [string]$Mode
    )

    $arguments = @(
        "list",
        $SolutionPath,
        "package",
        $Mode,
        "--include-transitive",
        "--format",
        "json",
        "--output-version",
        "1"
    )
    $output = @(& dotnet @arguments)
    $exitCode = $LASTEXITCODE
    if ($exitCode -ne 0) {
        throw "NuGet $Mode query failed with exit code $exitCode."
    }

    try {
        $report = ($output -join [Environment]::NewLine) |
            ConvertFrom-Json -ErrorAction Stop
    }
    catch {
        throw "NuGet $Mode query did not return valid JSON: $($_.Exception.Message)"
    }
    if ($report.version -ne 1) {
        throw "Unsupported dependency audit schema version: $($report.version)"
    }
    return $report
}

function Assert-ProjectCoverage {
    param(
        $Report,
        [string[]]$ExpectedProjects,
        [string]$Mode
    )

    $reportedProjects = [Collections.Generic.HashSet[string]]::new(
        [StringComparer]::OrdinalIgnoreCase)
    foreach ($project in @($Report.projects)) {
        if ($null -ne $project.path) {
            [void]$reportedProjects.Add((Normalize-ProjectPath $project.path))
        }
    }

    foreach ($project in $ExpectedProjects) {
        if (-not $reportedProjects.Contains($project)) {
            throw "NuGet $Mode audit omitted project: $project"
        }
    }
}

function Get-ReportPackages {
    param($Report)

    foreach ($project in @($Report.projects)) {
        foreach ($framework in @($project.frameworks)) {
            if ($null -eq $framework) {
                continue
            }

            $packages = @($framework.topLevelPackages) + @($framework.transitivePackages)
            foreach ($package in $packages) {
                if ($null -eq $package) {
                    continue
                }

                [pscustomobject]@{
                    Project = $project.path
                    Framework = $framework.framework
                    Id = $package.id
                    Version = $package.resolvedVersion
                    Package = $package
                }
            }
        }
    }
}

Push-Location $root
try {
    $solutionPath = (Resolve-Path -LiteralPath $Solution).Path
    $expectedProjects = @(
        Get-ChildItem -LiteralPath (Join-Path $root "src") -Filter "*.csproj" -File -Recurse
        Get-ChildItem -LiteralPath (Join-Path $root "tests") -Filter "*.csproj" -File -Recurse
    ) | ForEach-Object { Normalize-ProjectPath $_.FullName }
    if ($expectedProjects.Count -eq 0) {
        throw "Dependency audit found no solution projects."
    }

    $vulnerabilityReport = Invoke-NuGetPackageReport $solutionPath "--vulnerable"
    $deprecationReport = Invoke-NuGetPackageReport $solutionPath "--deprecated"
    Assert-ProjectCoverage $vulnerabilityReport $expectedProjects "--vulnerable"
    Assert-ProjectCoverage $deprecationReport $expectedProjects "--deprecated"

    $vulnerablePackages = @(Get-ReportPackages $vulnerabilityReport)
    if ($vulnerablePackages.Count -gt 0) {
        $details = $vulnerablePackages | ForEach-Object {
            " - $($_.Id) $($_.Version) " +
                "severity=$($_.Package.severity) $($_.Package.advisoryUrl) " +
                "($(Split-Path -Leaf $_.Project), $($_.Framework))"
        }
        throw "Dependency vulnerability audit failed:`n$($details -join "`n")"
    }

    $deprecatedPackages = @(
        Get-ReportPackages $deprecationReport |
            Where-Object { @($_.Package.deprecationReasons).Count -gt 0 }
    )
    if ($deprecatedPackages.Count -gt 0) {
        $details = $deprecatedPackages | ForEach-Object {
            $reasons = @($_.Package.deprecationReasons) -join ", "
            $alternative = $_.Package.alternativePackage
            $alternativeText = if ($null -eq $alternative) {
                "no package alternative"
            }
            else {
                "use $($alternative.id) $($alternative.versionRange)"
            }
            " - $($_.Id) $($_.Version) [$reasons] $alternativeText " +
                "($(Split-Path -Leaf $_.Project), $($_.Framework))"
        }
        throw "Dependency deprecation audit failed:`n$($details -join "`n")"
    }

    [pscustomobject]@{
        Solution = $solutionPath
        Projects = $expectedProjects.Count
        VulnerablePackages = 0
        DeprecatedPackages = 0
        Verification = "PASS"
    } | Format-List
}
finally {
    Pop-Location
}
