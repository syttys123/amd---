param(
    [Parameter(Mandatory = $true)]
    [string]$Version,
    [string]$OutputDirectory
)

$ErrorActionPreference = "Stop"

$root = Split-Path -Parent $PSCommandPath
$repositoryRoot = Split-Path -Parent $root
$artifactsRoot = [System.IO.Path]::GetFullPath(
    (Join-Path $repositoryRoot "artifacts"))
if (-not $OutputDirectory) {
    $OutputDirectory = Join-Path `
        $artifactsRoot `
        "native-release-review\v$Version"
}
$resolvedOutput = [System.IO.Path]::GetFullPath($OutputDirectory)
if (-not $resolvedOutput.StartsWith(
    $artifactsRoot + [System.IO.Path]::DirectorySeparatorChar,
    [System.StringComparison]::OrdinalIgnoreCase)) {
    throw "Review output must stay under artifacts: $resolvedOutput"
}

$statusText = (& git `
    -C $repositoryRoot `
    status `
    --porcelain `
    --ignore-submodules=dirty |
    Where-Object { $_ -notmatch "^.. docs/evidence/" } |
    Out-String).Trim()
if ($statusText) {
    throw "Native review bundle requires a clean tracked worktree."
}

$packageName = "amd-mobile-power-v$Version-win-x64-native-preview.zip"
$packagePath = Join-Path `
    (Join-Path $artifactsRoot "native-packages") `
    $packageName
$packageHashPath = "$packagePath.sha256"
$releaseGatePath = Join-Path `
    $repositoryRoot `
    "docs\evidence\packaging\v$Version-release-gate-$(Get-Date -Format 'yyyy-MM-dd').json"
$cleanEvidencePath = Join-Path `
    $repositoryRoot `
    "docs\evidence\packaging\v$Version-clean-$(Get-Date -Format 'yyyy-MM-dd').json"
$shellEvidencePath = Join-Path `
    $repositoryRoot `
    "docs\evidence\packaging\v$Version-shell-integration-$(Get-Date -Format 'yyyy-MM-dd').json"
$policyEvidencePath = Join-Path `
    $repositoryRoot `
    "docs\evidence\hardware\v$Version-power-policy-no-change-$(Get-Date -Format 'yyyy-MM-dd').json"

foreach ($path in @(
    $packagePath,
    $packageHashPath,
    $releaseGatePath,
    $cleanEvidencePath,
    $shellEvidencePath,
    $policyEvidencePath
)) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "Native review input is missing: $path"
    }
}

$releaseGate = Get-Content -LiteralPath $releaseGatePath -Raw | ConvertFrom-Json
$cleanEvidence = Get-Content -LiteralPath $cleanEvidencePath -Raw | ConvertFrom-Json
$packageHash = (Get-FileHash -LiteralPath $packagePath -Algorithm SHA256).Hash.ToLowerInvariant()
if ($releaseGate.SHA256 -ne $packageHash -or
    $cleanEvidence.SHA256 -ne $packageHash -or
    $releaseGate.Version -ne $Version) {
    throw "Native review package or evidence hash/version does not match."
}

if (Test-Path -LiteralPath $resolvedOutput) {
    Remove-Item -LiteralPath $resolvedOutput -Recurse -Force
}
New-Item -ItemType Directory -Path $resolvedOutput -Force | Out-Null

$copies = @(
    @{ Source = $packagePath; Destination = $packageName },
    @{ Source = $packageHashPath; Destination = "$packageName.sha256" },
    @{ Source = $releaseGatePath; Destination = "release-gate.json" },
    @{ Source = $cleanEvidencePath; Destination = "clean-package.json" },
    @{ Source = $shellEvidencePath; Destination = "shell-integration.json" },
    @{ Source = $policyEvidencePath; Destination = "power-policy-no-change.json" },
    @{ Source = (Join-Path $repositoryRoot "README.md"); Destination = "README.md" },
    @{ Source = (Join-Path $repositoryRoot "LICENSE"); Destination = "LICENSE" },
    @{ Source = (Join-Path $repositoryRoot "docs\THIRD_PARTY_NOTICES.md"); Destination = "THIRD_PARTY_NOTICES.md" },
    @{ Source = (Join-Path $repositoryRoot "docs\PACKAGING.md"); Destination = "PACKAGING.md" },
    @{ Source = (Join-Path $repositoryRoot "docs\BUILDING.md"); Destination = "BUILDING.md" },
    @{ Source = (Join-Path $repositoryRoot "docs\NATIVE_RC_STATUS.md"); Destination = "NATIVE_RC_STATUS.md" }
)
foreach ($copy in $copies) {
    Copy-Item `
        -LiteralPath $copy.Source `
        -Destination (Join-Path $resolvedOutput $copy.Destination) `
        -Force
}

$files = Get-ChildItem -LiteralPath $resolvedOutput -File |
    Sort-Object Name |
    ForEach-Object {
        [ordered]@{
            Name = $_.Name
            Size = $_.Length
            SHA256 = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
        }
    }
$manifest = [ordered]@{
    Status = "REVIEW_ONLY"
    Version = $Version
    SourceCommit = $releaseGate.SourceCommit
    PackageSHA256 = $packageHash
    PackageSize = (Get-Item -LiteralPath $packagePath).Length
    Files = $files
    RecordedAt = (Get-Date).ToString("o")
}
$manifest |
    ConvertTo-Json -Depth 8 |
    Set-Content -LiteralPath (Join-Path $resolvedOutput "MANIFEST.json") -Encoding UTF8

$checksumLines = Get-ChildItem -LiteralPath $resolvedOutput -File |
    Where-Object Name -ne "SHA256SUMS.txt" |
    Sort-Object Name |
    ForEach-Object {
        $hash = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
        "$hash  $($_.Name)"
    }
$checksumLines |
    Set-Content -LiteralPath (Join-Path $resolvedOutput "SHA256SUMS.txt") -Encoding ascii

[pscustomobject]@{
    Status = "REVIEW_ONLY"
    Version = $Version
    SourceCommit = $releaseGate.SourceCommit
    PackageSHA256 = $packageHash
    OutputDirectory = $resolvedOutput
    Files = $files.Count + 2
} | Format-List
