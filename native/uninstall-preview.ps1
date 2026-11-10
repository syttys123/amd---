param(
    [string]$InstallDirectory = (
        Join-Path $env:LOCALAPPDATA "Programs\AmdMobilePowerNativePreview"
    ),
    [switch]$NoStartup,
    [switch]$NoShellIntegration
)

$ErrorActionPreference = "Stop"

$resolvedInstall = [System.IO.Path]::GetFullPath($InstallDirectory)
$marker = Join-Path $resolvedInstall "NATIVE-PREVIEW-INSTALL.txt"
if (-not (Test-Path -LiteralPath $marker)) {
    throw "Refusing to uninstall an unmarked directory: $resolvedInstall"
}

Get-Process `
    -Name "amd-mobile-power-gui", "amdmobilepower_native_worker" `
    -ErrorAction SilentlyContinue |
    Stop-Process -Force -ErrorAction SilentlyContinue

if (-not $NoShellIntegration) {
    $startMenuShortcut = Join-Path `
        ([Environment]::GetFolderPath("Programs")) `
        "AMD Mobile Power Native Preview\AMD Mobile Power Native Preview.lnk"
    if (Test-Path -LiteralPath $startMenuShortcut) {
        Remove-Item -LiteralPath $startMenuShortcut -Force
    }

    $startMenuDirectory = Split-Path -Parent $startMenuShortcut
    if ((Test-Path -LiteralPath $startMenuDirectory) -and
        -not (Get-ChildItem -LiteralPath $startMenuDirectory -Force)) {
        Remove-Item -LiteralPath $startMenuDirectory -Force
    }
}

if (-not $NoStartup) {
    $startupShortcut = Join-Path `
        ([Environment]::GetFolderPath("Startup")) `
        "AMD Mobile Power Native Preview.lnk"
    if (Test-Path -LiteralPath $startupShortcut) {
        Remove-Item -LiteralPath $startupShortcut -Force
    }
}

if (-not $NoShellIntegration) {
    $uninstallKey = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\AmdMobilePowerNativePreview"
    if (Test-Path -LiteralPath $uninstallKey) {
        Remove-Item -LiteralPath $uninstallKey -Recurse -Force
    }
}

Remove-Item -LiteralPath $resolvedInstall -Recurse -Force
Write-Output "Native preview uninstalled: $resolvedInstall"
