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
    $headerTitle = $null
    $powerLine = $null
    $targetInput = $null
    $writeStateLabel = $null
    $statusLabel = $null
    $detailsButton = $null
    $simpleModeButton = $null
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
        $headerTitle = $elements |
            Where-Object {
                $_.Current.ControlType -eq
                    [System.Windows.Automation.ControlType]::Text -and
                $_.Current.Name -eq "AMD Mobile Power"
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
        $writeStateLabel = $elements |
            Where-Object {
                $_.Current.ControlType -eq
                    [System.Windows.Automation.ControlType]::Text -and
                $_.Current.Name -match "^(只读模式|写入已解锁|平台不支持写入)$"
            } |
            Select-Object -First 1
        $statusLabel = $elements |
            Where-Object {
                $_.Current.ControlType -eq
                    [System.Windows.Automation.ControlType]::Text -and
                $_.Current.Name -match "^(正在连接 worker\.\.\.|worker 已连接，状态已更新|状态已刷新)"
            } |
            Select-Object -First 1
        $detailsButton = $elements |
            Where-Object {
                $_.Current.ControlType -eq
                    [System.Windows.Automation.ControlType]::Button -and
                $_.Current.Name -eq "详情"
            } |
            Select-Object -First 1
        $simpleModeButton = $elements |
            Where-Object {
                $_.Current.ControlType -eq
                    [System.Windows.Automation.ControlType]::Button -and
                $_.Current.Name -eq "简洁模式"
            } |
            Select-Object -First 1
        if ($targetLabel -and $headerTitle -and $powerLine -and
            $targetInput -and $writeStateLabel -and $statusLabel -and
            $simpleModeButton) {
            break
        }
        Start-Sleep -Milliseconds 250
    }
    if (-not $targetLabel) {
        throw "Simple-mode dashboard is missing the target-power label."
    }
    if (-not $headerTitle) {
        throw "Simple-mode dashboard is missing the full AMD Mobile Power title."
    }
    if (-not $powerLine) {
        throw "Simple-mode dashboard is missing a live dynamic-limit power-line text."
    }
    if (-not $targetInput) {
        throw "Simple-mode dashboard is missing the target-power input."
    }
    if (-not $writeStateLabel) {
        throw "Simple-mode dashboard is missing the write-state label."
    }
    if (-not $statusLabel) {
        throw "Simple-mode dashboard is missing the status message."
    }
    if (-not $simpleModeButton) {
        throw "Simple-mode dashboard is missing the simple/advanced mode switch."
    }
    if ($detailsButton) {
        throw "Simple-mode dashboard still exposes the overlapping details button."
    }

    $stateBounds = $writeStateLabel.Current.BoundingRectangle
    $statusBounds = $statusLabel.Current.BoundingRectangle
    $statusOverlap =
        -not (
            $stateBounds.Right -le $statusBounds.Left -or
            $statusBounds.Right -le $stateBounds.Left -or
            $stateBounds.Bottom -le $statusBounds.Top -or
            $statusBounds.Bottom -le $stateBounds.Top
        )
    if ($statusOverlap) {
        throw "Simple-mode write-state and status labels overlap."
    }

    $width = $windowRect.Right - $windowRect.Left
    $height = $windowRect.Bottom - $windowRect.Top
    $headerBounds = $headerTitle.Current.BoundingRectangle
    $modeBounds = $simpleModeButton.Current.BoundingRectangle
    $headerRightGap = [int]($modeBounds.Left - $headerBounds.Right)
    if ($headerBounds.Right -gt $modeBounds.Left -or $headerRightGap -lt 12) {
        throw "The full header title overlaps or crowds the mode controls; gap=$headerRightGap px."
    }
    $stateWidthRatio = $stateBounds.Width / $width
    if ($stateWidthRatio -gt 0.15) {
        throw "The write-state status label is too wide: width=$($stateBounds.Width) px, ratio=$stateWidthRatio."
    }
    $targetBounds = $null
    $left = $null
    $right = $null
    $top = $null
    $bottom = $null
    $lastCandidateBounds = $null
    $lastCandidateRegion = $null
    $lastAcceptedRegion = $null
    $stableRegionReads = 0
    $deadline = [DateTime]::UtcNow.AddSeconds(3)
    while ([DateTime]::UtcNow -lt $deadline) {
        $candidateBounds = $targetLabel.Current.BoundingRectangle
        $lastCandidateBounds = $candidateBounds
        $candidateLeft = [Math]::Max(
            0,
            [int]($candidateBounds.Left - $windowRect.Left) - 42)
        $candidateRight = [Math]::Min(
            $width - 1,
            [int]($candidateBounds.Left - $windowRect.Left) - 5)
        $candidateTop = [Math]::Max(
            0,
            [int]($candidateBounds.Top - $windowRect.Top))
        $candidateBottom = [Math]::Min(
            $height - 1,
            [int]($candidateBounds.Bottom - $windowRect.Top) - 1)
        $candidateRegion =
            "{0},{1},{2},{3}" -f
                $candidateLeft,
                $candidateTop,
                $candidateRight,
                $candidateBottom
        $lastCandidateRegion = $candidateRegion
        # Some WinForms text peers report an overly wide right edge. The
        # left/top/bottom anchor and the clipped sampling region are what this
        # pixel check actually depends on.
        $boundsUsable =
            $candidateBounds.Width -gt 0 -and
            $candidateBounds.Height -gt 0 -and
            $candidateBounds.Left -ge $windowRect.Left -and
            $candidateBounds.Left -lt $windowRect.Right -and
            $candidateBounds.Top -ge $windowRect.Top -and
            $candidateBounds.Bottom -le $windowRect.Bottom -and
            $candidateRight -ge $candidateLeft -and
            $candidateBottom -ge $candidateTop
        if ($boundsUsable -and $lastAcceptedRegion -eq $candidateRegion) {
            $stableRegionReads++
        }
        elseif ($boundsUsable) {
            $lastAcceptedRegion = $candidateRegion
            $stableRegionReads = 1
        }
        else {
            $lastAcceptedRegion = $null
            $stableRegionReads = 0
        }
        if ($stableRegionReads -ge 2) {
            $targetBounds = $candidateBounds
            $left = $candidateLeft
            $right = $candidateRight
            $top = $candidateTop
            $bottom = $candidateBottom
            break
        }
        Start-Sleep -Milliseconds 100
    }
    if ($stableRegionReads -lt 2) {
        $message = (
            "Target-left pixel region could not be stabilized inside the " +
            "dashboard capture. Window={0},{1},{2},{3}; Target={4},{5},{6},{7}; " +
            "Region={8}; StableReads={9}; BoundsUsable={10}."
        ) -f
                $windowRect.Left,
                $windowRect.Top,
                $windowRect.Right,
                $windowRect.Bottom,
                $lastCandidateBounds.Left,
                $lastCandidateBounds.Top,
                $lastCandidateBounds.Right,
                $lastCandidateBounds.Bottom,
                $lastCandidateRegion,
                $stableRegionReads,
                $boundsUsable
        throw $message
    }

    $bitmap = New-Object System.Drawing.Bitmap $width, $height
    $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
    try {
        $graphics.CopyFromScreen(
            $windowRect.Left,
            $windowRect.Top,
            0,
            0,
            $bitmap.Size)

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
        HeaderTitleText = $headerTitle.Current.Name
        HeaderRightGapPixels = $headerRightGap
        PowerLineText = $powerLine.Current.Name
        TargetInputText = $targetInput.Current.Name
        TargetLeftArtifactPixels = 0
        StatusStateWidthPixels = [int]$stateBounds.Width
        StatusStateWidthRatio = [Math]::Round($stateWidthRatio, 4)
        StatusBarDetailsButton = "Absent"
        StatusBarOverlap = "PASS"
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
