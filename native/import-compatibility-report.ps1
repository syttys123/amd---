param(
    [Parameter(Mandatory = $true)]
    [string]$ReportPath,
    [string]$DestinationDirectory = "docs\evidence\compatibility",
    [string]$IndexPath,
    [string]$MarkdownPath = "docs\COMPATIBILITY_REPORTS.md"
)

$ErrorActionPreference = "Stop"

$root = Split-Path -Parent $PSCommandPath
$repositoryRoot = Split-Path -Parent $root
if (-not $IndexPath) {
    $IndexPath = Join-Path $DestinationDirectory "index.json"
}

function Resolve-RepositoryPath {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    $resolved = [System.IO.Path]::GetFullPath(
        $(if ([System.IO.Path]::IsPathRooted($Path)) {
            $Path
        }
        else {
            Join-Path $repositoryRoot $Path
        }))
    $repositoryPrefix = $repositoryRoot.TrimEnd(
        [System.IO.Path]::DirectorySeparatorChar,
        [System.IO.Path]::AltDirectorySeparatorChar) +
        [System.IO.Path]::DirectorySeparatorChar
    if (-not $resolved.StartsWith(
        $repositoryPrefix,
        [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Path must stay inside the repository: $resolved"
    }
    return $resolved
}

function Get-SafeSlug {
    param(
        [AllowNull()]
        [string]$Value,
        [string]$Fallback = "device"
    )

    if ([string]::IsNullOrWhiteSpace($Value)) {
        return $Fallback
    }
    $slug = $Value.ToLowerInvariant() -replace "[^a-z0-9]+", "-"
    $slug = $slug.Trim("-")
    if ([string]::IsNullOrWhiteSpace($slug)) {
        return $Fallback
    }
    if ($slug.Length -gt 72) {
        return $slug.Substring(0, 72).TrimEnd("-")
    }
    return $slug
}

function Format-LimitValue {
    param(
        [AllowNull()]
        [object]$Value
    )

    if ($null -eq $Value) {
        return "--"
    }
    return [string]$Value
}

$resolvedReport = (Resolve-Path -LiteralPath $ReportPath).Path
$destination = Resolve-RepositoryPath $DestinationDirectory
$resolvedIndex = Resolve-RepositoryPath $IndexPath
$resolvedMarkdown = Resolve-RepositoryPath $MarkdownPath

$reportText = Get-Content -LiteralPath $resolvedReport -Raw
$report = $reportText | ConvertFrom-Json
if ($null -eq $report) {
    throw "Compatibility report is empty."
}
if ([int]$report.schemaVersion -ne 1 -or
    [string]$report.reportType -ne "amd-mobile-power-native-compatibility") {
    throw "Unsupported compatibility report schema or type."
}
if ([string]$report.collectionStatus -notin @("PASS", "FAILED")) {
    throw "Unexpected collectionStatus: $($report.collectionStatus)"
}
if ($null -eq $report.privacy) {
    throw "Compatibility report is missing the privacy block."
}
foreach ($property in @(
    "localPathsIncluded",
    "processIdIncluded",
    "accountNamesIncluded",
    "serialNumbersIncluded",
    "recentLogsIncluded",
    "networkUploadPerformed"
)) {
    if ($null -eq $report.privacy.PSObject.Properties[$property] -or
        [bool]$report.privacy.$property) {
        throw "Compatibility report privacy flag is missing or true: $property"
    }
}
if ($null -eq $report.worker -or [bool]$report.worker.writeControlsEnabled) {
    throw "Compatibility report must come from a read-only worker."
}
$profileCatalogCount = $null
if ($null -ne $report.profileCatalog) {
    if ([int]$report.profileCatalog.schemaVersion -ne 1) {
        throw "Compatibility profile catalog has an unsupported schema."
    }
    $catalogProfiles = @($report.profileCatalog.profiles)
    if ($catalogProfiles.Count -lt 10) {
        throw "Compatibility profile catalog is missing generation profiles."
    }
    $catalogIds = @($catalogProfiles | ForEach-Object { [string]$_.id })
    if (@($catalogIds | Select-Object -Unique).Count -ne $catalogIds.Count) {
        throw "Compatibility profile catalog contains duplicate ids."
    }
    $verifiedProfiles = @($catalogProfiles | Where-Object { [bool]$_.isVerified })
    if ($verifiedProfiles.Count -ne 1) {
        throw "Compatibility profile catalog must contain exactly one verified profile."
    }
    foreach ($family in 0..15) {
        $matches = @(
            $catalogProfiles | Where-Object {
                [bool]$_.isFamilyFallback -and
                    @($_.families) -contains $family
            })
        if ($matches.Count -ne 1) {
            throw "Compatibility profile catalog must map RyzenAdj family $family exactly once."
        }
    }
    $profileCatalogCount = $catalogProfiles.Count
}
foreach ($pattern in @(
    '(?i)(?<![A-Za-z0-9])[A-Z]:\\',
    '(?i)(?<![A-Za-z0-9])[A-Z]:/',
    '(?i)\\\\\.\\pipe\\',
    '(?i)\\\\Users\\\\'
)) {
    if ($reportText -match $pattern) {
        throw "Compatibility report contains a local path or pipe name."
    }
}

$collectedAt = [DateTimeOffset]::MinValue
if (-not [DateTimeOffset]::TryParse(
    [string]$report.collectedAt,
    [ref]$collectedAt)) {
    throw "Compatibility report has an invalid collectedAt value."
}

$manufacturer = [string]$report.host.manufacturer
$model = [string]$report.host.model
$systemName = "$manufacturer $model".Trim()
if ([string]::IsNullOrWhiteSpace($systemName)) {
    $systemName = "Unknown system"
}
$stamp = $collectedAt.ToString("yyyyMMdd-HHmmss")
$reportFileName = "$(Get-SafeSlug $systemName)-$stamp.json"
$reportHash = (Get-FileHash -LiteralPath $resolvedReport -Algorithm SHA256).
    Hash.ToLowerInvariant()

$entries = @()
if (Test-Path -LiteralPath $resolvedIndex -PathType Leaf) {
    $indexText = Get-Content -LiteralPath $resolvedIndex -Raw
    if (-not [string]::IsNullOrWhiteSpace($indexText)) {
        $index = $indexText | ConvertFrom-Json
        if ($null -ne $index) {
            $entries = @($index)
        }
    }
}

$existing = $entries | Where-Object {
    $_.reportSha256 -eq $reportHash
} | Select-Object -First 1
if ($null -ne $existing) {
    throw "Compatibility report is already indexed: $($existing.reportFile)"
}

New-Item -ItemType Directory -Path $destination -Force | Out-Null
$destinationFile = Join-Path $destination $reportFileName
if (Test-Path -LiteralPath $destinationFile) {
    throw "Destination report already exists: $destinationFile"
}
Copy-Item -LiteralPath $resolvedReport -Destination $destinationFile

$platform = $report.platform
$telemetry = $report.telemetry
$entry = [pscustomobject][ordered]@{
    reportSha256 = $reportHash
    reportFile = [System.IO.Path]::GetRelativePath(
        $repositoryRoot,
        $destinationFile).Replace("\", "/")
    collectedAt = $collectedAt.ToString("o")
    collectionStatus = [string]$report.collectionStatus
    packageVersion = [string]$report.package.version
    system = $systemName
    cpu = if ($null -ne $platform) {
        [string]$platform.processorName
    }
    else {
        $null
    }
    family = if ($null -ne $platform) {
        "$($platform.ryzenAdjFamily) $($platform.ryzenAdjFamilyName)".Trim()
    }
    else {
        $null
    }
    smuBiosVersion = if ($null -ne $platform) {
        $platform.smuBiosVersion
    }
    else {
        $null
    }
    pmTableVersion = if ($null -ne $platform) {
        $platform.pmTableVersion
    }
    else {
        $null
    }
    profile = if ($null -ne $platform -and $null -ne $platform.profile) {
        [string]$platform.profile.id
    }
    else {
        $null
    }
    profileRange = if ($null -ne $platform -and $null -ne $platform.profile) {
        "$($platform.profile.minimumWatts)-$($platform.profile.maximumWatts) W"
    }
    else {
        $null
    }
    supported = if ($null -ne $platform) {
        [bool]$platform.isSupported
    }
    else {
        $null
    }
    unsupportedReason = if ($null -ne $platform) {
        $platform.unsupportedReason
    }
    else {
        $null
    }
    powerLine = if ($null -ne $telemetry) {
        [string]$telemetry.powerLine
    }
    else {
        $null
    }
    profileCatalogCount = $profileCatalogCount
    stapmWatts = if ($null -ne $telemetry) {
        $telemetry.stapmLimitWatts
    }
    else {
        $null
    }
    fastWatts = if ($null -ne $telemetry) {
        $telemetry.fastLimitWatts
    }
    else {
        $null
    }
    slowWatts = if ($null -ne $telemetry) {
        $telemetry.slowLimitWatts
    }
    else {
        $null
    }
    workerVersion = [string]$report.worker.version
    importedAt = (Get-Date).ToString("o")
}

$entries = @($entries + $entry) | Sort-Object collectedAt -Descending
$indexDirectory = Split-Path -Parent $resolvedIndex
if ($indexDirectory) {
    New-Item -ItemType Directory -Path $indexDirectory -Force | Out-Null
}
$entries |
    ConvertTo-Json -Depth 8 |
    Set-Content -LiteralPath $resolvedIndex -Encoding UTF8

$lines = New-Object System.Collections.Generic.List[string]
$lines.Add("# Compatibility Reports")
$lines.Add("")
$lines.Add("Generated by ``native/import-compatibility-report.ps1``.")
$lines.Add(
    "Only sanitized, read-only reports with false privacy flags are indexed.")
$lines.Add("")
foreach ($item in $entries) {
    $lines.Add("## $($item.system)")
    $lines.Add("")
    $lines.Add("- Collected: $($item.collectedAt)")
    $lines.Add("- Status: ``$($item.collectionStatus)``")
    $lines.Add("- CPU: $($item.cpu)")
    $lines.Add("- Family: $($item.family)")
    $lines.Add(
        "- SMU / PM table: $($item.smuBiosVersion) / $($item.pmTableVersion)")
    $lines.Add(
        "- Profile: $($item.profile) [$($item.profileRange)]")
    if ($null -ne $item.profileCatalogCount) {
        $lines.Add("- Profile catalog: $($item.profileCatalogCount) entries")
    }
    $lines.Add("- Platform supported: $($item.supported)")
    if (-not [string]::IsNullOrWhiteSpace([string]$item.unsupportedReason)) {
        $lines.Add("- Unsupported reason: $($item.unsupportedReason)")
    }
    $lines.Add("- Power line: $($item.powerLine)")
    $lines.Add(
        "- Limits: STAPM $(Format-LimitValue $item.stapmWatts) / " +
        "Fast $(Format-LimitValue $item.fastWatts) / " +
        "Slow $(Format-LimitValue $item.slowWatts) W")
    $lines.Add("- Package: $($item.packageVersion)")
    $lines.Add("- Worker: $($item.workerVersion)")
    $lines.Add("- Evidence: ``$($item.reportFile)``")
    $lines.Add("")
}
$markdownDirectory = Split-Path -Parent $resolvedMarkdown
if ($markdownDirectory) {
    New-Item -ItemType Directory -Path $markdownDirectory -Force | Out-Null
}
$lines | Set-Content -LiteralPath $resolvedMarkdown -Encoding UTF8

[pscustomobject]@{
    Verification = "PASS"
    System = $systemName
    Cpu = $entry.cpu
    Family = $entry.family
    CollectionStatus = $entry.collectionStatus
    PlatformSupported = $entry.supported
    Report = $entry.reportFile
    ReportSHA256 = $reportHash
    Index = [System.IO.Path]::GetRelativePath(
        $repositoryRoot,
        $resolvedIndex).Replace("\", "/")
    Markdown = [System.IO.Path]::GetRelativePath(
        $repositoryRoot,
        $resolvedMarkdown).Replace("\", "/")
} | Format-List
