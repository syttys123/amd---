param(
    [string]$Version = "1.0.0",
    [string]$PackagePath = "artifacts\packages\amd-mobile-power-v1.0.0-win-x64-lite.zip",
    [string]$VideoPath = "artifacts\media\amd-mobile-power-promo-draft-2026-11-10\amd-mobile-power-intro-draft-2026-11-10.mp4",
    [string]$CaptionsPath = "artifacts\media\amd-mobile-power-promo-draft-2026-11-10\captions-zh.srt",
    [string]$BilibiliCoverPath = "docs\assets\bilibili-cover-2026-11-10.png",
    [string]$PromoCoverPath = "docs\assets\promo-draft-cover-2026-11-10.png",
    [switch]$AllowDirty
)

$ErrorActionPreference = "Stop"

$root = Split-Path -Parent $PSCommandPath
$artifactsRoot = Join-Path $root "artifacts"
$reviewRoot = Join-Path $artifactsRoot "release-review"

function Resolve-ProjectPath {
    param([string]$Path)

    if ([IO.Path]::IsPathRooted($Path)) {
        return [IO.Path]::GetFullPath($Path)
    }
    return [IO.Path]::GetFullPath((Join-Path $root $Path))
}

function Assert-FileExists {
    param([string]$Path, [string]$Label)

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "$Label is missing: $Path"
    }
}

