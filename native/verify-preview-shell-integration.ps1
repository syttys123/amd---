param(
    [string]$PackageDirectory,
    [string]$EvidencePath
)

$ErrorActionPreference = "Stop"

$root = Split-Path -Parent $PSCommandPath
$repositoryRoot = Split-Path -Parent $root
$artifactsRoot = [System.IO.Path]::GetFullPath(
    (Join-Path $repositoryRoot "artifacts"))
$installDirectory = [System.IO.Path]::GetFullPath(
    (Join-Path $artifactsRoot "native-build\shell-integration-install"))
$startMenuDirectory = Join-Path `
    ([Environment]::GetFolderPath("Programs")) `
    "AMD Mobile Power Native Preview"
$startMenuShortcut = Join-Path `
    $startMenuDirectory `
    "AMD Mobile Power Native Preview.lnk"
$startupShortcut = Join-Path `
    ([Environment]::GetFolderPath("Startup")) `
    "AMD Mobile Power Native Preview.lnk"
$uninstallKey = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\AmdMobilePowerNativePreview"

if (-not $PackageDirectory) {
    $verifyRoot = Join-Path $artifactsRoot "native-build\package-verify"
    $PackageDirectory = Get-ChildItem `
        -LiteralPath $verifyRoot `
        -Directory `
        -ErrorAction Stop |
        Where-Object {
            (Test-Path -LiteralPath (Join-Path $_.FullName "install-preview.ps1")) -and
            (Test-Path -LiteralPath (Join-Path $_.FullName "uninstall-preview.ps1"))
        } |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1 -ExpandProperty FullName
}

if (-not $PackageDirectory) {
    throw "Native preview package directory was not found."
}

$PackageDirectory = (Resolve-Path -LiteralPath $PackageDirectory).Path
$installer = Join-Path $PackageDirectory "install-preview.ps1"
$uninstaller = Join-Path $PackageDirectory "uninstall-preview.ps1"
$buildInfoPath = Join-Path $PackageDirectory "BUILD-INFO.txt"
if (-not (Test-Path -LiteralPath $installer) -or
    -not (Test-Path -LiteralPath $uninstaller) -or
    -not (Test-Path -LiteralPath $buildInfoPath)) {
    throw "Package directory does not contain the native preview installer pair."
}

$version = $null
foreach ($line in Get-Content -LiteralPath $buildInfoPath) {
    if ($line -match "^Version=(.+)$") {
        $version = $Matches[1].Trim()
        break
    }
}
if (-not $version) {
    throw "Package BUILD-INFO.txt does not contain a Version field."
}

foreach ($path in @($installDirectory, $startMenuShortcut, $startupShortcut)) {
    if (Test-Path -LiteralPath $path) {
        throw "Refusing to overwrite existing shell-integration artifact: $path"
    }
}
if (Test-Path -LiteralPath $uninstallKey) {
    throw "Refusing to overwrite the existing native preview uninstall key."
}
if (-not $installDirectory.StartsWith(
    $artifactsRoot + [System.IO.Path]::DirectorySeparatorChar,
    [System.StringComparison]::OrdinalIgnoreCase)) {
    throw "Refusing to use an install directory outside artifacts: $installDirectory"
}

$result = [ordered]@{
    Version = $version
    SourcePackageCommit = $null
    Verification = "PASS"
    InstallDirectoryCreated = $false
    InstallMarkerCreated = $false
    StartMenuShortcutCreated = $false
    StartupShortcutCreated = $false
    UninstallEntryCreated = $false
    UninstallEntryVersion = $null
    Cleanup = "Not run"
}
foreach ($line in Get-Content -LiteralPath $buildInfoPath) {
    if ($line -match "^Commit=(.+)$") {
        $result.SourcePackageCommit = $Matches[1].Trim()
        break
    }
}

if (-not $EvidencePath) {
    $evidenceDate = Get-Date -Format "yyyy-MM-dd"
    $EvidencePath = Join-Path `
        $repositoryRoot `
        "docs\evidence\packaging\v$version-shell-integration-$evidenceDate.json"
}

try {
    $installOutput = & powershell.exe `
        -NoProfile `
        -ExecutionPolicy Bypass `
        -File $installer `
        -InstallDirectory $installDirectory `
        -NoLaunch 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "Real shell integration install failed: $installOutput"
    }

    $result.InstallDirectoryCreated = Test-Path -LiteralPath $installDirectory
    $result.InstallMarkerCreated = Test-Path -LiteralPath `
        (Join-Path $installDirectory "NATIVE-PREVIEW-INSTALL.txt")
    $result.StartMenuShortcutCreated = Test-Path -LiteralPath $startMenuShortcut
    $result.StartupShortcutCreated = Test-Path -LiteralPath $startupShortcut
    $result.UninstallEntryCreated = Test-Path -LiteralPath $uninstallKey
    if ($result.UninstallEntryCreated) {
        $result.UninstallEntryVersion = (Get-ItemProperty `
            -LiteralPath $uninstallKey `
            -Name "DisplayVersion" `
            -ErrorAction Stop).DisplayVersion
    }

    if (-not $result.InstallDirectoryCreated -or
        -not $result.InstallMarkerCreated -or
        -not $result.StartMenuShortcutCreated -or
        -not $result.StartupShortcutCreated -or
        -not $result.UninstallEntryCreated -or
        $result.UninstallEntryVersion -ne $version) {
        throw "Real shell integration install did not produce the expected state."
    }

    $uninstallOutput = & powershell.exe `
        -NoProfile `
        -ExecutionPolicy Bypass `
        -File $uninstaller `
        -InstallDirectory $installDirectory 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "Real shell integration uninstall failed: $uninstallOutput"
    }
    if ((Test-Path -LiteralPath $installDirectory) -or
        (Test-Path -LiteralPath $startMenuShortcut) -or
        (Test-Path -LiteralPath $startupShortcut) -or
        (Test-Path -LiteralPath $uninstallKey)) {
        throw "Real shell integration uninstall left residual state."
    }
    $result.Cleanup = "PASS"
}
finally {
    if ((Test-Path -LiteralPath $uninstaller) -and
        (Test-Path -LiteralPath (Join-Path $installDirectory "NATIVE-PREVIEW-INSTALL.txt"))) {
        try {
            $null = & powershell.exe `
                -NoProfile `
                -ExecutionPolicy Bypass `
                -File $uninstaller `
                -InstallDirectory $installDirectory 2>&1
        }
        catch {
        }
    }

    if (Test-Path -LiteralPath $startMenuShortcut) {
        Remove-Item -LiteralPath $startMenuShortcut -Force
    }
    if (Test-Path -LiteralPath $startupShortcut) {
        Remove-Item -LiteralPath $startupShortcut -Force
    }
    if ((Test-Path -LiteralPath $startMenuDirectory) -and
        -not (Get-ChildItem -LiteralPath $startMenuDirectory -Force)) {
        Remove-Item -LiteralPath $startMenuDirectory -Force
    }
    if (Test-Path -LiteralPath $uninstallKey) {
        Remove-Item -LiteralPath $uninstallKey -Recurse -Force
    }
    if (Test-Path -LiteralPath $installDirectory) {
        Remove-Item -LiteralPath $installDirectory -Recurse -Force
    }

    $result.ResidualInstallDirectory = Test-Path -LiteralPath $installDirectory
    $result.ResidualStartMenuShortcut = Test-Path -LiteralPath $startMenuShortcut
    $result.ResidualStartupShortcut = Test-Path -LiteralPath $startupShortcut
    $result.ResidualUninstallEntry = Test-Path -LiteralPath $uninstallKey
    $result.RecordedAt = (Get-Date).ToString("o")

    $evidenceDirectory = Split-Path -Parent $EvidencePath
    if ($evidenceDirectory) {
        New-Item -ItemType Directory -Path $evidenceDirectory -Force | Out-Null
    }
    $result |
        ConvertTo-Json -Depth 5 |
        Set-Content -LiteralPath $EvidencePath -Encoding UTF8
}

if ($result.ResidualInstallDirectory -or
    $result.ResidualStartMenuShortcut -or
    $result.ResidualStartupShortcut -or
    $result.ResidualUninstallEntry) {
    throw "Real shell integration cleanup left residual state."
}

$result | Format-List
