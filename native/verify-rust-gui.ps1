param(
    [switch]$NoBuild,
    [switch]$VerifyWorker,
    [string]$GuiExecutable,
    [string]$WorkerExecutable,
    [string]$PipeName
)

$ErrorActionPreference = "Stop"

$root = Split-Path -Parent $PSCommandPath
$repositoryRoot = Split-Path -Parent $root
$manifest = Join-Path $root "rust-gui\Cargo.toml"
$executable = Join-Path $root "rust-gui\target\release\amd-mobile-power-gui.exe"
if ($GuiExecutable) {
    $executable = (Resolve-Path -LiteralPath $GuiExecutable).Path
}

if (-not $NoBuild) {
    & cargo build `
        --manifest-path $manifest `
        --release `
        --locked `
        --offline
    if ($LASTEXITCODE -ne 0) {
        throw "Rust GUI build failed."
    }
}

if (-not (Test-Path -LiteralPath $executable)) {
    throw "Rust GUI executable was not built: $executable"
}

Add-Type @"
using System;
using System.Text;
using System.Runtime.InteropServices;

public static class AmdMobilePowerRustGuiNative {
    public delegate bool EnumChildProc(IntPtr hwnd, IntPtr lparam);

    [DllImport("user32.dll", SetLastError = true)]
    public static extern bool ShowWindowAsync(IntPtr hWnd, int nCmdShow);

    [DllImport("user32.dll")]
    public static extern bool IsWindowVisible(IntPtr hWnd);

    [DllImport("user32.dll")]
    public static extern bool IsIconic(IntPtr hWnd);

    [DllImport("user32.dll", SetLastError = true)]
    public static extern bool PostMessage(
        IntPtr hWnd,
        uint msg,
        UIntPtr wParam,
        IntPtr lParam);

    [DllImport("user32.dll")]
    public static extern bool EnumChildWindows(
        IntPtr parent,
        EnumChildProc callback,
        IntPtr lParam);

    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    public static extern int GetWindowText(
        IntPtr hWnd,
        StringBuilder text,
        int count);
}
"@

$wmCommand = 0x0111
$wmClose = 0x0010
$wmApp = 0x8000
$wmAppTray = $wmApp + 2
$wmLButtonUp = 0x0202
$swMinimize = 6
$swRestore = 9
$menuExit = 2

function Wait-ProcessWindow {
    param(
        [System.Diagnostics.Process]$Process,
        [int]$TimeoutMilliseconds = 8000
    )

    $deadline = [DateTime]::UtcNow.AddMilliseconds($TimeoutMilliseconds)
    while ([DateTime]::UtcNow -lt $deadline) {
        $Process.Refresh()
        if ($Process.HasExited) {
            throw "Rust GUI exited before creating a window."
        }
        if ($Process.MainWindowHandle -ne [IntPtr]::Zero) {
            return $Process.MainWindowHandle
        }
        Start-Sleep -Milliseconds 50
    }
    throw "Rust GUI did not create a window in time."
}

function Wait-Until {
    param(
        [scriptblock]$Condition,
        [string]$Description,
        [int]$TimeoutMilliseconds = 5000
    )

    $deadline = [DateTime]::UtcNow.AddMilliseconds($TimeoutMilliseconds)
    while ([DateTime]::UtcNow -lt $deadline) {
        if (& $Condition) {
            return
        }
        Start-Sleep -Milliseconds 50
    }
    throw "Timed out waiting for: $Description"
}

function Post-GuiMessage {
    param(
        [IntPtr]$Window,
        [uint32]$Message,
        [uint64]$WParam = 0,
        [int64]$LParam = 0
    )

    $posted = [AmdMobilePowerRustGuiNative]::PostMessage(
        $Window,
        $Message,
        [UIntPtr]$WParam,
        [IntPtr]$LParam)
    if (-not $posted) {
        throw "PostMessage failed for 0x$($Message.ToString('X4'))."
    }
}

function Get-GuiStatusText {
    param(
        [IntPtr]$Window
    )

    $script:statusText = ""
    $callback = [AmdMobilePowerRustGuiNative+EnumChildProc]{
        param($child, $lparam)
        $text = New-Object System.Text.StringBuilder 8192
        [AmdMobilePowerRustGuiNative]::GetWindowText(
            $child,
            $text,
            $text.Capacity) | Out-Null
        $value = $text.ToString()
        if (-not [string]::IsNullOrWhiteSpace($value)) {
            $script:statusText = $value
        }
        return $true
    }
    [AmdMobilePowerRustGuiNative]::EnumChildWindows(
        $Window,
        $callback,
        [IntPtr]::Zero) | Out-Null
    return $script:statusText
}

