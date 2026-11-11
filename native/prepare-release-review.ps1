param(
    [Parameter(Mandatory = $true)]
    [string]$Version,
    [string]$OutputDirectory,
    [switch]$IncludeMedia,
    [string]$VideoPath = "artifacts\media\amd-mobile-power-native-promo-draft-2026-11-11\amd-mobile-power-native-intro-draft-2026-11-11.mp4",
    [string]$MediaEvidencePath = "docs\evidence\media\native-promo-draft-2026-11-11.json",
    [string]$BilibiliCoverPath = "docs\assets\bilibili-cover-native-2026-11-11.png",
    [string]$ContactSheetPath = "docs\assets\native-promo-draft-contact-sheet-2026-11-11.png",
    [string]$LaunchCopyPath = "docs\NATIVE_LAUNCH_COPY_ZH.md"
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
    $shellEvidencePath
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

# The aggregate gate records whether the controlled no-change hardware write
# ran. A candidate that skipped it must not claim a hardware write artifact.
$includePolicyEvidence = $releaseGate.NoChangePolicy -eq "PASS"
if ($includePolicyEvidence -and
    -not (Test-Path -LiteralPath $policyEvidencePath -PathType Leaf)) {
    throw ("Release gate recorded NoChangePolicy=PASS but the hardware " +
        "evidence file is missing: $policyEvidencePath")
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
    @{ Source = (Join-Path $repositoryRoot "README.md"); Destination = "README.md" },
    @{ Source = (Join-Path $repositoryRoot "LICENSE"); Destination = "LICENSE" },
    @{ Source = (Join-Path $repositoryRoot "docs\THIRD_PARTY_NOTICES.md"); Destination = "THIRD_PARTY_NOTICES.md" },
    @{ Source = (Join-Path $repositoryRoot "docs\PACKAGING.md"); Destination = "PACKAGING.md" },
    @{ Source = (Join-Path $repositoryRoot "docs\BUILDING.md"); Destination = "BUILDING.md" },
    @{ Source = (Join-Path $repositoryRoot "docs\NATIVE_RC_STATUS.md"); Destination = "NATIVE_RC_STATUS.md" }
)
if ($includePolicyEvidence) {
    $copies += @{
        Source = $policyEvidencePath
        Destination = "power-policy-no-change.json"
    }
}
if ($IncludeMedia) {
    $mediaInputs = @(
        @{ Source = $VideoPath; Destination = "amd-mobile-power-native-intro-draft.mp4" },
        @{ Source = $MediaEvidencePath; Destination = "media-evidence.json" },
        @{ Source = $BilibiliCoverPath; Destination = "bilibili-cover.png" },
        @{ Source = $ContactSheetPath; Destination = "native-promo-contact-sheet.png" },
        @{ Source = $LaunchCopyPath; Destination = "NATIVE_LAUNCH_COPY_ZH.md" },
        @{
            Source = (Join-Path $repositoryRoot "docs\NATIVE_RELEASE_CANDIDATE_ZH.md")
            Destination = "NATIVE_RELEASE_CANDIDATE_ZH.md"
        }
    )
    foreach ($mediaInput in $mediaInputs) {
        $resolvedMediaSource = [System.IO.Path]::GetFullPath(
            $(if ([System.IO.Path]::IsPathRooted($mediaInput.Source)) {
                $mediaInput.Source
            }
            else {
                Join-Path $repositoryRoot $mediaInput.Source
            }))
        if (-not (Test-Path -LiteralPath $resolvedMediaSource -PathType Leaf)) {
            throw "Native media review input is missing: $resolvedMediaSource"
        }
        $copies += @{
            Source = $resolvedMediaSource
            Destination = $mediaInput.Destination
        }
    }
}
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
    NoChangePolicy = $releaseGate.NoChangePolicy
    MediaIncluded = [bool]$IncludeMedia
    Files = $files
    RecordedAt = (Get-Date).ToString("o")
}
if ($IncludeMedia) {
    $manifest.VideoSHA256 = (Get-FileHash `
        -LiteralPath ([System.IO.Path]::GetFullPath(
            $(if ([System.IO.Path]::IsPathRooted($VideoPath)) {
                $VideoPath
            }
            else {
                Join-Path $repositoryRoot $VideoPath
            }))) `
        -Algorithm SHA256).Hash.ToLowerInvariant()
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
    NoChangePolicy = $releaseGate.NoChangePolicy
    OutputDirectory = $resolvedOutput
    Files = $files.Count + 2
} | Format-List
