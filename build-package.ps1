param(
    [string]$Version = "0.1.0",
    [string]$Configuration = "Release"
)

$ErrorActionPreference = "Stop"

$root = Split-Path -Parent $PSCommandPath
$artifacts = Join-Path $root "artifacts"
$publishRoot = Join-Path $artifacts "publish"
$packageRoot = Join-Path $artifacts "packages"
$packageName = "amd-mobile-power-v$Version-win-x64"
$stage = Join-Path $packageRoot $packageName
$zipPath = Join-Path $packageRoot "$packageName.zip"
$ryzenAdjRuntime = Join-Path $artifacts "ryzenadj-runtime"

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

if (-not (Test-Path -LiteralPath (Join-Path $ryzenAdjRuntime "libryzenadj.dll"))) {
    & (Join-Path $root "build-ryzenadj.ps1") -Configuration $Configuration
}

Reset-ArtifactDirectory $publishRoot
New-Item -ItemType Directory -Path $packageRoot -Force | Out-Null
Reset-ArtifactDirectory $stage

dotnet publish (Join-Path $root "src\AmdMobilePower.Gui\AmdMobilePower.Gui.csproj") `
    -c $Configuration `
    -r win-x64 `
    --self-contained true `
    -p:Version=$Version `
    -o (Join-Path $publishRoot "gui")
if ($LASTEXITCODE -ne 0) {
    throw "GUI publish failed."
}

dotnet publish (Join-Path $root "src\AmdMobilePower.Worker\AmdMobilePower.Worker.csproj") `
    -c $Configuration `
    -r win-x64 `
    --self-contained true `
    -p:Version=$Version `
    -o (Join-Path $publishRoot "worker")
if ($LASTEXITCODE -ne 0) {
    throw "Worker publish failed."
}

Copy-Item -Path (Join-Path $publishRoot "gui\*") -Destination $stage -Recurse -Force
New-Item -ItemType Directory -Path (Join-Path $stage "worker") -Force | Out-Null
Copy-Item -Path (Join-Path $publishRoot "worker\*") -Destination (Join-Path $stage "worker") -Recurse -Force

Get-ChildItem -LiteralPath $stage -Filter "*.pdb" -File -Recurse |
    Remove-Item -Force

Copy-Item -Path (Join-Path $ryzenAdjRuntime "*") -Destination (Join-Path $stage "worker") -Force
New-Item -ItemType Directory -Path (Join-Path $stage "worker\profiles") -Force | Out-Null
Copy-Item -Path (Join-Path $root "profiles\*.json") -Destination (Join-Path $stage "worker\profiles") -Force

New-Item -ItemType Directory -Path (Join-Path $stage "licenses") -Force | Out-Null
Copy-Item -LiteralPath (Join-Path $root "third_party\RyzenAdj\LICENSE") `
    -Destination (Join-Path $stage "licenses\RyzenAdj-LICENSE.txt") -Force
Copy-Item -LiteralPath (Join-Path $root "docs\THIRD_PARTY_NOTICES.md") `
    -Destination (Join-Path $stage "THIRD_PARTY_NOTICES.md") -Force
Copy-Item -LiteralPath (Join-Path $root "packaging\portable-README.txt") `
    -Destination (Join-Path $stage "README.txt") -Force

$commit = (& git -C $root rev-parse HEAD).Trim()
@(
    "Name=$packageName"
    "Version=$Version"
    "Commit=$commit"
    "Configuration=$Configuration"
    "SelfContained=true"
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
"$zipHash  $packageName.zip" | Set-Content -LiteralPath "$zipPath.sha256" -Encoding ascii

Write-Output "Portable package: $zipPath"
Write-Output "SHA256: $zipHash"
