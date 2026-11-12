param(
    [string]$GuiExecutable,
    [string]$WorkerExecutable,
    [string]$OutputDirectory,
    [string]$EvidencePath
)

$ErrorActionPreference = "Stop"

$root = Split-Path -Parent $PSCommandPath
$repositoryRoot = Split-Path -Parent $root
$artifactsRoot = [System.IO.Path]::GetFullPath(
    (Join-Path $repositoryRoot "artifacts"))
if (-not $OutputDirectory) {
    $OutputDirectory = Join-Path $artifactsRoot "verify\dpi-fixtures-2026-11-12"
}
$OutputDirectory = [System.IO.Path]::GetFullPath($OutputDirectory)
if (-not $OutputDirectory.StartsWith(
    $artifactsRoot + [System.IO.Path]::DirectorySeparatorChar,
    [System.StringComparison]::OrdinalIgnoreCase)) {
    throw "DPI fixture output must stay under artifacts: $OutputDirectory"
}
if (-not $EvidencePath) {
    $EvidencePath = Join-Path `
        $repositoryRoot `
        "docs\evidence\ui\native-dpi-100-125-150-2026-11-12.json"
}
New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null

$captureScript = Join-Path $root "capture-rust-gui-redesign.ps1"
$results = @()
foreach ($scale in @("100", "125", "150")) {
    $scaleOutput = Join-Path $OutputDirectory "scale-$scale"
    $captureEvidence = Join-Path $scaleOutput "capture-$scale.json"
    & $captureScript `
        -GuiExecutable $GuiExecutable `
        -WorkerExecutable $WorkerExecutable `
        -OutputDirectory $scaleOutput `
        -EvidencePath $captureEvidence `
        -FilePrefix "native-dpi-$scale" `
        -Fixture worker-offline `
        -DpiFixture $scale

    $capture = Get-Content -LiteralPath $captureEvidence -Raw | ConvertFrom-Json
    if ([int]$capture.DpiFixture -ne [int]$scale) {
        throw "DPI capture evidence reports the wrong scale: $($capture.DpiFixture)"
    }
    $expectedSimple = [int][Math]::Floor((600 * [int]$scale + 50) / 100.0)
    $expectedSimpleHeight = [int][Math]::Floor((360 * [int]$scale + 50) / 100.0)
    $expectedAdvanced = [int][Math]::Floor((780 * [int]$scale + 50) / 100.0)
    $expectedAdvancedHeight = [int][Math]::Floor((680 * [int]$scale + 50) / 100.0)
    if ($capture.SimpleClientSize -ne "${expectedSimple}x${expectedSimpleHeight}") {
        throw "Simple client size mismatch at $scale%: $($capture.SimpleClientSize)"
    }
    if ($capture.AdvancedClientSize -ne "${expectedAdvanced}x${expectedAdvancedHeight}") {
        throw "Advanced client size mismatch at $scale%: $($capture.AdvancedClientSize)"
    }
    foreach ($captureFile in @($capture.Simple, $capture.Advanced)) {
        if (-not (Test-Path -LiteralPath $captureFile.Path -PathType Leaf)) {
            throw "DPI capture image is missing: $($captureFile.Path)"
        }
        if ($captureFile.Width -lt $expectedSimple -or
            $captureFile.Height -lt $expectedSimpleHeight) {
            throw "DPI capture image is unexpectedly small at $scale%."
        }
    }

    $results += [pscustomobject]@{
        Scale = [int]$scale
        SimpleClientSize = $capture.SimpleClientSize
        AdvancedClientSize = $capture.AdvancedClientSize
        SimpleImage = $capture.Simple.Path
        AdvancedImage = $capture.Advanced.Path
        Evidence = $captureEvidence
    }
}

$result = [ordered]@{
    SchemaVersion = 1
    Verification = "PASS"
    Method = "test-only logical DPI override; system scaling was not changed"
    Fixture = "worker-offline"
    Scales = $results
    RecordedAt = (Get-Date).ToString("o")
}
$evidenceDirectory = Split-Path -Parent $EvidencePath
if ($evidenceDirectory) {
    New-Item -ItemType Directory -Path $evidenceDirectory -Force | Out-Null
}
$result |
    ConvertTo-Json -Depth 8 |
    Set-Content -LiteralPath $EvidencePath -Encoding UTF8

[pscustomobject]@{
    Verification = "PASS"
    Evidence = $EvidencePath
    Scales = ($results | ForEach-Object {
        "$($_.Scale)%: $($_.SimpleClientSize) / $($_.AdvancedClientSize)"
    }) -join "; "
} | Format-List
