param(
    [Parameter(Mandatory = $true)]
    [string]$PackagePath,
    [string]$TargetDirectory = "C:\RyzenAdj",
    [string]$BackupDirectory,
    [string]$EvidencePath,
    [switch]$Apply,
    [switch]$NoLaunch,
    [switch]$SkipShellIntegration,
    [string]$GuiArguments
)

$ErrorActionPreference = "Stop"

$root = Split-Path -Parent $PSCommandPath
$repositoryRoot = Split-Path -Parent $root
$artifactsRoot = [System.IO.Path]::GetFullPath(
    (Join-Path $repositoryRoot "artifacts"))
$guiArgumentContractPath = Join-Path $root "gui-cli-contract.json"

function Get-GuiArgumentContract {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "GUI argument contract is missing: $Path"
    }
    $contract = Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
    if ($null -eq $contract.arguments) {
        throw "GUI argument contract has no arguments map: $Path"
    }
    return $contract
}

# The native GUI has its own parser. Legacy .NET shortcuts carry flags such as
# --simple-mode; keeping unknown flags verbatim is what made the desktop
# shortcut exit immediately with "unknown argument".
function Resolve-SupportedGuiArguments {
    param(
        [AllowEmptyString()]
        [string]$Arguments,
        [Parameter(Mandatory = $true)]
        $Contract
    )

    $kept = New-Object System.Collections.Generic.List[string]
    $dropped = New-Object System.Collections.Generic.List[string]
    if (-not [string]::IsNullOrWhiteSpace($Arguments)) {
        $tokens = @(
            $Arguments -split "\s+" |
                Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
        $index = 0
        while ($index -lt $tokens.Count) {
            $token = $tokens[$index]
            $entry = $Contract.arguments.PSObject.Properties[$token]
            if ($null -eq $entry) {
                $dropped.Add($token)
                $index += 1
                continue
            }
            $kept.Add($token)
            if ([bool]$entry.Value.takesValue) {
                if ($index + 1 -ge $tokens.Count) {
                    throw "Argument $token requires a value. Fix the shortcut before promoting."
                }
                $kept.Add($tokens[$index + 1])
                $index += 2
                continue
            }
            $index += 1
        }
    }
    return [pscustomobject]@{
        Arguments = ($kept -join " ")
        Dropped = @($dropped)
    }
}

# Launches the promoted GUI with the exact shortcut arguments under an
# isolated LOCALAPPDATA and a unique worker pipe. That proves the shortcut
# really starts a window without touching the user's saved power policy.
function Test-PromotedGuiLaunch {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Executable,
        [AllowEmptyString()]
        [string]$Arguments
    )

    if (-not (Test-Path -LiteralPath $Executable -PathType Leaf)) {
        throw "Promoted GUI is missing: $Executable"
    }
    $isolatedLocalAppData = Resolve-ArtifactPath (
        Join-Path $artifactsRoot "promotion-launch-$([Guid]::NewGuid().ToString('N'))")
    $pipeName = "AmdMobilePower.Worker.promote.$([Guid]::NewGuid().ToString('N').Substring(0, 8))"
    $previousLocalAppData = $env:LOCALAPPDATA
    $argumentList = @()
    if (-not [string]::IsNullOrWhiteSpace($Arguments)) {
        $argumentList += @(
            $Arguments -split "\s+" |
                Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    }
    $argumentList += @("--pipe-name", $pipeName)
    $process = $null
    try {
        New-Item -ItemType Directory -Path $isolatedLocalAppData -Force | Out-Null
        $env:LOCALAPPDATA = $isolatedLocalAppData
        $process = Start-Process `
            -FilePath $Executable `
            -WorkingDirectory (Split-Path -Parent $Executable) `
            -ArgumentList $argumentList `
            -PassThru
        $deadline = [DateTime]::UtcNow.AddSeconds(20)
        while ([DateTime]::UtcNow -lt $deadline) {
            $process.Refresh()
            if ($process.HasExited) {
                throw "Promoted GUI exited with code $($process.ExitCode). Arguments: $($argumentList -join ' ')"
            }
            if ($process.MainWindowHandle -ne [IntPtr]::Zero -and
                $process.MainWindowTitle -like "AMD Mobile Power*") {
                return [pscustomobject]@{
                    Result = "PASS"
                    Arguments = ($argumentList -join " ")
                    WindowTitle = $process.MainWindowTitle
                }
            }
            Start-Sleep -Milliseconds 250
        }
        throw "Promoted GUI did not create a window. Arguments: $($argumentList -join ' ')"
    }
    finally {
        if ($null -ne $process) {
            Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
        }
        Get-CimInstance Win32_Process `
            -Filter "Name = 'amdmobilepower_native_worker.exe'" `
            -ErrorAction SilentlyContinue |
            Where-Object { $_.CommandLine -like "*$pipeName*" } |
            ForEach-Object {
                Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue
            }
        $env:LOCALAPPDATA = $previousLocalAppData
        if (Test-Path -LiteralPath $isolatedLocalAppData) {
            Remove-Item -LiteralPath $isolatedLocalAppData -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

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
        [string[]]$LegacyTargets
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
        $matchesTarget = $false
        foreach ($candidate in $LegacyTargets) {
            if ($shortcut.TargetPath.Equals(
                $candidate,
                [System.StringComparison]::OrdinalIgnoreCase)) {
                $matchesTarget = $true
                break
            }
        }
        if ($matchesTarget) {
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
        if ($null -ne $item.PSObject.Properties["ResolvedArguments"]) {
            $shortcut.Arguments = [string]$item.ResolvedArguments
        }
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
$nativeGui = Join-Path $resolvedTarget "amd-mobile-power-gui.exe"
$shortcutTargets = @($legacyGui, $nativeGui)
$shortcutSnapshots = @()
if (-not $SkipShellIntegration) {
    foreach ($rootPath in $desktopRoots) {
        $shortcutSnapshots += @(Get-ShortcutTargets `
            -Root $rootPath `
            -LegacyTargets $shortcutTargets)
    }
    if ($programsRoot) {
        $shortcutSnapshots += @(Get-ShortcutTargets `
            -Root $programsRoot `
            -LegacyTargets $shortcutTargets)
    }
}

$guiContract = $null
$explicitArguments = $null
if ($GuiArguments -or $shortcutSnapshots.Count -gt 0) {
    $guiContract = Get-GuiArgumentContract -Path $guiArgumentContractPath
    if ($GuiArguments) {
        $parsed = Resolve-SupportedGuiArguments `
            -Arguments $GuiArguments `
            -Contract $guiContract
        if (@($parsed.Dropped).Count -gt 0) {
            throw ("GuiArguments contains arguments the GUI rejects: " +
                (@($parsed.Dropped) -join ", "))
        }
        $explicitArguments = $parsed.Arguments
    }
}
if ($shortcutSnapshots.Count -gt 0) {
    foreach ($snapshot in $shortcutSnapshots) {
        $sourceArguments = $snapshot.Arguments
        if ($null -ne $explicitArguments) {
            $sourceArguments = $explicitArguments
        }
        $resolved = Resolve-SupportedGuiArguments `
            -Arguments $sourceArguments `
            -Contract $guiContract
        $snapshot | Add-Member `
            -NotePropertyName ResolvedArguments `
            -NotePropertyValue $resolved.Arguments `
            -Force
        $snapshot | Add-Member `
            -NotePropertyName DroppedArguments `
            -NotePropertyValue @($resolved.Dropped) `
            -Force
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
    GuiArguments = $GuiArguments
    LegacyShortcuts = @($shortcutSnapshots | ForEach-Object { $_.Path })
    ShortcutArguments = @($shortcutSnapshots | ForEach-Object {
        [pscustomobject]@{
            Path = $_.Path
            Before = $_.Arguments
            After = $_.ResolvedArguments
            Dropped = @($_.DroppedArguments)
        }
    })
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

    $primaryShortcutArguments = ""
    if ($shortcutSnapshots.Count -gt 0) {
        $primaryShortcutArguments = [string]$shortcutSnapshots[0].ResolvedArguments
    }
    $launchResult = "Skipped"
    if (-not $NoLaunch) {
        $launch = Test-PromotedGuiLaunch `
            -Executable (Join-Path $resolvedTarget "amd-mobile-power-gui.exe") `
            -Arguments $primaryShortcutArguments
        $launchResult = $launch.Result
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
        GuiArguments = $GuiArguments
        ShortcutsUpdated = @($shortcutSnapshots | ForEach-Object { $_.Path })
        ShortcutArguments = @($shortcutSnapshots | ForEach-Object {
            [pscustomobject]@{
                Path = $_.Path
                Before = $_.Arguments
                After = $_.ResolvedArguments
                Dropped = @($_.DroppedArguments)
            }
        })
        LaunchVerification = $launchResult
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
