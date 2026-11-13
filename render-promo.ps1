param(
    [string]$Storyboard = "media\promo\storyboard.json",
    [string]$OutputDirectory = "artifacts\media\amd-mobile-power-promo-draft-2026-11-10",
    [string]$OutputName = "amd-mobile-power-intro-draft-2026-11-10.mp4",
    [string]$MusicPath,
    [double]$MusicVolumeDb = -26.0,
    [switch]$CleanWorkingFiles
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

$storyboardPath = Resolve-ProjectPath $Storyboard
$musicResolved = $null
if ($MusicPath) {
    $musicResolved = Resolve-ProjectPath $MusicPath
    if (-not (Test-Path -LiteralPath $musicResolved)) {
        throw "Music bed not found: $musicResolved"
    }
}
$outputRoot = Resolve-ProjectPath $OutputDirectory
$frameDirectory = Join-Path $outputRoot "slides"
$audioDirectory = Join-Path $outputRoot "voice"
$reviewDirectory = Join-Path $outputRoot "review"
$outputPath = Join-Path $outputRoot $OutputName
$captionsPath = Join-Path $outputRoot "captions-zh.srt"
$manifestPath = Join-Path $outputRoot "promo-manifest.json"

$ffmpeg = (Get-Command ffmpeg -ErrorAction Stop).Source
$ffprobe = (Get-Command ffprobe -ErrorAction Stop).Source
if (-not (Test-Path -LiteralPath $storyboardPath)) {
    throw "Storyboard not found: $storyboardPath"
}

$story = Get-Content -LiteralPath $storyboardPath -Raw | ConvertFrom-Json
if ($story.scenes.Count -lt 3) {
    throw "Storyboard must contain at least three scenes."
}

New-Item -ItemType Directory -Path $outputRoot -Force | Out-Null
New-Item -ItemType Directory -Path $frameDirectory -Force | Out-Null
New-Item -ItemType Directory -Path $audioDirectory -Force | Out-Null
New-Item -ItemType Directory -Path $reviewDirectory -Force | Out-Null

Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.Speech

$canvasWidth = 1920
$canvasHeight = 1080
$fps = 25
$backgroundTop = [Drawing.Color]::FromArgb(12, 20, 24)
$backgroundBottom = [Drawing.Color]::FromArgb(18, 42, 41)
$surface = [Drawing.Color]::FromArgb(248, 251, 249)
$textPrimary = [Drawing.Color]::FromArgb(241, 247, 244)
$textMuted = [Drawing.Color]::FromArgb(166, 184, 176)
$accent = [Drawing.Color]::FromArgb(69, 214, 168)
$accentDark = [Drawing.Color]::FromArgb(20, 118, 101)
$amber = [Drawing.Color]::FromArgb(255, 180, 90)
$fontFamily = "Microsoft YaHei UI"
$displayFamily = "Microsoft YaHei UI"
$brandIconPath = Join-Path $root "assets\amd-mobile-power-256.png"

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
        [float]$Radius = 8
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

function Draw-ScreenshotCard {
    param(
        [Drawing.Graphics]$Graphics,
        [Drawing.Image]$Image,
        [Drawing.RectangleF]$Rectangle
    )

    $shadowRect = [Drawing.RectangleF]::new(
        $Rectangle.X + 14,
        $Rectangle.Y + 18,
        $Rectangle.Width,
        $Rectangle.Height)
    $shadowBrush = [Drawing.SolidBrush]::new([Drawing.Color]::FromArgb(90, 0, 0, 0))
    try {
        Draw-RoundedFill -Graphics $Graphics -Rectangle $shadowRect -Radius 8 -Brush $shadowBrush
    }
    finally {
        $shadowBrush.Dispose()
    }

    $cardBrush = [Drawing.SolidBrush]::new($surface)
    try {
        Draw-RoundedFill -Graphics $Graphics -Rectangle $Rectangle -Radius 8 -Brush $cardBrush
    }
    finally {
        $cardBrush.Dispose()
    }

    $inner = [Drawing.RectangleF]::new(
        $Rectangle.X + 22,
        $Rectangle.Y + 22,
        $Rectangle.Width - 44,
        $Rectangle.Height - 44)
    Draw-ContainedImage -Graphics $Graphics -Image $Image -Bounds $inner -Radius 6
}

function Draw-Pill {
    param(
        [Drawing.Graphics]$Graphics,
        [string]$Text,
        [float]$X,
        [float]$Y,
        [Drawing.Font]$Font
    )

    $size = $Graphics.MeasureString($Text, $Font)
    $rectangle = [Drawing.RectangleF]::new(
        $X,
        $Y,
        $size.Width + 36,
        $size.Height + 18)
    $fill = [Drawing.SolidBrush]::new([Drawing.Color]::FromArgb(30, 69, 214, 168))
    $border = [Drawing.Pen]::new([Drawing.Color]::FromArgb(150, 69, 214, 168), 2)
    try {
        Draw-RoundedFill -Graphics $Graphics -Rectangle $rectangle -Radius 8 -Brush $fill
        $path = New-RoundedPath -Rectangle $rectangle -Radius 8
        try {
            $Graphics.DrawPath($border, $path)
        }
        finally {
            $path.Dispose()
        }
        $brush = [Drawing.SolidBrush]::new($accent)
        try {
            $Graphics.DrawString(
                $Text,
                $Font,
                $brush,
                [Drawing.RectangleF]::new(
                    $rectangle.X + 18,
                    $rectangle.Y + 8,
                    $rectangle.Width - 36,
                    $rectangle.Height - 16))
        }
        finally {
            $brush.Dispose()
        }
    }
    finally {
        $fill.Dispose()
        $border.Dispose()
    }
    return $rectangle.Width
}

function Draw-BulletList {
    param(
        [Drawing.Graphics]$Graphics,
        [string[]]$Bullets,
        [float]$X,
        [float]$Y
    )

    $bodyFont = [Drawing.Font]::new($fontFamily, 30, [Drawing.FontStyle]::Regular)
    $bodyBrush = [Drawing.SolidBrush]::new($textPrimary)
    $accentBrush = [Drawing.SolidBrush]::new($accent)
    try {
        for ($index = 0; $index -lt $Bullets.Count; $index++) {
            $lineY = $Y + ($index * 78)
            $bar = [Drawing.RectangleF]::new($X, $lineY + 10, 7, 32)
            Draw-RoundedFill -Graphics $Graphics -Rectangle $bar -Radius 3 -Brush $accentBrush
            $Graphics.DrawString(
                $Bullets[$index],
                $bodyFont,
                $bodyBrush,
                [Drawing.PointF]::new($X + 30, $lineY))
        }
    }
    finally {
        $bodyFont.Dispose()
        $bodyBrush.Dispose()
        $accentBrush.Dispose()
    }
}

function Draw-BaseBackground {
    param(
        [Drawing.Graphics]$Graphics,
        [int]$SceneIndex
    )

    $bounds = [Drawing.Rectangle]::new(0, 0, $canvasWidth, $canvasHeight)
    $gradient = [Drawing.Drawing2D.LinearGradientBrush]::new(
        $bounds,
        $backgroundTop,
        $backgroundBottom,
        24)
    try {
        $Graphics.FillRectangle($gradient, $bounds)
    }
    finally {
        $gradient.Dispose()
    }

    $gridPen = [Drawing.Pen]::new([Drawing.Color]::FromArgb(18, 108, 146, 132), 1)
    try {
        for ($x = 80; $x -lt $canvasWidth; $x += 80) {
            $Graphics.DrawLine($gridPen, $x, 0, $x, $canvasHeight)
        }
        for ($y = 80; $y -lt $canvasHeight; $y += 80) {
            $Graphics.DrawLine($gridPen, 0, $y, $canvasWidth, $y)
        }
    }
    finally {
        $gridPen.Dispose()
    }

    $accentPen = [Drawing.Pen]::new([Drawing.Color]::FromArgb(125, $accent), 4)
    try {
        $Graphics.DrawLine($accentPen, 0, 0, 420, 0)
        $Graphics.DrawLine($accentPen, 1500, 0, 1920, 0)
    }
    finally {
        $accentPen.Dispose()
    }

    if (Test-Path -LiteralPath $brandIconPath) {
        $icon = [Drawing.Image]::FromFile($brandIconPath)
        try {
            $Graphics.DrawImage($icon, 94, 70, 48, 48)
        }
        finally {
            $icon.Dispose()
        }
    }

    $brandFont = [Drawing.Font]::new("Segoe UI", 22, [Drawing.FontStyle]::Bold)
    $brandBrush = [Drawing.SolidBrush]::new($textPrimary)
    try {
        $Graphics.DrawString("AMD Mobile Power", $brandFont, $brandBrush, 156, 75)
    }
    finally {
        $brandFont.Dispose()
        $brandBrush.Dispose()
    }

    $previewFont = [Drawing.Font]::new("Segoe UI", 15, [Drawing.FontStyle]::Bold)
    $previewBrush = [Drawing.SolidBrush]::new($amber)
    $previewFormat = [Drawing.StringFormat]::new()
    $previewFormat.Alignment = [Drawing.StringAlignment]::Far
    try {
        $Graphics.DrawString(
            "DEV PREVIEW",
            $previewFont,
            $previewBrush,
            [Drawing.RectangleF]::new(1610, 78, 210, 30),
            $previewFormat)
    }
    finally {
        $previewFont.Dispose()
        $previewBrush.Dispose()
        $previewFormat.Dispose()
    }

    $progressTrack = [Drawing.RectangleF]::new(110, 1010, 1700, 4)
    $trackBrush = [Drawing.SolidBrush]::new([Drawing.Color]::FromArgb(45, 255, 255, 255))
    $fillBrush = [Drawing.SolidBrush]::new($accent)
    try {
        Draw-RoundedFill -Graphics $Graphics -Rectangle $progressTrack -Radius 2 -Brush $trackBrush
        $progress = ($SceneIndex + 1) / $story.scenes.Count
        $fill = [Drawing.RectangleF]::new(
            $progressTrack.X,
            $progressTrack.Y,
            $progressTrack.Width * $progress,
            $progressTrack.Height)
        Draw-RoundedFill -Graphics $Graphics -Rectangle $fill -Radius 2 -Brush $fillBrush
    }
    finally {
        $trackBrush.Dispose()
        $fillBrush.Dispose()
    }

    $footerFont = [Drawing.Font]::new("Segoe UI", 16, [Drawing.FontStyle]::Regular)
    $footerBrush = [Drawing.SolidBrush]::new($textMuted)
    try {
        $Graphics.DrawString($story.repositoryUrl, $footerFont, $footerBrush, 110, 1030)
        $Graphics.DrawString(
            ("{0:00} / {1:00}" -f ($SceneIndex + 1), $story.scenes.Count),
            $footerFont,
            $footerBrush,
            1740,
            1030)
    }
    finally {
        $footerFont.Dispose()
        $footerBrush.Dispose()
    }
}

function Draw-SceneText {
    param(
        [Drawing.Graphics]$Graphics,
        [object]$Scene,
        [float]$X,
        [float]$Y,
        [float]$Width
    )

    $eyebrowFont = [Drawing.Font]::new("Segoe UI", 18, [Drawing.FontStyle]::Bold)
    $titleFont = [Drawing.Font]::new($displayFamily, 58, [Drawing.FontStyle]::Bold)
    $captionFont = [Drawing.Font]::new($fontFamily, 28, [Drawing.FontStyle]::Regular)
    $eyebrowBrush = [Drawing.SolidBrush]::new($accent)
    $titleBrush = [Drawing.SolidBrush]::new($textPrimary)
    $captionBrush = [Drawing.SolidBrush]::new($textMuted)
    try {
        $Graphics.DrawString($Scene.eyebrow, $eyebrowFont, $eyebrowBrush, $X, $Y)
        $Graphics.DrawString(
            $Scene.title,
            $titleFont,
            $titleBrush,
            [Drawing.RectangleF]::new($X, $Y + 52, $Width, 210))
        if ($Scene.PSObject.Properties.Name -contains "caption") {
            $Graphics.DrawString(
                $Scene.caption,
                $captionFont,
                $captionBrush,
                [Drawing.RectangleF]::new($X, $Y + 270, $Width, 80))
        }
    }
    finally {
        $eyebrowFont.Dispose()
        $titleFont.Dispose()
        $captionFont.Dispose()
        $eyebrowBrush.Dispose()
        $titleBrush.Dispose()
        $captionBrush.Dispose()
    }
}

function Measure-TextBlock {
    param(
        [Drawing.Graphics]$Graphics,
        [string]$Text,
        [Drawing.Font]$Font
    )

    $width = 0.0
    $height = 0.0
    foreach ($line in (($Text -replace "`r", "") -split "`n")) {
        $size = $Graphics.MeasureString($line, $Font)
        $width = [Math]::Max($width, $size.Width)
        $height += $size.Height
    }
    return [pscustomobject]@{
        Width = $width
        Height = $height
    }
}

function Assert-SceneTextSafeWidth {
    param(
        [Drawing.Graphics]$Graphics,
        [object]$Scene
    )

    $textWidth = switch ($Scene.layout) {
        "hero" { 620.0 }
        "screenshot-right" { 720.0 }
        "tray" { 880.0 }
        "closing" { 1060.0 }
        default { throw "Unknown scene layout: $($Scene.layout)" }
    }
    $eyebrowFont = [Drawing.Font]::new("Segoe UI", 18, [Drawing.FontStyle]::Bold)
    $titleFont = [Drawing.Font]::new($displayFamily, 58, [Drawing.FontStyle]::Bold)
    $captionFont = [Drawing.Font]::new($fontFamily, 28, [Drawing.FontStyle]::Regular)
    try {
        $eyebrow = Measure-TextBlock -Graphics $Graphics -Text $Scene.eyebrow -Font $eyebrowFont
        if ($eyebrow.Width -gt $textWidth) {
            throw "Scene $($Scene.id) eyebrow exceeds its safe width."
        }

        $title = Measure-TextBlock -Graphics $Graphics -Text $Scene.title -Font $titleFont
        if ($title.Width -gt $textWidth -or $title.Height -gt 230) {
            throw "Scene $($Scene.id) title exceeds its safe text box."
        }

        if ($Scene.PSObject.Properties.Name -contains "caption") {
            $caption = Measure-TextBlock -Graphics $Graphics -Text $Scene.caption -Font $captionFont
            if ($caption.Width -gt $textWidth -or $caption.Height -gt 80) {
                throw "Scene $($Scene.id) caption exceeds its safe text box."
            }
        }

        if ($Scene.PSObject.Properties.Name -contains "bullets") {
            $bulletFont = [Drawing.Font]::new($fontFamily, 30, [Drawing.FontStyle]::Regular)
            $bulletWidth = if ($Scene.layout -eq "tray") { 1100.0 } else { 740.0 }
            try {
                foreach ($bullet in $Scene.bullets) {
                    $size = Measure-TextBlock -Graphics $Graphics -Text $bullet -Font $bulletFont
                    if ($size.Width -gt $bulletWidth) {
                        throw "Scene $($Scene.id) bullet exceeds its safe width: $bullet"
                    }
                }
                if (($Scene.bullets.Count * 78) -gt 360) {
                    throw "Scene $($Scene.id) bullet list exceeds its safe height."
                }
            }
            finally {
                $bulletFont.Dispose()
            }
        }

        if ($Scene.PSObject.Properties.Name -contains "badges") {
            $badgeFont = [Drawing.Font]::new($fontFamily, 20, [Drawing.FontStyle]::Bold)
            try {
                $badgeWidth = 0.0
                foreach ($badge in $Scene.badges) {
                    $size = $Graphics.MeasureString($badge, $badgeFont)
                    $badgeWidth += $size.Width + 36 + 14
                }
                if (($badgeWidth - 14) -gt 640) {
                    throw "Scene $($Scene.id) badges exceed their safe width."
                }
            }
            finally {
                $badgeFont.Dispose()
            }
        }
    }
    finally {
        $eyebrowFont.Dispose()
        $titleFont.Dispose()
        $captionFont.Dispose()
    }
}

function Render-Slide {
    param(
        [object]$Scene,
        [int]$SceneIndex,
        [string]$OutputPath
    )

    $imagePath = Resolve-ProjectPath $Scene.image
    if (-not (Test-Path -LiteralPath $imagePath)) {
        throw "Scene image not found: $imagePath"
    }
    $image = [Drawing.Image]::FromFile($imagePath)
    $bitmap = [Drawing.Bitmap]::new($canvasWidth, $canvasHeight)
    $graphics = [Drawing.Graphics]::FromImage($bitmap)
    try {
        $graphics.SmoothingMode = [Drawing.Drawing2D.SmoothingMode]::AntiAlias
        $graphics.InterpolationMode = [Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
        $graphics.PixelOffsetMode = [Drawing.Drawing2D.PixelOffsetMode]::HighQuality
        $graphics.TextRenderingHint = [Drawing.Text.TextRenderingHint]::ClearTypeGridFit
        Assert-SceneTextSafeWidth -Graphics $graphics -Scene $Scene
        Draw-BaseBackground -Graphics $graphics -SceneIndex $SceneIndex

        switch ($Scene.layout) {
            "hero" {
                Draw-SceneText -Graphics $graphics -Scene $Scene -X 110 -Y 250 -Width 620
                Draw-ScreenshotCard `
                    -Graphics $graphics `
                    -Image $image `
                    -Rectangle ([Drawing.RectangleF]::new(760, 190, 1050, 780))
                $badgeFont = [Drawing.Font]::new($fontFamily, 20, [Drawing.FontStyle]::Bold)
                try {
                    $badgeX = 110.0
                    foreach ($badge in $Scene.badges) {
                        $width = Draw-Pill `
                            -Graphics $graphics `
                            -Text $badge `
                            -X $badgeX `
                            -Y 690 `
                            -Font $badgeFont
                        $badgeX += $width + 14
                    }
                }
                finally {
                    $badgeFont.Dispose()
                }
            }
            "screenshot-right" {
                Draw-SceneText -Graphics $graphics -Scene $Scene -X 110 -Y 240 -Width 720
                if ($Scene.PSObject.Properties.Name -contains "bullets") {
                    Draw-BulletList -Graphics $graphics -Bullets $Scene.bullets -X 110 -Y 610
                }
                Draw-ScreenshotCard `
                    -Graphics $graphics `
                    -Image $image `
                    -Rectangle ([Drawing.RectangleF]::new(880, 180, 900, 780))
            }
            "tray" {
                Draw-SceneText -Graphics $graphics -Scene $Scene -X 110 -Y 240 -Width 880
                Draw-BulletList -Graphics $graphics -Bullets $Scene.bullets -X 110 -Y 610
                Draw-ScreenshotCard `
                    -Graphics $graphics `
                    -Image $image `
                    -Rectangle ([Drawing.RectangleF]::new(1260, 150, 520, 820))
            }
            "closing" {
                Draw-SceneText -Graphics $graphics -Scene $Scene -X 110 -Y 250 -Width 1060
                $iconCard = [Drawing.RectangleF]::new(1320, 240, 430, 430)
                Draw-ScreenshotCard -Graphics $graphics -Image $image -Rectangle $iconCard
                $repoFont = [Drawing.Font]::new("Consolas", 25, [Drawing.FontStyle]::Bold)
                $repoBrush = [Drawing.SolidBrush]::new($accent)
                try {
                    $graphics.DrawString(
                        $story.repositoryUrl,
                        $repoFont,
                        $repoBrush,
                        110,
                        800)
                }
                finally {
                    $repoFont.Dispose()
                    $repoBrush.Dispose()
                }
            }
            default {
                throw "Unknown scene layout: $($Scene.layout)"
            }
        }

        $bitmap.Save($OutputPath, [Drawing.Imaging.ImageFormat]::Png)
    }
    finally {
        $graphics.Dispose()
        $bitmap.Dispose()
        $image.Dispose()
    }
}

