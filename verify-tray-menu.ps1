param(
    [string]$PackageDirectory = "artifacts\packages\amd-mobile-power-v0.1.3-dev-win-x64-lite",
    [string]$ScreenshotPath = "docs\assets\tray-menu-clean-package-2026-11-10.png",
    [switch]$VerifyGracefulExit
)

$ErrorActionPreference = "Stop"

$root = Split-Path -Parent $PSCommandPath
$packagePath = if ([IO.Path]::IsPathRooted($PackageDirectory)) {
    [IO.Path]::GetFullPath($PackageDirectory)
}
else {
    [IO.Path]::GetFullPath((Join-Path $root $PackageDirectory))
}
$executable = Join-Path $packagePath "AmdMobilePower.exe"
if (-not (Test-Path -LiteralPath $executable)) {
    throw "Packaged AmdMobilePower.exe was not found: $executable"
}

$resolvedScreenshotPath = if ([IO.Path]::IsPathRooted($ScreenshotPath)) {
    [IO.Path]::GetFullPath($ScreenshotPath)
}
else {
    [IO.Path]::GetFullPath((Join-Path $root $ScreenshotPath))
}
$screenshotDirectory = Split-Path -Parent $resolvedScreenshotPath
if (-not (Test-Path -LiteralPath $screenshotDirectory)) {
    New-Item -ItemType Directory -Path $screenshotDirectory -Force | Out-Null
}

if (Get-Process -Name "AmdMobilePower", "AmdMobilePower.Worker" -ErrorAction SilentlyContinue) {
    throw "Refusing tray verification while an AMD Mobile Power process is already running."
}

Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName UIAutomationClient
Add-Type -AssemblyName UIAutomationTypes
Add-Type -TypeDefinition @'
using System;
using System.Text;
using System.Runtime.InteropServices;

public static class AmdTrayNative
{
    public delegate bool EnumWindowsProc(IntPtr hWnd, IntPtr lParam);

    [StructLayout(LayoutKind.Sequential)]
    public struct RECT
    {
        public int Left;
        public int Top;
        public int Right;
        public int Bottom;
    }

    [DllImport("user32.dll")]
    public static extern bool EnumWindows(EnumWindowsProc callback, IntPtr lParam);

    [DllImport("user32.dll")]
    public static extern bool EnumChildWindows(
        IntPtr parent,
        EnumWindowsProc callback,
        IntPtr lParam);

    [DllImport("user32.dll")]
    public static extern int GetClassName(IntPtr hWnd, StringBuilder text, int count);

    [DllImport("user32.dll")]
    public static extern bool GetWindowRect(IntPtr hWnd, out RECT rect);

    [DllImport("user32.dll")]
    public static extern bool IsWindowVisible(IntPtr hWnd);

    [DllImport("user32.dll")]
    public static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint processId);

    [DllImport("user32.dll")]
    public static extern int GetSystemMetrics(int index);

    [DllImport("user32.dll")]
    public static extern bool SetCursorPos(int x, int y);

    [DllImport("user32.dll")]
    public static extern bool SetForegroundWindow(IntPtr hWnd);

    [DllImport("user32.dll")]
    public static extern void mouse_event(
        uint flags,
        uint dx,
        uint dy,
        uint data,
        UIntPtr extraInfo);

    [DllImport("user32.dll")]
    public static extern void keybd_event(
        byte key,
        byte scan,
        uint flags,
        UIntPtr extraInfo);

    public const uint LeftDown = 0x0002;
    public const uint LeftUp = 0x0004;
    public const uint RightDown = 0x0008;
    public const uint RightUp = 0x0010;
    public const byte Escape = 0x1B;
    public const byte ApplicationsKey = 0x5D;

    public static string GetClass(IntPtr hwnd)
    {
        StringBuilder value = new StringBuilder(256);
        GetClassName(hwnd, value, value.Capacity);
        return value.ToString();
    }
}
'@

function Get-NativeWindows {
    $windows = New-Object System.Collections.Generic.List[object]
    [AmdTrayNative]::EnumWindows(
        {
            param($handle, $state)
            $rect = New-Object AmdTrayNative+RECT
            [AmdTrayNative]::GetWindowRect($handle, [ref]$rect) | Out-Null
            $processId = [uint32]0
            [AmdTrayNative]::GetWindowThreadProcessId($handle, [ref]$processId) | Out-Null
            $windows.Add([pscustomobject]@{
                Handle = $handle
                ClassName = [AmdTrayNative]::GetClass($handle)
                ProcessId = $processId
                Visible = [AmdTrayNative]::IsWindowVisible($handle)
                Rect = $rect
            })
            return $true
        },
        [IntPtr]::Zero) | Out-Null
    return $windows
}

