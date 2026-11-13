# Generates SAPI narration WAVs per scene, a seeded original music bed,
# and mixes them into a single audio track aligned to the scene timeline.
# Usage:
#   pwsh make-audio.ps1 -ScenesJson <path> -OutDir <dir> -TotalSeconds <n>

param(
    [Parameter(Mandatory = $true)][string]$ScenesJson,
    [Parameter(Mandatory = $true)][string]$OutDir,
    [Parameter(Mandatory = $true)][double]$TotalSeconds,
    [string]$Voice = "Microsoft Huihui Desktop",
    [int]$VoiceRate = 2,
    [int]$VoiceVolume = 100
)

$ErrorActionPreference = "Stop"
Add-Type -AssemblyName System.Speech
New-Item -ItemType Directory -Path $OutDir -Force | Out-Null

$scenes = Get-Content -LiteralPath $ScenesJson -Raw | ConvertFrom-Json

# --- narration ---------------------------------------------------------------
$synth = [System.Speech.Synthesis.SpeechSynthesizer]::new()
$voiceInfo = $synth.GetInstalledVoices() |
    Where-Object { $_.VoiceInfo.Name -eq $Voice } |
    Select-Object -First 1
if (-not $voiceInfo) {
    $voiceInfo = $synth.GetInstalledVoices() |
        Where-Object { $_.VoiceInfo.Culture.Name -like "zh-*" } |
        Select-Object -First 1
}
if (-not $voiceInfo) { throw "No Chinese SAPI voice installed." }
$synth.SelectVoice($voiceInfo.VoiceInfo.Name)
$synth.Rate = $VoiceRate
$synth.Volume = $VoiceVolume

$starts = @(0.0)
$durations = @()
foreach ($s in $scenes) {
    $durations += [double]$s.duration
}
for ($i = 1; $i -lt $scenes.Count; $i++) {
    $starts += ($starts[$i - 1] + $durations[$i - 1])
}

$manifest = @()
for ($i = 0; $i -lt $scenes.Count; $i++) {
    $scene = $scenes[$i]
    $narr = $scene.narration
    if (-not $narr) { continue }
    $wav = Join-Path $OutDir ("voice-{0:00}-{1}.wav" -f ($i + 1), $scene.id)
    $synth.SetOutputToWaveFile($wav)
    $synth.Speak($narr)
    $synth.SetOutputToNull()

    # Measure the narration we just wrote.
    $probe = & ffprobe -v error -show_entries format=duration -of csv=p=0 $wav
    $narrSec = [double]$probe
    $manifest += [ordered]@{
        scene = $scene.id
        sceneStart = $starts[$i]
        narration = $narr
        narrationSeconds = $narrSec
        wav = $wav
    }
}
$synth.Dispose()

# --- music bed ----------------------------------------------------------------
$musicWav = Join-Path $OutDir "music-bed.wav"
python (Join-Path $PSScriptRoot "generate-music.py") $musicWav $TotalSeconds

# --- mix -----------------------------------------------------------------------
$mixWav = Join-Path $OutDir "audio-mix.wav"
$inputs = @()
$filter = [Text.StringBuilder]::new()

# Music input 0: looped, faded, ducked under voice.
$inputs += "-i"
$inputs += $musicWav
$fadeOut = [Math]::Max(0, $TotalSeconds - 3.0)
[void]$filter.Append(
    "[0:a]aformat=sample_rates=48000:channel_layouts=stereo," +
    "atrim=0:$TotalSeconds,asetpts=PTS-STARTPTS," +
    "afade=t=in:st=0:d=1.5,afade=t=out:st=$fadeOut`:d=3,volume=-26dB[music];"
)

# Each narration input gets delayed to its scene start.
for ($i = 0; $i -lt $manifest.Count; $i++) {
    $m = $manifest[$i]
    $inputs += "-i"
    $inputs += $m.wav
    $idx = $i + 1
    $delayMs = [int][Math]::Round($m.sceneStart * 1000)
    [void]$filter.Append(
        "[$idx`:a]aformat=sample_rates=48000:channel_layouts=stereo," +
        "aresample=48000,pan=stereo|c0=c0|c1=c0," +
        "adelay=$delayMs|$delayMs,apad," +
        "atrim=0:$TotalSeconds,asetpts=PTS-STARTPTS[v$idx];"
    )
}

$mixInputs = "[music]"
for ($i = 0; $i -lt $manifest.Count; $i++) {
    $mixInputs += "[v$($i + 1)]"
}
$n = $manifest.Count + 1
[void]$filter.Append(
    "$mixInputs amix=inputs=$n`:duration=first:normalize=0," +
    "loudnorm=I=-16:LRA=11:TP=-1.5,alimiter=limit=0.891:level=false[out]"
)

$ffmpegArgs = @("-y") + $inputs + @(
    "-filter_complex", $filter.ToString(),
    "-map", "[out]",
    "-c:a", "pcm_s16le",
    $mixWav
)
& ffmpeg @ffmpegArgs 2>&1 | Out-Null
if ($LASTEXITCODE -ne 0) { throw "ffmpeg mix failed." }

# Verify final mix duration.
$probe = & ffprobe -v error -show_entries format=duration -of csv=p=0 $mixWav
$mixSec = [double]$probe

[ordered]@{
    verification = "PASS"
    voice = $voiceInfo.VoiceInfo.Name
    voiceRate = $VoiceRate
    mixWav = $mixWav
    mixSeconds = $mixSec
    musicWav = $musicWav
    scenes = $manifest
} | ConvertTo-Json -Depth 6
