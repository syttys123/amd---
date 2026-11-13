param(
    [Parameter(Mandatory = $true)]
    [string]$Version,
    [string]$OutputDirectory,
    [switch]$IncludeMedia,
    [string]$VideoPath,
    [string]$MediaEvidencePath,
    [string]$BilibiliCoverPath,
    [string]$ContactSheetPath,
    [string]$LaunchCopyPath,
    [string]$ReleaseCandidatePath
)

$ErrorActionPreference = "Stop"

$root = Split-Path -Parent $PSCommandPath
$repositoryRoot = Split-Path -Parent $root
$artifactsRoot = [System.IO.Path]::GetFullPath(
    (Join-Path $repositoryRoot "artifacts"))

function Get-NewestFile {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Directory,
        [Parameter(Mandatory = $true)]
        [string]$Filter
    )

    if (-not (Test-Path -LiteralPath $Directory -PathType Container)) {
        return $null
    }
    return Get-ChildItem -LiteralPath $Directory -Filter $Filter -File |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1
}

function Resolve-DefaultFile {
    param(
        [AllowEmptyString()]
        [string]$Provided,
        [string[]]$Candidates
    )

    if (-not [string]::IsNullOrWhiteSpace($Provided)) {
        return $Provided
    }
    foreach ($candidate in $Candidates) {
        if ($candidate -and (Test-Path -LiteralPath $candidate -PathType Leaf)) {
            return $candidate
        }
    }
    return $Candidates | Where-Object { $_ } | Select-Object -First 1
}

$today = Get-Date -Format "yyyy-MM-dd"
$newestPromoVideo = Get-NewestFile `
    -Directory (Join-Path $artifactsRoot "media\promo-html-v1") `
    -Filter "*.mp4"
$newestCover = Get-NewestFile `
    -Directory (Join-Path $repositoryRoot "docs\assets") `
    -Filter "bilibili-cover-*.png"
$newestContactSheet = Get-NewestFile `
    -Directory (Join-Path $repositoryRoot "docs\assets") `
    -Filter "native-promo-*-contact-sheet-*.png"

$VideoPath = Resolve-DefaultFile -Provided $VideoPath -Candidates @(
    $(if ($newestPromoVideo) { $newestPromoVideo.FullName })
)
$MediaEvidencePath = Resolve-DefaultFile -Provided $MediaEvidencePath -Candidates @(
    (Join-Path $repositoryRoot "docs\evidence\media\native-promo-$Version-draft-$today.json"),
    (Join-Path $repositoryRoot "docs\evidence\media\native-promo-draft-$today.json")
)
$BilibiliCoverPath = Resolve-DefaultFile -Provided $BilibiliCoverPath -Candidates @(
    $(if ($newestCover) { $newestCover.FullName })
)
$ContactSheetPath = Resolve-DefaultFile -Provided $ContactSheetPath -Candidates @(
    $(if ($newestContactSheet) { $newestContactSheet.FullName })
)
$LaunchCopyPath = Resolve-DefaultFile -Provided $LaunchCopyPath -Candidates @(
    (Join-Path $repositoryRoot "docs\NATIVE_LAUNCH_COPY_$($Version)_ZH.md"),
    (Join-Path $repositoryRoot "docs\NATIVE_LAUNCH_COPY_ZH.md")
)
$ReleaseCandidatePath = Resolve-DefaultFile -Provided $ReleaseCandidatePath -Candidates @(
    (Join-Path $repositoryRoot "docs\NATIVE_RELEASE_CANDIDATE_$($Version)_ZH.md"),
    (Join-Path $repositoryRoot "docs\NATIVE_RELEASE_CANDIDATE_ZH.md")
)
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

$packagedUiEvidencePath = Join-Path `
    $repositoryRoot `
    "docs\evidence\ui\native-packaged-$Version-ui-$today.json"
if (Test-Path -LiteralPath $packagedUiEvidencePath -PathType Leaf) {
    $copies += @{
        Source = $packagedUiEvidencePath
        Destination = "packaged-ui.json"
    }
}

$deploymentEvidenceCandidate = @(
    (Join-Path $repositoryRoot "docs\evidence\packaging\v$Version-native-deployment-$today.json"),
    (Join-Path $repositoryRoot "docs\evidence\packaging\v$Version-deployment-$today.json")
) | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } | Select-Object -First 1
if ($deploymentEvidenceCandidate) {
    $copies += @{
        Source = $deploymentEvidenceCandidate
        Destination = "deployment.json"
    }
}

$releaseNotesPath = Join-Path $repositoryRoot "docs\release-notes-$Version-zh.md"
if (Test-Path -LiteralPath $releaseNotesPath -PathType Leaf) {
    $copies += @{
        Source = $releaseNotesPath
        Destination = "RELEASE_NOTES_ZH.md"
    }
}

$releaseAssetsPath = Join-Path $repositoryRoot "docs\release-assets-$Version.json"
if (Test-Path -LiteralPath $releaseAssetsPath -PathType Leaf) {
    $copies += @{
        Source = $releaseAssetsPath
        Destination = "RELEASE_ASSETS.json"
    }
}

foreach ($reviewDoc in @(
    "RELEASE_CHECKLIST.md",
    "RELEASE_RUNBOOK.md"
)) {
    $reviewDocPath = Join-Path $repositoryRoot (Join-Path "docs" $reviewDoc)
    if (Test-Path -LiteralPath $reviewDocPath -PathType Leaf) {
        $copies += @{
            Source = $reviewDocPath
            Destination = $reviewDoc
        }
    }
}

$dpiEvidenceFile = Get-NewestFile `
    -Directory (Join-Path $repositoryRoot "docs\evidence\ui") `
    -Filter "native-dpi-100-125-150-*.json"
$dpiEvidencePath = if ($dpiEvidenceFile) {
    $dpiEvidenceFile.FullName
}
else {
    Join-Path `
        $repositoryRoot `
        "docs\evidence\ui\native-dpi-100-125-150-$today.json"
}
$dpiGate = "PENDING"
$dpiEvidence = $null
if (Test-Path -LiteralPath $dpiEvidencePath -PathType Leaf) {
    $dpiEvidence = Get-Content -LiteralPath $dpiEvidencePath -Raw | ConvertFrom-Json
    if ($dpiEvidence.Verification -eq "PASS") {
        $dpiGate = "PASS"
        $copies += @{
            Source = $dpiEvidencePath
            Destination = "dpi-fixtures.json"
        }
        foreach ($entry in @($dpiEvidence.Scales)) {
            foreach ($capture in @(
                @{ Source = $entry.SimpleImage; Destination = "dpi-$($entry.Scale)-simple.png" },
                @{ Source = $entry.AdvancedImage; Destination = "dpi-$($entry.Scale)-advanced.png" }
            )) {
                if (-not (Test-Path -LiteralPath $capture.Source -PathType Leaf)) {
                    throw "DPI fixture image is missing: $($capture.Source)"
                }
                $copies += $capture
            }
        }
    }
}
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
        @{ Source = $ReleaseCandidatePath; Destination = "NATIVE_RELEASE_CANDIDATE_ZH.md" }
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
    DpiLayoutFixtures100And150 = $dpiGate
    Dpi100And150SystemSessions = "PENDING"
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
