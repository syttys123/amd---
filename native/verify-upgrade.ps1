param(
    [Parameter(Mandatory = $true)]
    [string]$OldPackage,
    [Parameter(Mandatory = $true)]
    [string]$NewPackage,
    [string]$EvidencePath
)

$ErrorActionPreference = "Stop"

$root = Split-Path -Parent $PSCommandPath
$repositoryRoot = Split-Path -Parent $root
$artifactsRoot = [System.IO.Path]::GetFullPath(
    (Join-Path $repositoryRoot "artifacts"))
$workDirectory = [System.IO.Path]::GetFullPath(
    (Join-Path $artifactsRoot "native-build\upgrade-verify-$([Guid]::NewGuid().ToString('N'))"))
$powerShellExecutable = if (Get-Command pwsh.exe -ErrorAction SilentlyContinue) {
    (Get-Command pwsh.exe -ErrorAction Stop).Source
}
else {
    Join-Path $PSHOME "powershell.exe"
}
$artifactsPrefix = $artifactsRoot + [System.IO.Path]::DirectorySeparatorChar
if (-not $workDirectory.StartsWith(
    $artifactsPrefix,
    [System.StringComparison]::OrdinalIgnoreCase)) {
    throw "Unsafe upgrade verification directory: $workDirectory"
}

function Expand-NativePackage {
    param(
        [string]$Archive,
        [string]$Destination
    )

    New-Item -ItemType Directory -Path $Destination -Force | Out-Null
    Expand-Archive -LiteralPath $Archive -DestinationPath $Destination -Force
    $packageDirectory = Get-ChildItem `
        -LiteralPath $Destination `
        -Directory |
        Where-Object {
            (Test-Path -LiteralPath (Join-Path $_.FullName "install-preview.ps1")) -and
            (Test-Path -LiteralPath (Join-Path $_.FullName "BUILD-INFO.txt"))
        } |
        Select-Object -First 1 -ExpandProperty FullName
    if (-not $packageDirectory) {
        throw "Expanded archive does not contain a native preview package: $Archive"
    }
    return $packageDirectory
}

function Read-BuildInfo {
    param([string]$PackageDirectory)

    $values = @{}
    foreach ($line in Get-Content -LiteralPath (Join-Path $PackageDirectory "BUILD-INFO.txt")) {
        if ($line -match "^([^=]+)=(.+)$") {
            $values[$Matches[1].Trim()] = $Matches[2].Trim()
        }
    }
    return $values
}

