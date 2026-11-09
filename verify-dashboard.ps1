param(
    [string]$PackageDirectory = "artifacts\packages\amd-mobile-power-v0.1.3-dev-win-x64-lite",
    [string]$ScreenshotPath = "artifacts\verify\dashboard-simple.png",
    [string]$EvidencePath = ""
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
    throw "Refusing dashboard verification while an AMD Mobile Power process is already running."
}

Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName UIAutomationClient
Add-Type -AssemblyName UIAutomationTypes
Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;

public static class AmdDashboardNative
{
    [StructLayout(LayoutKind.Sequential)]
    public struct RECT
    {
        public int Left;
        public int Top;
        public int Right;
        public int Bottom;
    }

    [DllImport("user32.dll")]
    public static extern bool GetWindowRect(IntPtr hWnd, out RECT rect);

    [DllImport("user32.dll")]
    public static extern bool SetForegroundWindow(IntPtr hWnd);
}
'@

function Stop-PackageProcesses {
    Get-Process -Name "AmdMobilePower", "AmdMobilePower.Worker" -ErrorAction SilentlyContinue |
        Where-Object {
            try {
                $path = $_.Path
                $path -and $path.StartsWith(
                    $packagePath + [IO.Path]::DirectorySeparatorChar,
                    [StringComparison]::OrdinalIgnoreCase)
            }
            catch {
                $false
            }
        } |
        Stop-Process -Force -ErrorAction SilentlyContinue
}