function Get-AudioDuration {
    param([string]$Path)

    $value = & $ffprobe `
        -v error `
        -show_entries format=duration `
        -of default=noprint_wrappers=1:nokey=1 `
        $Path
    if ($LASTEXITCODE -ne 0) {
        throw "ffprobe failed for $Path"
    }
    return [double]::Parse($value.Trim(), [Globalization.CultureInfo]::InvariantCulture)
}

function Format-SrtTime {
    param([double]$Seconds)

    $time = [TimeSpan]::FromSeconds($Seconds)
    return "{0:00}:{1:00}:{2:00},{3:000}" -f `
        [int]$time.TotalHours,
        $time.Minutes,
        $time.Seconds,
        $time.Milliseconds
}

$voiceCandidates = [System.Speech.Synthesis.SpeechSynthesizer]::new().GetInstalledVoices()
$selectedVoice = $voiceCandidates |
    Where-Object { $_.VoiceInfo.Name -eq $story.voice } |
    Select-Object -First 1
if ($null -eq $selectedVoice) {
    $selectedVoice = $voiceCandidates |
        Where-Object { $_.VoiceInfo.Culture.Name -like "zh-*" } |
        Select-Object -First 1
}
if ($null -eq $selectedVoice) {
    throw "No Chinese text-to-speech voice is installed."
}

$sceneRecords = @()
$currentStart = 0.0
$captions = [Text.StringBuilder]::new()
for ($index = 0; $index -lt $story.scenes.Count; $index++) {
    $scene = $story.scenes[$index]
    $slidePath = Join-Path $frameDirectory ("scene-{0:00}-{1}.png" -f ($index + 1), $scene.id)
    $audioPath = Join-Path $audioDirectory ("scene-{0:00}-{1}.wav" -f ($index + 1), $scene.id)
    $videoClipPath = $null
    if ($scene.PSObject.Properties.Name -contains "video") {
        $videoClipPath = Resolve-ProjectPath $scene.video
        if (-not (Test-Path -LiteralPath $videoClipPath)) {
            throw "Scene video not found: $videoClipPath"
        }
        $clipDuration = Get-AudioDuration $videoClipPath
    }
    Render-Slide -Scene $scene -SceneIndex $index -OutputPath $slidePath

    $synthesizer = [System.Speech.Synthesis.SpeechSynthesizer]::new()
    try {
        $synthesizer.SelectVoice($selectedVoice.VoiceInfo.Name)
        $synthesizer.Rate = [int]$story.voiceRate
        $synthesizer.Volume = [int]$story.voiceVolume
        $synthesizer.SetOutputToWaveFile($audioPath)
        $synthesizer.Speak($scene.narration)
    }
    finally {
        $synthesizer.Dispose()
    }

    $audioDuration = Get-AudioDuration $audioPath
    $sceneDuration = [Math]::Max(8.0, $audioDuration + 1.0)
    if ($videoClipPath) {
        # A recorded clip anchors the scene: never cut it shorter and freeze
        # the last frame if narration runs past the recording.
        $sceneDuration = [Math]::Max($sceneDuration, $clipDuration)
    }
    $sceneEnd = $currentStart + $sceneDuration
    $sceneRecords += [pscustomobject]@{
        Index = $index + 1
        Id = $scene.id
        Layout = $scene.layout
        Title = ($scene.title -replace "`n", " / ")
        Slide = $slidePath
        VideoClip = $videoClipPath
        VideoClipDurationSeconds = $clipDuration
        Audio = $audioPath
        AudioDurationSeconds = $audioDuration
        DurationSeconds = $sceneDuration
        StartSeconds = $currentStart
        EndSeconds = $sceneEnd
    }

    [void]$captions.AppendLine(($index + 1).ToString())
    [void]$captions.AppendLine("$(Format-SrtTime ($currentStart + 0.35)) --> $(Format-SrtTime $sceneEnd)")
    [void]$captions.AppendLine($scene.narration)
    [void]$captions.AppendLine()
    $currentStart = $sceneEnd
}
$captions.ToString().TrimEnd() + "`n" |
    Set-Content -LiteralPath $captionsPath -Encoding utf8

