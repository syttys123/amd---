param(
    [Parameter(Mandatory = $true)]
    [string]$GuiExecutable,
    [string]$OutputDirectory,
    [string]$EvidencePath,
    [switch]$ExpectRegression
)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSCommandPath
$repositoryRoot = Split-Path -Parent $root
$artifactsRoot = Join-Path $repositoryRoot "artifacts"
if (-not $OutputDirectory) {
    $OutputDirectory = Join-Path $artifactsRoot "verify\maximize-scroll"
}
$OutputDirectory = [System.IO.Path]::GetFullPath($OutputDirectory)
if (-not $OutputDirectory.StartsWith(
    $artifactsRoot + [System.IO.Path]::DirectorySeparatorChar,
    [System.StringComparison]::OrdinalIgnoreCase)) {
    throw "Output must stay under artifacts."
}
if (-not $EvidencePath) {
    $EvidencePath = Join-Path `
        $repositoryRoot `
        "docs\evidence\ui\native-maximize-scroll-2026-11-13.json"
}
New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null

Add-Type -AssemblyName System.Drawing
Add-Type @"
using System;
using System.Runtime.InteropServices;

public static class AmdMobilePowerMaximizeScroll {
    public delegate bool EnumChildProc(IntPtr hwnd, IntPtr lparam);

    [DllImport("user32.dll")]
    public static extern bool SetProcessDpiAwarenessContext(IntPtr value);

    [DllImport("user32.dll")]
    public static extern bool GetClientRect(IntPtr hwnd, out RECT rect);

    [DllImport("user32.dll")]
    public static extern bool GetWindowRect(IntPtr hwnd, out RECT rect);

    [DllImport("user32.dll")]
    public static extern bool ScreenToClient(IntPtr hwnd, ref POINT point);

    [DllImport("user32.dll")]
    public static extern IntPtr GetDlgItem(IntPtr hwnd, int id);

    [DllImport("user32.dll")]
    public static extern bool GetScrollInfo(IntPtr hwnd, int bar, ref SCROLLINFO info);

    [DllImport("user32.dll")]
    public static extern bool SetWindowPos(
        IntPtr hwnd, IntPtr after, int x, int y, int width, int height, uint flags);

    [DllImport("user32.dll")]
    public static extern bool ShowWindowAsync(IntPtr hwnd, int command);

    [DllImport("user32.dll")]
    public static extern IntPtr SendMessage(
        IntPtr hwnd, uint message, UIntPtr wParam, IntPtr lParam);

    [DllImport("user32.dll")]
    public static extern bool PostMessage(
        IntPtr hwnd, uint message, UIntPtr wParam, IntPtr lParam);

    [DllImport("user32.dll")]
    public static extern bool PrintWindow(IntPtr hwnd, IntPtr hdc, uint flags);

    [DllImport("user32.dll")]
    public static extern bool SetForegroundWindow(IntPtr hwnd);

    public struct RECT {
        public int Left;
        public int Top;
        public int Right;
        public int Bottom;
    }

    public struct POINT {
        public int X;
        public int Y;
    }

    public struct SCROLLINFO {
        public uint cbSize;
        public uint fMask;
        public int nMin;
        public int nMax;
        public uint nPage;
        public int nPos;
        public int nTrackPos;
    }
}
"@

function Get-ScrollInfo {
    param([IntPtr]$Window, [int]$Bar)
    $info = New-Object AmdMobilePowerMaximizeScroll+SCROLLINFO
    $info.cbSize = [Runtime.InteropServices.Marshal]::SizeOf(
        [type][AmdMobilePowerMaximizeScroll+SCROLLINFO])
    $info.fMask = 0x17
    [AmdMobilePowerMaximizeScroll]::GetScrollInfo(
        $Window, $Bar, [ref]$info) | Out-Null
    return $info
}

function Save-WindowImage {
    param([IntPtr]$Window, [string]$Path)
    $rect = New-Object AmdMobilePowerMaximizeScroll+RECT
    [AmdMobilePowerMaximizeScroll]::GetWindowRect($Window, [ref]$rect) | Out-Null
    $width = [Math]::Max(1, $rect.Right - $rect.Left)
    $height = [Math]::Max(1, $rect.Bottom - $rect.Top)
    $bitmap = New-Object System.Drawing.Bitmap $width, $height
    $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
    try {
        $hdc = $graphics.GetHdc()
        try {
            [AmdMobilePowerMaximizeScroll]::PrintWindow(
                $Window, $hdc, 2) | Out-Null
        }
        finally {
            $graphics.ReleaseHdc($hdc)
        }
        $bitmap.Save($Path, [System.Drawing.Imaging.ImageFormat]::Png)
    }
    finally {
        $graphics.Dispose()
        $bitmap.Dispose()
    }
}

$stateDirectory = Join-Path `
    $artifactsRoot `
    "verify\maximize-scroll-state-$([Guid]::NewGuid().ToString('N'))"
New-Item -ItemType Directory -Path $stateDirectory -Force | Out-Null
$previousLocalAppData = $env:LOCALAPPDATA
$env:LOCALAPPDATA = $stateDirectory
$process = $null
$window = $null