function Get-Sha256 {
    param([string]$Path)

    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Write-Utf8Text {
    param([string]$Path, [string]$Content)

    $encoding = New-Object System.Text.UTF8Encoding -ArgumentList $false
    [IO.File]::WriteAllText($Path, $Content, $encoding)
}

function Read-ZipEntryText {
    param([string]$ArchivePath, [string]$NamePattern)

    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $archive = [IO.Compression.ZipFile]::OpenRead($ArchivePath)
    try {
        $entry = $archive.Entries |
            Where-Object { $_.FullName -match $NamePattern } |
            Select-Object -First 1
        if ($null -eq $entry) {
            throw "ZIP entry matching '$NamePattern' is missing."
        }

        $reader = New-Object System.IO.StreamReader -ArgumentList $entry.Open()
        try {
            return $reader.ReadToEnd()
        }
        finally {
            $reader.Dispose()
        }
    }
    finally {
        $archive.Dispose()
    }
}

function ConvertFrom-KeyValueText {
    param([string]$Text)

    $values = @{}
    foreach ($line in ($Text -split "`r?`n")) {
        $index = $line.IndexOf("=")
        if ($index -gt 0) {
            $values[$line.Substring(0, $index)] = $line.Substring($index + 1)
        }
    }
    return $values
}

Push-Location $root
try {
    $status = @(git status --porcelain --ignore-submodules=dirty)
    if (-not $AllowDirty -and $status.Count -gt 0) {
        throw "Release review preparation requires a clean worktree.`n$($status -join "`n")"
    }

    $resolvedPackage = Resolve-ProjectPath $PackagePath
    $resolvedVideo = Resolve-ProjectPath $VideoPath
    $resolvedCaptions = Resolve-ProjectPath $CaptionsPath
    $resolvedBilibiliCover = Resolve-ProjectPath $BilibiliCoverPath
    $resolvedPromoCover = Resolve-ProjectPath $PromoCoverPath
    $requiredFiles = @(
        @{ Path = $resolvedPackage; Label = "Portable package" },
        @{ Path = "$resolvedPackage.sha256"; Label = "Package checksum sidecar" },
        @{ Path = $resolvedVideo; Label = "Promotional video" },
        @{ Path = $resolvedCaptions; Label = "Chinese captions" },
        @{ Path = $resolvedBilibiliCover; Label = "Bilibili cover" },
        @{ Path = $resolvedPromoCover; Label = "Promotional video cover" },
        @{ Path = (Join-Path $root "docs\RELEASE_CANDIDATE_ZH.md"); Label = "Release candidate dossier" },
        @{ Path = (Join-Path $root "docs\LAUNCH_COPY_ZH.md"); Label = "Launch copy" },
        @{ Path = (Join-Path $root "docs\THIRD_PARTY_NOTICES.md"); Label = "Third-party notices" },
        @{ Path = (Join-Path $root "docs\SECURITY.md"); Label = "Security boundary" },
        @{ Path = (Join-Path $root "docs\INSTALLATION.md"); Label = "Installation guide" }
    )
    foreach ($required in $requiredFiles) {
        Assert-FileExists $required.Path $required.Label
    }

    $package = Get-Item -LiteralPath $resolvedPackage
    $packageHash = Get-Sha256 $resolvedPackage
    $sidecar = (Get-Content -LiteralPath "$resolvedPackage.sha256" -Raw).Trim()
    $expectedSidecar = "$packageHash  $($package.Name)"
    if ($sidecar -ne $expectedSidecar) {
        throw "Package checksum sidecar does not match the ZIP."
    }

    $buildInfo = ConvertFrom-KeyValueText (
        Read-ZipEntryText $resolvedPackage "/BUILD-INFO\.txt$")
    if ($buildInfo["Version"] -ne $Version) {
        throw "Package version $($buildInfo["Version"]) does not match requested $Version."
    }
    if ($buildInfo["WorkingTree"] -ne "Clean") {
        throw "Package was not built from a clean worktree."
    }

    $packageCommit = $buildInfo["Commit"]
    if ($packageCommit -notmatch "^[0-9a-f]{40}$") {
        throw "Package BUILD-INFO contains an invalid commit: $packageCommit"
    }

    $head = (git rev-parse HEAD).Trim()
    git merge-base --is-ancestor $packageCommit $head
    if ($LASTEXITCODE -ne 0) {
        throw "Package commit $packageCommit is not an ancestor of HEAD $head."
    }

    $changedPaths = @(git diff --name-only "$packageCommit..$head")
    $runtimeSensitive = @(
        $changedPaths | Where-Object {
            $_ -match "^(src/|profiles/|packaging/|third_party/|assets/|" +
                "build-package\.ps1$|build-ryzenadj\.ps1$|" +
                "Directory\.Build\.props$|AmdMobilePower\.sln$|\.gitmodules$)"
        }
    )
    if ($runtimeSensitive.Count -gt 0) {
        throw "Runtime-sensitive files changed after the package commit:`n$(
            $runtimeSensitive -join "`n"
        )"
    }

    & (Join-Path $root "verify-media.ps1")
    if ($LASTEXITCODE -ne 0) {
        throw "Media verification failed with exit code $LASTEXITCODE."
    }

    $shortHead = $head.Substring(0, 7)
    $bundleName = "amd-mobile-power-v$Version-$shortHead"
    $bundlePath = Join-Path $reviewRoot $bundleName
    $resolvedReviewRoot = [IO.Path]::GetFullPath($reviewRoot)
    $resolvedBundle = [IO.Path]::GetFullPath($bundlePath)
    if (-not $resolvedBundle.StartsWith(
        $resolvedReviewRoot + [IO.Path]::DirectorySeparatorChar,
        [StringComparison]::OrdinalIgnoreCase)) {
        throw "Release review bundle escaped artifacts/release-review."
    }
    if (Test-Path -LiteralPath $resolvedBundle) {
        Remove-Item -LiteralPath $resolvedBundle -Recurse -Force
    }
    New-Item -ItemType Directory -Path $resolvedBundle -Force | Out-Null

    $copies = @(
        @{ Source = $resolvedPackage; Destination = "app\$($package.Name)" },
        @{ Source = "$resolvedPackage.sha256"; Destination = "app\$($package.Name).sha256" },
        @{ Source = $resolvedVideo; Destination = "media\amd-mobile-power-intro.mp4" },
        @{ Source = $resolvedCaptions; Destination = "media\captions-zh.srt" },
        @{ Source = $resolvedBilibiliCover; Destination = "media\bilibili-cover.png" },
        @{ Source = $resolvedPromoCover; Destination = "media\promo-cover.png" },
        @{ Source = (Join-Path $root "docs\RELEASE_CANDIDATE_ZH.md"); Destination = "docs\RELEASE-CANDIDATE-ZH.md" },
        @{ Source = (Join-Path $root "docs\LAUNCH_COPY_ZH.md"); Destination = "docs\LAUNCH-COPY-ZH.md" },
        @{ Source = (Join-Path $root "docs\THIRD_PARTY_NOTICES.md"); Destination = "docs\THIRD-PARTY-NOTICES.md" },
        @{ Source = (Join-Path $root "docs\SECURITY.md"); Destination = "docs\SECURITY.md" },
        @{ Source = (Join-Path $root "docs\INSTALLATION.md"); Destination = "docs\INSTALLATION.md" }
    )
    foreach ($copy in $copies) {
        $destination = Join-Path $resolvedBundle $copy.Destination
        $destinationDirectory = Split-Path -Parent $destination
        New-Item -ItemType Directory -Path $destinationDirectory -Force | Out-Null
        Copy-Item -LiteralPath $copy.Source -Destination $destination -Force
    }

    $videoManifestPath = Join-Path (
        Split-Path -Parent $resolvedVideo
    ) "promo-manifest.json"
    Assert-FileExists $videoManifestPath "Promotional video manifest"
    $videoManifest = Get-Content -LiteralPath $videoManifestPath -Raw -Encoding UTF8 |
        ConvertFrom-Json

    $manifest = [pscustomobject]@{
        schemaVersion = 1
        status = "DRAFT_FOR_HUMAN_REVIEW"
        preparedAt = (Get-Date).ToString("o")
        repository = "https://github.com/syttys123/amd-mobile-power"
        source = [pscustomobject]@{
            currentCommit = $head
            packageCommit = $packageCommit
            changedAfterPackage = $changedPaths.Count
            runtimeSensitiveChanges = 0
            workingTree = $buildInfo["WorkingTree"]
        }
        package = [pscustomobject]@{
            file = "app/$($package.Name)"
            version = $buildInfo["Version"]
            sizeBytes = $package.Length
            sha256 = $packageHash
            builtAt = $buildInfo["BuiltAt"]
        }
        media = [pscustomobject]@{
            video = "media/amd-mobile-power-intro.mp4"
            videoSha256 = Get-Sha256 $resolvedVideo
            videoDurationSeconds = $videoManifest.output.durationSeconds
            captions = "media/captions-zh.srt"
            captionsSha256 = Get-Sha256 $resolvedCaptions
            cover = "media/bilibili-cover.png"
            coverSha256 = Get-Sha256 $resolvedBilibiliCover
            promoCover = "media/promo-cover.png"
            promoCoverSha256 = Get-Sha256 $resolvedPromoCover
        }
        approval = [pscustomobject]@{
            publicationAuthorized = $false
            requiresOwnerReview = $true
            requiresAuthenticatedHumanUpload = $true
            networkUploadPerformed = $false
        }
        openGates = @(
            "Read-only evidence from a second AMD platform",
            "GitHub Actions billing or repository visibility confirmation",
            "Project-owner review of final video, claims, cover, and release assets",
            "Explicit approval before GitHub release or Bilibili upload"
        )
    }
    $manifestPath = Join-Path $resolvedBundle "release-review-manifest.json"
    Write-Utf8Text $manifestPath (($manifest | ConvertTo-Json -Depth 8) + "`n")

    $readme = @"
AMD Mobile Power release review bundle
====================================

Status: DRAFT_FOR_HUMAN_REVIEW
Generated without login, upload, hardware write, or publication.

GitHub:
- Review app/$($package.Name) and its SHA256 sidecar.
- Use docs/LAUNCH-COPY-ZH.md for the release title and body.
- Confirm docs/RELEASE-CANDIDATE-ZH.md before attaching assets.

Bilibili:
- Review media/amd-mobile-power-intro.mp4 and media/bilibili-cover.png.
- Use docs/LAUNCH-COPY-ZH.md for title, description, tags, and pinned comment.

No file in this directory is authorization to publish.
"@
    Write-Utf8Text (Join-Path $resolvedBundle "README-REVIEW.txt") ($readme.TrimStart() + "`n")

    $checksumLines = @(
        Get-ChildItem -LiteralPath $resolvedBundle -File -Recurse |
            Where-Object { $_.Name -ne "SHA256SUMS.txt" } |
            Sort-Object FullName |
            ForEach-Object {
                $relative = $_.FullName.Substring($resolvedBundle.Length + 1).Replace("\", "/")
                "$(Get-Sha256 $_.FullName)  $relative"
            }
    )
    $checksumPath = Join-Path $resolvedBundle "SHA256SUMS.txt"
    $encoding = New-Object System.Text.UTF8Encoding -ArgumentList $false
    [IO.File]::WriteAllLines($checksumPath, [string[]]$checksumLines, $encoding)

    [pscustomobject]@{
        Bundle = $resolvedBundle
        Status = "DRAFT_FOR_HUMAN_REVIEW"
        CurrentCommit = $head
        PackageCommit = $packageCommit
        PackageSHA256 = $packageHash
        VideoSHA256 = Get-Sha256 $resolvedVideo
        Files = @(Get-ChildItem -LiteralPath $resolvedBundle -File -Recurse).Count
        Checksums = $checksumLines.Count
        NetworkUploadPerformed = $false
        Verification = "PASS"
    } | Format-List
}
finally {
    Pop-Location
}
