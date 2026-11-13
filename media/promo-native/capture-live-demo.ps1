param(
    [Parameter(Mandatory = $true)]
    [string]$GuiExecutable,
    [string]$OutputDirectory,
    [string]$ClipPath,
    [string]$UiFixture = "firmware-clamp",
    [int]$DpiFixture = 125,
    [ValidateSet("advanced", "simple")]
    [string]$Mode = "advanced",
    [double]$DurationSeconds = 13.5,
    [int]$Fps = 10
)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent (
    Split-Path -Parent (Split-Path -Parent $PSCommandPath))
if (-not $OutputDirectory) {
    $OutputDirectory = Join-Path $root "artifacts\media\live-demo"
}
if (-not $ClipPath) {
    $ClipPath = Join-Path $OutputDirectory "presets-demo.mp4"
}
$resolvedOutput = [System.IO.Path]::GetFullPath($OutputDirectory)
$artifactsRoot = [System.IO.Path]::GetFullPath((Join-Path $root "artifacts"))
if (-not $resolvedOutput.StartsWith(
    $artifactsRoot + [System.IO.Path]::DirectorySeparatorChar,
    [System.StringComparison]::OrdinalIgnoreCase)) {
    throw "Output must stay under artifacts: $resolvedOutput"
}
New-Item -ItemType Directory -Path $resolvedOutput -Force | Out-Null
$frameDirectory = Join-Path $resolvedOutput "frames"
if (Test-Path -LiteralPath $frameDirectory) {
    Remove-Item -LiteralPath $frameDirectory -Recurse -Force
}
New-Item -ItemType Directory -Path $frameDirectory -Force | Out-Null

Add-Type -AssemblyName System.Drawing
Add-Type @"
using System;
using System.Runtime.InteropServices;

public static class AmdMobilePowerLiveDemo {
    [DllImport("user32.dll")]
    public static extern bool SetProcessDpiAwarenessContext(IntPtr value);

    [DllImport("user32.dll")]
    public static extern bool GetClientRect(IntPtr hwnd, out RECT rect);

    [DllImport("user32.dll")]
    public static extern bool PrintWindow(IntPtr hwnd, IntPtr hdc, uint flags);

    [DllImport("user32.dll")]
    public static extern IntPtr SendMessage(
        IntPtr hwnd, uint message, UIntPtr wParam, IntPtr lParam);

    [DllImport("user32.dll", CharSet = CharSet.Unicode, EntryPoint = "SendMessageW")]
    public static extern IntPtr SendMessageText(
        IntPtr hwnd, uint message, UIntPtr wParam, string lParam);

    [DllImport("user32.dll")]
    public static extern IntPtr GetDlgItem(IntPtr hwnd, int id);

    [DllImport("user32.dll")]
    public static extern bool PostMessage(
        IntPtr hwnd, uint message, UIntPtr wParam, IntPtr lParam);

    [DllImport("user32.dll")]
    public static extern bool SetForegroundWindow(IntPtr hwnd);

    [DllImport("user32.dll")]
    public static extern bool AdjustWindowRectExForDpi(
        ref RECT rect, int style, int menu, int exStyle, uint dpi);

    [DllImport("user32.dll")]
    public static extern uint GetDpiForWindow(IntPtr hwnd);

    [DllImport("user32.dll")]
    public static extern bool SetWindowPos(
        IntPtr hwnd, IntPtr after, int x, int y, int width, int height, uint flags);

    public struct RECT {
        public int Left;
        public int Top;
        public int Right;
        public int Bottom;
    }
}
"@

# The capture process must be per-monitor DPI aware, otherwise every
# GetClientRect measurement comes back virtualized to 96 DPI and PrintWindow
# renders only the top-left fraction of the real window.
[AmdMobilePowerLiveDemo]::SetProcessDpiAwarenessContext([IntPtr](-4)) | Out-Null

