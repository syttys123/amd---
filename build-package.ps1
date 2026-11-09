param(
    [string]$Version = "0.1.0",
    [string]$Configuration = "Release",
    [switch]$FrameworkDependent
)

$ErrorActionPreference = "Stop"

$root = Split-Path -Parent $PSCommandPath
$artifacts = Join-Path $root "artifacts"
$publishRoot = Join-Path $artifacts "publish"
$packageRoot = Join-Path $artifacts "packages"
$packageSuffix = if ($FrameworkDependent) { "-lite" } else { "" }
$packageName = "amd-mobile-power-v$Version-win-x64$packageSuffix"
$stage = Join-Path $packageRoot $packageName
$zipPath = Join-Path $packageRoot "$packageName.zip"
$ryzenAdjRuntime = Join-Path $artifacts "ryzenadj-runtime"
$selfContainedValue = if ($FrameworkDependent) { "false" } else { "true" }

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
    --self-contained $selfContainedValue `
    -p:NuGetAudit=false `
    -p:Version=$Version `
    -o (Join-Path $publishRoot "gui")
if ($LASTEXITCODE -ne 0) {
    throw "GUI publish failed."
}

dotnet publish (Join-Path $root "src\AmdMobilePower.Worker\AmdMobilePower.Worker.csproj") `
    -c $Configuration `
    -r win-x64 `
    --self-contained $selfContainedValue `
    -p:NuGetAudit=false `
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
Copy-Item -LiteralPath (Join-Path $root "third_party\licenses\GPL-3.0.txt") `
    -Destination (Join-Path $stage "licenses\GPL-3.0.txt") -Force
Copy-Item -LiteralPath (Join-Path $root "third_party\licenses\InpOut32-LICENSE.txt") `
    -Destination (Join-Path $stage "licenses\InpOut32-LICENSE.txt") -Force
Copy-Item -LiteralPath (Join-Path $root "third_party\licenses\WinRing0-COPYRIGHT.txt") `
    -Destination (Join-Path $stage "licenses\WinRing0-COPYRIGHT.txt") -Force
Copy-Item -LiteralPath (Join-Path $root "docs\THIRD_PARTY_NOTICES.md") `
    -Destination (Join-Path $stage "THIRD_PARTY_NOTICES.md") -Force
Copy-Item -LiteralPath (Join-Path $root "packaging\portable-README.txt") `
    -Destination (Join-Path $stage "README.txt") -Force
if ($FrameworkDependent) {
    @(
        ""
        "轻量版运行时要求:"
        "  需要安装 Microsoft .NET 8 Desktop Runtime x64。"
        "  如果尚未安装，请从 Microsoft 官方 .NET 8 下载页面获取。"
    ) | Add-Content -LiteralPath (Join-Path $stage "README.txt") -Encoding utf8
}
Copy-Item -LiteralPath (Join-Path $root "docs\MIGRATING_FROM_LEGACY.md") `
    -Destination (Join-Path $stage "MIGRATING-FROM-LEGACY.md") -Force
Copy-Item -LiteralPath (Join-Path $root "docs\RELEASE_CHECKLIST.md") `
    -Destination (Join-Path $stage "RELEASE-CHECKLIST.md") -Force
Copy-Item -LiteralPath (Join-Path $root "packaging\install.ps1") `
    -Destination (Join-Path $stage "install.ps1") -Force
Copy-Item -LiteralPath (Join-Path $root "packaging\uninstall.ps1") `
    -Destination (Join-Path $stage "uninstall.ps1") -Force
Copy-Item -LiteralPath (Join-Path $root "packaging\migrate-legacy-owner.ps1") `
    -Destination (Join-Path $stage "migrate-legacy-owner.ps1") -Force

$commit = (& git -C $root rev-parse HEAD).Trim()
$statusText = (& git -C $root status --porcelain --ignore-submodules=dirty | Out-String).Trim()
$workingTree = if ($statusText) {
    "Dirty"
}
else {
    "Clean"
}
@(
    "Name=$packageName"
    "Version=$Version"
    "Commit=$commit"
    "WorkingTree=$workingTree"
    "Configuration=$Configuration"
    "SelfContained=$(-not $FrameworkDependent)"
    "FrameworkDependent=$FrameworkDependent"
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
