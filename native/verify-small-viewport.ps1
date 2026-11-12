param(
    [Parameter(Mandatory = $true)]
    [string]$GuiExecutable,
    [string]$OutputDirectory,
    [string]$EvidencePath
)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSCommandPath
$repositoryRoot = Split-Path -Parent $root
$artifactsRoot = Join-Path $repositoryRoot "artifacts"
if (-not $OutputDirectory) {
    $OutputDirectory = Join-Path $artifactsRoot "verify\small-viewport-200"
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
        "docs\evidence\ui\native-workarea-200-1366x768-2026-11-13.json"
}
New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null

Add-Type -AssemblyName System.Drawing
Add-Type @"
using System;
using System.Runtime.InteropServices;

public static class AmdMobilePowerSmallViewport {
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
    public static extern IntPtr SendMessage(
        IntPtr hwnd, uint message, UIntPtr wParam, IntPtr lParam);

    [DllImport("user32.dll")]
    public static extern bool PostMessage(
        IntPtr hwnd, uint message, UIntPtr wParam, IntPtr lParam);

    [DllImport("user32.dll")]
    public static extern bool PrintWindow(IntPtr hwnd, IntPtr hdc, uint flags);

    [DllImport("user32.dll")]
    public static extern IntPtr GetForegroundWindow();

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
        public uint Size;
        public uint Mask;
        public int Min;
        public int Max;
        public uint Page;
        public int Position;
        public int TrackPosition;
    }
}
"@

function Get-ScrollInfo {
    param([IntPtr]$Window, [int]$Bar)

    $info = New-Object AmdMobilePowerSmallViewport+SCROLLINFO
    $info.Size = [System.Runtime.InteropServices.Marshal]::SizeOf($info)
    $info.Mask = 0x0017
    [AmdMobilePowerSmallViewport]::GetScrollInfo(
        $Window, $Bar, [ref]$info) | Out-Null
    return $info
}

