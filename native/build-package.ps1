param(
    [string]$Version = "0.3.0-native-preview.1",
    [switch]$NoBuild,
    [switch]$NoVerify,
    [string]$EvidencePath
)

$ErrorActionPreference = "Stop"

$root = Split-Path -Parent $PSCommandPath
$repositoryRoot = Split-Path -Parent $root
$artifacts = Join-Path $repositoryRoot "artifacts"
$nativePackages = Join-Path $artifacts "native-packages"
$stageName = "amd-mobile-power-v$Version-win-x64-native-preview"
$stage = Join-Path $nativePackages $stageName
$zipPath = Join-Path $nativePackages "$stageName.zip"
$guiRuntime = Join-Path $artifacts "native-build\gui-runtime"
$verifyRoot = Join-Path $artifacts "native-build\package-verify"

function Reset-ArtifactDirectory {
    param([string]$Path)

    $resolvedArtifacts = [System.IO.Path]::GetFullPath($artifacts)
    $resolvedPath = [System.IO.Path]::GetFullPath($Path)
    if (-not $resolvedPath.StartsWith(
        $resolvedArtifacts + [System.IO.Path]::DirectorySeparatorChar,
        [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Refusing to reset a directory outside artifacts: $resolvedPath"
    }
    if (Test-Path -LiteralPath $resolvedPath) {
        Remove-Item -LiteralPath $resolvedPath -Recurse -Force
    }
    New-Item -ItemType Directory -Path $resolvedPath -Force | Out-Null
}

if (-not $NoBuild) {
    & (Join-Path $root "build.ps1") -Offline
    if ($LASTEXITCODE -ne 0) {
        throw "Native build failed."
    }
}

foreach ($required in @(
    "amd-mobile-power-gui.exe",
    "amdmobilepower_native_worker.exe",
    "libryzenadj.dll",
    "WinRing0x64.dll",
    "WinRing0x64.sys",
    "inpoutx64.dll"
)) {
    if (-not (Test-Path -LiteralPath (Join-Path $guiRuntime $required))) {
        throw "Native runtime is missing ${required}: $guiRuntime"
    }
}

New-Item -ItemType Directory -Path $nativePackages -Force | Out-Null
Reset-ArtifactDirectory $stage
Copy-Item -Path (Join-Path $guiRuntime "*") -Destination $stage -Force

New-Item -ItemType Directory -Path (Join-Path $stage "licenses") -Force | Out-Null
Copy-Item -LiteralPath (Join-Path $repositoryRoot "third_party\RyzenAdj\LICENSE") `
    -Destination (Join-Path $stage "licenses\RyzenAdj-LICENSE.txt") -Force
Copy-Item -LiteralPath (Join-Path $repositoryRoot "third_party\licenses\GPL-3.0.txt") `
    -Destination (Join-Path $stage "licenses\GPL-3.0.txt") -Force
Copy-Item -LiteralPath (Join-Path $repositoryRoot "third_party\licenses\InpOut32-LICENSE.txt") `
    -Destination (Join-Path $stage "licenses\InpOut32-LICENSE.txt") -Force
Copy-Item -LiteralPath (Join-Path $repositoryRoot "third_party\licenses\WinRing0-COPYRIGHT.txt") `
    -Destination (Join-Path $stage "licenses\WinRing0-COPYRIGHT.txt") -Force
Copy-Item -LiteralPath (Join-Path $repositoryRoot "docs\THIRD_PARTY_NOTICES.md") `
    -Destination (Join-Path $stage "THIRD_PARTY_NOTICES.md") -Force
Copy-Item -LiteralPath (Join-Path $root "portable-README.txt") `
    -Destination (Join-Path $stage "README.txt") -Force

$commit = (& git -C $repositoryRoot rev-parse HEAD).Trim()
$statusText = (& git -C $repositoryRoot status --porcelain --ignore-submodules=dirty |
    Out-String).Trim()
$workingTree = if ($statusText) { "Dirty" } else { "Clean" }
@(
    "Name=$stageName"
    "Version=$Version"
    "Commit=$commit"
    "WorkingTree=$workingTree"
    "Platform=win-x64"
    "Native=True"
    "BuiltAt=$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss zzz')"
) | Set-Content -LiteralPath (Join-Path $stage "BUILD-INFO.txt") -Encoding utf8

$checksumLines = Get-ChildItem -LiteralPath $stage -File -Recurse |
    Sort-Object FullName |
    ForEach-Object {
        $relative = [System.IO.Path]::GetRelativePath($stage, $_.FullName).Replace("\", "/")
        $hash = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
        "$hash  $relative"
    }
$checksumLines | Set-Content -LiteralPath (Join-Path $stage "SHA256SUMS.txt") -Encoding ascii

if (Test-Path -LiteralPath $zipPath) {
    Remove-Item -LiteralPath $zipPath -Force
}
Compress-Archive -LiteralPath $stage -DestinationPath $zipPath -CompressionLevel Optimal
$zipHash = (Get-FileHash -LiteralPath $zipPath -Algorithm SHA256).Hash.ToLowerInvariant()
"$zipHash  $stageName.zip" | Set-Content -LiteralPath "$zipPath.sha256" -Encoding ascii

if (-not $NoVerify) {
    Reset-ArtifactDirectory $verifyRoot
    Expand-Archive -LiteralPath $zipPath -DestinationPath $verifyRoot -Force
    $verifyGui = Join-Path $verifyRoot "$stageName\amd-mobile-power-gui.exe"
    & (Join-Path $root "verify-rust-gui.ps1") `
        -NoBuild `
        -VerifyWorker `
        -VerifyWriteControls `
        -GuiExecutable $verifyGui
    if ($LASTEXITCODE -ne 0) {
        throw "Extracted native package verification failed."
    }
}

$result = [pscustomobject]@{
    Package = $zipPath
    SHA256 = $zipHash
    Size = (Get-Item -LiteralPath $zipPath).Length
    WorkingTree = $workingTree
    Verification = if ($NoVerify) { "Skipped" } else { "PASS" }
}

if ($EvidencePath) {
    $evidenceDirectory = Split-Path -Parent $EvidencePath
    if ($evidenceDirectory) {
        New-Item -ItemType Directory -Path $evidenceDirectory -Force | Out-Null
    }
    [pscustomobject]@{
        Version = $Version
        Package = $stageName + ".zip"
        SHA256 = $zipHash
        Size = $result.Size
        SourceCommit = $commit
        WorkingTree = $workingTree
        Verification = $result.Verification
        RecordedAt = (Get-Date).ToString("o")
    } |
        ConvertTo-Json -Depth 6 |
        Set-Content -LiteralPath $EvidencePath -Encoding UTF8
}

$result | Format-List