try {
    [AmdMobilePowerMaximizeScroll]::SetProcessDpiAwarenessContext(
        [IntPtr](-4)) | Out-Null
    $process = Start-Process `
        -FilePath $GuiExecutable `
        -WorkingDirectory (Split-Path -Parent $GuiExecutable) `
        -ArgumentList @(
            "--advanced-mode",
            "--ui-fixture", "worker-offline",
            "--pipe-name", "AmdMobilePower.Worker.maxscroll.$([Guid]::NewGuid().ToString('N'))"
        ) `
        -PassThru
    $deadline = [DateTime]::UtcNow.AddSeconds(10)
    while ([DateTime]::UtcNow -lt $deadline) {
        $process.Refresh()
        if ($process.HasExited) {
            throw "GUI exited before creating a window."
        }
        if ($process.MainWindowHandle -ne [IntPtr]::Zero) {
            $window = $process.MainWindowHandle
            break
        }
        Start-Sleep -Milliseconds 100
    }
    if ($window -eq [IntPtr]::Zero) {
        throw "GUI did not create a window."
    }
    [AmdMobilePowerMaximizeScroll]::SetForegroundWindow($window) | Out-Null
    Start-Sleep -Milliseconds 600

    # Shrink the advanced window to its minimum height so the page scrolls.
    [AmdMobilePowerMaximizeScroll]::SetWindowPos(
        $window, [IntPtr]::Zero, 40, 40, 796, 460, 0x0014) | Out-Null
    Start-Sleep -Milliseconds 400
    $shortClient = New-Object AmdMobilePowerMaximizeScroll+RECT
    [AmdMobilePowerMaximizeScroll]::GetClientRect(
        $window, [ref]$shortClient) | Out-Null
    if ($shortClient.Bottom -gt 440) {
        throw "Window did not shrink below the scrolling threshold."
    }

    # SB_BOTTOM scrolls to the largest offset.
    [AmdMobilePowerMaximizeScroll]::PostMessage(
        $window, 0x0115,
        [System.UIntPtr]::new([uint32]7), [IntPtr]::Zero) | Out-Null
    Start-Sleep -Milliseconds 300
    $scrolled = Get-ScrollInfo -Window $window -Bar 1
    if ($scrolled.nPos -lt 100) {
        throw "Short advanced window did not scroll (position $($scrolled.nPos))."
    }
    $shortImage = Join-Path $OutputDirectory "advanced-scrolled-short.png"
    Save-WindowImage -Window $window -Path $shortImage

    # Grow the viewport beyond the content height and re-check the offset.
    [AmdMobilePowerMaximizeScroll]::ShowWindowAsync(
        $window, 3) | Out-Null
    Start-Sleep -Milliseconds 700
    $maxClient = New-Object AmdMobilePowerMaximizeScroll+RECT
    [AmdMobilePowerMaximizeScroll]::GetClientRect(
        $window, [ref]$maxClient) | Out-Null
    $afterMaximize = Get-ScrollInfo -Window $window -Bar 1
    $advancedButton = [AmdMobilePowerMaximizeScroll]::GetDlgItem($window, 109)
    $buttonRect = New-Object AmdMobilePowerMaximizeScroll+RECT
    [AmdMobilePowerMaximizeScroll]::GetWindowRect(
        $advancedButton, [ref]$buttonRect) | Out-Null
    $buttonTop = New-Object AmdMobilePowerMaximizeScroll+POINT
    $buttonTop.X = $buttonRect.Left
    $buttonTop.Y = $buttonRect.Top
    [AmdMobilePowerMaximizeScroll]::ScreenToClient(
        $window, [ref]$buttonTop) | Out-Null
    $maxImage = Join-Path $OutputDirectory "advanced-maximized.png"
    Save-WindowImage -Window $window -Path $maxImage

    $regressed = ($afterMaximize.nPos -gt 0) -or ($buttonTop.Y -lt 0)
    $result = if ($ExpectRegression) {
        if ($regressed) { "PASS" } else { "FAIL" }
    }
    else {
        if ($regressed) { "FAIL" } else { "PASS" }
    }
    if ($result -ne "PASS") {
        throw ("Maximize scroll verification failed: position=$($afterMaximize.nPos) " +
            "headerTop=$($buttonTop.Y) client=$($maxClient.Right)x$($maxClient.Bottom)")
    }

    [ordered]@{
        SchemaVersion = 1
        Verification = "PASS"
        Expectation = if ($ExpectRegression) { "REGRESSION_PRESENT" } else { "FIX_APPLIED" }
        GuiExecutable = [System.IO.Path]::GetFullPath($GuiExecutable)
        ShortClient = "$($shortClient.Right)x$($shortClient.Bottom)"
        ScrolledPosition = $scrolled.nPos
        MaximizedClient = "$($maxClient.Right)x$($maxClient.Bottom)"
        PositionAfterMaximize = $afterMaximize.nPos
        HeaderTopAfterMaximize = $buttonTop.Y
        ShortImage = $shortImage
        MaximizedImage = $maxImage
        RecordedAt = (Get-Date).ToString("o")
    } |
        ConvertTo-Json -Depth 6 |
        Set-Content -LiteralPath $EvidencePath -Encoding UTF8
}
finally {
    if ($null -ne $window -and $window -ne [IntPtr]::Zero) {
        [AmdMobilePowerMaximizeScroll]::PostMessage(
            $window, 0x0010,
            [System.UIntPtr]::Zero, [IntPtr]::Zero) | Out-Null
    }
    if ($process) {
        $process.WaitForExit(3000) | Out-Null
        if (-not $process.HasExited) {
            Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
        }
    }
    $env:LOCALAPPDATA = $previousLocalAppData
    if (Test-Path -LiteralPath $stateDirectory) {
        Remove-Item -LiteralPath $stateDirectory -Recurse -Force
    }
}

Get-Content -LiteralPath $EvidencePath -Raw