function Save-WindowImage {
    param([IntPtr]$Window, [string]$Path)

    $rect = New-Object AmdMobilePowerSmallViewport+RECT
    [AmdMobilePowerSmallViewport]::GetWindowRect($Window, [ref]$rect) | Out-Null
    $bitmap = New-Object System.Drawing.Bitmap (
        $rect.Right - $rect.Left), ($rect.Bottom - $rect.Top)
    $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
    try {
        $graphics.Clear([System.Drawing.Color]::White)
        $hdc = $graphics.GetHdc()
        try {
            if (-not [AmdMobilePowerSmallViewport]::PrintWindow($Window, $hdc, 2)) {
                throw "PrintWindow failed."
            }
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
    "verify\small-viewport-state-$([Guid]::NewGuid().ToString('N'))"
New-Item -ItemType Directory -Path $stateDirectory -Force | Out-Null
$previousLocalAppData = $env:LOCALAPPDATA
$previousWorkArea = $env:AMD_MOBILE_POWER_WORK_AREA_FIXTURE
$env:LOCALAPPDATA = $stateDirectory
$env:AMD_MOBILE_POWER_WORK_AREA_FIXTURE = "1366x728"
$process = $null
$window = [IntPtr]::Zero

try {
    [AmdMobilePowerSmallViewport]::SetProcessDpiAwarenessContext(
        [IntPtr](-4)) | Out-Null
    $process = Start-Process `
        -FilePath $GuiExecutable `
        -WorkingDirectory (Split-Path -Parent $GuiExecutable) `
        -ArgumentList @(
            "--simple-mode",
            "--dpi-fixture", "200",
            "--ui-fixture", "worker-offline"
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
    [AmdMobilePowerSmallViewport]::SetForegroundWindow($window) | Out-Null
    Start-Sleep -Milliseconds 800

    $simpleClient = New-Object AmdMobilePowerSmallViewport+RECT
    [AmdMobilePowerSmallViewport]::GetClientRect(
        $window, [ref]$simpleClient) | Out-Null
    $simpleV = Get-ScrollInfo -Window $window -Bar 1
    if ($simpleClient.Bottom -ge 720) {
        throw "Simple client did not shrink below 360 logical pixels at 200%."
    }
    if ($simpleV.Max -lt $simpleV.Page) {
        throw "Simple short viewport did not expose vertical scrolling."
    }
    [AmdMobilePowerSmallViewport]::SendMessage(
        $window, 0x0115, [UIntPtr]7, [IntPtr]::Zero) | Out-Null
    Start-Sleep -Milliseconds 200
    $simpleV = Get-ScrollInfo -Window $window -Bar 1
    if ($simpleV.Position -le 0) {
        throw "Simple footer did not move into view."
    }
    $simpleExport = [AmdMobilePowerSmallViewport]::GetDlgItem($window, 107)
    $exportRect = New-Object AmdMobilePowerSmallViewport+RECT
    [AmdMobilePowerSmallViewport]::GetWindowRect(
        $simpleExport, [ref]$exportRect) | Out-Null
    $exportBottom = New-Object AmdMobilePowerSmallViewport+POINT
    $exportBottom.X = $exportRect.Right
    $exportBottom.Y = $exportRect.Bottom
    [AmdMobilePowerSmallViewport]::ScreenToClient(
        $window, [ref]$exportBottom) | Out-Null
    if ($exportBottom.X -gt $simpleClient.Right -or
        $exportBottom.Y -gt $simpleClient.Bottom) {
        throw "Simple footer remained clipped."
    }
    $simpleImage = Join-Path $OutputDirectory "simple-200-1366x728.png"
    Save-WindowImage -Window $window -Path $simpleImage

    $advancedButton = [AmdMobilePowerSmallViewport]::GetDlgItem($window, 109)
    [AmdMobilePowerSmallViewport]::SendMessage(
        $advancedButton, 0x00F5, [UIntPtr]109, [IntPtr]::Zero) | Out-Null
    Start-Sleep -Milliseconds 500
    $advancedClient = New-Object AmdMobilePowerSmallViewport+RECT
    [AmdMobilePowerSmallViewport]::GetClientRect(
        $window, [ref]$advancedClient) | Out-Null
    $advancedV = Get-ScrollInfo -Window $window -Bar 1
    $advancedH = Get-ScrollInfo -Window $window -Bar 0
    if ($advancedClient.Right -gt 1366 -or $advancedClient.Bottom -gt 728) {
        throw "Advanced client exceeded the fixture work area."
    }
    if ($advancedV.Max -lt $advancedV.Page -or
        $advancedH.Max -lt $advancedH.Page) {
        throw "Advanced short viewport did not expose both scroll ranges."
    }
    $advancedImage = Join-Path $OutputDirectory "advanced-200-1366x728.png"
    Save-WindowImage -Window $window -Path $advancedImage

    [ordered]@{
        SchemaVersion = 1
        Verification = "PASS"
        WorkAreaFixture = "1366x728"
        DpiFixture = 200
        SimpleClient = "$($simpleClient.Right)x$($simpleClient.Bottom)"
        SimpleScrollPosition = $simpleV.Position
        AdvancedClient = "$($advancedClient.Right)x$($advancedClient.Bottom)"
        AdvancedVerticalRange = "$($advancedV.Page)/$($advancedV.Max + 1)"
        AdvancedHorizontalRange = "$($advancedH.Page)/$($advancedH.Max + 1)"
        SimpleImage = $simpleImage
        AdvancedImage = $advancedImage
        RecordedAt = (Get-Date).ToString("o")
    } |
        ConvertTo-Json -Depth 6 |
        Set-Content -LiteralPath $EvidencePath -Encoding UTF8
}
finally {
    if ($window -ne [IntPtr]::Zero) {
        [AmdMobilePowerSmallViewport]::PostMessage(
            $window, 0x0010, [UIntPtr]::Zero, [IntPtr]::Zero) | Out-Null
    }
    if ($process) {
        $process.WaitForExit(3000) | Out-Null
        if (-not $process.HasExited) {
            $process.Kill($true)
        }
    }
    $env:LOCALAPPDATA = $previousLocalAppData
    $env:AMD_MOBILE_POWER_WORK_AREA_FIXTURE = $previousWorkArea
    if (Test-Path -LiteralPath $stateDirectory) {
        Remove-Item -LiteralPath $stateDirectory -Recurse -Force
    }
}

Get-Content -LiteralPath $EvidencePath -Raw