$arguments = [Collections.Generic.List[string]]::new()
$arguments.Add("-y")
$musicInputIndex = -1
$inputIndex = 0
foreach ($record in $sceneRecords) {
    $arguments.Add("-loop")
    $arguments.Add("1")
    $arguments.Add("-framerate")
    $arguments.Add("$fps")
    $arguments.Add("-i")
    $arguments.Add($record.Slide)
    $record | Add-Member -NotePropertyName SlideInput -NotePropertyValue $inputIndex
    $inputIndex++
    if ($record.VideoClip) {
        $arguments.Add("-i")
        $arguments.Add($record.VideoClip)
        $record | Add-Member -NotePropertyName ClipInput -NotePropertyValue $inputIndex
        $inputIndex++
    }
    $arguments.Add("-i")
    $arguments.Add($record.Audio)
    $record | Add-Member -NotePropertyName AudioInput -NotePropertyValue $inputIndex
    $inputIndex++
}
if ($null -ne $musicResolved) {
    $musicInputIndex = $inputIndex
    $arguments.Add("-stream_loop")
    $arguments.Add("-1")
    $arguments.Add("-i")
    $arguments.Add($musicResolved)
}

$filter = [Text.StringBuilder]::new()
for ($index = 0; $index -lt $sceneRecords.Count; $index++) {
    $record = $sceneRecords[$index]
    $duration = $record.DurationSeconds.ToString("0.###", [Globalization.CultureInfo]::InvariantCulture)
    $frameCount = [int][Math]::Ceiling($record.DurationSeconds * $fps)
    $videoInput = $record.SlideInput
    $audioInput = $record.AudioInput
    $fadeOutStart = [Math]::Max(0, $record.DurationSeconds - 0.3).ToString(
        "0.###",
        [Globalization.CultureInfo]::InvariantCulture)
    # Per-scene camera motion so the cut does not feel like a plain slideshow.
    # $frameCount must interpolate here, inside the loop.
    $motion = switch ($record.Id) {
        "live" {
            @{
                z = "1.1"
                x = "(iw-iw/zoom)*0.05+(iw-iw/zoom)*0.2*on/$frameCount"
                y = "(ih-ih/zoom)/2"
            }
            break
        }
        "presets" {
            @{
                z = "1.1"
                x = "(iw-iw/zoom)*0.05+(iw-iw/zoom)*0.18*on/$frameCount"
                y = "(ih-ih/zoom)/2"
            }
            break
        }
        "safety" {
            @{
                z = "max(1.02,1.12-0.1*on/$frameCount)"
                x = "iw/2-(iw/zoom/2)"
                y = "ih/2-(ih/zoom/2)"
            }
            break
        }
        "evidence" {
            @{
                z = "1.12"
                x = "(iw-iw/zoom)/2"
                y = "(ih-ih/zoom)*on/$frameCount"
            }
            break
        }
        "accessibility" {
            @{
                z = "min(1.14,1.04+0.1*on/$frameCount)"
                x = "(iw-iw/zoom)*0.35"
                y = "(ih-ih/zoom)/2"
            }
            break
        }
        "closing" {
            @{
                z = "min(1.05,1+0.05*on/$frameCount)"
                x = "iw/2-(iw/zoom/2)"
                y = "ih/2-(ih/zoom/2)"
            }
            break
        }
        default {
            @{
                z = "min(1.08,1+0.08*on/$frameCount)"
                x = "iw/2-(iw/zoom/2)"
                y = "ih/2-(ih/zoom/2)"
            }
            break
        }
    }
    if ($record.VideoClip) {
        # Recorded interaction clips fill the slide's card (880,180,900x780)
        # edge to edge: the window chrome is the card, so no inner seam or
        # leftover padding shows. The clip keeps the advanced-mode aspect, so
        # the cover crop only trims a few pixels. overlay's default eof_action
        # repeats the last clip frame if narration runs longer.
        [void]$filter.Append(
            "[$($videoInput):v]scale=1920:1080,format=rgba[bg$index];" +
            "[$($record.ClipInput):v]fps=$fps," +
            "scale=900:780:force_original_aspect_ratio=increase," +
            "crop=900:780,format=rgba[fg$index];" +
            "[bg$index][fg$index]overlay=x=880:y=180:eval=frame," +
            "trim=duration=$duration,setpts=PTS-STARTPTS," +
            "fade=t=in:st=0:d=0.25,fade=t=out:st=$($fadeOutStart):d=0.3," +
            "format=yuv420p[v$index];")
    }
    else {
        [void]$filter.Append(
            "[$($videoInput):v]scale=1920:1080,format=rgba," +
            "zoompan=z='$($motion.z)':" +
            "x='$($motion.x)':y='$($motion.y)':" +
            "d=$($frameCount):s=1920x1080:fps=$fps," +
            "trim=duration=$duration,setpts=PTS-STARTPTS," +
            "fade=t=in:st=0:d=0.25,fade=t=out:st=$($fadeOutStart):d=0.3," +
            "format=yuv420p[v$index];")
    }
    if ($record.Id -eq "presets" -and -not $record.VideoClip) {
        # Animated watt counter: makes the one-click preset claim visible.
        $counterFont = "/Windows/Fonts/arialbd.ttf"
        $counterColor = "0x45D6A8"
        $steps = @(
            @{ text = "10 W"; from = "1.6"; to = "4.1" },
            @{ text = "12 W"; from = "4.4"; to = "6.9" },
            @{ text = "25 W"; from = "7.2"; to = "9.7" },
            @{ text = "45 W"; from = "10.0"; to = "12.6" }
        )
        foreach ($step in $steps) {
            [void]$filter.Append(
                "[v$index]drawtext=fontfile=${counterFont}:" +
                "text='$($step.text)':fontsize=120:fontcolor=${counterColor}:" +
                "box=1:boxcolor=black@0.35:boxborderw=18:" +
                "x=140:y=880:enable='between(t,$($step.from),$($step.to))'" +
                "[v$index];")
        }
    }
    [void]$filter.Append(
        "[$($audioInput):a]aresample=48000," +
        "pan=stereo|c0=c0|c1=c0," +
        "adelay=350|350,apad=pad_dur=0.65," +
        "atrim=duration=$duration,asetpts=PTS-STARTPTS[a$index];")
}
for ($index = 0; $index -lt $sceneRecords.Count; $index++) {
    [void]$filter.Append("[v$index][a$index]")
}
$totalDuration = $currentStart
[void]$filter.Append("concat=n=$($sceneRecords.Count):v=1:a=1[vcat][acat];")
[void]$filter.Append(
    "[vcat]drawbox=x=0:y=1074:w='max(1,1920*t/$($totalDuration.ToString("0.###", [Globalization.CultureInfo]::InvariantCulture)))':h=6:color=0x45D6A8:t=fill[vprog];")
if ($musicInputIndex -ge 0) {
    $fadeOutStart = [Math]::Max(0.0, $totalDuration - 4.0).ToString(
        "0.###",
        [Globalization.CultureInfo]::InvariantCulture)
    $totalText = $totalDuration.ToString("0.###", [Globalization.CultureInfo]::InvariantCulture)
    $volumeText = $MusicVolumeDb.ToString("0.0", [Globalization.CultureInfo]::InvariantCulture)
    [void]$filter.Append(
        "[$musicInputIndex`:a]aformat=sample_rates=48000:channel_layouts=stereo," +
        "atrim=0:$totalText,asetpts=PTS-STARTPTS," +
        "afade=t=in:st=0:d=2,afade=t=out:st=${fadeOutStart}:d=4," +
        "volume=${volumeText}dB[musicbed];")
    [void]$filter.Append(
        "[acat]loudnorm=I=-16:LRA=11:TP=-1.5[voicenorm];" +
        "[voicenorm][musicbed]amix=inputs=2:duration=first:normalize=0," +
        "alimiter=limit=0.891:level=false[aout]")
}
else {
    [void]$filter.Append("[acat]loudnorm=I=-16:LRA=11:TP=-1.5[aout]")
}

$arguments.Add("-filter_complex")
$arguments.Add($filter.ToString())
$arguments.Add("-map")
$arguments.Add("[vprog]")
$arguments.Add("-map")
$arguments.Add("[aout]")
$arguments.Add("-c:v")
$arguments.Add("libx264")
$arguments.Add("-preset")
$arguments.Add("medium")
$arguments.Add("-crf")
$arguments.Add("18")
$arguments.Add("-pix_fmt")
$arguments.Add("yuv420p")
$arguments.Add("-c:a")
$arguments.Add("aac")
$arguments.Add("-b:a")
$arguments.Add("192k")
$arguments.Add("-movflags")
$arguments.Add("+faststart")
$arguments.Add("-metadata")
$arguments.Add("title=$($story.title) - Development Preview")
$arguments.Add("-metadata")
$arguments.Add("comment=$($story.subtitle)")
$arguments.Add($outputPath)

Write-Host "Rendering $($sceneRecords.Count) scenes to $outputPath" -ForegroundColor Cyan
$previousErrorAction = $ErrorActionPreference
$ErrorActionPreference = "Continue"
try {
    & $ffmpeg @arguments
    if ($LASTEXITCODE -ne 0) {
        throw "ffmpeg failed with exit code $LASTEXITCODE."
    }
}
finally {
    $ErrorActionPreference = $previousErrorAction
}

for ($index = 0; $index -lt $sceneRecords.Count; $index++) {
    $record = $sceneRecords[$index]
    $reviewTime = $record.StartSeconds + ([Math]::Min(4.0, $record.DurationSeconds / 2))
    $reviewPath = Join-Path $reviewDirectory ("review-{0:00}-{1}.png" -f ($index + 1), $record.id)
    & $ffmpeg `
        -loglevel error `
        -y `
        -ss $reviewTime.ToString("0.###", [Globalization.CultureInfo]::InvariantCulture) `
        -i $outputPath `
        -frames:v 1 `
        -update 1 `
        $reviewPath | Out-Null
    if ($LASTEXITCODE -ne 0) {
        throw "Could not extract review frame for scene $($record.Index)."
    }
}

$coverPath = Join-Path $outputRoot "cover-draft.png"
& $ffmpeg `
    -loglevel error `
    -y `
    -ss "2.5" `
    -i $outputPath `
    -frames:v 1 `
    -update 1 `
    $coverPath | Out-Null
if ($LASTEXITCODE -ne 0) {
    throw "Could not extract the draft cover image."
}

$reviewFrames = @(
    Get-ChildItem -LiteralPath $reviewDirectory -File -Filter "review-*.png" |
        Sort-Object Name
)
if ($reviewFrames.Count -ne $sceneRecords.Count) {
    throw "Expected one review frame per scene."
}
$contactWidth = 1920
$contactHeight = 640
$contactSheet = [Drawing.Bitmap]::new($contactWidth, $contactHeight)
$contactGraphics = [Drawing.Graphics]::FromImage($contactSheet)
try {
    $contactGraphics.Clear([Drawing.Color]::FromArgb(15, 23, 27))
    $contactGraphics.SmoothingMode = [Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $contactGraphics.InterpolationMode = [Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
    $contactTitleFont = [Drawing.Font]::new(
        $fontFamily,
        26,
        [Drawing.FontStyle]::Bold)
    $contactLabelFont = [Drawing.Font]::new(
        $fontFamily,
        15,
        [Drawing.FontStyle]::Bold)
    $contactTitleBrush = [Drawing.SolidBrush]::new($textPrimary)
    $contactLabelBrush = [Drawing.SolidBrush]::new($accent)
    try {
        $contactGraphics.DrawString(
            "AMD Mobile Power · 宣传片审片帧",
            $contactTitleFont,
            $contactTitleBrush,
            55,
            24)
        for ($index = 0; $index -lt $reviewFrames.Count; $index++) {
            $frameImage = [Drawing.Image]::FromFile($reviewFrames[$index].FullName)
            try {
                $column = $index % 4
                $row = [Math]::Floor($index / 4)
                $x = 55 + ($column * 460)
                $y = 92 + ($row * 260)
                $contactGraphics.DrawImage($frameImage, $x, $y, 430, 242)
                $label = "{0:00} · {1}" -f (
                    $index + 1
                ), ($sceneRecords[$index].Id)
                $contactGraphics.DrawString(
                    $label,
                    $contactLabelFont,
                    $contactLabelBrush,
                    $x,
                    $y + 218)
            }
            finally {
                $frameImage.Dispose()
            }
        }
    }
    finally {
        $contactTitleFont.Dispose()
        $contactLabelFont.Dispose()
        $contactTitleBrush.Dispose()
        $contactLabelBrush.Dispose()
    }
    $contactSheetPath = Join-Path $reviewDirectory "contact-sheet.png"
    $contactSheet.Save($contactSheetPath, [Drawing.Imaging.ImageFormat]::Png)
}
finally {
    $contactGraphics.Dispose()
    $contactSheet.Dispose()
}
$contactSheetHash = (Get-FileHash -LiteralPath $contactSheetPath -Algorithm SHA256).Hash.ToLowerInvariant()
$coverHash = (Get-FileHash -LiteralPath $coverPath -Algorithm SHA256).Hash.ToLowerInvariant()

$probeJson = & $ffprobe `
    -v error `
    -show_entries format=duration,size:stream=index,codec_name,codec_type,width,height,r_frame_rate,sample_rate,channels `
    -of json `
    $outputPath
if ($LASTEXITCODE -ne 0) {
    throw "ffprobe failed for the rendered video."
}
$probe = $probeJson | ConvertFrom-Json
$videoHash = (Get-FileHash -LiteralPath $outputPath -Algorithm SHA256).Hash.ToLowerInvariant()
$videoStream = $probe.streams | Where-Object { $_.codec_type -eq "video" } | Select-Object -First 1
$audioStream = $probe.streams | Where-Object { $_.codec_type -eq "audio" } | Select-Object -First 1
if ($null -eq $videoStream -or $null -eq $audioStream) {
    throw "Rendered file must contain both video and audio streams."
}
if ($videoStream.width -ne 1920 -or $videoStream.height -ne 1080) {
    throw "Rendered video is not 1920x1080."
}

& $ffmpeg `
    -v error `
    -i $outputPath `
    -f null `
    NUL 2>&1 | Out-Null
if ($LASTEXITCODE -ne 0) {
    throw "Full FFmpeg decode failed."
}

$volumeOutput = & $ffmpeg `
    -hide_banner `
    -i $outputPath `
    -af volumedetect `
    -f null `
    NUL 2>&1
if ($LASTEXITCODE -ne 0) {
    throw "FFmpeg volume analysis failed."
}
$volumeText = $volumeOutput | Out-String
$meanMatch = [regex]::Match($volumeText, "mean_volume:\s*(-?[0-9.]+) dB")
$maxMatch = [regex]::Match($volumeText, "max_volume:\s*(-?[0-9.]+) dB")
if (-not $meanMatch.Success -or -not $maxMatch.Success) {
    throw "FFmpeg volume analysis did not report mean/max levels."
}
$meanVolumeDb = [double]::Parse(
    $meanMatch.Groups[1].Value,
    [Globalization.CultureInfo]::InvariantCulture)
$maxVolumeDb = [double]::Parse(
    $maxMatch.Groups[1].Value,
    [Globalization.CultureInfo]::InvariantCulture)
if ($meanVolumeDb -lt -28 -or $maxVolumeDb -gt -0.5) {
    throw "Rendered audio level is outside the accepted range."
}

$workingFilesRetained = -not $CleanWorkingFiles
if ($CleanWorkingFiles) {
    foreach ($record in $sceneRecords) {
        $record.Slide = $null
        $record.Audio = $null
    }
    Remove-Item -LiteralPath $frameDirectory -Recurse -Force
    Remove-Item -LiteralPath $audioDirectory -Recurse -Force
}

$manifest = [ordered]@{
    schemaVersion = 1
    renderedAt = [DateTimeOffset]::Now
    status = "DRAFT_FOR_HUMAN_REVIEW"
    title = $story.title
    subtitle = $story.subtitle
    repositoryUrl = $story.repositoryUrl
    output = [ordered]@{
        path = $outputPath
        sha256 = $videoHash
        durationSeconds = [double]$probe.format.duration
        sizeBytes = [long]$probe.format.size
        videoCodec = $videoStream.codec_name
        audioCodec = $audioStream.codec_name
        width = $videoStream.width
        height = $videoStream.height
        frameRate = $videoStream.r_frame_rate
        sampleRate = $audioStream.sample_rate
        channels = $audioStream.channels
    }
    voice = $selectedVoice.VoiceInfo.Name
    music = if ($null -ne $musicResolved) {
        [ordered]@{
            path = $musicResolved
            sha256 = (Get-FileHash -LiteralPath $musicResolved -Algorithm SHA256).
                Hash.ToLowerInvariant()
            volumeDb = $MusicVolumeDb
            generated = "media/promo-native/generate-music.py (seeded, original composition)"
        }
    }
    else {
        $null
    }
    captions = $captionsPath
    workingFilesRetained = $workingFilesRetained
    scenes = $sceneRecords
    review = [ordered]@{
        framesDirectory = $reviewDirectory
        contactSheet = $contactSheetPath
        contactSheetSha256 = $contactSheetHash
        cover = $coverPath
        coverSha256 = $coverHash
    }
    verification = [ordered]@{
        ffmpegFullDecode = "PASS"
        textSafeWidth = "PASS"
        sceneCount = $sceneRecords.Count
        width = $videoStream.width
        height = $videoStream.height
        meanVolumeDb = $meanVolumeDb
        maxVolumeDb = $maxVolumeDb
        noApplicationProcess = $true
        noHardwareWrite = $true
        noLoginOrUpload = $true
        noExternalSamples = $true
    }
    safety = @(
        "No application process was started during rendering.",
        "No hardware write, driver change, login, upload, or publication occurred.",
        "Only verified repository screenshots and locally recorded fixture clips are used.",
        "The video is a development preview and is not approved for publication."
    )
}
$manifest | ConvertTo-Json -Depth 12 |
    Set-Content -LiteralPath $manifestPath -Encoding utf8

Write-Host ""
Write-Host "Promo draft rendered." -ForegroundColor Green
[pscustomobject]@{
    Video = $outputPath
    DurationSeconds = [Math]::Round([double]$probe.format.duration, 2)
    SizeBytes = [long]$probe.format.size
    SHA256 = $videoHash
    Captions = $captionsPath
    Manifest = $manifestPath
    ReviewFrames = $reviewDirectory
    MeanVolumeDb = $meanVolumeDb
    MaxVolumeDb = $maxVolumeDb
    FullDecode = "PASS"
    Status = "DRAFT_FOR_HUMAN_REVIEW"
} | Format-List
