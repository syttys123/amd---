param(
    [string]$Solution = "AmdMobilePower.sln",
    [switch]$NoRestore
)

$ErrorActionPreference = "Stop"

$root = Split-Path -Parent $PSCommandPath

function Normalize-ProjectPath {
    param([string]$Path)

    return [IO.Path]::GetFullPath($Path).TrimEnd(
        [IO.Path]::DirectorySeparatorChar,
        [IO.Path]::AltDirectorySeparatorChar)
}

Push-Location $root
try {
    $solutionPath = (Resolve-Path -LiteralPath $Solution).Path
    $arguments = @(
        "list",
        $solutionPath,
        "package",
        "--vulnerable",
        "--include-transitive",
        "--format",
        "json",
        "--output-version",
        "1"
    )
    if ($NoRestore) {
        $arguments += "--no-restore"
    }

    $output = @(& dotnet @arguments)
    $exitCode = $LASTEXITCODE
    if ($exitCode -ne 0) {
        throw "NuGet vulnerability query failed with exit code $exitCode."
    }

    try {
        $report = ($output -join [Environment]::NewLine) |
            ConvertFrom-Json -ErrorAction Stop
    }
    catch {
        throw "NuGet vulnerability query did not return valid JSON: $($_.Exception.Message)"
    }

    if ($report.version -ne 1) {
        throw "Unsupported dependency audit schema version: $($report.version)"
    }

    $expectedProjects = @(
        Get-ChildItem -LiteralPath (Join-Path $root "src") -Filter "*.csproj" -File -Recurse
        Get-ChildItem -LiteralPath (Join-Path $root "tests") -Filter "*.csproj" -File -Recurse
    ) | ForEach-Object { Normalize-ProjectPath $_.FullName }
    if ($expectedProjects.Count -eq 0) {
        throw "Dependency audit found no solution projects."
    }

    $reportedProjects = [Collections.Generic.HashSet[string]]::new(
        [StringComparer]::OrdinalIgnoreCase)
    foreach ($project in @($report.projects)) {
        if ($null -ne $project.path) {
            [void]$reportedProjects.Add((Normalize-ProjectPath $project.path))
        }
    }

    foreach ($project in $expectedProjects) {
        if (-not $reportedProjects.Contains($project)) {
            throw "Dependency audit omitted project: $project"
        }
    }

    $vulnerablePackages = @(
        foreach ($project in @($report.projects)) {
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
                        Severity = $package.severity
                        AdvisoryUrl = $package.advisoryUrl
                    }
                }
            }
        }
    )

    if ($vulnerablePackages.Count -gt 0) {
        $details = $vulnerablePackages | ForEach-Object {
            " - $($_.Id) $($_.Version) severity=$($_.Severity) " +
                "$($_.AdvisoryUrl) ($(Split-Path -Leaf $_.Project), $($_.Framework))"
        }
        throw "Dependency vulnerability audit failed:`n$($details -join "`n")"
    }

    [pscustomobject]@{
        Solution = $solutionPath
        Projects = $expectedProjects.Count
        VulnerablePackages = 0
        Verification = "PASS"
    } | Format-List
}
finally {
    Pop-Location
}