function Get-RelativeFileHashes {
    param([string]$Directory)

    $hashes = @{}
    foreach ($file in Get-ChildItem -LiteralPath $Directory -File -Recurse) {
        $relative = [System.IO.Path]::GetRelativePath(
            $Directory,
            $file.FullName).Replace("\", "/")
        $hashes[$relative] = (
            Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256
        ).Hash.ToLowerInvariant()
    }
    return $hashes
}

function Invoke-PowerShellFile {
    param(
        [string]$File,
        [string[]]$Arguments
    )

    $output = & $powerShellExecutable `
        -NoProfile `
        -ExecutionPolicy Bypass `
        -File $File `
        @Arguments 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "PowerShell verification step failed: $File`n$($output -join "`n")"
    }
    return $output
}

$oldArchive = (Resolve-Path -LiteralPath $OldPackage).Path
$newArchive = (Resolve-Path -LiteralPath $NewPackage).Path
$oldHash = (Get-FileHash -LiteralPath $oldArchive -Algorithm SHA256).Hash.ToLowerInvariant()
$newHash = (Get-FileHash -LiteralPath $newArchive -Algorithm SHA256).Hash.ToLowerInvariant()
$installDirectory = Join-Path $workDirectory "install"
$result = [ordered]@{
    Verification = "Not run"
    OldPackage = (Split-Path -Leaf $oldArchive)
    OldPackageSHA256 = $oldHash
    NewPackage = (Split-Path -Leaf $newArchive)
    NewPackageSHA256 = $newHash
    OldVersion = $null
    NewVersion = $null
    InstallFlow = "Not run"
    InstalledPayloadMatchesNewPackage = $false
    RemovedSupersededFiles = @()
    ReadOnlyGuiAfterUpgrade = "Not run"
    Uninstall = "Not run"
    ResidualInstallDirectory = $null
    RecordedAt = $null
}

try {
    $oldPackageDirectory = Expand-NativePackage `
        -Archive $oldArchive `
        -Destination (Join-Path $workDirectory "old")
    $newPackageDirectory = Expand-NativePackage `
        -Archive $newArchive `
        -Destination (Join-Path $workDirectory "new")
    $oldBuildInfo = Read-BuildInfo -PackageDirectory $oldPackageDirectory
    $newBuildInfo = Read-BuildInfo -PackageDirectory $newPackageDirectory
    $result.OldVersion = $oldBuildInfo.Version
    $result.NewVersion = $newBuildInfo.Version
    if (-not $result.OldVersion -or -not $result.NewVersion) {
        throw "Package BUILD-INFO.txt is missing Version."
    }

    $oldInstaller = Join-Path $oldPackageDirectory "install-preview.ps1"
    $newInstaller = Join-Path $newPackageDirectory "install-preview.ps1"
    $installArguments = @(
        "-InstallDirectory", $installDirectory,
        "-NoStartup",
        "-NoShellIntegration",
        "-NoLaunch"
    )
    $null = Invoke-PowerShellFile -File $oldInstaller -Arguments $installArguments
    $installedOld = Read-BuildInfo -PackageDirectory $installDirectory
    if ($installedOld.Version -ne $result.OldVersion) {
        throw "Old package install version mismatch: $($installedOld.Version)"
    }

    $oldFiles = Get-RelativeFileHashes -Directory $oldPackageDirectory
    $newFiles = Get-RelativeFileHashes -Directory $newPackageDirectory
    $null = Invoke-PowerShellFile -File $newInstaller -Arguments $installArguments
    $installedNew = Read-BuildInfo -PackageDirectory $installDirectory
    if ($installedNew.Version -ne $result.NewVersion) {
        throw "Upgrade install version mismatch: $($installedNew.Version)"
    }

    foreach ($relative in $newFiles.Keys) {
        $installedPath = Join-Path $installDirectory $relative
        if (-not (Test-Path -LiteralPath $installedPath -PathType Leaf)) {
            throw "Upgraded install is missing new package file: $relative"
        }
        $actual = (
            Get-FileHash -LiteralPath $installedPath -Algorithm SHA256
        ).Hash.ToLowerInvariant()
        if ($actual -ne $newFiles[$relative]) {
            throw "Upgraded install hash mismatch: $relative"
        }
    }
    $result.InstalledPayloadMatchesNewPackage = $true
    $result.InstallFlow = "PASS"

    $removed = @(
        $oldFiles.Keys |
            Where-Object { -not $newFiles.ContainsKey($_) } |
            Sort-Object
    )
    foreach ($relative in $removed) {
        if (Test-Path -LiteralPath (Join-Path $installDirectory $relative)) {
            throw "Upgraded install retained superseded file: $relative"
        }
    }
    $result.RemovedSupersededFiles = $removed

    $verifyGui = Join-Path $root "verify-rust-gui.ps1"
    $installedGui = Join-Path $installDirectory "amd-mobile-power-gui.exe"
    $guiOutput = Invoke-PowerShellFile `
        -File $verifyGui `
        -Arguments @("-NoBuild", "-VerifyWorker", "-GuiExecutable", $installedGui)
    if (($guiOutput -join "`n") -notmatch "Verification\s+:\s+PASS" -or
        ($guiOutput -join "`n") -notmatch "WorkerReadOnly\s+:\s+PASS") {
        throw "Upgraded GUI did not pass read-only worker verification."
    }
    $result.ReadOnlyGuiAfterUpgrade = "PASS"

    $installedUninstaller = Join-Path $installDirectory "uninstall-preview.ps1"
    $null = Invoke-PowerShellFile `
        -File $installedUninstaller `
        -Arguments @(
            "-InstallDirectory", $installDirectory,
            "-NoStartup",
            "-NoShellIntegration"
        )
    $result.ResidualInstallDirectory = Test-Path -LiteralPath $installDirectory
    if ($result.ResidualInstallDirectory) {
        throw "Upgrade uninstall left the install directory behind."
    }
    $result.Uninstall = "PASS"
    $result.Verification = "PASS"
}
finally {
    $result.RecordedAt = (Get-Date).ToString("o")
    if ($EvidencePath) {
        $evidenceDirectory = Split-Path -Parent $EvidencePath
        if ($evidenceDirectory) {
            New-Item -ItemType Directory -Path $evidenceDirectory -Force | Out-Null
        }
        $result |
            ConvertTo-Json -Depth 6 |
            Set-Content -LiteralPath $EvidencePath -Encoding UTF8
    }
    if (Test-Path -LiteralPath $workDirectory) {
        Remove-Item -LiteralPath $workDirectory -Recurse -Force
    }
}

$result | Format-List
