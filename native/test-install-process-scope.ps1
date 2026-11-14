param(
    [string]$PackageDirectory = (
        Join-Path `
            (Split-Path -Parent $PSScriptRoot) `
            "artifacts\native-packages\amd-mobile-power-v1.0.31-win-x64-native-preview"
    ),
    [string]$StableInstallDirectory = "C:\RyzenAdj"
)

$ErrorActionPreference = "Stop"

$repositoryRoot = Split-Path -Parent $PSScriptRoot
$artifactsRoot = [System.IO.Path]::GetFullPath(
    (Join-Path $repositoryRoot "artifacts"))
$verifyRoot = [System.IO.Path]::GetFullPath(
    (Join-Path $artifactsRoot "verify"))
$operationId = [Guid]::NewGuid().ToString("N")
$testPackage = Join-Path $verifyRoot "install-guard-package-$operationId"
$testTarget = Join-Path $verifyRoot "install-guard-target-$operationId"

function Assert-UnderVerifyRoot {
    param([Parameter(Mandatory = $true)][string]$Path)

    $resolved = [System.IO.Path]::GetFullPath($Path)
    if (-not $resolved.StartsWith(
        $verifyRoot + [System.IO.Path]::DirectorySeparatorChar,
        [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Unsafe test path: $resolved"
    }
    return $resolved
}

function Get-StableProcessIds {
    param([Parameter(Mandatory = $true)][string]$InstallDirectory)

    $prefix = [System.IO.Path]::GetFullPath($InstallDirectory).TrimEnd(
        [System.IO.Path]::DirectorySeparatorChar,
        [System.IO.Path]::AltDirectorySeparatorChar) +
        [System.IO.Path]::DirectorySeparatorChar
    @(
        Get-CimInstance `
            -ClassName Win32_Process `
            -Filter "Name='amd-mobile-power-gui.exe' OR Name='amdmobilepower_native_worker.exe'" |
            Where-Object {
                -not [string]::IsNullOrWhiteSpace($_.ExecutablePath) -and
                [System.IO.Path]::GetFullPath($_.ExecutablePath).StartsWith(
                    $prefix,
                    [System.StringComparison]::OrdinalIgnoreCase)
            } |
            ForEach-Object { [int]$_.ProcessId } |
            Sort-Object
    )
}

if (-not (Test-Path -LiteralPath $PackageDirectory -PathType Container)) {
    throw "Package directory is missing: $PackageDirectory"
}
if (-not (Test-Path -LiteralPath $StableInstallDirectory -PathType Container)) {
    throw "Stable install directory is missing: $StableInstallDirectory"
}

$stableBefore = Get-StableProcessIds -InstallDirectory $StableInstallDirectory
if ($stableBefore.Count -eq 0) {
    throw "No stable GUI/worker process is running; run this guard with the deployed app active."
}

Assert-UnderVerifyRoot $testPackage | Out-Null
Assert-UnderVerifyRoot $testTarget | Out-Null

try {
    New-Item -ItemType Directory -Path $testPackage -Force | Out-Null
    Copy-Item `
        -Path (Join-Path $PackageDirectory "*") `
        -Destination $testPackage `
        -Recurse `
        -Force
    Copy-Item `
        -LiteralPath (Join-Path $PSScriptRoot "install-preview.ps1") `
        -Destination (Join-Path $testPackage "install-preview.ps1") `
        -Force
    Copy-Item `
        -LiteralPath (Join-Path $PSScriptRoot "uninstall-preview.ps1") `
        -Destination (Join-Path $testPackage "uninstall-preview.ps1") `
        -Force

    & powershell.exe `
        -NoProfile `
        -ExecutionPolicy Bypass `
        -File (Join-Path $testPackage "install-preview.ps1") `
        -InstallDirectory $testTarget `
        -NoStartup `
        -NoShellIntegration `
        -NoLaunch
    if ($LASTEXITCODE -ne 0) {
        throw "Isolated install failed with exit code $LASTEXITCODE."
    }

    & powershell.exe `
        -NoProfile `
        -ExecutionPolicy Bypass `
        -File (Join-Path $testPackage "uninstall-preview.ps1") `
        -InstallDirectory $testTarget `
        -NoStartup `
        -NoShellIntegration
    if ($LASTEXITCODE -ne 0) {
        throw "Isolated uninstall failed with exit code $LASTEXITCODE."
    }

    $stableAfter = Get-StableProcessIds -InstallDirectory $StableInstallDirectory
    $beforeText = $stableBefore -join ","
    $afterText = $stableAfter -join ","
    if ($beforeText -ne $afterText) {
        throw "Stable process set changed. Before=$beforeText After=$afterText"
    }

    [pscustomobject]@{
        Verification = "PASS"
        StableInstallDirectory = $StableInstallDirectory
        StableProcessIds = $beforeText
        IsolatedTargetLeftBehind = Test-Path -LiteralPath $testTarget
        RecordedAt = (Get-Date).ToString("o")
    } | Format-List
}
finally {
    foreach ($path in @($testPackage, $testTarget)) {
        $resolved = Assert-UnderVerifyRoot $path
        if (Test-Path -LiteralPath $resolved) {
            Remove-Item -LiteralPath $resolved -Recurse -Force
        }
    }
}
