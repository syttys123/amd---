param(
    [string]$PackageDirectory = "artifacts\packages\amd-mobile-power-v0.1.3-dev-win-x64-lite",
    [string]$InstallDirectory
)

$ErrorActionPreference = "Stop"

$root = Split-Path -Parent $PSCommandPath
$packagePath = if ([IO.Path]::IsPathRooted($PackageDirectory)) {
    [IO.Path]::GetFullPath($PackageDirectory)
}
else {
    [IO.Path]::GetFullPath((Join-Path $root $PackageDirectory))
}
$installer = Join-Path $packagePath "install.ps1"
if (-not (Test-Path -LiteralPath $installer)) {
    throw "Packaged install.ps1 was not found: $installer"
}

$artifacts = [IO.Path]::GetFullPath((Join-Path $root "artifacts"))
$resolvedInstallDirectory = if ($InstallDirectory) {
    [IO.Path]::GetFullPath($InstallDirectory)
}
else {
    [IO.Path]::GetFullPath(
        (Join-Path $artifacts ("verify\shell-" + [Guid]::NewGuid().ToString("N")))
    )
}
$verifyRoot = [IO.Path]::GetFullPath((Join-Path $artifacts "verify"))
if (-not $resolvedInstallDirectory.StartsWith(
    $verifyRoot + [IO.Path]::DirectorySeparatorChar,
    [StringComparison]::OrdinalIgnoreCase)) {
    throw "Shell integration test directory must be below $verifyRoot."
}

$startMenuShortcut = Join-Path (
    [Environment]::GetFolderPath("ApplicationData")
) "Microsoft\Windows\Start Menu\Programs\AMD Mobile Power.lnk"
$startupShortcut = Join-Path (
    [Environment]::GetFolderPath("Startup")
) "AMD Mobile Power.lnk"
$uninstallKey =
    "HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\AmdMobilePower"

function Assert-Condition {
    param(
        [bool]$Condition,
        [string]$Message
    )

    if (-not $Condition) {
        throw $Message
    }
}

function Invoke-ScheduledTaskCommand {
    param([string[]]$Arguments)

    $previousErrorAction = $ErrorActionPreference
    try {
        $ErrorActionPreference = "SilentlyContinue"
        $output = & schtasks.exe @Arguments 2>&1
        return [pscustomobject]@{
            ExitCode = $LASTEXITCODE
            Output = ($output -join "`n")
        }
    }
    finally {
        $ErrorActionPreference = $previousErrorAction
        $global:LASTEXITCODE = 0
    }
}

function Invoke-Uninstaller {
    param(
        [string]$Path,
        [string]$TargetDirectory
    )

    $null = & powershell.exe `
        -NoProfile `
        -ExecutionPolicy Bypass `
        -File $Path `
        -InstallDirectory $TargetDirectory
    return $LASTEXITCODE
}

function Wait-ForDirectoryRemoval {
    param(
        [string]$Path,
        [int]$TimeoutMilliseconds = 10000
    )

    $deadline = [DateTime]::UtcNow.AddMilliseconds($TimeoutMilliseconds)
    while ((Test-Path -LiteralPath $Path) -and [DateTime]::UtcNow -lt $deadline) {
        Start-Sleep -Milliseconds 250
    }
}

if ((Test-Path -LiteralPath $startMenuShortcut) -or
    (Test-Path -LiteralPath $startupShortcut) -or
    (Test-Path -LiteralPath $uninstallKey)) {
    throw "Refusing shell integration test because existing integration artifacts exist."
}

