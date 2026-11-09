param(
    [string]$VideoPath = "artifacts\media\amd-mobile-power-promo-draft-2026-11-10\amd-mobile-power-intro-draft-2026-11-10.mp4",
    [string]$ManifestPath = "artifacts\media\amd-mobile-power-promo-draft-2026-11-10\promo-manifest.json",
    [string]$EvidencePath = "docs\evidence\media\promo-draft-2026-11-10.json"
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

function Assert-Condition {
    param(
        [bool]$Condition,
        [string]$Message
    )

    if (-not $Condition) {
        throw $Message
    }
}

function Assert-Equal {
    param(
        [string]$Name,
        [object]$Actual,
        [object]$Expected
    )

    if ([string]$Actual -cne [string]$Expected) {
        throw "$Name mismatch: actual=$Actual expected=$Expected"
    }
}

function Assert-FileHash {
    param(
        [string]$Name,
        [string]$Path,
        [string]$ExpectedHash
    )

    Assert-Condition (Test-Path -LiteralPath $Path) "$Name is missing: $Path"
    $actualHash = (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
    Assert-Equal $Name $actualHash $ExpectedHash.ToLowerInvariant()
}

function Get-ImageDimensions {
    param([string]$Path)

    $image = [Drawing.Image]::FromFile($Path)
    try {
        return [pscustomobject]@{
            Width = $image.Width
            Height = $image.Height
        }
    }
    finally {
        $image.Dispose()
    }
}

function Get-ImageLumaMetrics {
    param([string]$Path)

    $bitmap = [Drawing.Bitmap]::new($Path)
    try {
        $samples = 0
        $sum = 0.0
        $sumSquares = 0.0
        $nonDark = 0
        for ($y = 0; $y -lt $bitmap.Height; $y += 4) {
            for ($x = 0; $x -lt $bitmap.Width; $x += 4) {
                $color = $bitmap.GetPixel($x, $y)
                $luma = (0.2126 * $color.R) + (0.7152 * $color.G) + (0.0722 * $color.B)
                $sum += $luma
                $sumSquares += $luma * $luma
                if ($luma -gt 40) {
                    $nonDark++
                }
                $samples++
            }
        }
        $mean = $sum / $samples
        $variance = ($sumSquares / $samples) - ($mean * $mean)
        return [pscustomobject]@{
            MeanLuma = $mean
            LumaStdDev = [Math]::Sqrt([Math]::Max(0.0, $variance))
            NonDarkRatio = $nonDark / $samples
        }
    }
    finally {
        $bitmap.Dispose()
    }
}

$resolvedVideoPath = Resolve-ProjectPath $VideoPath
$resolvedManifestPath = Resolve-ProjectPath $ManifestPath
$resolvedEvidencePath = Resolve-ProjectPath $EvidencePath

Assert-Condition (Test-Path -LiteralPath $resolvedVideoPath) "Video is missing: $resolvedVideoPath"
Assert-Condition (Test-Path -LiteralPath $resolvedManifestPath) "Manifest is missing: $resolvedManifestPath"
Assert-Condition (Test-Path -LiteralPath $resolvedEvidencePath) "Evidence is missing: $resolvedEvidencePath"

$ffmpeg = (Get-Command ffmpeg -ErrorAction Stop).Source
$ffprobe = (Get-Command ffprobe -ErrorAction Stop).Source
Add-Type -AssemblyName System.Drawing

$manifest = Get-Content -LiteralPath $resolvedManifestPath -Raw -Encoding UTF8 |
    ConvertFrom-Json
$evidence = Get-Content -LiteralPath $resolvedEvidencePath -Raw -Encoding UTF8 |
    ConvertFrom-Json
Assert-Condition (-not [string]::IsNullOrWhiteSpace($manifest.status)) "Manifest status is empty."
Assert-Equal "manifest status" $manifest.status $evidence.status

$videoInfo = Get-Item -LiteralPath $resolvedVideoPath
$videoHash = (Get-FileHash -LiteralPath $resolvedVideoPath -Algorithm SHA256).Hash.ToLowerInvariant()
Assert-Equal "video size" $videoInfo.Length $manifest.output.sizeBytes
Assert-Equal "video size evidence" $videoInfo.Length $evidence.video.sizeBytes
Assert-Equal "video SHA256" $videoHash $manifest.output.sha256
Assert-Equal "video evidence SHA256" $videoHash $evidence.video.sha256

$probeJson = & $ffprobe `
    -v error `
    -show_entries format=duration,size:stream=index,codec_name,codec_type,width,height,r_frame_rate,sample_rate,channels `
    -of json `
    $resolvedVideoPath
if ($LASTEXITCODE -ne 0) {
    throw "ffprobe failed for $resolvedVideoPath"
}
$probe = $probeJson | ConvertFrom-Json
$videoStream = $probe.streams |
    Where-Object { $_.codec_type -eq "video" } |
    Select-Object -First 1
$audioStream = $probe.streams |
    Where-Object { $_.codec_type -eq "audio" } |
    Select-Object -First 1
Assert-Condition ($null -ne $videoStream) "Video stream is missing."
Assert-Condition ($null -ne $audioStream) "Audio stream is missing."

$duration = [double]::Parse(
    $probe.format.duration,
    [Globalization.CultureInfo]::InvariantCulture)
Assert-Condition (
    [Math]::Abs($duration - [double]$manifest.output.durationSeconds) -le 0.02
) "Video duration does not match the manifest."
Assert-Condition (
    [Math]::Abs($duration - [double]$evidence.video.durationSeconds) -le 0.02
) "Video duration does not match the evidence."
Assert-Equal "video codec" $videoStream.codec_name $manifest.output.videoCodec
Assert-Equal "audio codec" $audioStream.codec_name $manifest.output.audioCodec
Assert-Equal "video width" $videoStream.width $manifest.output.width
Assert-Equal "video height" $videoStream.height $manifest.output.height
Assert-Equal "frame rate" $videoStream.r_frame_rate $manifest.output.frameRate
Assert-Equal "sample rate" $audioStream.sample_rate $manifest.output.sampleRate
Assert-Equal "audio channels" $audioStream.channels $manifest.output.channels

$previousErrorActionPreference = $ErrorActionPreference
$ErrorActionPreference = "Continue"
try {
    & $ffmpeg `
        -v error `
        -i $resolvedVideoPath `
        -f null `
        NUL 2>&1 | Out-Null
    $decodeExitCode = $LASTEXITCODE

    $volumeOutput = & $ffmpeg `
        -hide_banner `
        -i $resolvedVideoPath `
        -af volumedetect `
        -f null `
        NUL 2>&1
    $volumeExitCode = $LASTEXITCODE
}
finally {
    $ErrorActionPreference = $previousErrorActionPreference
}
if ($decodeExitCode -ne 0) {
    throw "Full FFmpeg decode failed."
}

if ($volumeExitCode -ne 0) {
    throw "FFmpeg volume analysis failed."
}
$volumeText = $volumeOutput | Out-String
$meanMatch = [regex]::Match($volumeText, "mean_volume:\s*(-?[0-9.]+) dB")
$maxMatch = [regex]::Match($volumeText, "max_volume:\s*(-?[0-9.]+) dB")
Assert-Condition ($meanMatch.Success -and $maxMatch.Success) "Volume metrics are missing."
$meanVolumeDb = [double]::Parse(
    $meanMatch.Groups[1].Value,
    [Globalization.CultureInfo]::InvariantCulture)
$maxVolumeDb = [double]::Parse(
    $maxMatch.Groups[1].Value,
    [Globalization.CultureInfo]::InvariantCulture)
Assert-Condition (
    [Math]::Abs($meanVolumeDb - [double]$manifest.verification.meanVolumeDb) -le 0.1
) "Mean volume does not match the manifest."
Assert-Condition (
    [Math]::Abs($maxVolumeDb - [double]$manifest.verification.maxVolumeDb) -le 0.1
) "Peak volume does not match the manifest."
Assert-Condition ($meanVolumeDb -ge -28) "Mean volume is too low."
Assert-Condition ($maxVolumeDb -le -0.5) "Peak volume is too high."

$captionsPath = Resolve-ProjectPath $evidence.narration.captions
Assert-FileHash "captions" $captionsPath $evidence.narration.captionsSha256

$storyboardPath = Resolve-ProjectPath $evidence.source.storyboard
$rendererPath = Resolve-ProjectPath $evidence.source.renderer
Assert-FileHash "storyboard" $storyboardPath $evidence.source.storyboardSha256
Assert-FileHash "renderer" $rendererPath $evidence.source.rendererSha256

$coverPath = Resolve-ProjectPath $evidence.reviewAssets.cover
$contactSheetPath = Resolve-ProjectPath $evidence.reviewAssets.contactSheet
Assert-FileHash "cover" $coverPath $evidence.reviewAssets.coverSha256
Assert-FileHash "contact sheet" $contactSheetPath $evidence.reviewAssets.contactSheetSha256

$coverDimensions = Get-ImageDimensions $coverPath
$contactSheetDimensions = Get-ImageDimensions $contactSheetPath
Assert-Equal "cover width" $coverDimensions.Width $evidence.reviewAssets.coverWidth
Assert-Equal "cover height" $coverDimensions.Height $evidence.reviewAssets.coverHeight
Assert-Equal "contact sheet width" $contactSheetDimensions.Width $evidence.reviewAssets.contactSheetWidth
Assert-Equal "contact sheet height" $contactSheetDimensions.Height $evidence.reviewAssets.contactSheetHeight

$launchCoverPath = Resolve-ProjectPath $evidence.bilibiliCover.path
Assert-FileHash "Bilibili cover" $launchCoverPath $evidence.bilibiliCover.sha256
$launchCoverInfo = Get-Item -LiteralPath $launchCoverPath
Assert-Equal "Bilibili cover size" $launchCoverInfo.Length $evidence.bilibiliCover.sizeBytes
$launchCoverDimensions = Get-ImageDimensions $launchCoverPath
Assert-Equal "Bilibili cover width" $launchCoverDimensions.Width $evidence.bilibiliCover.width
Assert-Equal "Bilibili cover height" $launchCoverDimensions.Height $evidence.bilibiliCover.height
$launchCoverRendererPath = Resolve-ProjectPath $evidence.bilibiliCover.renderer
Assert-FileHash "Bilibili cover renderer" $launchCoverRendererPath $evidence.bilibiliCover.rendererSha256
$launchCoverMetrics = Get-ImageLumaMetrics $launchCoverPath
Assert-Condition ($launchCoverMetrics.LumaStdDev -ge 20) "Bilibili cover has too little visual variation."
Assert-Condition (
    $launchCoverMetrics.NonDarkRatio -ge 0.05 -and $launchCoverMetrics.NonDarkRatio -le 0.95
) "Bilibili cover appears blank or overexposed."

[pscustomobject]@{
    Status = $manifest.status
    Video = $resolvedVideoPath
    DurationSeconds = $duration
    SizeBytes = $videoInfo.Length
    SHA256 = $videoHash
    Width = $videoStream.width
    Height = $videoStream.height
    FrameRate = $videoStream.r_frame_rate
    MeanVolumeDb = $meanVolumeDb
    MaxVolumeDb = $maxVolumeDb
    SceneCount = $manifest.verification.sceneCount
    FullDecode = "PASS"
    EvidenceHashes = "PASS"
    ReviewAssets = "PASS"
    BilibiliCover = "PASS"
    Verification = "PASS"
} | Format-List
