param(
    [string]$PackageDirectory,
    [int]$Cycles = 3,
    [switch]$NoBuild
)

$ErrorActionPreference = "Stop"

$root = Split-Path -Parent $PSCommandPath
if (-not $NoBuild) {
    Push-Location $root
    try {
        dotnet build AmdMobilePower.sln -c Release
        if ($LASTEXITCODE -ne 0) {
            throw "Release build failed with exit code $LASTEXITCODE."
        }
    }
    finally {
        Pop-Location
    }
}

if (-not $PackageDirectory) {
    $package = Get-ChildItem `
        -LiteralPath (Join-Path $root "artifacts\packages") `
        -Directory `
        -Filter "amd-mobile-power-v*-win-x64-lite" `
        -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1
    if (-not $package) {
        throw "No portable package was found. Pass -PackageDirectory explicitly."
    }
    $PackageDirectory = $package.FullName
}

$packagePath = if ([IO.Path]::IsPathRooted($PackageDirectory)) {
    [IO.Path]::GetFullPath($PackageDirectory)
}
else {
    [IO.Path]::GetFullPath((Join-Path $root $PackageDirectory))
}
$executable = Join-Path $packagePath "AmdMobilePower.exe"
if (-not (Test-Path -LiteralPath $executable)) {
    throw "AmdMobilePower.exe was not found: $executable"
}

if (Get-Process -Name "AmdMobilePower" -ErrorAction SilentlyContinue) {
    throw "Refusing UI lifecycle verification while an AmdMobilePower GUI is already running."
}

if (-not ("AmdMobilePower.UiLifecycleNative" -as [type])) {
    Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;

namespace AmdMobilePower
{
    public static class UiLifecycleNative
    {
        [DllImport("user32.dll")]
        public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);

        [DllImport("user32.dll")]
        public static extern bool IsIconic(IntPtr hWnd);

        [DllImport("user32.dll")]
        public static extern bool IsWindowVisible(IntPtr hWnd);

        [DllImport("user32.dll")]
        public static extern IntPtr SendMessage(
            IntPtr hWnd,
            uint message,
            IntPtr wParam,
            IntPtr lParam);
    }
}
'@
}

function Assert-Condition {
    param(
        [bool]$Condition,
        [string]$Message
    )

    if (-not $Condition) {
        throw $Message
    }
}

function Assert-ProcessAlive {
    param(
        [System.Diagnostics.Process]$Process,
        [string]$Context
    )

    $Process.Refresh()
    if ($Process.HasExited) {
        throw "$Context exited unexpectedly with code $($Process.ExitCode)."
    }
}

function Wait-ForMainWindow {
    param(
        [System.Diagnostics.Process]$Process,
        [int]$TimeoutMilliseconds = 12000,
        [switch]$RequireVisible
    )

    $deadline = [DateTime]::UtcNow.AddMilliseconds($TimeoutMilliseconds)
    while ([DateTime]::UtcNow -lt $deadline) {
        Assert-ProcessAlive -Process $Process -Context "GUI"
        $Process.Refresh()
        $handle = $Process.MainWindowHandle
        if ($handle -ne [IntPtr]::Zero -and
            (-not $RequireVisible -or
             [AmdMobilePower.UiLifecycleNative]::IsWindowVisible($handle))) {
            return $handle
        }
        Start-Sleep -Milliseconds 150
    }
    throw "GUI main window did not become available within $TimeoutMilliseconds ms."
}

function Wait-ForHiddenWindow {
    param(
        [System.Diagnostics.Process]$Process,
        [IntPtr]$Handle,
        [int]$TimeoutMilliseconds = 5000
    )

    $deadline = [DateTime]::UtcNow.AddMilliseconds($TimeoutMilliseconds)
    while ([DateTime]::UtcNow -lt $deadline) {
        Assert-ProcessAlive -Process $Process -Context "GUI"
        if (-not [AmdMobilePower.UiLifecycleNative]::IsWindowVisible($Handle)) {
            return
        }
        Start-Sleep -Milliseconds 120
    }
    throw "GUI window remained visible after close-to-tray."
}