$uninstaller = Join-Path $resolvedInstallDirectory "uninstall.ps1"
try {
    & $installer -InstallDirectory $resolvedInstallDirectory -NoLaunch
    Assert-Condition ($LASTEXITCODE -eq 0) `
        "install.ps1 returned exit code $LASTEXITCODE."
    Assert-Condition (Test-Path -LiteralPath $resolvedInstallDirectory) `
        "Install directory was not created."
    Assert-Condition (
        Test-Path -LiteralPath (Join-Path $resolvedInstallDirectory "AmdMobilePower.exe")
    ) "Installed executable is missing."
    Assert-Condition (Test-Path -LiteralPath $startMenuShortcut) `
        "Start menu shortcut is missing."
    Assert-Condition (Test-Path -LiteralPath $uninstallKey) `
        "Current-user uninstall registry entry is missing."

    $registry = Get-ItemProperty -LiteralPath $uninstallKey
    Assert-Condition ($registry.InstallLocation -eq $resolvedInstallDirectory) `
        "Registry install location does not match the requested directory."
    Assert-Condition (
        $registry.UninstallString.Contains(
            $resolvedInstallDirectory,
            [StringComparison]::OrdinalIgnoreCase)
    ) "Registry uninstall command does not include the install directory."

    $taskQuery = Invoke-ScheduledTaskCommand -Arguments @(
        "/Query",
        "/TN", "AmdMobilePower"
    )
    $scheduledTaskVerified = $taskQuery.ExitCode -eq 0
    $startupFallbackExists = Test-Path -LiteralPath $startupShortcut
    if ($scheduledTaskVerified) {
        Assert-Condition (-not $startupFallbackExists) `
            "Startup shortcut exists even though the logon task was created."
    }
    else {
        Assert-Condition $startupFallbackExists `
            "Neither a logon task nor the Startup shortcut fallback is available."
    }

    $uninstallExitCode = Invoke-Uninstaller `
        -Path $uninstaller `
        -TargetDirectory $resolvedInstallDirectory
    Assert-Condition ($uninstallExitCode -eq 0) `
        "uninstall.ps1 returned exit code $uninstallExitCode."
    Wait-ForDirectoryRemoval -Path $resolvedInstallDirectory

    Assert-Condition (-not (Test-Path -LiteralPath $resolvedInstallDirectory)) `
        "Uninstall left the install directory behind."
    Assert-Condition (-not (Test-Path -LiteralPath $startMenuShortcut)) `
        "Uninstall left the Start menu shortcut behind."
    Assert-Condition (-not (Test-Path -LiteralPath $startupShortcut)) `
        "Uninstall left the Startup shortcut behind."
    Assert-Condition (-not (Test-Path -LiteralPath $uninstallKey)) `
        "Uninstall left the registry entry behind."

    if ($scheduledTaskVerified) {
        $taskAfterUninstall = Invoke-ScheduledTaskCommand -Arguments @(
            "/Query",
            "/TN", "AmdMobilePower"
        )
        Assert-Condition ($taskAfterUninstall.ExitCode -ne 0) `
            "Uninstall left the logon task behind."
    }

    [pscustomobject]@{
        Verification = "PASS"
        InstallDirectory = $resolvedInstallDirectory
        StartMenuShortcut = "Created and removed"
        UninstallEntry = "Created and removed"
        LogonBehavior = if ($scheduledTaskVerified) {
            "Scheduled task created and removed"
        }
        else {
            "Startup shortcut fallback created and removed"
        }
    } | Format-List
}
finally {
    $cleanupUninstaller = if (Test-Path -LiteralPath $uninstaller) {
        $uninstaller
    }
    else {
        Join-Path $root "packaging\uninstall.ps1"
    }

    if ((Test-Path -LiteralPath $resolvedInstallDirectory) -or
        (Test-Path -LiteralPath $startMenuShortcut) -or
        (Test-Path -LiteralPath $startupShortcut) -or
        (Test-Path -LiteralPath $uninstallKey)) {
        try {
            & $cleanupUninstaller -InstallDirectory $resolvedInstallDirectory | Out-Null
            Wait-ForDirectoryRemoval -Path $resolvedInstallDirectory
        }
        catch {
            Write-Warning "Shell integration cleanup failed: $($_.Exception.Message)"
        }
    }
}
