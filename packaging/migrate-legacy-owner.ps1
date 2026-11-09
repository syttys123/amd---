param(
    [switch]$Apply,
    [string]$TaskName = "RyzenAdjWatch",
    [string]$TaskPath = "\AMD\",
    [string]$StartupShortcutName = "Ryzen Power.lnk"
)

$ErrorActionPreference = "Stop"

$task = Get-ScheduledTask -TaskName $TaskName -TaskPath $TaskPath -ErrorAction Stop
$legacyMutexPresent = $false
try {
    $mutex = [Threading.Mutex]::OpenExisting("Local\RyzenAdjPowerWorker")
    $mutex.Dispose()
    $legacyMutexPresent = $true
}
catch [Threading.WaitHandleCannotBeOpenedException] {
}

$startupDirectory = [Environment]::GetFolderPath("Startup")
$startupShortcut = Join-Path $startupDirectory $StartupShortcutName
$disabledStartupShortcut = "$startupShortcut.disabled"

Write-Output "Legacy task: $TaskPath$TaskName"
Write-Output "Task state: $($task.State)"
Write-Output "Legacy worker mutex present: $legacyMutexPresent"
Write-Output "Legacy startup shortcut present: $(Test-Path -LiteralPath $startupShortcut)"

if (-not $Apply) {
    Write-Output ""
    Write-Output "Preview only. With -Apply this script will:"
    Write-Output "1. Disable the legacy logon task."
    Write-Output "2. Stop the currently running task."
    Write-Output "3. Disable the legacy Startup-folder shortcut without deleting it."
    Write-Output "4. Leave C:\RyzenAdj files and configuration unchanged."
    Write-Output "5. Require a Windows reboot to release any hidden task child and SMU state."
    return
}

$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = [Security.Principal.WindowsPrincipal]::new($identity)
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw "Run this script from an elevated PowerShell session."
}

Disable-ScheduledTask -TaskName $TaskName -TaskPath $TaskPath | Out-Null
if ($task.State -eq "Running") {
    Stop-ScheduledTask -TaskName $TaskName -TaskPath $TaskPath
}

if (Test-Path -LiteralPath $startupShortcut) {
    if (Test-Path -LiteralPath $disabledStartupShortcut) {
        throw "Disabled shortcut already exists: $disabledStartupShortcut"
    }

    Move-Item `
        -LiteralPath $startupShortcut `
        -Destination $disabledStartupShortcut
}

$updatedTask = Get-ScheduledTask -TaskName $TaskName -TaskPath $TaskPath -ErrorAction Stop
Write-Output "Updated task state: $($updatedTask.State)"
Write-Output "Legacy startup shortcut disabled: $(Test-Path -LiteralPath $disabledStartupShortcut)"
Write-Output "Reboot Windows before starting the AMD Mobile Power worker."