function Get-TrayNotifyWindow {
    param([IntPtr]$ShellHandle)

    $trayMatches = New-Object System.Collections.Generic.List[object]
    [AmdTrayNative]::EnumChildWindows(
        $ShellHandle,
        {
            param($handle, $state)
            if ([AmdTrayNative]::GetClass($handle) -eq "TrayNotifyWnd") {
                $rect = New-Object AmdTrayNative+RECT
                [AmdTrayNative]::GetWindowRect($handle, [ref]$rect) | Out-Null
                $trayMatches.Add([pscustomobject]@{
                    Handle = $handle
                    Rect = $rect
                })
            }
            return $true
        },
        [IntPtr]::Zero) | Out-Null
    if ($trayMatches.Count -ne 1) {
        throw "Expected exactly one TrayNotifyWnd, found $($trayMatches.Count)."
    }
    return $trayMatches[0]
}

function Get-ShowHiddenIconsButton {
    param([IntPtr]$ShellHandle)

    $shellElement =
        [System.Windows.Automation.AutomationElement]::FromHandle($ShellHandle)
    $children = $shellElement.FindAll(
        [System.Windows.Automation.TreeScope]::Descendants,
        [System.Windows.Automation.Condition]::TrueCondition)
    return $children |
        Where-Object {
            $_.Current.ControlType -eq
                [System.Windows.Automation.ControlType]::Button -and
            $_.Current.AutomationId -eq "SystemTrayIcon" -and
            $_.Current.Name -match "隐藏|hidden"
        } |
        Select-Object -First 1
}

function Invoke-MouseClick {
    param(
        [int]$X,
        [int]$Y,
        [bool]$RightButton
    )

    [AmdTrayNative]::SetCursorPos($X, $Y) | Out-Null
    Start-Sleep -Milliseconds 150
    if ($RightButton) {
        [AmdTrayNative]::mouse_event(
            [AmdTrayNative]::RightDown, 0, 0, 0, [UIntPtr]::Zero)
        Start-Sleep -Milliseconds 120
        [AmdTrayNative]::mouse_event(
            [AmdTrayNative]::RightUp, 0, 0, 0, [UIntPtr]::Zero)
    }
    else {
        [AmdTrayNative]::mouse_event(
            [AmdTrayNative]::LeftDown, 0, 0, 0, [UIntPtr]::Zero)
        Start-Sleep -Milliseconds 80
        [AmdTrayNative]::mouse_event(
            [AmdTrayNative]::LeftUp, 0, 0, 0, [UIntPtr]::Zero)
    }
}

function Wait-ForOverflowWindow {
    param([int]$TimeoutMilliseconds = 3000)

    $deadline = [DateTime]::UtcNow.AddMilliseconds($TimeoutMilliseconds)
    while ([DateTime]::UtcNow -lt $deadline) {
        $window = Get-NativeWindows |
            Where-Object {
                $_.ClassName -eq "TopLevelWindowForOverflowXamlIsland" -and
                $_.Visible
            } |
            Select-Object -First 1
        if ($window) {
            return $window
        }
        Start-Sleep -Milliseconds 120
    }
    throw "Windows tray overflow did not open."
}

function Wait-ForAppTrayButton {
    param([IntPtr]$OverflowHandle)

    $deadline = [DateTime]::UtcNow.AddSeconds(5)
    while ([DateTime]::UtcNow -lt $deadline) {
        $overflowElement =
            [System.Windows.Automation.AutomationElement]::FromHandle($OverflowHandle)
        $automationChildren = $overflowElement.FindAll(
            [System.Windows.Automation.TreeScope]::Descendants,
            [System.Windows.Automation.Condition]::TrueCondition)
        $button = $automationChildren |
            Where-Object {
                $_.Current.ControlType -eq
                    [System.Windows.Automation.ControlType]::Button -and
                $_.Current.Name.StartsWith(
                    "AMD Mobile Power",
                    [StringComparison]::OrdinalIgnoreCase)
            } |
            Select-Object -First 1
        if ($button) {
            return $button
        }
        Start-Sleep -Milliseconds 150
    }
    throw "AMD Mobile Power notification icon was not found in the overflow."
}

