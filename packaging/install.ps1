param(
    [string]$InstallDirectory = "$env:LOCALAPPDATA\Programs\AmdMobilePower",
    [switch]$NoStartup,
    [switch]$NoLaunch,
    [switch]$NoShellIntegration
)

$ErrorActionPreference = "Stop"

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

$sourceDirectory = $PSScriptRoot.TrimEnd([IO.Path]::DirectorySeparatorChar)
$sourceExecutable = Join-Path $sourceDirectory "AmdMobilePower.exe"
if (-not (Test-Path -LiteralPath $sourceExecutable)) {
    throw "AmdMobilePower.exe was not found next to install.ps1."
}

$resolvedInstallDirectory = [IO.Path]::GetFullPath($InstallDirectory).TrimEnd(
    [IO.Path]::DirectorySeparatorChar)
$resolvedSourceDirectory = [IO.Path]::GetFullPath($sourceDirectory).TrimEnd(
    [IO.Path]::DirectorySeparatorChar)
if ($resolvedInstallDirectory -eq [IO.Path]::GetPathRoot($resolvedInstallDirectory) -or
    $resolvedInstallDirectory -eq $resolvedSourceDirectory) {
    throw "Refusing to install into the source directory or a filesystem root."
}
$installPathDepth = @(
    $resolvedInstallDirectory.Split(
        [IO.Path]::DirectorySeparatorChar,
        [StringSplitOptions]::RemoveEmptyEntries)
).Count
if ($installPathDepth -lt 3) {
    throw "InstallDirectory must contain at least two path segments below the drive root."
}

Get-Process -Name "AmdMobilePower", "AmdMobilePower.Worker" -ErrorAction SilentlyContinue |
    Where-Object {
        $_.Path -and $_.Path.StartsWith(
            $resolvedInstallDirectory + [IO.Path]::DirectorySeparatorChar,
            [StringComparison]::OrdinalIgnoreCase)
    } |
    Stop-Process -Force

if (Test-Path -LiteralPath $resolvedInstallDirectory) {
    Remove-Item -LiteralPath $resolvedInstallDirectory -Recurse -Force
}
New-Item -ItemType Directory -Path $resolvedInstallDirectory -Force | Out-Null
Copy-Item -Path (Join-Path $sourceDirectory "*") `
    -Destination $resolvedInstallDirectory `
    -Recurse `
    -Force

$installedExecutable = Join-Path $resolvedInstallDirectory "AmdMobilePower.exe"
$installedUninstaller = Join-Path $resolvedInstallDirectory "uninstall.ps1"
if (-not $NoShellIntegration) {
    $startMenuDirectory = Join-Path ([Environment]::GetFolderPath("ApplicationData")) `
        "Microsoft\Windows\Start Menu\Programs"
    $shortcutPath = Join-Path $startMenuDirectory "AMD Mobile Power.lnk"

    $shell = New-Object -ComObject WScript.Shell
    $shortcut = $shell.CreateShortcut($shortcutPath)
    $shortcut.TargetPath = $installedExecutable
    $shortcut.Arguments = "--tray"
    $shortcut.WorkingDirectory = $resolvedInstallDirectory
    $shortcut.IconLocation = "$installedExecutable,0"
    $shortcut.Description = "AMD Mobile Power"
    $shortcut.Save()

    if (-not $NoStartup) {
        $taskCommand = "`"$installedExecutable`" --tray"
        $taskRegistration = Invoke-ScheduledTaskCommand -Arguments @(
            "/Create",
            "/TN", "AmdMobilePower",
            "/SC", "ONLOGON",
            "/TR", $taskCommand,
            "/RL", "LIMITED",
            "/F"
        )
        if ($taskRegistration.ExitCode -ne 0) {
            Write-Warning "Scheduled task registration failed; using a Startup folder shortcut."
            $startupShortcut = Join-Path (
                [Environment]::GetFolderPath("Startup")
            ) "AMD Mobile Power.lnk"
            $shortcut = $shell.CreateShortcut($startupShortcut)
            $shortcut.TargetPath = $installedExecutable
            $shortcut.Arguments = "--tray"
            $shortcut.WorkingDirectory = $resolvedInstallDirectory
            $shortcut.IconLocation = "$installedExecutable,0"
            $shortcut.Save()
        }
    }

    $version = "0.1.0"
    $buildInfo = Join-Path $resolvedInstallDirectory "BUILD-INFO.txt"
    if (Test-Path -LiteralPath $buildInfo) {
        $versionLine = Get-Content -LiteralPath $buildInfo |
            Where-Object { $_ -like "Version=*" } |
            Select-Object -First 1
        if ($versionLine) {
            $version = $versionLine.Substring("Version=".Length).Trim()
        }
    }

    $uninstallKey = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\AmdMobilePower"
    New-Item -Path $uninstallKey -Force | Out-Null
    Set-ItemProperty -Path $uninstallKey -Name DisplayName -Value "AMD Mobile Power"
    Set-ItemProperty -Path $uninstallKey -Name DisplayVersion -Value $version
    Set-ItemProperty -Path $uninstallKey -Name InstallLocation -Value $resolvedInstallDirectory
    Set-ItemProperty -Path $uninstallKey -Name DisplayIcon -Value "$installedExecutable,0"
    Set-ItemProperty -Path $uninstallKey -Name Publisher -Value "AMD Mobile Power contributors"
    Set-ItemProperty -Path $uninstallKey -Name NoModify -Value 1 -Type DWord
    Set-ItemProperty -Path $uninstallKey -Name NoRepair -Value 1 -Type DWord
    Set-ItemProperty -Path $uninstallKey -Name UninstallString -Value (
        "powershell.exe -NoProfile -ExecutionPolicy Bypass -File `"$installedUninstaller`" " +
        "-InstallDirectory `"$resolvedInstallDirectory`""
    )
}

if (-not $NoLaunch) {
    Start-Process -FilePath $installedExecutable `
        -ArgumentList "--tray" `
        -WorkingDirectory $resolvedInstallDirectory
}

Write-Output "Installed AMD Mobile Power to $resolvedInstallDirectory"