$firstProcess = $null
$secondProcess = $null
$existingWorkerIds = @(
    Get-Process `
        -Name "amdmobilepower_native_worker" `
        -ErrorAction SilentlyContinue |
        Select-Object -ExpandProperty Id
)
try {
    Get-Process `
        -Name "amd-mobile-power-gui" `
        -ErrorAction SilentlyContinue |
        Stop-Process -Force

    $startArguments = @()
    if ($PipeName) {
        $startArguments += @("--pipe-name", $PipeName)
    }
    if (-not $WorkerExecutable -and $VerifyWorker) {
        $adjacentWorker = Join-Path `
            (Split-Path -Parent $executable) `
            "amdmobilepower_native_worker.exe"
        $WorkerExecutable = if (Test-Path -LiteralPath $adjacentWorker) {
            $adjacentWorker
        }
        else {
            Join-Path `
                $repositoryRoot `
                "artifacts\native-build\worker-runtime\amdmobilepower_native_worker.exe"
        }
    }
    if ($WorkerExecutable) {
        $startArguments += @("--worker-executable", $WorkerExecutable)
    }

    $firstProcess = Start-Process `
        -FilePath $executable `
        -WorkingDirectory (Split-Path -Parent $executable) `
        -ArgumentList $startArguments `
        -PassThru
    $window = Wait-ProcessWindow -Process $firstProcess
    if ($firstProcess.MainWindowTitle -notlike "AMD Mobile Power*") {
        throw "Unexpected Rust GUI window title: $($firstProcess.MainWindowTitle)"
    }

    $workerStatus = ""
    if ($VerifyWorker) {
        if (-not (Test-Path -LiteralPath $WorkerExecutable)) {
            throw "Worker executable was not found: $WorkerExecutable"
        }
        $deadline = [DateTime]::UtcNow.AddSeconds(15)
        while ([DateTime]::UtcNow -lt $deadline) {
            $workerStatus = Get-GuiStatusText -Window $window
            if ($workerStatus -match "Worker: connected") {
                break
            }
            Start-Sleep -Milliseconds 200
        }
        if ($workerStatus -notmatch "Worker: connected") {
            throw "Rust GUI did not connect to the read-only worker: $workerStatus"
        }
        if ($workerStatus -notmatch "Power source:" -or
            $workerStatus -notmatch "Fast limit:") {
            throw "Rust GUI worker status is incomplete: $workerStatus"
        }
    }

    for ($cycle = 1; $cycle -le 3; $cycle++) {
        Post-GuiMessage `
            -Window $window `
            -Message 0x0112 `
            -WParam 0xF020
        Wait-Until `
            -Description "minimize cycle $cycle" `
            -Condition {
                [AmdMobilePowerRustGuiNative]::IsIconic($window)
            }

        if (-not [AmdMobilePowerRustGuiNative]::ShowWindowAsync(
            $window, $swRestore)) {
            throw "ShowWindowAsync(SW_RESTORE) failed in cycle $cycle."
        }
        Wait-Until `
            -Description "restore cycle $cycle" `
            -Condition {
                (-not [AmdMobilePowerRustGuiNative]::IsIconic($window)) -and
                [AmdMobilePowerRustGuiNative]::IsWindowVisible($window)
            }
    }

    Post-GuiMessage -Window $window -Message $wmClose
    Wait-Until `
        -Description "close-to-tray" `
        -Condition {
            -not [AmdMobilePowerRustGuiNative]::IsWindowVisible($window)
        }
    $firstProcess.Refresh()
    if ($firstProcess.HasExited) {
        throw "Close request terminated the Rust GUI instead of hiding to tray."
    }

    Post-GuiMessage `
        -Window $window `
        -Message $wmAppTray `
        -LParam $wmLButtonUp
    Wait-Until `
        -Description "tray restore" `
        -Condition {
            [AmdMobilePowerRustGuiNative]::IsWindowVisible($window)
        }

    Post-GuiMessage -Window $window -Message $wmClose
    Wait-Until `
        -Description "hidden before second instance" `
        -Condition {
            -not [AmdMobilePowerRustGuiNative]::IsWindowVisible($window)
        }

    $secondProcess = Start-Process `
        -FilePath $executable `
        -WorkingDirectory (Split-Path -Parent $executable) `
        -ArgumentList $startArguments `
        -PassThru
    if (-not $secondProcess.WaitForExit(5000)) {
        throw "Second Rust GUI instance did not exit."
    }
    Wait-Until `
        -Description "second-instance wake" `
        -Condition {
            [AmdMobilePowerRustGuiNative]::IsWindowVisible($window)
        }

    Post-GuiMessage `
        -Window $window `
        -Message $wmCommand `
        -WParam $menuExit
    if (-not $firstProcess.WaitForExit(5000)) {
        throw "Rust GUI did not exit after the explicit Exit command."
    }
    if ($firstProcess.ExitCode -ne 0) {
        throw "Rust GUI exited with code $($firstProcess.ExitCode)."
    }

    [pscustomobject]@{
        Verification = "PASS"
        Executable = $executable
        MinimizeRestoreCycles = 3
        CloseToTray = "PASS"
        TrayRestore = "PASS"
        SingleInstanceWake = "PASS"
        WorkerReadOnly = if ($VerifyWorker) { "PASS" } else { "Not requested" }
        WorkerStatus = if ($VerifyWorker) { $workerStatus } else { $null }
        ExplicitExit = "PASS"
        ExitCode = $firstProcess.ExitCode
    } | Format-List
}
finally {
    try {
        $currentWorkerProcesses = @(
            Get-Process `
                -Name "amdmobilepower_native_worker" `
                -ErrorAction SilentlyContinue
        )
        foreach ($workerProcess in $currentWorkerProcesses) {
            if ($existingWorkerIds -notcontains $workerProcess.Id) {
                Stop-Process -Id $workerProcess.Id -Force -ErrorAction SilentlyContinue
            }
        }
    }
    catch {
    }
    foreach ($process in @($secondProcess, $firstProcess)) {
        if ($null -ne $process) {
            try {
                $process.Refresh()
                if (-not $process.HasExited) {
                    $process.Kill($true)
                    $process.WaitForExit(5000) | Out-Null
                }
            }
            catch {
            }
            $process.Dispose()
        }
    }
}
