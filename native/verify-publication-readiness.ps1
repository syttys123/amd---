param(
    [string]$Version = "1.0.0-native",
    [string]$EvidencePath
)

$ErrorActionPreference = "Stop"

$root = Split-Path -Parent $PSCommandPath
$repositoryRoot = Split-Path -Parent $root
$artifactsRoot = [System.IO.Path]::GetFullPath(
    (Join-Path $repositoryRoot "artifacts"))

function Read-JsonFile {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "Required JSON file is missing: $Path"
    }
    return Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
}

function Get-Sha256 {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).
        Hash.ToLowerInvariant()
}

function Get-BuildInfo {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    $values = @{}
    foreach ($line in Get-Content -LiteralPath $Path) {
        if ($line -match "^([^=]+)=(.*)$") {
            $values[$Matches[1]] = $Matches[2]
        }
    }
    return $values
}

if (-not $EvidencePath) {
    $EvidencePath = Join-Path `
        $repositoryRoot `
        "docs\evidence\release\native-publication-readiness-$(Get-Date -Format 'yyyy-MM-dd').json"
}

$packageName = "amd-mobile-power-v$Version-win-x64-native-preview.zip"
$packagePath = Join-Path `
    (Join-Path $artifactsRoot "native-packages") `
    $packageName
$releaseGatePath = Join-Path `
    $repositoryRoot `
    "docs\evidence\packaging\v$Version-release-gate-$(Get-Date -Format 'yyyy-MM-dd').json"
$cleanEvidencePath = Join-Path `
    $repositoryRoot `
    "docs\evidence\packaging\v$Version-clean-$(Get-Date -Format 'yyyy-MM-dd').json"
$deploymentEvidencePath = Join-Path `
    $repositoryRoot `
    "docs\evidence\packaging\v$Version-deployment-$(Get-Date -Format 'yyyy-MM-dd').json"
$policyEvidencePath = Join-Path `
    $repositoryRoot `
    "docs\evidence\hardware\v$Version-power-policy-no-change-$(Get-Date -Format 'yyyy-MM-dd').json"
$packagedUiEvidencePath = Join-Path `
    $repositoryRoot `
    "docs\evidence\ui\native-packaged-1.0.0-ui-$(Get-Date -Format 'yyyy-MM-dd').json"
$mediaEvidencePath = Join-Path `
    $repositoryRoot `
    "docs\evidence\media\native-promo-draft-$(Get-Date -Format 'yyyy-MM-dd').json"
$compatibilityIndexPath = Join-Path `
    $repositoryRoot `
    "docs\evidence\compatibility\index.json"
$reviewBundle = Join-Path `
    $artifactsRoot `
    "native-release-review\v$Version"

if (-not (Test-Path -LiteralPath $packagePath -PathType Leaf)) {
    throw "Native package is missing: $packagePath"
}
$packageHash = Get-Sha256 $packagePath
$releaseGate = Read-JsonFile $releaseGatePath
$cleanEvidence = Read-JsonFile $cleanEvidencePath
$deployment = Read-JsonFile $deploymentEvidencePath
$policyEvidence = Read-JsonFile $policyEvidencePath
$packagedUi = Read-JsonFile $packagedUiEvidencePath
$media = Read-JsonFile $mediaEvidencePath
$compatibilityIndex = Read-JsonFile $compatibilityIndexPath

$checks = [ordered]@{}
$blockers = New-Object System.Collections.Generic.List[string]

$checks.PackageHash = (
    $releaseGate.SHA256 -eq $packageHash -and
    $cleanEvidence.SHA256 -eq $packageHash -and
    $releaseGate.Version -eq $Version
)
if (-not $checks.PackageHash) {
    $blockers.Add("Package hash or version does not match the clean/release evidence.")
}

$checks.PackageVerification = (
    $cleanEvidence.Verification -eq "PASS" -and
    $cleanEvidence.ChecksumEntries -ge 16 -and
    $cleanEvidence.RuntimeVerification -eq "PASS"
)
if (-not $checks.PackageVerification) {
    $blockers.Add("Clean package verification is incomplete.")
}

$checks.NoChangePolicy = (
    $releaseGate.NoChangePolicy -eq "PASS" -and
    $policyEvidence.Verification -eq "PASS" -and
    $policyEvidence.PolicyDisabled -eq "PASS" -and
    $policyEvidence.Shutdown -eq "PASS"
)
if (-not $checks.NoChangePolicy) {
    $blockers.Add("Controlled current-value policy evidence is incomplete.")
}

$checks.PackagedUi = (
    $packagedUi.Verification -eq "PASS" -and
    $packagedUi.TaskbarIconAvailable -eq $true -and
    $packagedUi.TrayIconId -eq 1 -and
    $packagedUi.CloseToTray -eq "PASS" -and
    $packagedUi.TrayRestore -eq "PASS" -and
    $packagedUi.SingleInstanceWake -eq "PASS" -and
    $packagedUi.InitialUiMode -eq "simple" -and
    $packagedUi.FinalUiMode -eq "advanced"
)
if (-not $checks.PackagedUi) {
    $blockers.Add("Packaged GUI/tray/mode evidence is incomplete.")
}