function Save-Frame {
    param([IntPtr]$Window, [string]$Path)
    $rect = New-Object AmdMobilePowerLiveDemo+RECT
    [AmdMobilePowerLiveDemo]::GetClientRect($Window, [ref]$rect) | Out-Null
    $width = [Math]::Max(1, $rect.Right)
    $height = [Math]::Max(1, $rect.Bottom)
    $bitmap = New-Object System.Drawing.Bitmap $width, $height
    $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
    try {
        $hdc = $graphics.GetHdc()
        try {
            # PW_CLIENTONLY | PW_RENDERFULLCONTENT: render just the client
            # area into a client-sized bitmap. Plain PW_RENDERFULLCONTENT
            # draws the whole window (title bar and borders) shifted into the
            # smaller bitmap, which shows a dark left strip and crops the
            # bottom row.
            [AmdMobilePowerLiveDemo]::PrintWindow($Window, $hdc, 3) | Out-Null
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
    "media\live-demo-state-$([Guid]::NewGuid().ToString('N'))"
$stateFileDirectory = Join-Path $stateDirectory "AmdMobilePower"
New-Item -ItemType Directory -Path $stateFileDirectory -Force | Out-Null
# Seed the same simple-mode state the verified screenshot capture uses. The
# demo then switches to advanced through the GUI's own mode command, which is
# the code path that sizes the window and lays out with the fixture DPI.
# Launching straight into --advanced-mode leaves the window at its creation
# size and the advanced content strip stays clipped.
[ordered]@{
    presets = @(10, 25, 45)
    mode = $Mode
    topMost = $false
} | ConvertTo-Json | Set-Content `
    -LiteralPath (Join-Path $stateFileDirectory "rust-ui-state.json") `
    -Encoding UTF8
$previousLocalAppData = $env:LOCALAPPDATA
$env:LOCALAPPDATA = $stateDirectory
$process = $null
$window = $null

try {
    $process = Start-Process `
        -FilePath $GuiExecutable `
        -WorkingDirectory (Split-Path -Parent $GuiExecutable) `
        -ArgumentList @(
            "--enable-write-controls",
            "--ui-fixture", $UiFixture,
            "--dpi-fixture", "$DpiFixture",
            "--pipe-name", "AmdMobilePower.Worker.livedemo.$([Guid]::NewGuid().ToString('N'))"
        ) `
        -PassThru
    $deadline = [DateTime]::UtcNow.AddSeconds(15)
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
    if ($null -eq $window -or $window -eq [IntPtr]::Zero) {
        throw "GUI did not create a window."
    }
    [AmdMobilePowerLiveDemo]::SetForegroundWindow($window) | Out-Null
    Start-Sleep -Milliseconds 400

    if ($Mode -eq "advanced") {
        # Switch to advanced mode through the GUI command so apply_view_mode
        # sizes the window itself (780x680 logical scaled by the DPI fixture)
        # and resets scroll offsets, exactly like the verified screenshot
        # capture. In this DPI-aware process the client reports device
        # pixels, so the threshold stays a logical lower bound.
        [AmdMobilePowerLiveDemo]::SendMessage(
            $window, 0x0111,
            [System.UIntPtr]::new(109),
            [IntPtr]::Zero) | Out-Null
        $fixtureScale = $DpiFixture / 100.0
        $minClientWidth = [int][Math]::Round(760 * $fixtureScale)
        $minClientHeight = [int][Math]::Round(660 * $fixtureScale)
        $resizeDeadline = [DateTime]::UtcNow.AddSeconds(5)
        $measured = New-Object AmdMobilePowerLiveDemo+RECT
        do {
            Start-Sleep -Milliseconds 100
            [AmdMobilePowerLiveDemo]::GetClientRect(
                $window, [ref]$measured) | Out-Null
        } while (($measured.Right -lt $minClientWidth -or
                $measured.Bottom -lt $minClientHeight) -and
            [DateTime]::UtcNow -lt $resizeDeadline)
        if ($measured.Right -lt $minClientWidth -or
            $measured.Bottom -lt $minClientHeight) {
            throw ("Advanced client is too small for the demo: " +
                "$($measured.Right)x$($measured.Bottom), need at least " +
                "${minClientWidth}x${minClientHeight}")
        }
        [AmdMobilePowerLiveDemo]::SetForegroundWindow($window) | Out-Null
        Start-Sleep -Milliseconds 400
    }

    # Timed interaction script. Nothing writes hardware because the fixture
    # only simulates apply/read-back. Presets seed as 10/25/45 W so the demo
    # matches the 10 / 25 / 45 W headline.
    if ($Mode -eq "advanced") {
        # Select each preset card in turn, then edit preset 1 and save so the
        # row still reads 10 / 25 / 45 W at the end.
        $timeline = @(
            @{ At = 1.2; Action = "command"; Command = 102 },
            @{ At = 4.0; Action = "command"; Command = 101 },
            @{ At = 6.6; Action = "command"; Command = 103 },
            @{ At = 9.2; Action = "set_text"; Control = 301; Text = "12" },
            @{ At = 10.0; Action = "set_text"; Control = 301; Text = "10" },
            @{ At = 10.8; Action = "command"; Command = 106 }
        )
    }
    else {
        # Simple mode: a short settle, then 25 -> 45 -> 10 with a pause on
        # each selection so the target field and apply result are readable.
        $timeline = @(
            @{ At = 1.6; Action = "command"; Command = 102 },
            @{ At = 4.6; Action = "command"; Command = 103 },
            @{ At = 7.6; Action = "command"; Command = 101 }
        )
    }

    $watch = [System.Diagnostics.Stopwatch]::StartNew()
    $frameIndex = 0
    $frameInterval = 1.0 / $Fps
    $nextFrameAt = 0.0
    while ($watch.Elapsed.TotalSeconds -lt $DurationSeconds) {
        $elapsed = $watch.Elapsed.TotalSeconds
        foreach ($step in $timeline) {
            if (-not $step.ContainsKey("Done") -and $elapsed -ge $step.At) {
                switch ($step.Action) {
                    "command" {
                        [AmdMobilePowerLiveDemo]::SendMessage(
                            $window, 0x0111,
                            [System.UIntPtr]::new([uint32]$step.Command),
                            [IntPtr]::Zero) | Out-Null
                    }
                    "set_text" {
                        $control = [AmdMobilePowerLiveDemo]::GetDlgItem(
                            $window, [int]$step.Control)
                        if ($control -ne [IntPtr]::Zero) {
                            [AmdMobilePowerLiveDemo]::SendMessageText(
                                $control, 0x000C,
                                [System.UIntPtr]::Zero,
                                [string]$step.Text) | Out-Null
                        }
                    }
                }
                $step.Done = $true
            }
        }
        if ($elapsed -ge $nextFrameAt) {
            $framePath = Join-Path `
                $frameDirectory `
                ("frame-{0:d4}.png" -f $frameIndex)
            Save-Frame -Window $window -Path $framePath
            $frameIndex++
            $nextFrameAt += $frameInterval
        }
        Start-Sleep -Milliseconds 25
    }

    $ffmpeg = (Get-Command ffmpeg -ErrorAction Stop).Source
    $actualRate = [Math]::Max(1.0, $frameIndex / $DurationSeconds)
    $actualRateText = $actualRate.ToString(
        "0.###",
        [Globalization.CultureInfo]::InvariantCulture)
    # Keep the raw client-sized frames: the promo renderer places this clip
    # inside its screenshot card and adds the scene fades itself. H.264 needs
    # even dimensions, so round down to a multiple of two.
    $filter = "scale=trunc(iw/2)*2:trunc(ih/2)*2,format=yuv420p"
    & $ffmpeg `
        -y `
        -framerate $actualRateText `
        -i (Join-Path $frameDirectory "frame-%04d.png") `
        -filter_complex $filter `
        -r 25 `
        -c:v libx264 `
        -preset medium `
        -crf 18 `
        -movflags +faststart `
        $ClipPath
    if ($LASTEXITCODE -ne 0) {
        throw "ffmpeg failed with exit code $LASTEXITCODE."
    }

    $hash = (Get-FileHash -LiteralPath $ClipPath -Algorithm SHA256).
        Hash.ToLowerInvariant()
    [ordered]@{
        Verification = "PASS"
        Clip = $ClipPath
        ClipSha256 = $hash
        DurationSeconds = $DurationSeconds
        Frames = $frameIndex
        Fixture = $UiFixture
        DpiFixture = $DpiFixture
        RecordedAt = (Get-Date).ToString("o")
    } | ConvertTo-Json
}
finally {
    if ($null -ne $window -and $window -ne [IntPtr]::Zero) {
        [AmdMobilePowerLiveDemo]::PostMessage(
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
