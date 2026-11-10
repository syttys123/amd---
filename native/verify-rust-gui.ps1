param(
    [switch]$NoBuild,
    [switch]$VerifyWorker,
    [switch]$VerifyWriteControls,
    [switch]$ExecuteNoChangePreset,
    [switch]$ExecutePolicySave,
    [string]$GuiExecutable,
    [string]$WorkerExecutable,
    [string]$PipeName,
    [string]$EvidencePath
)

$ErrorActionPreference = "Stop"
if ($ExecuteNoChangePreset) {
    $VerifyWriteControls = $true
    $VerifyWorker = $true
}
if ($ExecutePolicySave) {
    $VerifyWriteControls = $true
}

$root = Split-Path -Parent $PSCommandPath
$repositoryRoot = Split-Path -Parent $root
$manifest = Join-Path $root "rust-gui\Cargo.toml"
$executable = Join-Path $root "rust-gui\target\release\amd-mobile-power-gui.exe"
if ($GuiExecutable) {
    $executable = (Resolve-Path -LiteralPath $GuiExecutable).Path
}

$artifactsRoot = [System.IO.Path]::GetFullPath(
    (Join-Path $repositoryRoot "artifacts"))
$isolatedLocalAppData = [System.IO.Path]::GetFullPath(
    (Join-Path $artifactsRoot "native-build\rust-gui-state-$([Guid]::NewGuid().ToString('N'))"))
