param(
    [string]$InstallDirectory = "$env:LOCALAPPDATA\Programs\AmdMobilePower",
    [switch]$RemoveUserData,
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

$resolvedInstallDirectory = [IO.Path]::GetFullPath($InstallDirectory).TrimEnd(
    [IO.Path]::DirectorySeparatorChar)
if ($resolvedInstallDirectory -eq [IO.Path]::GetPathRoot($resolvedInstallDirectory)) {
    throw "Refusing to uninstall from a filesystem root."
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

if (-not $NoShellIntegration) {
    $taskQuery = Invoke-ScheduledTaskCommand -Arguments @(
        "/Query",
        "/TN", "AmdMobilePower"
    )
    if ($taskQuery.ExitCode -eq 0) {
        $taskRemoval = Invoke-ScheduledTaskCommand -Arguments @(
            "/Delete",
            "/TN", "AmdMobilePower",
            "/F"
        )
        if ($taskRemoval.ExitCode -ne 0) {
            Write-Warning "Scheduled task removal failed; continuing with the remaining cleanup."
        }
    }

    $shortcutPath = Join-Path (
        [Environment]::GetFolderPath("ApplicationData")
    ) "Microsoft\Windows\Start Menu\Programs\AMD Mobile Power.lnk"
    Remove-Item -LiteralPath $shortcutPath -Force -ErrorAction SilentlyContinue

    $startupShortcut = Join-Path (
        [Environment]::GetFolderPath("Startup")
    ) "AMD Mobile Power.lnk"
    Remove-Item -LiteralPath $startupShortcut -Force -ErrorAction SilentlyContinue

    Remove-Item `
        -LiteralPath "HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\AmdMobilePower" `
        -Recurse `
        -Force `
        -ErrorAction SilentlyContinue
}

if ($RemoveUserData -and (Test-Path -LiteralPath "HKCU:\Software\AmdMobilePower")) {
    Remove-Item -LiteralPath "HKCU:\Software\AmdMobilePower" -Recurse -Force
}

$currentScript = [IO.Path]::GetFullPath($MyInvocation.MyCommand.Path)
$scriptRunsFromInstallDirectory = $currentScript.StartsWith(
    $resolvedInstallDirectory + [IO.Path]::DirectorySeparatorChar,
    [StringComparison]::OrdinalIgnoreCase)
if ($scriptRunsFromInstallDirectory) {
    $cleanupScript = Join-Path $env:TEMP "AmdMobilePower-Cleanup-$PID.ps1"
    @"
Start-Sleep -Seconds 2
Remove-Item -LiteralPath '$resolvedInstallDirectory' -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item -LiteralPath '$cleanupScript' -Force -ErrorAction SilentlyContinue
"@ | Set-Content -LiteralPath $cleanupScript -Encoding utf8
    Start-Process -FilePath "powershell.exe" `
        -ArgumentList "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$cleanupScript`"" `
        -WindowStyle Hidden
}
else {
    Remove-Item -LiteralPath $resolvedInstallDirectory -Recurse -Force -ErrorAction SilentlyContinue
}

if ($RemoveUserData) {
    $userData = Join-Path $env:LOCALAPPDATA "AmdMobilePower"
    if (Test-Path -LiteralPath $userData) {
        Remove-Item -LiteralPath $userData -Recurse -Force
    }
}

Write-Output "Uninstalled AMD Mobile Power from $resolvedInstallDirectory"
