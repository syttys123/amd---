param(
    [string]$OutputPath = "docs\assets\bilibili-cover-2026-11-10.png"
)

$ErrorActionPreference = "Stop"

$root = Split-Path -Parent $PSCommandPath
function Resolve-ProjectPath {
    param([string]$Path)

    if ([IO.Path]::IsPathRooted($Path)) {
        return [IO.Path]::GetFullPath($Path)
    }
    return [IO.Path]::GetFullPath((Join-Path $root $Path))
}

function New-RoundedPath {
    param(
        [Drawing.RectangleF]$Rectangle,
        [float]$Radius
    )

    $path = [Drawing.Drawing2D.GraphicsPath]::new()
    $diameter = [Math]::Min($Radius * 2, [Math]::Min($Rectangle.Width, $Rectangle.Height))
    $path.AddArc($Rectangle.X, $Rectangle.Y, $diameter, $diameter, 180, 90)
    $path.AddArc(
        $Rectangle.Right - $diameter,
        $Rectangle.Y,
        $diameter,
        $diameter,
        270,
        90)
    $path.AddArc(
        $Rectangle.Right - $diameter,
        $Rectangle.Bottom - $diameter,
        $diameter,
        $diameter,
        0,
        90)
    $path.AddArc(
        $Rectangle.X,
        $Rectangle.Bottom - $diameter,
        $diameter,
        $diameter,
        90,
        90)
    $path.CloseFigure()
    return $path
}

function Draw-RoundedFill {
    param(
        [Drawing.Graphics]$Graphics,
        [Drawing.RectangleF]$Rectangle,
        [float]$Radius,
        [Drawing.Brush]$Brush
    )

    $path = New-RoundedPath -Rectangle $Rectangle -Radius $Radius
    try {
        $Graphics.FillPath($Brush, $path)
    }
    finally {
        $path.Dispose()
    }
}

function Draw-ContainedImage {
    param(
        [Drawing.Graphics]$Graphics,
        [Drawing.Image]$Image,
        [Drawing.RectangleF]$Bounds,
        [float]$Radius
    )

    $scale = [Math]::Min(
        $Bounds.Width / $Image.Width,
        $Bounds.Height / $Image.Height)
    $width = $Image.Width * $scale
    $height = $Image.Height * $scale
    $destination = [Drawing.RectangleF]::new(
        $Bounds.X + (($Bounds.Width - $width) / 2),
        $Bounds.Y + (($Bounds.Height - $height) / 2),
        $width,
        $height)
    $path = New-RoundedPath -Rectangle $destination -Radius $Radius
    $state = $Graphics.Save()
    try {
        $Graphics.SetClip($path)
        $Graphics.DrawImage(
            $Image,
            [Drawing.RectangleF]::new(
                [float]$destination.X,
                [float]$destination.Y,
                [float]$destination.Width,
                [float]$destination.Height))
    }
    finally {
        $Graphics.Restore($state)
        $path.Dispose()
    }
}

function Assert-TextWidth {
    param(
        [Drawing.Graphics]$Graphics,
        [string]$Name,
        [string]$Text,
        [Drawing.Font]$Font,
        [float]$MaximumWidth
    )

    $size = $Graphics.MeasureString($Text, $Font)
    if ($size.Width -gt $MaximumWidth) {
        throw "$Name exceeds its safe width: $($size.Width) > $MaximumWidth"
    }
}

Add-Type -AssemblyName System.Drawing

$resolvedOutputPath = Resolve-ProjectPath $OutputPath
$outputDirectory = Split-Path -Parent $resolvedOutputPath
New-Item -ItemType Directory -Path $outputDirectory -Force | Out-Null

$screenshotPath = Resolve-ProjectPath "docs\assets\main-dashboard-clean-package-2026-11-10.png"
$iconPath = Resolve-ProjectPath "assets\amd-mobile-power-256.png"
if (-not (Test-Path -LiteralPath $screenshotPath)) {
    throw "Dashboard screenshot not found: $screenshotPath"
}
if (-not (Test-Path -LiteralPath $iconPath)) {
    throw "Application icon not found: $iconPath"
}

$width = 1146
$height = 717
$backgroundTop = [Drawing.Color]::FromArgb(10, 22, 26)
$backgroundBottom = [Drawing.Color]::FromArgb(19, 49, 45)
$textPrimary = [Drawing.Color]::FromArgb(241, 247, 244)
$textMuted = [Drawing.Color]::FromArgb(169, 188, 180)
$accent = [Drawing.Color]::FromArgb(69, 214, 168)
$amber = [Drawing.Color]::FromArgb(255, 180, 90)
$surface = [Drawing.Color]::FromArgb(246, 250, 248)
$fontFamily = "Microsoft YaHei UI"