function Get-MenuWindow {
    param([uint32]$ProcessId)

    $deadline = [DateTime]::UtcNow.AddSeconds(3)
    while ([DateTime]::UtcNow -lt $deadline) {
        $window = Get-NativeWindows |
            Where-Object {
                $_.ProcessId -eq $ProcessId -and
                $_.Visible -and
                $_.ClassName.StartsWith(
                    "WindowsForms10.Window.",
                    [StringComparison]::Ordinal)
            } |
            Select-Object -First 1
        if ($window) {
            $element =
                [System.Windows.Automation.AutomationElement]::FromHandle($window.Handle)
            if ($element.Current.ControlType -eq
                [System.Windows.Automation.ControlType]::Menu) {
                return $window
            }
        }
        Start-Sleep -Milliseconds 120
    }
    $remainingWindows = Get-NativeWindows |
        Where-Object { $_.ProcessId -eq $ProcessId -and $_.Visible } |
        ForEach-Object {
            "$($_.Handle):$($_.ClassName):$(
                $_.Rect.Left),$($_.Rect.Top),$($_.Rect.Right),$($_.Rect.Bottom)"
        }
    throw "AMD Mobile Power tray menu did not open. Visible PID windows: $(
        $remainingWindows -join '; ')"
}

function Stop-PackageProcesses {
    Get-Process -Name "AmdMobilePower", "AmdMobilePower.Worker" -ErrorAction SilentlyContinue |
        Where-Object {
            try {
                $processPath = $_.Path
                $processPath -and $processPath.StartsWith(
                    $packagePath + [IO.Path]::DirectorySeparatorChar,
                    [StringComparison]::OrdinalIgnoreCase)
            }
            catch {
                $false
            }
        } |
        Stop-Process -Force
}

function Wait-PackageProcessesStopped {
    $deadline = [DateTime]::UtcNow.AddSeconds(8)
    while ([DateTime]::UtcNow -lt $deadline) {
        $remaining = @(
            Get-Process -Name "AmdMobilePower", "AmdMobilePower.Worker" -ErrorAction SilentlyContinue |
                Where-Object {
                    try {
                        $processPath = $_.Path
                        $processPath -and $processPath.StartsWith(
                            $packagePath + [IO.Path]::DirectorySeparatorChar,
                            [StringComparison]::OrdinalIgnoreCase)
                    }
                    catch {
                        $false
                    }
                }
        )
        if ($remaining.Count -eq 0) {
            return
        }
        Start-Sleep -Milliseconds 200
    }

    throw "GUI or worker process remained after the tray Exit action."
}

