param(
    [string]$InstallDirectory = (
        Join-Path $env:LOCALAPPDATA "Programs\AmdMobilePowerNativePreview"
    ),
    [switch]$NoStartup,
    [switch]$NoShellIntegration,
    [switch]$NoLaunch
)

$ErrorActionPreference = "Stop"

$sourceDirectory = $PSCommandPath | Split-Path -Parent
$nativePreviewVersion = "0.4.0-native-preview.1"
$buildInfoPath = Join-Path $sourceDirectory "BUILD-INFO.txt"
if (Test-Path -LiteralPath $buildInfoPath) {
    foreach ($line in Get-Content -LiteralPath $buildInfoPath) {
        if ($line -match "^Version=(.+)$") {
            $nativePreviewVersion = $Matches[1].Trim()
            break
        }
    }
}

$guiExecutable = Join-Path $sourceDirectory "amd-mobile-power-gui.exe"
$workerExecutable = Join-Path $sourceDirectory "amdmobilepower_native_worker.exe"
if (-not (Test-Path -LiteralPath $guiExecutable) -or
    -not (Test-Path -LiteralPath $workerExecutable)) {
    throw "Run this script from an extracted native preview package."
}

$resolvedSource = [System.IO.Path]::GetFullPath($sourceDirectory)
$resolvedInstall = [System.IO.Path]::GetFullPath($InstallDirectory)
if ($resolvedInstall.Equals(
    $resolvedSource,
    [System.StringComparison]::OrdinalIgnoreCase)) {
    throw "InstallDirectory must differ from the package directory."
}

Get-Process `
    -Name "amd-mobile-power-gui", "amdmobilepower_native_worker" `
    -ErrorAction SilentlyContinue |
    Stop-Process -Force -ErrorAction SilentlyContinue

New-Item -ItemType Directory -Path $resolvedInstall -Force | Out-Null
Copy-Item `
    -Path (Join-Path $resolvedSource "*") `
    -Destination $resolvedInstall `
    -Recurse `
    -Force
"Native preview install marker" |
    Set-Content `
        -LiteralPath (Join-Path $resolvedInstall "NATIVE-PREVIEW-INSTALL.txt") `
        -Encoding ascii

$installedGui = Join-Path $resolvedInstall "amd-mobile-power-gui.exe"
$startMenuShortcut = $null
$startupShortcut = $null
$uninstallKey = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\AmdMobilePowerNativePreview"

if (-not $NoShellIntegration) {
    $shell = New-Object -ComObject WScript.Shell
    $programs = [Environment]::GetFolderPath("Programs")
    $startMenuDirectory = Join-Path $programs "AMD Mobile Power Native Preview"
    New-Item -ItemType Directory -Path $startMenuDirectory -Force | Out-Null
    $startMenuShortcut = Join-Path `
        $startMenuDirectory `
        "AMD Mobile Power Native Preview.lnk"
    $shortcut = $shell.CreateShortcut($startMenuShortcut)
    $shortcut.TargetPath = $installedGui
    $shortcut.WorkingDirectory = $resolvedInstall
    $shortcut.IconLocation = "$installedGui,0"
    $shortcut.Description = "AMD Mobile Power native preview"
    $shortcut.Save()

    $uninstallScript = Join-Path $resolvedInstall "uninstall-preview.ps1"
    New-Item -Path $uninstallKey -Force | Out-Null
    New-ItemProperty `
        -Path $uninstallKey `
        -Name "DisplayName" `
        -Value "AMD Mobile Power Native Preview" `
        -PropertyType String `
        -Force | Out-Null
    New-ItemProperty `
        -Path $uninstallKey `
        -Name "DisplayVersion" `
        -Value $nativePreviewVersion `
        -PropertyType String `
        -Force | Out-Null
    New-ItemProperty `
        -Path $uninstallKey `
        -Name "InstallLocation" `
        -Value $resolvedInstall `
        -PropertyType String `
        -Force | Out-Null
    New-ItemProperty `
        -Path $uninstallKey `
        -Name "UninstallString" `
        -Value "powershell.exe -NoProfile -ExecutionPolicy Bypass -File `"$uninstallScript`"" `
        -PropertyType String `
        -Force | Out-Null
}

if (-not $NoStartup) {
    $shell = New-Object -ComObject WScript.Shell
    $startup = [Environment]::GetFolderPath("Startup")
    $startupShortcut = Join-Path `
        $startup `
        "AMD Mobile Power Native Preview.lnk"
    $shortcut = $shell.CreateShortcut($startupShortcut)
    $shortcut.TargetPath = $installedGui
    $shortcut.Arguments = "--tray"
    $shortcut.WorkingDirectory = $resolvedInstall
    $shortcut.IconLocation = "$installedGui,0"
    $shortcut.Description = "Start AMD Mobile Power native preview in read-only mode"
    $shortcut.Save()
}

if (-not $NoLaunch) {
    Start-Process `
        -FilePath $installedGui `
        -WorkingDirectory $resolvedInstall
}

[pscustomobject]@{
    Version = $nativePreviewVersion
    InstallDirectory = $resolvedInstall
    StartMenuShortcut = $startMenuShortcut
    StartupShortcut = $startupShortcut
    Launched = (-not $NoLaunch)
} | Format-List