$bitmap = [Drawing.Bitmap]::new($width, $height)
$graphics = [Drawing.Graphics]::FromImage($bitmap)
$screenshot = [Drawing.Image]::FromFile($screenshotPath)
$icon = [Drawing.Image]::FromFile($iconPath)
try {
    $graphics.SmoothingMode = [Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $graphics.InterpolationMode = [Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
    $graphics.PixelOffsetMode = [Drawing.Drawing2D.PixelOffsetMode]::HighQuality
    $graphics.TextRenderingHint = [Drawing.Text.TextRenderingHint]::ClearTypeGridFit

    $bounds = [Drawing.Rectangle]::new(0, 0, $width, $height)
    $background = [Drawing.Drawing2D.LinearGradientBrush]::new(
        $bounds,
        $backgroundTop,
        $backgroundBottom,
        24)
    try {
        $graphics.FillRectangle($background, $bounds)
    }
    finally {
        $background.Dispose()
    }

    $gridPen = [Drawing.Pen]::new([Drawing.Color]::FromArgb(18, 105, 145, 132), 1)
    try {
        for ($x = 38; $x -lt $width; $x += 54) {
            $graphics.DrawLine($gridPen, $x, 0, $x, $height)
        }
        for ($y = 38; $y -lt $height; $y += 54) {
            $graphics.DrawLine($gridPen, 0, $y, $width, $y)
        }
    }
    finally {
        $gridPen.Dispose()
    }

    $accentPen = [Drawing.Pen]::new([Drawing.Color]::FromArgb(140, $accent), 4)
    try {
        $graphics.DrawLine($accentPen, 0, 0, 270, 0)
        $graphics.DrawLine($accentPen, 900, 0, $width, 0)
    }
    finally {
        $accentPen.Dispose()
    }

    $graphics.DrawImage($icon, 48, 42, 38, 38)
    $brandFont = [Drawing.Font]::new("Segoe UI", 18, [Drawing.FontStyle]::Bold)
    $brandBrush = [Drawing.SolidBrush]::new($textPrimary)
    try {
        $graphics.DrawString("AMD Mobile Power", $brandFont, $brandBrush, 98, 51)
    }
    finally {
        $brandFont.Dispose()
        $brandBrush.Dispose()
    }

    $previewFont = [Drawing.Font]::new("Segoe UI", 14, [Drawing.FontStyle]::Bold)
    $previewBrush = [Drawing.SolidBrush]::new($amber)
    $previewFormat = [Drawing.StringFormat]::new()
    $previewFormat.Alignment = [Drawing.StringAlignment]::Far
    try {
        $graphics.DrawString(
            "DEV PREVIEW",
            $previewFont,
            $previewBrush,
            [Drawing.RectangleF]::new(880, 52, 218, 26),
            $previewFormat)
    }
    finally {
        $previewFont.Dispose()
        $previewBrush.Dispose()
        $previewFormat.Dispose()
    }

    $eyebrowFont = [Drawing.Font]::new("Segoe UI", 16, [Drawing.FontStyle]::Bold)
    $titleFont = [Drawing.Font]::new($fontFamily, 54, [Drawing.FontStyle]::Bold)
    $accentTitleFont = [Drawing.Font]::new($fontFamily, 66, [Drawing.FontStyle]::Bold)
    $subtitleFont = [Drawing.Font]::new($fontFamily, 24, [Drawing.FontStyle]::Regular)
    $eyebrowBrush = [Drawing.SolidBrush]::new($accent)
    $titleBrush = [Drawing.SolidBrush]::new($textPrimary)
    $accentBrush = [Drawing.SolidBrush]::new($accent)
    $subtitleBrush = [Drawing.SolidBrush]::new($textMuted)
    try {
        Assert-TextWidth $graphics "eyebrow" "AMD THIN & LIGHT" $eyebrowFont 500
        Assert-TextWidth $graphics "title line 1" "AMD 轻薄本" $titleFont 500
        Assert-TextWidth $graphics "title line 2" "功耗看得见" $accentTitleFont 500
        Assert-TextWidth $graphics "subtitle" "实时功耗 · 可编辑预设 · 只读诊断" $subtitleFont 500

        $graphics.DrawString("AMD THIN & LIGHT", $eyebrowFont, $eyebrowBrush, 50, 136)
        $graphics.DrawString("AMD 轻薄本", $titleFont, $titleBrush, 50, 178)
        $graphics.DrawString("功耗看得见", $accentTitleFont, $accentBrush, 50, 250)
        $graphics.DrawString(
            "实时功耗 · 可编辑预设 · 只读诊断",
            $subtitleFont,
            $subtitleBrush,
            52,
            342)
    }
    finally {
        $eyebrowFont.Dispose()
        $titleFont.Dispose()
        $accentTitleFont.Dispose()
        $subtitleFont.Dispose()
        $eyebrowBrush.Dispose()
        $titleBrush.Dispose()
        $accentBrush.Dispose()
        $subtitleBrush.Dispose()
    }

    $pillFont = [Drawing.Font]::new($fontFamily, 17, [Drawing.FontStyle]::Bold)
    $pillBrush = [Drawing.SolidBrush]::new($accent)
    $pillFill = [Drawing.SolidBrush]::new([Drawing.Color]::FromArgb(28, 69, 214, 168))
    $pillBorder = [Drawing.Pen]::new([Drawing.Color]::FromArgb(130, 69, 214, 168), 1)
    try {
        $pillX = 52.0
        foreach ($text in @("原生 GUI", "1 秒刷新", "回读校验")) {
            $size = $graphics.MeasureString($text, $pillFont)
            $rectangle = [Drawing.RectangleF]::new(
                $pillX,
                414,
                $size.Width + 30,
                $size.Height + 14)
            Draw-RoundedFill -Graphics $graphics -Rectangle $rectangle -Radius 8 -Brush $pillFill
            $path = New-RoundedPath -Rectangle $rectangle -Radius 8
            try {
                $graphics.DrawPath($pillBorder, $path)
            }
            finally {
                $path.Dispose()
            }
            $graphics.DrawString(
                $text,
                $pillFont,
                $pillBrush,
                [Drawing.RectangleF]::new(
                    $rectangle.X + 15,
                    $rectangle.Y + 7,
                    $rectangle.Width - 30,
                    $rectangle.Height - 14))
            $pillX += $rectangle.Width + 10
        }
    }
    finally {
        $pillFont.Dispose()
        $pillBrush.Dispose()
        $pillFill.Dispose()
        $pillBorder.Dispose()
    }

    $cardRectangle = [Drawing.RectangleF]::new(602, 116, 492, 456)
    $shadowRectangle = [Drawing.RectangleF]::new(612, 128, 492, 456)
    $shadowBrush = [Drawing.SolidBrush]::new([Drawing.Color]::FromArgb(90, 0, 0, 0))
    $cardBrush = [Drawing.SolidBrush]::new($surface)
    try {
        Draw-RoundedFill -Graphics $graphics -Rectangle $shadowRectangle -Radius 8 -Brush $shadowBrush
        Draw-RoundedFill -Graphics $graphics -Rectangle $cardRectangle -Radius 8 -Brush $cardBrush
        Draw-ContainedImage `
            -Graphics $graphics `
            -Image $screenshot `
            -Bounds ([Drawing.RectangleF]::new(626, 140, 444, 408)) `
            -Radius 6
    }
    finally {
        $shadowBrush.Dispose()
        $cardBrush.Dispose()
    }

    $footerFont = [Drawing.Font]::new("Consolas", 15, [Drawing.FontStyle]::Bold)
    $footerBrush = [Drawing.SolidBrush]::new($accent)
    $footerMutedBrush = [Drawing.SolidBrush]::new($textMuted)
    try {
        $graphics.DrawString(
            "github.com/syttys123/amd-mobile-power",
            $footerFont,
            $footerBrush,
            50,
            622)
        $graphics.DrawString(
            "READ-ONLY DEV BUILD",
            $footerFont,
            $footerMutedBrush,
            846,
            622)
    }
    finally {
        $footerFont.Dispose()
        $footerBrush.Dispose()
        $footerMutedBrush.Dispose()
    }

    $bitmap.Save($resolvedOutputPath, [Drawing.Imaging.ImageFormat]::Png)
}
finally {
    $icon.Dispose()
    $screenshot.Dispose()
    $graphics.Dispose()
    $bitmap.Dispose()
}

$hash = (Get-FileHash -LiteralPath $resolvedOutputPath -Algorithm SHA256).Hash.ToLowerInvariant()
[pscustomobject]@{
    Output = $resolvedOutputPath
    Width = $width
    Height = $height
    SHA256 = $hash
    TextSafeWidth = "PASS"
} | Format-List