$menuVisible = $false
$gracefulExit = "Not requested"
try {
    $gui = Start-Process `
        -FilePath $executable `
        -WorkingDirectory $packagePath `
        -ArgumentList "--tray" `
        -PassThru
    Start-Sleep -Seconds 8
    if ($gui.HasExited) {
        throw "Packaged GUI exited before registering its tray icon."
    }

    $screenWidth = [AmdTrayNative]::GetSystemMetrics(0)
    $screenHeight = [AmdTrayNative]::GetSystemMetrics(1)
    [AmdTrayNative]::SetCursorPos(
        [int]($screenWidth / 2),
        $screenHeight - 1) | Out-Null
    Start-Sleep -Milliseconds 900

    $shell = Get-NativeWindows |
        Where-Object { $_.ClassName -eq "Shell_TrayWnd" -and $_.Visible } |
        Select-Object -First 1
    if (-not $shell) {
        throw "Windows taskbar is unavailable."
    }
    $shellElement =
        [System.Windows.Automation.AutomationElement]::FromHandle($shell.Handle)
    $shellBounds = $shellElement.Current.BoundingRectangle
    $screenWidth = [Math]::Max($screenWidth, [int]$shellBounds.Right)
    $screenHeight = [Math]::Max($screenHeight, [int]$shellBounds.Bottom)
    $notify = Get-TrayNotifyWindow -ShellHandle $shell.Handle
    $overflowX = [int]$notify.Rect.Left + 11
    $overflowY = [int](($notify.Rect.Top + $notify.Rect.Bottom) / 2)
    $showHiddenButton = Get-ShowHiddenIconsButton -ShellHandle $shell.Handle
    $showHiddenBounds = if ($showHiddenButton) {
        $showHiddenButton.Current.BoundingRectangle
    }
    else {
        $null
    }
    $overflow = $null
    $appTrayButton = $null
    $trayBounds = $null
    $trayNotificationText = $null
    for ($attempt = 1; $attempt -le 3 -and -not $appTrayButton; $attempt++) {
        [AmdTrayNative]::keybd_event(
            [AmdTrayNative]::Escape, 0, 0, [UIntPtr]::Zero)
        [AmdTrayNative]::keybd_event(
            [AmdTrayNative]::Escape, 0, 2, [UIntPtr]::Zero)
        Start-Sleep -Milliseconds 350

        $overflowCandidates = New-Object System.Collections.Generic.List[object]
        if ($showHiddenBounds -and
            $showHiddenBounds.Width -gt 0 -and
            $showHiddenBounds.Height -gt 0) {
            $overflowCandidates.Add([pscustomobject]@{
                X = [int]($showHiddenBounds.Left + ($showHiddenBounds.Width / 2))
                Y = [int]($showHiddenBounds.Top + ($showHiddenBounds.Height / 2))
            })
        }

        $notifyWidth = [int]($notify.Rect.Right - $notify.Rect.Left)
        $scanLimit = [Math]::Min(160, $notifyWidth - 6)
        for ($offset = 6; $offset -le $scanLimit; $offset += 8) {
            $overflowCandidates.Add([pscustomobject]@{
                X = [int]$notify.Rect.Left + $offset
                Y = $overflowY
            })
        }

        foreach ($candidate in $overflowCandidates) {
            [AmdTrayNative]::keybd_event(
                [AmdTrayNative]::Escape, 0, 0, [UIntPtr]::Zero)
            [AmdTrayNative]::keybd_event(
                [AmdTrayNative]::Escape, 0, 2, [UIntPtr]::Zero)
            Start-Sleep -Milliseconds 120
            Invoke-MouseClick -X $candidate.X -Y $candidate.Y -RightButton $false
            try {
                $overflow = Wait-ForOverflowWindow -TimeoutMilliseconds 700
                break
            }
            catch {
            }
        }
        try {
            if (-not $overflow) {
                $overflow = Wait-ForOverflowWindow -TimeoutMilliseconds 2000
            }
            $candidateButton = Wait-ForAppTrayButton -OverflowHandle $overflow.Handle
            $candidateBounds = $candidateButton.Current.BoundingRectangle
            if ($candidateBounds.Width -le 0 -or $candidateBounds.Height -le 0) {
                throw "AMD Mobile Power tray icon has no clickable bounds."
            }
            $candidateText = $candidateButton.Current.Name.Trim()
            if ([string]::IsNullOrWhiteSpace($candidateText) -or
                $candidateText -notmatch "AMD Mobile Power.*(电源|电池)") {
                throw "AMD Mobile Power tray tooltip did not contain a power-line state."
            }
            $appTrayButton = $candidateButton
            $trayBounds = $candidateBounds
            $trayNotificationText = $candidateText
        }
        catch {
            if ($attempt -eq 3) {
                throw
            }
        }
    }
    if (-not $appTrayButton -or
        -not $trayBounds -or
        $trayBounds.Width -le 0 -or
        $trayBounds.Height -le 0) {
        throw "AMD Mobile Power tray icon has no clickable bounds."
    }
    $trayX = [int]($trayBounds.Left + ($trayBounds.Width / 2))
    $trayY = [int]($trayBounds.Top + ($trayBounds.Height / 2))
    [AmdTrayNative]::SetCursorPos($trayX, $trayY) | Out-Null
    Start-Sleep -Milliseconds 350
    $menu = $null
    for ($attempt = 1; $attempt -le 3 -and -not $menu; $attempt++) {
        try {
            $appTrayButton.SetFocus()
            [AmdTrayNative]::keybd_event(
                [AmdTrayNative]::ApplicationsKey, 0, 0, [UIntPtr]::Zero)
            Start-Sleep -Milliseconds 80
            [AmdTrayNative]::keybd_event(
                [AmdTrayNative]::ApplicationsKey, 0, 2, [UIntPtr]::Zero)
            $menu = Get-MenuWindow -ProcessId ([uint32]$gui.Id)
        }
        catch {
            try {
                Invoke-MouseClick -X $trayX -Y $trayY -RightButton $true
                $menu = Get-MenuWindow -ProcessId ([uint32]$gui.Id)
            }
            catch {
                if ($attempt -eq 3) {
                    throw
                }
            }
            Start-Sleep -Milliseconds 400
        }
    }
    $menuVisible = $true
    $menuElement =
        [System.Windows.Automation.AutomationElement]::FromHandle($menu.Handle)
    $menuChildren = $menuElement.FindAll(
        [System.Windows.Automation.TreeScope]::Descendants,
        [System.Windows.Automation.Condition]::TrueCondition)
    $menuItems = @(
        $menuChildren |
            Where-Object {
                $_.Current.ControlType -eq
                    [System.Windows.Automation.ControlType]::MenuItem
            } |
            ForEach-Object { $_.Current.Name }
    )
    $exitItem = $menuChildren |
        Where-Object {
            $_.Current.ControlType -eq
                [System.Windows.Automation.ControlType]::MenuItem -and
            $_.Current.Name -eq "退出"
        } |
        Select-Object -First 1
    foreach ($required in @(
        "打开 AMD Mobile Power",
        "刷新状态",
        "界面模式",
        "窗口置顶",
        "导出诊断...",
        "隐藏到托盘",
        "退出"
    )) {
        if ($menuItems -notcontains $required) {
            throw "Tray menu item is missing: $required"
        }
    }
    if (@($menuItems | Where-Object { $_ -match "^\d+ W$" }).Count -ne 3) {
        throw "Tray menu must expose exactly three editable power presets."
    }

    $menuRect = $menu.Rect
    $insideScreen =
        $menuRect.Left -ge 0 -and
        $menuRect.Top -ge 0 -and
        $menuRect.Right -le $screenWidth -and
        $menuRect.Bottom -le $screenHeight
    if (-not $insideScreen) {
        throw "Tray menu extends outside the screen: menu=$(
            $menuRect.Left),$($menuRect.Top),$($menuRect.Right),$($menuRect.Bottom); screen=$(
            $screenWidth)x$($screenHeight)."
    }
    if ($menuRect.Top -ge $trayBounds.Top) {
        throw "Tray menu did not open upward from the hidden-tray icon."
    }
    $horizontalGap = if ($menuRect.Right -lt $trayBounds.Left) {
        [int]($trayBounds.Left - $menuRect.Right)
    }
    elseif ($menuRect.Left -gt $trayBounds.Right) {
        [int]($menuRect.Left - $trayBounds.Right)
    }
    else {
        0
    }
    if ($horizontalGap -gt 80) {
        throw "Tray menu is not anchored near the notification icon; gap=$horizontalGap px."
    }

    $cropX = [Math]::Max(0, $menuRect.Left - 18)
    $cropY = [Math]::Max(0, $menuRect.Top - 22)
    $cropRight = [Math]::Min($screenWidth, $menuRect.Right + 28)
    $cropBottom = [Math]::Min(
        $screenHeight,
        [Math]::Max($menuRect.Bottom + 40, [int]$trayBounds.Bottom + 12))
    $width = $cropRight - $cropX
    $height = $cropBottom - $cropY
    $bitmap = New-Object System.Drawing.Bitmap $width, $height
    $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
    try {
        $graphics.CopyFromScreen($cropX, $cropY, 0, 0, $bitmap.Size)
        $bitmap.Save($resolvedScreenshotPath, [System.Drawing.Imaging.ImageFormat]::Png)
    }
    finally {
        $graphics.Dispose()
        $bitmap.Dispose()
    }

    if ($VerifyGracefulExit) {
        if ($null -eq $exitItem) {
            throw "Tray Exit menu item is unavailable."
        }
        $invokePattern = $exitItem.GetCurrentPattern(
            [System.Windows.Automation.InvokePattern]::Pattern)
        $invokePattern.Invoke()
        $menuVisible = $false
        Wait-PackageProcessesStopped
        $gracefulExit = "PASS"
    }
    else {
        [AmdTrayNative]::keybd_event(
            [AmdTrayNative]::Escape, 0, 0, [UIntPtr]::Zero)
        [AmdTrayNative]::keybd_event(
            [AmdTrayNative]::Escape, 0, 2, [UIntPtr]::Zero)
        Start-Sleep -Milliseconds 400
        $menuVisible = $false
    }

    $hash = (Get-FileHash -LiteralPath $resolvedScreenshotPath -Algorithm SHA256).
        Hash.ToLowerInvariant()
    [pscustomobject]@{
        Verification = "PASS"
        NotificationText = $trayNotificationText
        TrayIconBounds = (
            "{0},{1},{2},{3}" -f
                [int]$trayBounds.Left,
                [int]$trayBounds.Top,
                [int]$trayBounds.Right,
                [int]$trayBounds.Bottom
        )
        MenuDirection = "up"
        MenuHorizontalGap = $horizontalGap
        MenuBounds = (
            "{0},{1},{2},{3}" -f
                $menuRect.Left,
                $menuRect.Top,
                $menuRect.Right,
                $menuRect.Bottom
        )
        MenuItems = $menuItems.Count
        GracefulExit = $gracefulExit
        Screenshot = $resolvedScreenshotPath
        ScreenshotSize = "${width}x${height}"
        SHA256 = $hash
    } | Format-List
}
finally {
    if ($menuVisible) {
        [AmdTrayNative]::keybd_event(
            [AmdTrayNative]::Escape, 0, 0, [UIntPtr]::Zero)
        [AmdTrayNative]::keybd_event(
            [AmdTrayNative]::Escape, 0, 2, [UIntPtr]::Zero)
    }
    Stop-PackageProcesses
}
