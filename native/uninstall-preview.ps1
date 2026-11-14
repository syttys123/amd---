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

function Stop-ProcessesUnderInstallDirectory {
    param([Parameter(Mandatory = $true)][string]$Root)

    $prefix = [System.IO.Path]::GetFullPath($Root).TrimEnd(
        [System.IO.Path]::DirectorySeparatorChar,
        [System.IO.Path]::AltDirectorySeparatorChar) +
        [System.IO.Path]::DirectorySeparatorChar
    Get-CimInstance `
        -ClassName Win32_Process `
        -Filter "Name='amd-mobile-power-gui.exe' OR Name='amdmobilepower_native_worker.exe'" `
        -ErrorAction SilentlyContinue |
        ForEach-Object {
            $candidate = $_.ExecutablePath
            if ([string]::IsNullOrWhiteSpace($candidate)) {
                return
            }
            $candidate = [System.IO.Path]::GetFullPath($candidate)
            if ($candidate.StartsWith(
                $prefix,
                [System.StringComparison]::OrdinalIgnoreCase)) {
                Stop-Process `
                    -Id ([int]$_.ProcessId) `
                    -Force `
                    -ErrorAction SilentlyContinue
            }
        }
}

Stop-ProcessesUnderInstallDirectory -Root $resolvedInstall

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