$deployedBuildInfo = Get-BuildInfo (Join-Path "C:\RyzenAdj" "BUILD-INFO.txt")
$deployedGuiPath = Join-Path "C:\RyzenAdj" "amd-mobile-power-gui.exe"
$deployedWorkerPath = Join-Path "C:\RyzenAdj" "amdmobilepower_native_worker.exe"
$checks.LocalDeployment = (
    (Test-Path -LiteralPath $deployedGuiPath -PathType Leaf) -and
    (Test-Path -LiteralPath $deployedWorkerPath -PathType Leaf) -and
    $deployedBuildInfo["Version"] -eq $Version -and
    (Get-Sha256 $deployedGuiPath) -eq $deployment.DeployedGuiSHA256 -and
    (Get-Sha256 $deployedWorkerPath) -eq $deployment.DeployedWorkerSHA256 -and
    $deployment.UiVerification -eq "PASS"
)
if (-not $checks.LocalDeployment) {
    $blockers.Add("C:\RyzenAdj does not match the recorded deployment evidence.")
}

$shortcutPath = "<USER_HOME>\Desktop\功耗设置 5-60W.lnk"
$checks.DesktopShortcut = $false
if (Test-Path -LiteralPath $shortcutPath -PathType Leaf) {
    $shell = New-Object -ComObject WScript.Shell
    $shortcut = $shell.CreateShortcut($shortcutPath)
    $checks.DesktopShortcut = (
        $shortcut.TargetPath -eq (Join-Path "C:\RyzenAdj" "amd-mobile-power-gui.exe") -and
        $shortcut.Arguments -eq "--enable-write-controls --simple-mode"
    )
}
if (-not $checks.DesktopShortcut) {
    $blockers.Add("Desktop shortcut target or arguments do not match the deployment.")
}

$checks.CompatibilityIndex = (
    $null -ne $compatibilityIndex -and
    @($compatibilityIndex).Count -ge 1
)
if (-not $checks.CompatibilityIndex) {
    $blockers.Add("No sanitized compatibility report is indexed.")
}

$videoPath = Join-Path `
    $repositoryRoot `
    "artifacts\media\amd-mobile-power-native-promo-draft-2026-11-11\amd-mobile-power-native-intro-draft-2026-11-11.mp4"
$checks.MediaDraft = (
    (Test-Path -LiteralPath $videoPath -PathType Leaf) -and
    (Get-Sha256 $videoPath) -eq $media.video.sha256 -and
    $media.status -eq "DRAFT_FOR_HUMAN_REVIEW" -and
    $media.verification.ffmpegFullDecode -eq "PASS"
)
if (-not $checks.MediaDraft) {
    $blockers.Add("Native promotional-video draft or media evidence is incomplete.")
}

$checks.ReviewBundle = $false
$bundleChecksums = Join-Path $reviewBundle "SHA256SUMS.txt"
if (Test-Path -LiteralPath $bundleChecksums -PathType Leaf) {
    $checks.ReviewBundle = $true
    foreach ($line in Get-Content -LiteralPath $bundleChecksums) {
        if ($line -notmatch "^([a-f0-9]{64})  (.+)$") {
            $checks.ReviewBundle = $false
            break
        }
        $bundleFile = Join-Path $reviewBundle $Matches[2]
        if (-not (Test-Path -LiteralPath $bundleFile -PathType Leaf) -or
            (Get-Sha256 $bundleFile) -ne $Matches[1]) {
            $checks.ReviewBundle = $false
            break
        }
    }
}
if (-not $checks.ReviewBundle) {
    $blockers.Add("Native review bundle checksums are incomplete or invalid.")
}

$openGates = [ordered]@{
    SecondAmdDevice = "PENDING"
    Dpi100And150 = "PENDING"
    HostedWindowsCi = "PENDING"
    CleanWindowsWinRing0Baseline = "PENDING"
    HumanVideoAndClaimReview = "PENDING"
    ExplicitPublicReleaseApproval = "PENDING"
    BilibiliAuthenticatedUpload = "PENDING"
}

$localChecksPass = -not ($checks.Values -contains $false)
$result = [ordered]@{
    SchemaVersion = 1
    Version = $Version
    Package = $packageName
    PackageSHA256 = $packageHash
    LocalDeployment = "C:\RyzenAdj"
    Checks = $checks
    LocalReadiness = if ($localChecksPass) { "PASS" } else { "FAIL" }
    PublicReleaseReadiness = if ($localChecksPass) {
        "READY_FOR_HUMAN_REVIEW"
    }
    else {
        "BLOCKED_BY_LOCAL_CHECKS"
    }
    OpenGates = $openGates
    BlockersFromLocalChecks = @($blockers)
    Note = "No GitHub login, Bilibili login, upload, publication, or power write was performed by this check."
    RecordedAt = (Get-Date).ToString("o")
}

$evidenceDirectory = Split-Path -Parent $EvidencePath
if ($evidenceDirectory) {
    New-Item -ItemType Directory -Path $evidenceDirectory -Force | Out-Null
}
$result | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $EvidencePath -Encoding UTF8
$result | Format-List

if (-not $localChecksPass) {
    exit 1
}
