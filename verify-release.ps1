param(
    [string]$Version = "0.1.3-dev",
    [string]$Configuration = "Release",
    [switch]$FrameworkDependent,
    [switch]$AllowDirty,
    [switch]$VerifyShellIntegration,
    [switch]$VerifyTrayMenu,
    [switch]$VerifyTrayExit,
    [switch]$VerifyDiagnostics,
    [switch]$VerifyDashboard
)

$ErrorActionPreference = "Stop"

$root = Split-Path -Parent $PSCommandPath
$packageSuffix = if ($FrameworkDependent) { "-lite" } else { "" }
$packageName = "amd-mobile-power-v$Version-win-x64$packageSuffix"
$artifacts = Join-Path $root "artifacts"
$stage = Join-Path $artifacts "packages\$packageName"
$zipPath = "$stage.zip"

function Invoke-CheckedCommand {
    param(
        [string]$Name,
        [scriptblock]$Command
    )

    & $Command
    if ($LASTEXITCODE -ne 0) {
        throw "$Name failed with exit code $LASTEXITCODE."
    }
}

function Get-KeyValueFile {
    param([string]$Path)

    $values = @{}
    foreach ($line in Get-Content -LiteralPath $Path) {
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
        throw "Release verification requires a clean worktree.`n$($status -join "`n")"
    }

    Invoke-CheckedCommand "dotnet restore" {
        dotnet restore AmdMobilePower.sln
    }
    Invoke-CheckedCommand "dependency vulnerability and deprecation audit" {
        & (Join-Path $root "verify-dependencies.ps1") `
            -Solution "AmdMobilePower.sln"
    }
    Invoke-CheckedCommand "dotnet build" {
        dotnet build AmdMobilePower.sln -c $Configuration --no-restore
    }
    Invoke-CheckedCommand "dotnet test" {
        dotnet test --solution AmdMobilePower.sln -c $Configuration --no-build
    }
    Invoke-CheckedCommand "dotnet format" {
        dotnet format AmdMobilePower.sln --verify-no-changes --no-restore
    }

    & (Join-Path $root "build-package.ps1") `
        -Version $Version `
        -Configuration $Configuration `
        -FrameworkDependent:$FrameworkDependent
    if ($LASTEXITCODE -ne 0) {
        throw "Package build failed."
    }

    if (-not (Test-Path -LiteralPath $stage) -or -not (Test-Path -LiteralPath $zipPath)) {
        throw "Package output is incomplete."
    }

    $requiredFiles = @(
        "AmdMobilePower.exe",
        "BUILD-INFO.txt",
        "README.txt",
        "RELEASE-CHECKLIST.md",
        "THIRD_PARTY_NOTICES.md",
        "install.ps1",
        "uninstall.ps1",
        "collect-diagnostics.ps1",
        "worker\AmdMobilePower.Worker.exe",
        "worker\libryzenadj.dll",
        "worker\inpoutx64.dll",
        "worker\WinRing0x64.dll",
        "worker\WinRing0x64.sys",
        "worker\BUILD-INFO.txt",
        "licenses\GPL-3.0.txt",
        "licenses\InpOut32-LICENSE.txt",
        "licenses\RyzenAdj-LICENSE.txt",
        "licenses\WinRing0-COPYRIGHT.txt"
    )
    foreach ($relativePath in $requiredFiles) {
        if (-not (Test-Path -LiteralPath (Join-Path $stage $relativePath))) {
            throw "Required package file is missing: $relativePath"
        }
    }

    $buildInfo = Get-KeyValueFile (Join-Path $stage "BUILD-INFO.txt")
    $head = (git rev-parse HEAD).Trim()
    if ($buildInfo["Commit"] -ne $head) {
        throw "Package commit $($buildInfo["Commit"]) does not match HEAD $head."
    }
    $expectedTree = if ($AllowDirty) { "Dirty" } else { "Clean" }
    if ($buildInfo["WorkingTree"] -ne $expectedTree) {
        throw "Package working tree is $($buildInfo["WorkingTree"]), expected $expectedTree."
    }
    if ($buildInfo["Version"] -ne $Version) {
        throw "Package version is $($buildInfo["Version"]), expected $Version."
    }

    $ryzenAdjInfo = Get-KeyValueFile (Join-Path $stage "worker\BUILD-INFO.txt")
    $ryzenAdjHead = (git -C (Join-Path $root "third_party\RyzenAdj") rev-parse HEAD).Trim()
    if ($ryzenAdjInfo["RyzenAdjCommit"] -ne $ryzenAdjHead) {
        throw "Packaged RyzenAdj commit does not match the pinned submodule."
    }

    $profiles = @(Get-ChildItem -LiteralPath (Join-Path $stage "worker\profiles") -Filter "*.json" -File)
    if ($profiles.Count -lt 9) {
        throw "Expected at least nine profiles, found $($profiles.Count)."
    }

    $licenses = @(Get-ChildItem -LiteralPath (Join-Path $stage "licenses") -File)
    if ($licenses.Count -ne 4) {
        throw "Expected four license files, found $($licenses.Count)."
    }

    $gplHash = (Get-FileHash (Join-Path $stage "licenses\GPL-3.0.txt") -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($gplHash -ne "3972dc9744f6499f0f9b2dbf76696f2ae7ad8af9b23dde66d6af86c9dfb36986") {
        throw "GPL-3.0.txt does not match the reviewed canonical text."
    }

    $unexpectedStateFiles = @(
        Get-ChildItem -LiteralPath $stage -File -Recurse |
            Where-Object {
                $_.Extension -eq ".log" -or
                $_.Name -match "(?i)^(telemetry|probe-status|worker-init|ui-state|power-mode)"
            }
    )
    if ($unexpectedStateFiles.Count -gt 0) {
        throw "Machine-specific state files were packaged: $(
            ($unexpectedStateFiles | Select-Object -ExpandProperty FullName) -join ", "
        )"
    }

    $checksumLines = @(Get-Content -LiteralPath (Join-Path $stage "SHA256SUMS.txt"))
    $stagedFiles = @(Get-ChildItem -LiteralPath $stage -File -Recurse)
    if ($checksumLines.Count -ne ($stagedFiles.Count - 1)) {
        throw "SHA256SUMS.txt does not cover every staged file except itself."
    }
    foreach ($line in $checksumLines) {
        if ($line -notmatch "^([0-9a-f]{64})  (.+)$") {
            throw "Invalid SHA256SUMS.txt entry: $line"
        }
        $expectedHash = $matches[1]
        $relativePath = $matches[2].Replace("/", "\")
        $path = Join-Path $stage $relativePath
        if (-not (Test-Path -LiteralPath $path)) {
            throw "Checksum target is missing: $relativePath"
        }
        $actualHash = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant()
        if ($actualHash -ne $expectedHash) {
            throw "Checksum mismatch: $relativePath"
        }
    }

    $zipHash = (Get-FileHash -LiteralPath $zipPath -Algorithm SHA256).Hash.ToLowerInvariant()
    $sidecar = (Get-Content -LiteralPath "$zipPath.sha256" -Raw).Trim()
    if ($sidecar -ne "$zipHash  $packageName.zip") {
        throw "ZIP sidecar hash does not match the package."
    }

    $gui = Get-Item (Join-Path $stage "AmdMobilePower.exe")
    $worker = Get-Item (Join-Path $stage "worker\AmdMobilePower.Worker.exe")
    foreach ($executable in @($gui, $worker)) {
        if ($executable.VersionInfo.ProductVersion -ne $Version) {
            throw "$($executable.Name) product version does not match $Version."
        }
    }

    $resolvedArtifacts = [IO.Path]::GetFullPath($artifacts)
    $verifyRoot = Join-Path $resolvedArtifacts ("verify\release-" + [Guid]::NewGuid().ToString("N"))
    if (-not ([IO.Path]::GetFullPath($verifyRoot)).StartsWith(
        $resolvedArtifacts + [IO.Path]::DirectorySeparatorChar,
        [StringComparison]::OrdinalIgnoreCase)) {
        throw "Verification directory escaped artifacts."
    }

    & (Join-Path $stage "install.ps1") `
        -InstallDirectory $verifyRoot `
        -NoStartup `
        -NoLaunch `
        -NoShellIntegration
    $sentinel = Join-Path $verifyRoot "obsolete-version-marker.tmp"
    Set-Content -LiteralPath $sentinel -Value "old candidate" -Encoding ascii
    & (Join-Path $stage "install.ps1") `
        -InstallDirectory $verifyRoot `
        -NoStartup `
        -NoLaunch `
        -NoShellIntegration
    if (Test-Path -LiteralPath $sentinel) {
        throw "Overwrite upgrade left an obsolete marker behind."
    }
    & (Join-Path $stage "uninstall.ps1") `
        -InstallDirectory $verifyRoot `
        -NoShellIntegration
    if (Test-Path -LiteralPath $verifyRoot) {
        throw "Uninstall left the verification directory behind."
    }

    $shellIntegration = "Not requested"
    if ($VerifyShellIntegration) {
        & (Join-Path $root "verify-shell-integration.ps1") `
            -PackageDirectory $stage
        $shellIntegration = "PASS"
    }

    $trayMenu = "Not requested"
    $trayRecovery = "Not requested"
    $trayParentExit = "Not requested"
    $trayMenuScreenshot = $null
    if ($VerifyTrayMenu) {
        $trayVerifyDirectory = Join-Path $artifacts "verify"
        New-Item -ItemType Directory -Path $trayVerifyDirectory -Force | Out-Null
        $trayMenuScreenshot = Join-Path (
            $trayVerifyDirectory
        ) ("tray-menu-" + [Guid]::NewGuid().ToString("N") + ".png")
        & (Join-Path $root "verify-tray-menu.ps1") `
            -PackageDirectory $stage `
            -ScreenshotPath $trayMenuScreenshot `
            -VerifyGracefulExit:$VerifyTrayExit
        $trayMenu = "PASS"

        & (Join-Path $root "verify-tray-menu.ps1") `
            -PackageDirectory $stage `
            -ScreenshotPath $trayMenuScreenshot `
            -VerifyShowFromTray | Out-Null
        & (Join-Path $root "verify-tray-menu.ps1") `
            -PackageDirectory $stage `
            -ScreenshotPath $trayMenuScreenshot `
            -VerifyDoubleClickFromTray | Out-Null
        & (Join-Path $root "verify-tray-menu.ps1") `
            -PackageDirectory $stage `
            -ScreenshotPath $trayMenuScreenshot `
            -VerifyOpenFromMenu | Out-Null
        $trayRecovery = "PASS"

        & (Join-Path $root "verify-tray-menu.ps1") `
            -PackageDirectory $stage `
            -ScreenshotPath $trayMenuScreenshot `
            -VerifyParentExit | Out-Null
        $trayParentExit = "PASS"
    }

    $diagnostics = "Not requested"
    $diagnosticsPath = $null
    if ($VerifyDiagnostics) {
        $verifyDirectory = Join-Path $artifacts "verify"
        New-Item -ItemType Directory -Path $verifyDirectory -Force | Out-Null
        $diagnosticsPath = Join-Path (
            $verifyDirectory
        ) ("diagnostics-" + [Guid]::NewGuid().ToString("N") + ".json")

        & (Join-Path $stage "collect-diagnostics.ps1") `
            -OutputPath $diagnosticsPath
        if ($LASTEXITCODE -ne 0) {
            throw "Read-only diagnostics collection failed with exit code $LASTEXITCODE."
        }
        if (-not (Test-Path -LiteralPath $diagnosticsPath)) {
            throw "Read-only diagnostics output is missing."
        }

        $diagnosticsRaw = Get-Content -LiteralPath $diagnosticsPath -Raw
        $diagnosticsReport = $diagnosticsRaw | ConvertFrom-Json
        if ($diagnosticsReport.schemaVersion -ne 1) {
            throw "Diagnostics schemaVersion is not 1."
        }
        if ($diagnosticsReport.collectionStatus -ne "PASS") {
            throw "Diagnostics collectionStatus is not PASS."
        }
        if ($diagnosticsReport.worker.version -ne $Version) {
            throw "Diagnostics worker version $($diagnosticsReport.worker.version) does not match $Version."
        }
        if (-not $diagnosticsReport.worker.hardwareAdapterConfigured) {
            throw "Diagnostics did not configure the hardware adapter."
        }
        if ($diagnosticsReport.worker.writeControlsEnabled) {
            throw "Diagnostics unexpectedly enabled hardware writes."
        }
        if ($diagnosticsReport.cleanup.shutdownProtocol -ne "PASS") {
            throw "Diagnostics worker did not use the graceful shutdown protocol."
        }
        foreach ($privacyFlag in @(
            "localPathsIncluded",
            "processIdIncluded",
            "accountNamesIncluded",
            "serialNumbersIncluded",
            "recentLogsIncluded",
            "networkUploadPerformed"
        )) {
            if ($diagnosticsReport.privacy.$privacyFlag) {
                throw "Diagnostics privacy flag $privacyFlag must be false."
            }
        }
        foreach ($forbiddenField in @(
            "processId",
            "workerDirectory",
            "diagnosticLogDirectory",
            "recentWorkerLogLines",
            "recentGuiLogLines",
            "pipeName"
        )) {
            if ($diagnosticsRaw -match ('"' + $forbiddenField + '"')) {
                throw "Diagnostics unexpectedly contains field $forbiddenField."
            }
        }
        if ($diagnosticsRaw -match '(?i)[A-Z]:\\' -or
            $diagnosticsRaw.Contains('\\\\')) {
            throw "Diagnostics unexpectedly contains an absolute local path."
        }
        $diagnostics = "PASS"
    }

    $dashboard = "Not requested"
    $dashboardScreenshot = $null
    $dashboardScreenshotHash = $null
    if ($VerifyDashboard) {
        $dashboardDirectory = Join-Path $artifacts "verify"
        New-Item -ItemType Directory -Path $dashboardDirectory -Force | Out-Null
        $dashboardScreenshot = Join-Path (
            $dashboardDirectory
        ) ("dashboard-" + [Guid]::NewGuid().ToString("N") + ".png")
        $dashboardEvidence = Join-Path (
            $dashboardDirectory
        ) ("dashboard-" + [Guid]::NewGuid().ToString("N") + ".json")
        & (Join-Path $root "verify-dashboard.ps1") `
            -PackageDirectory $stage `
            -ScreenshotPath $dashboardScreenshot `
            -EvidencePath $dashboardEvidence
        $dashboard = "PASS"
        $dashboardScreenshotHash = (
            Get-FileHash -LiteralPath $dashboardScreenshot -Algorithm SHA256
        ).Hash.ToLowerInvariant()
    }

    [pscustomobject]@{
        Package = $zipPath
        SHA256 = $zipHash
        Commit = $head
        WorkingTree = $buildInfo["WorkingTree"]
        Files = $stagedFiles.Count
        Checksums = $checksumLines.Count
        Profiles = $profiles.Count
        Licenses = $licenses.Count
        ShellIntegration = $shellIntegration
        TrayMenu = $trayMenu
        TrayRecovery = $trayRecovery
        TrayParentExit = $trayParentExit
        TrayExit = if ($VerifyTrayExit) { "PASS" } else { "Not requested" }
        TrayMenuScreenshot = $trayMenuScreenshot
        Diagnostics = $diagnostics
        DiagnosticsReport = $diagnosticsPath
        Dashboard = $dashboard
        DashboardScreenshot = $dashboardScreenshot
        DashboardScreenshotSHA256 = $dashboardScreenshotHash
        DependencyAudit = "PASS"
        Verification = "PASS"
    } | Format-List
}
finally {
    Pop-Location
}
