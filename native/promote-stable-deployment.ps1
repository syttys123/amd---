param(
    [Parameter(Mandatory = $true)]
    [string]$PackagePath,
    [string]$TargetDirectory = "C:\RyzenAdj",
    [string]$BackupDirectory,
    [string]$EvidencePath,
    [switch]$Apply,
    [switch]$NoLaunch,
    [switch]$SkipShellIntegration
)

$ErrorActionPreference = "Stop"

$root = Split-Path -Parent $PSCommandPath
$repositoryRoot = Split-Path -Parent $root
$artifactsRoot = [System.IO.Path]::GetFullPath(
    (Join-Path $repositoryRoot "artifacts"))

function Resolve-ArtifactPath {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    $resolved = [System.IO.Path]::GetFullPath($Path)
    if (-not $resolved.StartsWith(
        $artifactsRoot + [System.IO.Path]::DirectorySeparatorChar,
        [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Path must stay under $artifactsRoot : $resolved"
    }
    return $resolved
}

function Assert-SafeTarget {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    $resolved = [System.IO.Path]::GetFullPath($Path)
    $pathRoot = [System.IO.Path]::GetPathRoot($resolved)
    if ([string]::IsNullOrWhiteSpace($pathRoot)) {
        throw "Target path has no filesystem root: $resolved"
    }
    $trimmedRoot = $pathRoot.TrimEnd(
        [System.IO.Path]::DirectorySeparatorChar,
        [System.IO.Path]::AltDirectorySeparatorChar)
    $trimmedTarget = $resolved.TrimEnd(
        [System.IO.Path]::DirectorySeparatorChar,
        [System.IO.Path]::AltDirectorySeparatorChar)
    if ($trimmedTarget.Equals(
        $trimmedRoot,
        [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Target must not be a filesystem root: $resolved"
    }
    return $resolved
}

function Get-ShortcutTargets {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Root,
        [Parameter(Mandatory = $true)]
        [string]$LegacyTarget
    )

    $items = @()
    if (-not (Test-Path -LiteralPath $Root)) {
        return $items
    }
    $shell = New-Object -ComObject WScript.Shell
    foreach ($shortcutFile in Get-ChildItem `
        -LiteralPath $Root `
        -Recurse `
        -Filter "*.lnk" `
        -ErrorAction SilentlyContinue) {
        $shortcut = $shell.CreateShortcut($shortcutFile.FullName)
        if ($shortcut.TargetPath.Equals(
            $LegacyTarget,
            [System.StringComparison]::OrdinalIgnoreCase)) {
            $items += [pscustomobject]@{
                Path = $shortcutFile.FullName
                Target = $shortcut.TargetPath
                Arguments = $shortcut.Arguments
                WorkingDirectory = $shortcut.WorkingDirectory
                IconLocation = $shortcut.IconLocation
            }
        }
    }
    return $items
}

function Update-ShortcutTargets {
    param(
        [Parameter(Mandatory = $true)]
        [object[]]$Shortcuts,
        [Parameter(Mandatory = $true)]
        [string]$NewTarget
    )

    $shell = New-Object -ComObject WScript.Shell
    foreach ($item in $Shortcuts) {
        $shortcut = $shell.CreateShortcut($item.Path)
        $shortcut.TargetPath = $NewTarget
        $shortcut.WorkingDirectory = Split-Path -Parent $NewTarget
        $shortcut.IconLocation = "$NewTarget,0"
        $shortcut.Save()
    }
}

function Restore-ShortcutTargets {
    param(
        [Parameter(Mandatory = $true)]
        [object[]]$Shortcuts
    )

    if ($Shortcuts.Count -eq 0) {
        return
    }
    $shell = New-Object -ComObject WScript.Shell
    foreach ($item in $Shortcuts) {
        if (-not (Test-Path -LiteralPath $item.Path)) {
            continue
        }
        $shortcut = $shell.CreateShortcut($item.Path)
        $shortcut.TargetPath = $item.Target
        $shortcut.Arguments = $item.Arguments
        $shortcut.WorkingDirectory = $item.WorkingDirectory
        $shortcut.IconLocation = $item.IconLocation
        $shortcut.Save()
    }
}

function Stop-ExistingOwners {
    $names = @(
        "amd-mobile-power-gui",
        "amdmobilepower_native_worker",
        "AmdMobilePower",
        "AmdMobilePower.Worker",
        "RyzenPower",
        "ryzenadj"
    )
    foreach ($name in $names) {
        Get-Process -Name $name -ErrorAction SilentlyContinue |
            Stop-Process -Force -ErrorAction SilentlyContinue
    }
}

$resolvedPackage = (Resolve-Path -LiteralPath $PackagePath).Path
if (-not $resolvedPackage.EndsWith(
    ".zip",
    [System.StringComparison]::OrdinalIgnoreCase)) {
    throw "PackagePath must point to a ZIP: $resolvedPackage"
}
$resolvedTarget = Assert-SafeTarget $TargetDirectory
$packageLeaf = [System.IO.Path]::GetFileNameWithoutExtension($resolvedPackage)
if (-not $BackupDirectory) {
    $BackupDirectory = "$resolvedTarget.before-" +
        "$(Get-Date -Format 'yyyyMMdd-HHmmss')"
}
$resolvedBackup = [System.IO.Path]::GetFullPath($BackupDirectory)
if ($resolvedBackup.Equals(
    $resolvedTarget,
    [System.StringComparison]::OrdinalIgnoreCase)) {
    throw "Backup directory must differ from the target."
}
if ($resolvedTarget.StartsWith(
    $resolvedBackup + [System.IO.Path]::DirectorySeparatorChar,
    [System.StringComparison]::OrdinalIgnoreCase)) {
    throw "Backup directory must not contain the target."
}
if (-not $EvidencePath) {
    $EvidencePath = Join-Path `
        $artifactsRoot `
        "deployment-backups\promote-$packageLeaf-$(Get-Date -Format 'yyyyMMdd-HHmmss').json"
}
$resolvedEvidence = Resolve-ArtifactPath $EvidencePath

$desktopRoots = @(
    [Environment]::GetFolderPath("Desktop"),
    "C:\Users\Public\Desktop"
) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Unique
$programsRoot = [Environment]::GetFolderPath("Programs")
$legacyGui = Join-Path $resolvedTarget "AmdMobilePower.exe"
$shortcutSnapshots = @()
if (-not $SkipShellIntegration) {
    foreach ($rootPath in $desktopRoots) {
        $shortcutSnapshots += @(Get-ShortcutTargets `
            -Root $rootPath `
            -LegacyTarget $legacyGui)
    }
    if ($programsRoot) {
        $shortcutSnapshots += @(Get-ShortcutTargets `
            -Root $programsRoot `
            -LegacyTarget $legacyGui)
    }
}

$packageVersion = "unknown"
Add-Type -AssemblyName System.IO.Compression.FileSystem
$archive = [System.IO.Compression.ZipFile]::OpenRead($resolvedPackage)
try {
    $buildInfoEntry = $archive.Entries |
        Where-Object { $_.FullName -match "/BUILD-INFO.txt$" } |
        Select-Object -First 1
    if ($null -eq $buildInfoEntry) {
        throw "Package does not contain BUILD-INFO.txt."
    }
    $reader = [System.IO.StreamReader]::new($buildInfoEntry.Open())
    try {
        foreach ($line in ($reader.ReadToEnd() -split "`r?`n")) {
            if ($line -match "^Version=(.+)$") {
                $packageVersion = $Matches[1].Trim()
                break
            }
        }
    }
    finally {
        $reader.Dispose()
    }
}
finally {
    $archive.Dispose()
}

$plan = [ordered]@{
    Package = $resolvedPackage
    PackageVersion = $packageVersion
    Target = $resolvedTarget
    Backup = $resolvedBackup
    Evidence = $resolvedEvidence
    LegacyShortcuts = @($shortcutSnapshots | ForEach-Object { $_.Path })
    Apply = [bool]$Apply
    NoLaunch = [bool]$NoLaunch
}
if (-not $Apply) {
    [pscustomobject]$plan | Format-List
    Write-Output "Dry run only. Re-run with -Apply to replace the target."
    return
}

$stagingRoot = Join-Path `
    $artifactsRoot `
    "deployment-backups\staging-$([Guid]::NewGuid().ToString('N'))"
$stagingRoot = Resolve-ArtifactPath $stagingRoot
$installed = $false
$movedExisting = $false
$shortcutsUpdated = $false
try {
    Stop-ExistingOwners
    New-Item -ItemType Directory -Path $stagingRoot -Force | Out-Null
    Expand-Archive -LiteralPath $resolvedPackage -DestinationPath $stagingRoot
    $packageDirectory = Get-ChildItem -LiteralPath $stagingRoot -Directory |
        Select-Object -First 1
    if ($null -eq $packageDirectory) {
        throw "Package ZIP has no top-level directory."
    }

    if (Test-Path -LiteralPath $resolvedTarget) {
        if (Test-Path -LiteralPath $resolvedBackup) {
            throw "Backup path already exists: $resolvedBackup"
        }
        Move-Item -LiteralPath $resolvedTarget -Destination $resolvedBackup
        $movedExisting = $true
    }

    & (Join-Path $packageDirectory.FullName "install-preview.ps1") `
        -InstallDirectory $resolvedTarget `
        -NoStartup `
        -NoShellIntegration `
        -NoLaunch
    if ($LASTEXITCODE -ne 0 -and $null -ne $LASTEXITCODE) {
        throw "install-preview.ps1 failed with exit code $LASTEXITCODE."
    }
    if (-not (Test-Path -LiteralPath (Join-Path $resolvedTarget "amd-mobile-power-gui.exe"))) {
        throw "Installed target is missing amd-mobile-power-gui.exe."
    }
    $installed = $true

    if (-not $SkipShellIntegration -and $shortcutSnapshots.Count -gt 0) {
        Update-ShortcutTargets `
            -Shortcuts $shortcutSnapshots `
            -NewTarget (Join-Path $resolvedTarget "amd-mobile-power-gui.exe")
        $shortcutsUpdated = $true
    }

    if (-not $NoLaunch) {
        $gui = Join-Path $resolvedTarget "amd-mobile-power-gui.exe"
        $process = Start-Process `
            -FilePath $gui `
            -WorkingDirectory $resolvedTarget `
            -PassThru
        $deadline = [DateTime]::UtcNow.AddSeconds(15)
        while ([DateTime]::UtcNow -lt $deadline) {
            $process.Refresh()
            if ($process.HasExited) {
                throw "Promoted GUI exited with code $($process.ExitCode)."
            }
            if ($process.MainWindowHandle -ne [IntPtr]::Zero) {
                break
            }
            Start-Sleep -Milliseconds 250
        }
        if ($process.MainWindowHandle -eq [IntPtr]::Zero) {
            throw "Promoted GUI did not create a window."
        }
    }

    $evidenceDirectory = Split-Path -Parent $resolvedEvidence
    if ($evidenceDirectory) {
        New-Item -ItemType Directory -Path $evidenceDirectory -Force | Out-Null
    }
    [pscustomobject]@{
        Verification = "PASS"
        Package = $resolvedPackage
        PackageSHA256 = (Get-FileHash -LiteralPath $resolvedPackage -Algorithm SHA256).
            Hash.ToLowerInvariant()
        PackageVersion = $packageVersion
        Target = $resolvedTarget
        Backup = $resolvedBackup
        ShortcutsUpdated = @($shortcutSnapshots | ForEach-Object { $_.Path })
        Launched = (-not $NoLaunch)
        RecordedAt = (Get-Date).ToString("o")
    } |
        ConvertTo-Json -Depth 6 |
        Set-Content -LiteralPath $resolvedEvidence -Encoding UTF8
    Get-Content -LiteralPath $resolvedEvidence -Raw
}
catch {
    $failure = $_
    try {
        Stop-ExistingOwners
        if ($shortcutsUpdated) {
            Restore-ShortcutTargets -Shortcuts $shortcutSnapshots
        }
        if (Test-Path -LiteralPath $resolvedTarget) {
            $installedPrefix = $resolvedTarget.TrimEnd(
                [System.IO.Path]::DirectorySeparatorChar) +
                [System.IO.Path]::DirectorySeparatorChar
            $resolvedInstall = [System.IO.Path]::GetFullPath($resolvedTarget)
            if (-not $resolvedInstall.StartsWith(
                $installedPrefix.TrimEnd(
                    [System.IO.Path]::DirectorySeparatorChar) +
                    [System.IO.Path]::DirectorySeparatorChar,
                [System.StringComparison]::OrdinalIgnoreCase)) {
                throw "Refusing to remove an unexpected target: $resolvedInstall"
            }
            Remove-Item -LiteralPath $resolvedInstall -Recurse -Force
        }
        if ($movedExisting -and (Test-Path -LiteralPath $resolvedBackup)) {
            Move-Item -LiteralPath $resolvedBackup -Destination $resolvedTarget
        }
    }
    catch {
        Write-Error "Rollback encountered an error: $($_.Exception.Message)"
    }
    throw $failure
}
finally {
    if (Test-Path -LiteralPath $stagingRoot) {
        $stagingPrefix = $artifactsRoot.TrimEnd(
            [System.IO.Path]::DirectorySeparatorChar) +
            [System.IO.Path]::DirectorySeparatorChar
        $resolvedStaging = [System.IO.Path]::GetFullPath($stagingRoot)
        if (-not $resolvedStaging.StartsWith(
            $stagingPrefix,
            [System.StringComparison]::OrdinalIgnoreCase)) {
            throw "Refusing to remove an unexpected staging path: $resolvedStaging"
        }
        Remove-Item -LiteralPath $resolvedStaging -Recurse -Force
    }
}