if (-not $isolatedLocalAppData.StartsWith(
    $artifactsRoot + [System.IO.Path]::DirectorySeparatorChar,
    [System.StringComparison]::OrdinalIgnoreCase)) {
    throw "Unsafe isolated LOCALAPPDATA path: $isolatedLocalAppData"
}
$previousLocalAppData = $env:LOCALAPPDATA
$env:LOCALAPPDATA = $isolatedLocalAppData

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
    public static extern IntPtr SendMessage(
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

    [DllImport("user32.dll")]
    public static extern IntPtr GetDlgItem(IntPtr hDlg, int nIDDlgItem);

    [DllImport("user32.dll", CharSet = CharSet.Unicode, EntryPoint = "SendMessageW")]
    public static extern IntPtr SendMessageText(
        IntPtr hWnd,
        uint msg,
        UIntPtr wParam,
        string lParam);
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
        if (-not [string]::IsNullOrWhiteSpace($value) -and
            $value.Length -gt $script:statusText.Length) {
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

function Get-GuiChildTexts {
    param(
        [IntPtr]$Window
    )

    $script:childTexts = [System.Collections.Generic.List[string]]::new()
    $callback = [AmdMobilePowerRustGuiNative+EnumChildProc]{
        param($child, $lparam)
        $text = New-Object System.Text.StringBuilder 8192
        [AmdMobilePowerRustGuiNative]::GetWindowText(
            $child,
            $text,
            $text.Capacity) | Out-Null
        $value = $text.ToString()
        if (-not [string]::IsNullOrWhiteSpace($value)) {
            $script:childTexts.Add($value)
        }
        return $true
    }
    [AmdMobilePowerRustGuiNative]::EnumChildWindows(
        $Window,
        $callback,
        [IntPtr]::Zero) | Out-Null
    return @($script:childTexts)
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
    if ($VerifyWriteControls) {
        $startArguments += "--enable-write-controls"
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
            if ($workerStatus -match "已连接 worker") {
                break
            }
            Start-Sleep -Milliseconds 200
        }
        if ($workerStatus -notmatch "已连接 worker") {
            throw "Rust GUI did not connect to the read-only worker: $workerStatus"
        }
        if ($workerStatus -notmatch "供电：" -or
            $workerStatus -notmatch "Fast 上限：") {
            throw "Rust GUI worker status is incomplete: $workerStatus"
        }
    }

    $writePresetResult = "Not requested"
    $presetEditingResult = "Not requested"
    if ($VerifyWriteControls) {
        $childTexts = @(Get-GuiChildTexts -Window $window)
        foreach ($required in @(
            "12 W",
            "25 W",
            "45 W",
            "应用",
            "快捷预设",
            "保存预设",
            "电池目标",
            "交流目标",
            "启用",
            "保存策略"
        )) {
            if ($childTexts -notcontains $required) {
                throw "Rust GUI write controls are missing '$required': $childTexts"
            }
        }

        if (-not $ExecuteNoChangePreset) {
            $editedPresets = @("11", "24", "43")
            for ($index = 0; $index -lt $editedPresets.Count; $index++) {
                $edit = [AmdMobilePowerRustGuiNative]::GetDlgItem(
                    $window,
                    301 + $index)
                if ($edit -eq [IntPtr]::Zero) {
                    throw "Rust GUI preset edit $($index + 1) was not found."
                }
                [AmdMobilePowerRustGuiNative]::SendMessageText(
                    $edit,
                    0x000C,
                    [UIntPtr]::Zero,
                    $editedPresets[$index]) | Out-Null
            }
            $savePresetButton = [AmdMobilePowerRustGuiNative]::GetDlgItem(
                $window,
                106)
            if ($savePresetButton -eq [IntPtr]::Zero) {
                throw "Rust GUI save-preset button was not found."
            }
            [AmdMobilePowerRustGuiNative]::SendMessage(
                $savePresetButton,
                0x00F5,
                [UIntPtr]106,
                [IntPtr]::Zero) | Out-Null
            $statePath = Join-Path `
                $isolatedLocalAppData `
                "AmdMobilePower\rust-ui-state.json"
            $presetSaved = $false
            $deadline = [DateTime]::UtcNow.AddSeconds(5)
            while ([DateTime]::UtcNow -lt $deadline) {
                $childTexts = @(Get-GuiChildTexts -Window $window)
                if ($childTexts -contains "11 W" -and
                    $childTexts -contains "24 W" -and
                    $childTexts -contains "43 W") {
                    $presetSaved = $true
                    break
                }
                Start-Sleep -Milliseconds 50
            }
            if (-not $presetSaved) {
                $stateText = if (Test-Path -LiteralPath $statePath) {
                    Get-Content -LiteralPath $statePath -Raw
                }
                else {
                    "<missing>"
                }
                throw "Rust GUI did not save and display edited presets: $childTexts`nState: $stateText"
            }
            $presetState = Get-Content -LiteralPath $statePath -Raw |
                ConvertFrom-Json
            if (($presetState.presets -join ",") -ne "11,24,43") {
                throw "Rust GUI preset state was not persisted: $($presetState | ConvertTo-Json -Depth 6)"
            }
            $presetEditingResult = "PASS"
        }

        if ($ExecutePolicySave) {
            Post-GuiMessage `
                -Window $window `
                -Message $wmCommand `
                -WParam 105
            $policySaved = $false
            $deadline = [DateTime]::UtcNow.AddSeconds(5)
            while ([DateTime]::UtcNow -lt $deadline) {
                if ((Get-GuiStatusText -Window $window) -match "自动策略已保存。") {
                    $policySaved = $true
                    break
                }
                Start-Sleep -Milliseconds 50
            }
            if (-not $policySaved) {
                throw "Rust GUI did not report a successful policy save."
            }
            if ($presetEditingResult -eq "PASS") {
                $statePath = Join-Path `
                    $isolatedLocalAppData `
                    "AmdMobilePower\rust-ui-state.json"
                $policyState = Get-Content -LiteralPath $statePath -Raw |
                    ConvertFrom-Json
                if (($policyState.presets -join ",") -ne "11,24,43") {
                    throw "Saving the power policy discarded edited presets: $($policyState | ConvertTo-Json -Depth 6)"
                }
            }
        }

        if ($ExecuteNoChangePreset) {
            if ($workerStatus -notmatch "供电：交流电" -or
                $workerStatus -notmatch "STAPM 上限：45\.00 W" -or
                $workerStatus -notmatch "Fast 上限：45\.00 W" -or
                $workerStatus -notmatch "Slow 上限：45\.00 W") {
                throw "No-change preset requires an AC 45/45/45 W starting state."
            }

            Post-GuiMessage `
                -Window $window `
                -Message $wmCommand `
                -WParam 103
            Post-GuiMessage `
                -Window $window `
                -Message $wmCommand `
                -WParam 104

            $deadline = [DateTime]::UtcNow.AddSeconds(10)
            $applied = $false
            while ([DateTime]::UtcNow -lt $deadline) {
                $childTexts = @(Get-GuiChildTexts -Window $window)
                if ($childTexts -contains "已应用 45 W / 45 W / 45 W。`n回读校验通过。") {
                    $applied = $true
                    break
                }
                if ($childTexts -match "应用失败") {
                    throw "Rust GUI preset apply failed: $childTexts"
                }
                Start-Sleep -Milliseconds 50
            }
            if (-not $applied) {
                throw "Rust GUI did not report a verified 45 W no-change preset."
            }
            $writePresetResult = "PASS"
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

    if ($EvidencePath) {
        $evidenceDirectory = Split-Path -Parent $EvidencePath
        if ($evidenceDirectory) {
            New-Item -ItemType Directory -Path $evidenceDirectory -Force | Out-Null
        }
        [pscustomobject]@{
            SourceCommit = (git -C $repositoryRoot rev-parse HEAD).Trim()
            Verification = "PASS"
            Path = "Rust GUI -> C++ worker -> RyzenAdj"
            Processor = if ($workerStatus -match "处理器：([^\r\n]+)") {
                $Matches[1].Trim()
            }
            else {
                $null
            }
            WorkerStatus = $workerStatus
            TargetWatts = if ($ExecuteNoChangePreset) { "45/45/45" } else { $null }
            WriteControls = if ($VerifyWriteControls) { "PASS" } else { "Not requested" }
            PresetEditing = $presetEditingResult
            WritePreset = $writePresetResult
            PolicySave = if ($ExecutePolicySave) { "PASS" } else { "Not requested" }
            RecordedAt = (Get-Date).ToString("o")
        } |
            ConvertTo-Json -Depth 8 |
            Set-Content -LiteralPath $EvidencePath -Encoding UTF8
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
        WriteControls = if ($VerifyWriteControls) { "PASS" } else { "Not requested" }
        PresetEditing = $presetEditingResult
        WritePreset = $writePresetResult
        PolicySave = if ($ExecutePolicySave) { "PASS" } else { "Not requested" }
        Evidence = if ($EvidencePath) { $EvidencePath } else { $null }
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
    $env:LOCALAPPDATA = $previousLocalAppData
    if (Test-Path -LiteralPath $isolatedLocalAppData) {
        Remove-Item -LiteralPath $isolatedLocalAppData -Recurse -Force
    }
}
