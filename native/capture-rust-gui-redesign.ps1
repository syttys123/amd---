param(
    [string]$GuiExecutable,
    [string]$WorkerExecutable,
    [string]$OutputDirectory,
    [string]$EvidencePath
)

$ErrorActionPreference = "Stop"
Add-Type -AssemblyName System.Drawing
Add-Type @"
using System;
using System.Runtime.InteropServices;

public static class AmdMobilePowerUiCapture {
    [DllImport("user32.dll")]
    public static extern bool SetProcessDpiAwarenessContext(IntPtr value);

    [DllImport("user32.dll")]
    public static extern bool GetWindowRect(IntPtr hwnd, out RECT rect);

    [DllImport("user32.dll")]
    public static extern IntPtr GetDlgItem(IntPtr hwnd, int id);

    [DllImport("user32.dll")]
    public static extern IntPtr SendMessage(
        IntPtr hwnd,
        uint message,
        UIntPtr wParam,
        IntPtr lParam);

    [DllImport("user32.dll")]
    public static extern bool PostMessage(
        IntPtr hwnd,
        uint message,
        UIntPtr wParam,
        IntPtr lParam);

    public struct RECT {
        public int Left;
        public int Top;
        public int Right;
        public int Bottom;
    }
}
"@

function Save-WindowImage {
    param(
        [IntPtr]$Window,
        [string]$Path
    )

    $rect = New-Object AmdMobilePowerUiCapture+RECT
    [AmdMobilePowerUiCapture]::GetWindowRect($Window, [ref]$rect) | Out-Null
    $width = $rect.Right - $rect.Left
    $height = $rect.Bottom - $rect.Top
    $bitmap = New-Object System.Drawing.Bitmap $width, $height
    $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
    try {
        $graphics.CopyFromScreen(
            $rect.Left,
            $rect.Top,
            0,
            0,
            $bitmap.Size)
        $bitmap.Save($Path, [System.Drawing.Imaging.ImageFormat]::Png)
    }
    finally {
        $graphics.Dispose()
        $bitmap.Dispose()
    }
    return [pscustomobject]@{
        Path = $Path
        Width = $width
        Height = $height
        SHA256 = (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
    }
}

$root = Split-Path -Parent $PSCommandPath
$repositoryRoot = Split-Path -Parent $root
$artifactsRoot = [System.IO.Path]::GetFullPath(
    (Join-Path $repositoryRoot "artifacts"))
if (-not $GuiExecutable) {
    $GuiExecutable = Join-Path $root "rust-gui\target\release\amd-mobile-power-gui.exe"
}
$GuiExecutable = (Resolve-Path -LiteralPath $GuiExecutable).Path
if (-not $WorkerExecutable) {
    $WorkerExecutable = Join-Path `
        $artifactsRoot `
        "native-build\worker-runtime\amdmobilepower_native_worker.exe"
}
$WorkerExecutable = (Resolve-Path -LiteralPath $WorkerExecutable).Path
if (-not $OutputDirectory) {
    $OutputDirectory = Join-Path $artifactsRoot "verify"
}
$OutputDirectory = [System.IO.Path]::GetFullPath($OutputDirectory)
if (-not $OutputDirectory.StartsWith(
    $artifactsRoot + [System.IO.Path]::DirectorySeparatorChar,
    [System.StringComparison]::OrdinalIgnoreCase)) {
    throw "Capture output must stay under artifacts: $OutputDirectory"
}
New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null

$stateDirectory = [System.IO.Path]::GetFullPath(
    (Join-Path $artifactsRoot "native-build\capture-state-$([Guid]::NewGuid().ToString('N'))"))
New-Item -ItemType Directory -Path $stateDirectory -Force | Out-Null
$previousLocalAppData = $env:LOCALAPPDATA
$env:LOCALAPPDATA = $stateDirectory
$pipeName = "AmdMobilePower.RedesignCapture.$([Guid]::NewGuid().ToString('N'))"
$process = $null
$window = [IntPtr]::Zero
$simpleCapture = $null
$advancedCapture = $null

try {
    [AmdMobilePowerUiCapture]::SetProcessDpiAwarenessContext(
        [IntPtr](-4)) | Out-Null
    $process = Start-Process `
        -FilePath $GuiExecutable `
        -WorkingDirectory (Split-Path -Parent $GuiExecutable) `
        -ArgumentList @(
            "--worker-executable", $WorkerExecutable,
            "--pipe-name", $pipeName,
            "--enable-write-controls"
        ) `
        -PassThru
    $deadline = [DateTime]::UtcNow.AddSeconds(10)
    while ([DateTime]::UtcNow -lt $deadline) {
        $process.Refresh()
        if ($process.HasExited) {
            throw "Rust GUI exited before creating the redesign window."
        }
        if ($process.MainWindowHandle -ne [IntPtr]::Zero) {
            $window = $process.MainWindowHandle
            break
        }
        Start-Sleep -Milliseconds 100
    }
    if ($window -eq [IntPtr]::Zero) {
        throw "Rust GUI did not create the redesign window in time."
    }

    Start-Sleep -Seconds 2
    $advancedCapture = Save-WindowImage `
        -Window $window `
        -Path (Join-Path $OutputDirectory "native-redesign-advanced-2026-11-11.png")
    $simpleButton = [AmdMobilePowerUiCapture]::GetDlgItem($window, 108)
    if ($simpleButton -eq [IntPtr]::Zero) {
        throw "Simple-mode control was not found."
    }
    [AmdMobilePowerUiCapture]::SendMessage(
        $simpleButton,
        0x00F5,
        [UIntPtr]108,
        [IntPtr]::Zero) | Out-Null
    Start-Sleep -Milliseconds 600
    $simpleCapture = Save-WindowImage `
        -Window $window `
        -Path (Join-Path $OutputDirectory "native-redesign-simple-2026-11-11.png")

    if ($EvidencePath) {
        $evidenceDirectory = Split-Path -Parent $EvidencePath
        if ($evidenceDirectory) {
            New-Item -ItemType Directory -Path $evidenceDirectory -Force | Out-Null
        }
        [ordered]@{
            SchemaVersion = 1
            CaptureMode = "write-controls-visible-no-write-requested"
            Simple = $simpleCapture
            Advanced = $advancedCapture
            RecordedAt = (Get-Date).ToString("o")
        } |
            ConvertTo-Json -Depth 6 |
            Set-Content -LiteralPath $EvidencePath -Encoding UTF8
    }
}
finally {
    if ($window -ne [IntPtr]::Zero) {
        [AmdMobilePowerUiCapture]::PostMessage(
            $window,
            0x0111,
            [UIntPtr]2,
            [IntPtr]::Zero) | Out-Null
    }
    if ($process) {
        $process.WaitForExit(5000) | Out-Null
        if (-not $process.HasExited) {
            $process.Kill($true)
        }
    }
    $env:LOCALAPPDATA = $previousLocalAppData
    if (Test-Path -LiteralPath $stateDirectory) {
        Remove-Item -LiteralPath $stateDirectory -Recurse -Force
    }
}

[pscustomobject]@{
    Simple = $simpleCapture.Path
    SimpleSize = "$($simpleCapture.Width)x$($simpleCapture.Height)"
    Advanced = $advancedCapture.Path
    AdvancedSize = "$($advancedCapture.Width)x$($advancedCapture.Height)"
} | Format-List