function Stop-ProcessTree {
    param([System.Diagnostics.Process]$Process)

    if ($null -eq $Process) {
        return
    }

    try {
        $Process.Refresh()
        if (-not $Process.HasExited) {
            $killTree = [System.Diagnostics.Process].GetMethod(
                "Kill",
                [Type[]]@([bool])
            )
            if ($killTree) {
                $Process.Kill($true)
            }
            else {
                Stop-Process -Id $Process.Id -Force -ErrorAction SilentlyContinue
            }
            $Process.WaitForExit(5000) | Out-Null
        }
    }
    catch {
    }
}

$startedAt = [DateTime]::Now
$first = $null
$second = $null
try {
    $first = Start-Process `
        -FilePath $executable `
        -WorkingDirectory $packagePath `
        -ArgumentList "--simple-mode" `
        -PassThru
    $handle = Wait-ForMainWindow -Process $first -RequireVisible

    for ($cycle = 1; $cycle -le $Cycles; $cycle++) {
        Assert-Condition (
            [AmdMobilePower.UiLifecycleNative]::ShowWindow($handle, 6)
        ) "SW_MINIMIZE failed on cycle $cycle."
        Start-Sleep -Milliseconds 350
        Assert-ProcessAlive -Process $first -Context "GUI after minimize"
        Assert-Condition (
            [AmdMobilePower.UiLifecycleNative]::IsIconic($handle)
        ) "Window was not minimized on cycle $cycle."
        Assert-Condition (
            [AmdMobilePower.UiLifecycleNative]::IsWindowVisible($handle)
        ) "Minimized window was hidden instead of remaining in the taskbar on cycle $cycle."

        Assert-Condition (
            [AmdMobilePower.UiLifecycleNative]::ShowWindow($handle, 9)
        ) "SW_RESTORE failed on cycle $cycle."
        Start-Sleep -Milliseconds 500
        Assert-ProcessAlive -Process $first -Context "GUI after restore"
        Assert-Condition (
            -not [AmdMobilePower.UiLifecycleNative]::IsIconic($handle)
        ) "Window remained minimized on cycle $cycle."
        Assert-Condition (
            [AmdMobilePower.UiLifecycleNative]::IsWindowVisible($handle)
        ) "Window remained hidden after restore on cycle $cycle."
    }

    [void][AmdMobilePower.UiLifecycleNative]::SendMessage(
        $handle,
        0x0010,
        [IntPtr]::Zero,
        [IntPtr]::Zero)
    Wait-ForHiddenWindow -Process $first -Handle $handle

    $second = Start-Process `
        -FilePath $executable `
        -WorkingDirectory $packagePath `
        -ArgumentList "--simple-mode" `
        -PassThru
    $restoredHandle = Wait-ForMainWindow `
        -Process $first `
        -TimeoutMilliseconds 12000 `
        -RequireVisible

    $secondDeadline = [DateTime]::UtcNow.AddSeconds(8)
    while (-not $second.HasExited -and [DateTime]::UtcNow -lt $secondDeadline) {
        Start-Sleep -Milliseconds 150
        $second.Refresh()
    }
    Assert-Condition $second.HasExited `
        "A second GUI instance remained running instead of waking the first instance."
    Assert-Condition (
        [AmdMobilePower.UiLifecycleNative]::IsWindowVisible($restoredHandle)
    ) "First GUI instance did not become visible after second-instance wake-up."
    Assert-Condition (
        -not [AmdMobilePower.UiLifecycleNative]::IsIconic($restoredHandle)
    ) "First GUI instance was restored in a minimized state."

    Start-Sleep -Seconds 1
    $newCrashes = @(
        Get-WinEvent `
            -FilterHashtable @{
                LogName = "Application"
                Id = 1000
                StartTime = $startedAt
            } `
            -ErrorAction SilentlyContinue |
            Where-Object { $_.Message -match "AmdMobilePower\.exe" }
    )
    Assert-Condition (
        $newCrashes.Count -eq 0
    ) "A new AmdMobilePower application crash was recorded during the lifecycle test."

    [pscustomobject]@{
        Verification = "PASS"
        PackageDirectory = $packagePath
        Cycles = $Cycles
        MinimizeRestore = "PASS"
        CloseToTray = "PASS"
        SecondInstanceWakeUp = "PASS"
        ApplicationCrashEvents = 0
    } | Format-List
}
finally {
    Stop-ProcessTree -Process $second
    Stop-ProcessTree -Process $first
}
