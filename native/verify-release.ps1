param(
    [Parameter(Mandatory = $true)]
    [string]$Version,
    [switch]$NoBuild,
    [switch]$ExecuteNoChangePolicy,
    [switch]$VerifyShellIntegration,
    [switch]$AllowDirty,
    [string]$EvidencePath
)

$ErrorActionPreference = "Stop"

$root = Split-Path -Parent $PSCommandPath
$repositoryRoot = Split-Path -Parent $root
$packageEvidence = Join-Path `
    $repositoryRoot `
    "docs\evidence\packaging\v$Version-clean-$(Get-Date -Format 'yyyy-MM-dd').json"
$shellEvidence = Join-Path `
    $repositoryRoot `
    "docs\evidence\packaging\v$Version-shell-integration-$(Get-Date -Format 'yyyy-MM-dd').json"
$policyEvidence = Join-Path `
    $repositoryRoot `
    "docs\evidence\hardware\v$Version-power-policy-no-change-$(Get-Date -Format 'yyyy-MM-dd').json"

if (-not $EvidencePath) {
    $EvidencePath = Join-Path `
        $repositoryRoot `
        "docs\evidence\packaging\v$Version-release-gate-$(Get-Date -Format 'yyyy-MM-dd').json"
}

$statusText = (& git `
    -C $repositoryRoot `
    status `
    --porcelain `
    --ignore-submodules=dirty |
    Out-String).Trim()
if ($statusText -and -not $AllowDirty) {
    throw "Native release verification requires a clean worktree. Use -AllowDirty only for diagnostics."
}

if (-not $NoBuild) {
    & (Join-Path $root "build.ps1") -Offline
}

& (Join-Path $root "verify-native.ps1") `
    -NoBuild `
    -VerifyHardware `
    -VerifyRustGui `
    -VerifyRustWorker `
    -VerifyWriteGuard

& (Join-Path $root "verify-power-policy.ps1") -NoBuild

$null = & (Join-Path $root "build-package.ps1") `
    -NoBuild `
    -Version $Version `
    -EvidencePath $packageEvidence

$shellStatus = "Not requested"
if ($VerifyShellIntegration) {
    $null = & (Join-Path $root "verify-preview-shell-integration.ps1") `
        -EvidencePath $shellEvidence
    $shellStatus = "PASS"
}

$policyStatus = "Not requested"
if ($ExecuteNoChangePolicy) {
    $null = & (Join-Path $root "verify-power-policy.ps1") `
        -NoBuild `
        -ExecuteNoChangePolicy `
        -EvidencePath $policyEvidence
    $policyStatus = "PASS"
}

$package = Get-Content -LiteralPath $packageEvidence -Raw | ConvertFrom-Json
$result = [ordered]@{
    Version = $Version
    Verification = "PASS"
    Package = $package.Package
    SHA256 = $package.SHA256
    Size = $package.Size
    SourceCommit = $package.SourceCommit
    PackageEvidence = $packageEvidence
    ShellIntegration = $shellStatus
    ShellEvidence = if ($VerifyShellIntegration) { $shellEvidence } else { $null }
    NoChangePolicy = $policyStatus
    PolicyEvidence = if ($ExecuteNoChangePolicy) { $policyEvidence } else { $null }
    RecordedAt = (Get-Date).ToString("o")
}

$evidenceDirectory = Split-Path -Parent $EvidencePath
if ($evidenceDirectory) {
    New-Item -ItemType Directory -Path $evidenceDirectory -Force | Out-Null
}
$result |
    ConvertTo-Json -Depth 8 |
    Set-Content -LiteralPath $EvidencePath -Encoding UTF8

$result | Format-List