$gui = $null
try {
    $gui = Start-Process `
        -FilePath $executable `
        -WorkingDirectory $packagePath `
        -ArgumentList "--simple-mode" `
        -PassThru

    $deadline = [DateTime]::UtcNow.AddSeconds(12)
    $windowHandle = [IntPtr]::Zero
    while ([DateTime]::UtcNow -lt $deadline) {
        $gui.Refresh()
        if ($gui.HasExited) {
            throw "Packaged GUI exited before showing its dashboard."
        }
        $windowHandle = $gui.MainWindowHandle
        if ($windowHandle -ne [IntPtr]::Zero) {
            break
        }
        Start-Sleep -Milliseconds 200
    }
    if ($windowHandle -eq [IntPtr]::Zero) {
        throw "Packaged GUI did not expose a dashboard window."
    }

    [AmdDashboardNative]::SetForegroundWindow($windowHandle) | Out-Null
    Start-Sleep -Milliseconds 900

    $windowRect = New-Object AmdDashboardNative+RECT
    [AmdDashboardNative]::GetWindowRect($windowHandle, [ref]$windowRect) | Out-Null
    if ($windowRect.Right -le $windowRect.Left -or
        $windowRect.Bottom -le $windowRect.Top) {
        throw "Dashboard window bounds are invalid."
    }

    $rootElement =
        [System.Windows.Automation.AutomationElement]::FromHandle($windowHandle)
    $targetLabel = $null
    $powerLine = $null
    $targetInput = $null
    $deadline = [DateTime]::UtcNow.AddSeconds(10)
    while ([DateTime]::UtcNow -lt $deadline) {
        $elements = $rootElement.FindAll(
            [System.Windows.Automation.TreeScope]::Descendants,
            [System.Windows.Automation.Condition]::TrueCondition)
        $targetLabel = $elements |
            Where-Object {
                $_.Current.ControlType -eq
                    [System.Windows.Automation.ControlType]::Text -and
                $_.Current.Name -eq "目标功耗"
            } |
            Select-Object -First 1
        $powerLine = $elements |
            Where-Object {
                $_.Current.ControlType -eq
                    [System.Windows.Automation.ControlType]::Text -and
                $_.Current.Name -match "^动态上限 \d+(?:\.\d+)? W · (电源|电池)$"
            } |
            Select-Object -First 1
        $targetInput = $elements |
            Where-Object {
                $_.Current.ControlType -eq
                    [System.Windows.Automation.ControlType]::Edit -and
                $_.Current.Name -eq "简洁模式目标功耗"
            } |
            Select-Object -First 1
        if ($targetLabel -and $powerLine -and $targetInput) {
            break
        }
        Start-Sleep -Milliseconds 250
    }
    if (-not $targetLabel) {
        throw "Simple-mode dashboard is missing the target-power label."
    }
    if (-not $powerLine) {
        throw "Simple-mode dashboard is missing a live dynamic-limit power-line text."
    }
    if (-not $targetInput) {
        throw "Simple-mode dashboard is missing the target-power input."
    }

    $width = $windowRect.Right - $windowRect.Left
    $height = $windowRect.Bottom - $windowRect.Top
    $bitmap = New-Object System.Drawing.Bitmap $width, $height
    $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
    try {
        $graphics.CopyFromScreen(
            $windowRect.Left,
            $windowRect.Top,
            0,
            0,
            $bitmap.Size)

        $targetBounds = $targetLabel.Current.BoundingRectangle
        $left = [Math]::Max(
            0,
            [int]($targetBounds.Left - $windowRect.Left) - 42)
        $right = [Math]::Min(
            $width - 1,
            [int]($targetBounds.Left - $windowRect.Left) - 5)
        $top = [Math]::Max(
            0,
            [int]($targetBounds.Top - $windowRect.Top))
        $bottom = [Math]::Min(
            $height - 1,
            [int]($targetBounds.Bottom - $windowRect.Top) - 1)

        if ($right -lt $left -or $bottom -lt $top) {
            throw "Target-left pixel region is outside the dashboard capture."
        }

        $targetLeftArtifactPixels = 0
        for ($y = $top; $y -le $bottom; $y++) {
            for ($x = $left; $x -le $right; $x++) {
                $pixel = $bitmap.GetPixel($x, $y)
                if ($pixel.R -lt 245 -or
                    $pixel.G -lt 245 -or
                    $pixel.B -lt 245) {
                    $targetLeftArtifactPixels++
                }
            }
        }
        if ($targetLeftArtifactPixels -ne 0) {
            throw "Target-power left region contains $targetLeftArtifactPixels non-background pixels."
        }

        $bitmap.Save($resolvedScreenshotPath, [System.Drawing.Imaging.ImageFormat]::Png)
    }
    finally {
        $graphics.Dispose()
        $bitmap.Dispose()
    }

    $screenshotHash = (Get-FileHash -LiteralPath $resolvedScreenshotPath -Algorithm SHA256).
        Hash.ToLowerInvariant()
    $report = [pscustomobject]@{
        Verification = "PASS"
        PowerLineText = $powerLine.Current.Name
        TargetInputText = $targetInput.Current.Name
        TargetLeftArtifactPixels = 0
        WindowBounds = (
            "{0},{1},{2},{3}" -f
                $windowRect.Left,
                $windowRect.Top,
                $windowRect.Right,
                $windowRect.Bottom
        )
        Screenshot = $resolvedScreenshotPath
        ScreenshotSize = "${width}x${height}"
        ScreenshotSHA256 = $screenshotHash
    }

    if ($EvidencePath) {
        $resolvedEvidencePath = if ([IO.Path]::IsPathRooted($EvidencePath)) {
            [IO.Path]::GetFullPath($EvidencePath)
        }
        else {
            [IO.Path]::GetFullPath((Join-Path $root $EvidencePath))
        }
        $evidenceDirectory = Split-Path -Parent $resolvedEvidencePath
        if (-not (Test-Path -LiteralPath $evidenceDirectory)) {
            New-Item -ItemType Directory -Path $evidenceDirectory -Force | Out-Null
        }
        $report | ConvertTo-Json -Depth 4 |
            Set-Content -LiteralPath $resolvedEvidencePath -Encoding utf8
    }

    $report | Format-List
}
finally {
    Stop-PackageProcesses
}
