param(
    [Parameter(Mandatory = $true)]
    [string]$Version,
    [switch]$NoBuild,
    [switch]$ExecuteNoChangePolicy,
    [switch]$VerifyShellIntegration,
    [switch]$AllowDirty,
    [switch]$AllowBatteryWriteGuard,
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
    Where-Object { $_ -notmatch "^.. docs/evidence/" } |
    Out-String).Trim()
if ($statusText -and -not $AllowDirty) {
    throw "Native release verification requires a clean worktree. Use -AllowDirty only for diagnostics."
}

if (-not $NoBuild) {
    & (Join-Path $root "build.ps1") -Offline
}

$nativeArguments = @{
    NoBuild = $true
    VerifyHardware = $true
    VerifyRustGui = $true
    VerifyRustWorker = $true
    VerifyWriteGuard = $true
}
if ($AllowBatteryWriteGuard) {
    $nativeArguments.AllowBatteryWriteGuard = $true
}
& (Join-Path $root "verify-native.ps1") @nativeArguments

& (Join-Path $root "verify-power-policy.ps1") -NoBuild

$packageArguments = @{
    NoBuild = $true
    Version = $Version
    EvidencePath = $packageEvidence
    ReadOnlyRuntimeVerification = $true
}
$null = & (Join-Path $root "build-package.ps1") @packageArguments

$packageDirectory = Join-Path `
    (Join-Path $repositoryRoot "artifacts\native-packages") `
    "amd-mobile-power-v$Version-win-x64-native-preview"
$dpiEvidencePath = Join-Path `
    $repositoryRoot `
    "docs\evidence\ui\native-dpi-100-125-150-$(Get-Date -Format 'yyyy-MM-dd').json"
$null = & (Join-Path $root "verify-dpi-fixtures.ps1") `
    -GuiExecutable (Join-Path $packageDirectory "amd-mobile-power-gui.exe") `
    -WorkerExecutable (Join-Path $packageDirectory "amdmobilepower_native_worker.exe") `
    -EvidencePath $dpiEvidencePath
if (-not (Test-Path -LiteralPath $dpiEvidencePath -PathType Leaf) -or
    (Get-Content -LiteralPath $dpiEvidencePath -Raw |
        ConvertFrom-Json).Verification -ne "PASS") {
    throw "Native DPI layout fixtures failed."
}

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
$headCommit = (& git -C $repositoryRoot rev-parse HEAD).Trim()
if ($package.Version -ne $Version) {
    throw "Package evidence version mismatch: $($package.Version) != $Version"
}
if ($package.WorkingTree -ne "Clean") {
    throw "Package evidence was not produced from a clean worktree."
}

# A verified package stays valid while HEAD only moves forward over
# documentation. Any change to runtime, build, CI, or packaging paths after the
# recorded source commit invalidates the package and requires a rebuild.
if ($package.SourceCommit -ne $headCommit) {
    & git -C $repositoryRoot merge-base --is-ancestor $package.SourceCommit $headCommit
    if ($LASTEXITCODE -ne 0) {
        throw "Package source commit is not an ancestor of HEAD: $($package.SourceCommit)"
    }
    $driftPaths = @(
        & git -C $repositoryRoot diff `
            --name-only `
            $package.SourceCommit `
            $headCommit |
            Where-Object { $_ -and $_ -notmatch "^docs/" -and $_ -notmatch "^[^/]+\.md$" }
    )
    if ($driftPaths.Count -gt 0) {
        throw ("Package evidence is stale: HEAD changed non-documentation " +
            "paths after the package source commit: " + ($driftPaths -join ", "))
    }
}
if ($VerifyShellIntegration) {
    $shell = Get-Content -LiteralPath $shellEvidence -Raw | ConvertFrom-Json
    if ($shell.Version -ne $Version -or
        $shell.SourcePackageCommit -ne $headCommit -or
        $shell.Cleanup -ne "PASS") {
        throw "Shell-integration evidence does not match the release candidate."
    }
}
if ($ExecuteNoChangePolicy) {
    $policy = Get-Content -LiteralPath $policyEvidence -Raw | ConvertFrom-Json
    if ($policy.SourceCommit -ne $headCommit -or
        $policy.WorkingTree -ne "Clean" -or
        $policy.PolicyDisabled -ne "PASS" -or
        $policy.Shutdown -ne "PASS") {
        throw "Power-policy evidence does not match the release candidate."
    }
}
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
    DpiFixtures = "PASS"
    DpiEvidence = $dpiEvidencePath
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
