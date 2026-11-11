param(
    [switch]$NoBuild,
    [switch]$VerifyWorker,
    [switch]$VerifyWriteControls,
    [switch]$ExecuteNoChangePreset,
    [switch]$ExecutePolicySave,
    [ValidateSet("worker-offline", "firmware-clamp", "unsupported-platform", "long-error", "high-contrast")]
    [string]$UiFixture,
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
    public static extern bool IsWindowEnabled(IntPtr hWnd);

    [DllImport("user32.dll")]
    public static extern bool IsIconic(IntPtr hWnd);

    [DllImport("user32.dll")]
    public static extern IntPtr GetWindowLongPtr(IntPtr hWnd, int nIndex);

    [DllImport("user32.dll")]
    public static extern bool GetWindowRect(IntPtr hWnd, out RECT rect);

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

    public struct RECT {
        public int Left;
        public int Top;
        public int Right;
        public int Bottom;
    }
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
$gwlExStyle = -20
$wsExTopMost = 0x00000008

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

function Get-ControlText {
    param(
        [IntPtr]$Window,
        [int]$ControlId
    )

    $control = [AmdMobilePowerRustGuiNative]::GetDlgItem(
        $Window,
        $ControlId)
    if ($control -eq [IntPtr]::Zero) {
        return ""
    }
    $text = New-Object System.Text.StringBuilder 1024
    [AmdMobilePowerRustGuiNative]::GetWindowText(
        $control,
        $text,
        $text.Capacity) | Out-Null
    return $text.ToString()
}

function Export-GuiDiagnostics {
    param(
        [IntPtr]$Window,
        [string]$LocalAppDataRoot
    )

    $exportButton = [AmdMobilePowerRustGuiNative]::GetDlgItem(
        $Window,
        107)
    if ($exportButton -eq [IntPtr]::Zero -or
        -not [AmdMobilePowerRustGuiNative]::IsWindowEnabled($exportButton)) {
        throw "Rust GUI diagnostics export button is not usable."
    }
    [AmdMobilePowerRustGuiNative]::SendMessage(
        $exportButton,
        0x00F5,
        [UIntPtr]107,
        [IntPtr]::Zero) | Out-Null

    $diagnosticsDirectory = Join-Path `
        $LocalAppDataRoot `
        "AmdMobilePower\diagnostics"
    $diagnosticsPath = $null
    Wait-Until `
        -Description "diagnostics export" `
        -Condition {
            $script:diagnosticsPath = Get-ChildItem `
                -LiteralPath $diagnosticsDirectory `
                -Filter "native-gui-diagnostics-*.json" `
                -ErrorAction SilentlyContinue |
                Sort-Object LastWriteTimeUtc -Descending |
                Select-Object -First 1 -ExpandProperty FullName
            [bool]$script:diagnosticsPath
        }
    $diagnosticsPath = $script:diagnosticsPath
    return [pscustomobject]@{
        Path = $diagnosticsPath
        Document = Get-Content -LiteralPath $diagnosticsPath -Raw |
            ConvertFrom-Json
    }
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
    if ($UiFixture) {
        $startArguments += @("--ui-fixture", $UiFixture)
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
        if ($workerStatus -notmatch "已连接 worker ·" -or
            $workerStatus -notmatch "STAPM / Fast / Slow 上限" -or
            $workerStatus -notmatch "目标功耗：") {
            throw "Rust GUI worker status is incomplete: $workerStatus"
        }
    }

    $diagnosticsExportResult = "Not requested"
    $taskbarIconAvailable = $null
    $trayIconId = $null
    $initialUiMode = $null
    $finalUiMode = $null
    if ($VerifyWorker) {
        $exportButton = [AmdMobilePowerRustGuiNative]::GetDlgItem(
            $window,
            107)
        if ($exportButton -eq [IntPtr]::Zero) {
            throw "Rust GUI diagnostics export button was not found."
        }
        [AmdMobilePowerRustGuiNative]::SendMessage(
            $exportButton,
            0x00F5,
            [UIntPtr]107,
            [IntPtr]::Zero) | Out-Null

        $diagnosticsDirectory = Join-Path `
            $isolatedLocalAppData `
            "AmdMobilePower\diagnostics"
        $diagnosticsPath = $null
        $deadline = [DateTime]::UtcNow.AddSeconds(5)
        while ([DateTime]::UtcNow -lt $deadline) {
            $diagnosticsPath = Get-ChildItem `
                -LiteralPath $diagnosticsDirectory `
                -Filter "native-gui-diagnostics-*.json" `
                -ErrorAction SilentlyContinue |
                Sort-Object LastWriteTimeUtc -Descending |
                Select-Object -First 1 -ExpandProperty FullName
            if ($diagnosticsPath) {
                break
            }
            Start-Sleep -Milliseconds 50
        }
        if (-not $diagnosticsPath) {
            throw "Rust GUI did not write a diagnostics JSON file."
        }
        $diagnosticsText = Get-Content -LiteralPath $diagnosticsPath -Raw
        $diagnostics = $diagnosticsText | ConvertFrom-Json
        if ($diagnostics.schemaVersion -ne 1 -or
            $diagnostics.product -ne "AMD Mobile Power native preview" -or
            $diagnostics.privacy.containsLocalPaths -ne $false -or
            $diagnostics.privacy.containsProcessIds -ne $false -or
            $diagnostics.privacy.uploaded -ne $false -or
            $diagnostics.snapshot.platform.cpu.processorName -notmatch "^AMD Ryzen") {
            throw "Rust GUI diagnostics report is incomplete: $diagnosticsText"
        }
        if ($diagnosticsText.Contains($isolatedLocalAppData) -or
            $diagnosticsText -match "\\\\\.\\pipe\\") {
            throw "Rust GUI diagnostics report leaked a local path or pipe name."
        }
        if ($diagnostics.ui.taskbarIconAvailable -ne $true -or
            $diagnostics.ui.trayIconId -ne 1 -or
            $diagnostics.ui.mode -notin @("simple", "advanced")) {
            throw "Rust GUI diagnostics report does not describe the window icon/mode."
        }
        $taskbarIconAvailable = [bool]$diagnostics.ui.taskbarIconAvailable
        $trayIconId = [int]$diagnostics.ui.trayIconId
        $initialUiMode = [string]$diagnostics.ui.mode
        $diagnosticsExportResult = "PASS"
    }

    $viewModeResult = "Not requested"
    $topMostResult = "Not requested"
    $simpleButton = [AmdMobilePowerRustGuiNative]::GetDlgItem(
            $window,
            108)
        $advancedButton = [AmdMobilePowerRustGuiNative]::GetDlgItem(
            $window,
            109)
        $topMostButton = [AmdMobilePowerRustGuiNative]::GetDlgItem(
            $window,
            110)
        if ($simpleButton -eq [IntPtr]::Zero -or
            $advancedButton -eq [IntPtr]::Zero -or
            $topMostButton -eq [IntPtr]::Zero) {
            throw "Rust GUI mode or topmost controls are missing."
        }

        $initialRect = New-Object AmdMobilePowerRustGuiNative+RECT
        [AmdMobilePowerRustGuiNative]::GetWindowRect(
            $window,
            [ref]$initialRect) | Out-Null
        $initialHeight = $initialRect.Bottom - $initialRect.Top

        [AmdMobilePowerRustGuiNative]::SendMessage(
            $advancedButton,
            0x00F5,
            [UIntPtr]109,
            [IntPtr]::Zero) | Out-Null
        Wait-Until `
            -Description "advanced initial layout" `
            -Condition {
                $rect = New-Object AmdMobilePowerRustGuiNative+RECT
                [AmdMobilePowerRustGuiNative]::GetWindowRect(
                    $window,
                    [ref]$rect) | Out-Null
                ($rect.Bottom - $rect.Top) -gt $initialHeight
            }
        $advancedRect = New-Object AmdMobilePowerRustGuiNative+RECT
        [AmdMobilePowerRustGuiNative]::GetWindowRect(
            $window,
            [ref]$advancedRect) | Out-Null
        $advancedHeight = $advancedRect.Bottom - $advancedRect.Top

        [AmdMobilePowerRustGuiNative]::SendMessage(
            $simpleButton,
            0x00F5,
            [UIntPtr]108,
            [IntPtr]::Zero) | Out-Null
        Wait-Until `
            -Description "simple mode resize" `
            -Condition {
                $rect = New-Object AmdMobilePowerRustGuiNative+RECT
                [AmdMobilePowerRustGuiNative]::GetWindowRect(
                    $window,
                    [ref]$rect) | Out-Null
                ($rect.Bottom - $rect.Top) -lt $advancedHeight
            }
        if ($VerifyWriteControls) {
            $presetEdit = [AmdMobilePowerRustGuiNative]::GetDlgItem(
                $window,
                301)
            $presetButton = [AmdMobilePowerRustGuiNative]::GetDlgItem(
                $window,
                101)
            if ([AmdMobilePowerRustGuiNative]::IsWindowVisible($presetEdit) -or
                -not [AmdMobilePowerRustGuiNative]::IsWindowVisible($presetButton)) {
                throw "Simple mode did not hide advanced fields and keep quick presets."
            }
            foreach ($advancedControl in @(
                104,
                105,
                106,
                302,
                303,
                310,
                311,
                312,
                313,
                314,
                315,
                318,
                370
            )) {
                $control = [AmdMobilePowerRustGuiNative]::GetDlgItem(
                    $window,
                    $advancedControl)
                if ([AmdMobilePowerRustGuiNative]::IsWindowVisible($control)) {
                    throw "Simple mode left advanced control $advancedControl visible."
                }
            }
        }
        if ($VerifyWorker) {
            $deadline = [DateTime]::UtcNow.AddSeconds(4)
            $metricTitles = @()
            while ([DateTime]::UtcNow -lt $deadline) {
                $metricTitles = @(
                    Get-ControlText -Window $window -ControlId 330
                    Get-ControlText -Window $window -ControlId 331
                    Get-ControlText -Window $window -ControlId 332
                    Get-ControlText -Window $window -ControlId 333
                )
                if (($metricTitles -join "|") -eq "STAPM|PPT Fast|PPT Slow|CPU 温度") {
                    break
                }
                Start-Sleep -Milliseconds 50
            }
            if (($metricTitles -join "|") -ne "STAPM|PPT Fast|PPT Slow|CPU 温度") {
                throw "Simple mode telemetry matrix is incomplete: $($metricTitles -join '|')"
            }
            $deviceLabel = [AmdMobilePowerRustGuiNative]::GetDlgItem(
                $window,
                370)
            if ([AmdMobilePowerRustGuiNative]::IsWindowVisible($deviceLabel)) {
                throw "Simple mode left advanced device details visible."
            }
        }

        [AmdMobilePowerRustGuiNative]::SendMessage(
            $topMostButton,
            0x00F5,
            [UIntPtr]110,
            [IntPtr]::Zero) | Out-Null
        $extendedStyle = [AmdMobilePowerRustGuiNative]::GetWindowLongPtr(
            $window,
            $gwlExStyle).ToInt64()
        if (($extendedStyle -band $wsExTopMost) -eq 0) {
            throw "Rust GUI topmost toggle did not set WS_EX_TOPMOST."
        }

        [AmdMobilePowerRustGuiNative]::SendMessage(
            $advancedButton,
            0x00F5,
            [UIntPtr]109,
            [IntPtr]::Zero) | Out-Null
        Wait-Until `
            -Description "advanced mode resize" `
            -Condition {
                $rect = New-Object AmdMobilePowerRustGuiNative+RECT
                [AmdMobilePowerRustGuiNative]::GetWindowRect(
                    $window,
                    [ref]$rect) | Out-Null
                ($rect.Bottom - $rect.Top) -ge $advancedHeight
            }
        if ($VerifyWriteControls) {
            foreach ($advancedControl in @(
                105,
                106,
                301,
                302,
                303,
                310,
                311,
                312,
                313,
                314,
                315,
                318,
                370
            )) {
                $control = [AmdMobilePowerRustGuiNative]::GetDlgItem(
                    $window,
                    $advancedControl)
                if (-not [AmdMobilePowerRustGuiNative]::IsWindowVisible($control)) {
                    throw "Advanced mode did not restore control $advancedControl."
                }
            }
        }

        $windowStatePath = Join-Path `
            $isolatedLocalAppData `
            "AmdMobilePower\rust-ui-state.json"
        $windowState = Get-Content -LiteralPath $windowStatePath -Raw |
            ConvertFrom-Json
        if ($windowState.mode -ne "advanced" -or
            $windowState.topMost -ne $true) {
            throw "Window preferences were not persisted: $($windowState | ConvertTo-Json -Depth 6)"
        }
        $finalUiMode = [string]$windowState.mode
        if ($initialUiMode -and ($initialUiMode -ne "simple" -or $finalUiMode -ne "advanced")) {
            throw "Packaged mode synchronization did not move from simple to advanced."
        }
    $viewModeResult = "PASS"
    $topMostResult = "PASS"

    $writePresetResult = "Not requested"
    $presetEditingResult = "Not requested"
    $batteryOnlyToggleResult = "Not requested"
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
            "外接目标",
            "启用",
            "仅电池",
            "保存策略"
        )) {
            if ($childTexts -notcontains $required) {
                throw "Rust GUI write controls are missing '$required': $childTexts"
            }
        }

        Wait-Until `
            -Description "battery-only policy toggle to become usable" `
            -Condition {
                $control = [AmdMobilePowerRustGuiNative]::GetDlgItem(
                    $window,
                    318)
                $control -ne [IntPtr]::Zero -and
                    [AmdMobilePowerRustGuiNative]::IsWindowVisible($control) -and
                    [AmdMobilePowerRustGuiNative]::IsWindowEnabled($control) -and
                    (Get-ControlText -Window $window -ControlId 318) -eq "仅电池"
            }
        $batteryOnlyButton = [AmdMobilePowerRustGuiNative]::GetDlgItem(
            $window,
            318)
        $batteryOnlyText = Get-ControlText -Window $window -ControlId 318
        if ($batteryOnlyText -ne "仅电池") {
            throw "Rust GUI battery-only policy toggle is not usable: '$batteryOnlyText'."
        }
        Wait-Until `
            -Description "policy enable toggle to become usable" `
            -Condition {
                $control = [AmdMobilePowerRustGuiNative]::GetDlgItem(
                    $window,
                    315)
                $control -ne [IntPtr]::Zero -and
                    [AmdMobilePowerRustGuiNative]::IsWindowEnabled($control)
            }
        $policyEnabledButton = [AmdMobilePowerRustGuiNative]::GetDlgItem($window, 315)

        $before = Export-GuiDiagnostics `
            -Window $window `
            -LocalAppDataRoot $isolatedLocalAppData
        if ($before.Document.ui.mode -ne "advanced" -or
            $before.Document.ui.topMost -ne $true -or
            $before.Document.ui.taskbarIconAvailable -ne $true -or
            $before.Document.ui.trayIconId -ne 1 -or
            [bool]$before.Document.ui.highContrast -ne ($UiFixture -eq "high-contrast") -or
            [bool]$before.Document.ui.batteryOnly -or
            [bool]$before.Document.ui.policyEnabled) {
            throw "Unexpected native UI mode, contrast, icon, or policy state."
        }

        [AmdMobilePowerRustGuiNative]::SendMessage(
            $batteryOnlyButton,
            0x00F5,
            [UIntPtr]318,
            [IntPtr]::Zero) | Out-Null
        Start-Sleep -Milliseconds 150
        $batteryOnlyOn = Export-GuiDiagnostics `
            -Window $window `
            -LocalAppDataRoot $isolatedLocalAppData
        if (-not [bool]$batteryOnlyOn.Document.ui.batteryOnly) {
            throw "Battery-only toggle was not reflected in diagnostics."
        }

        [AmdMobilePowerRustGuiNative]::SendMessage(
            $policyEnabledButton,
            0x00F5,
            [UIntPtr]315,
            [IntPtr]::Zero) | Out-Null
        Start-Sleep -Milliseconds 150
        $policyEnabled = Export-GuiDiagnostics `
            -Window $window `
            -LocalAppDataRoot $isolatedLocalAppData
        if (-not [bool]$policyEnabled.Document.ui.batteryOnly -or
            -not [bool]$policyEnabled.Document.ui.policyEnabled) {
            throw "Policy toggles were not reflected together in diagnostics."
        }

        [AmdMobilePowerRustGuiNative]::SendMessage(
            $batteryOnlyButton, 0x00F5, [UIntPtr]318, [IntPtr]::Zero) | Out-Null
        [AmdMobilePowerRustGuiNative]::SendMessage(
            $policyEnabledButton, 0x00F5, [UIntPtr]315, [IntPtr]::Zero) | Out-Null
        Start-Sleep -Milliseconds 150
        $restored = Export-GuiDiagnostics `
            -Window $window `
            -LocalAppDataRoot $isolatedLocalAppData
        if ([bool]$restored.Document.ui.batteryOnly -or
            [bool]$restored.Document.ui.policyEnabled) {
            throw "Native UI policy toggles did not return to the default state."
        }
        $batteryOnlyToggleResult = "PASS"

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
            Processor = if ($workerStatus -match "worker · [^\r\n]+\r?\n([^\r\n]+)") {
                $Matches[1].Trim()
            }
            elseif ($workerStatus -match "处理器：([^\r\n]+)") {
                $Matches[1].Trim()
            }
            else {
                $null
            }
            WorkerStatus = $workerStatus
            GuiExecutable = Split-Path -Leaf $executable
            GuiSHA256 = (Get-FileHash -LiteralPath $executable -Algorithm SHA256).Hash.ToLowerInvariant()
            WorkerExecutable = if ($WorkerExecutable) {
                Split-Path -Leaf $WorkerExecutable
            } else {
                $null
            }
            WorkerSHA256 = if ($WorkerExecutable) {
                (Get-FileHash -LiteralPath $WorkerExecutable -Algorithm SHA256).Hash.ToLowerInvariant()
            } else {
                $null
            }
            MinimizeRestoreCycles = 3
            CloseToTray = "PASS"
            TrayRestore = "PASS"
            SingleInstanceWake = "PASS"
            TaskbarIconAvailable = $taskbarIconAvailable
            TrayIconId = $trayIconId
            InitialUiMode = $initialUiMode
            FinalUiMode = $finalUiMode
            DiagnosticsExport = $diagnosticsExportResult
            ViewModes = $viewModeResult
            TopMost = $topMostResult
            TargetWatts = if ($ExecuteNoChangePreset) { "45/45/45" } else { $null }
            WriteControls = if ($VerifyWriteControls) { "PASS" } else { "Not requested" }
            PresetEditing = $presetEditingResult
            BatteryOnlyToggle = $batteryOnlyToggleResult
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
        DiagnosticsExport = $diagnosticsExportResult
        ViewModes = $viewModeResult
        TopMost = $topMostResult
        WriteControls = if ($VerifyWriteControls) { "PASS" } else { "Not requested" }
        PresetEditing = $presetEditingResult
        BatteryOnlyToggle = $batteryOnlyToggleResult
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
