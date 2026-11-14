param(
    [string]$Version = "0.5.0-native-preview.1",
    [switch]$NoBuild,
    [switch]$NoVerify,
    [switch]$SkipRuntimeVerification,
    [switch]$ReadOnlyRuntimeVerification,
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

# Compress-Archive stamps every entry with the file's mtime, so two builds of
# identical files produce different ZIPs. Writing the archive directly with a
# fixed entry timestamp and a sorted entry order makes the package hash a pure
# function of the staged content.
function New-DeterministicZip {
    param(
        [Parameter(Mandatory = $true)][string]$Stage,
        [Parameter(Mandatory = $true)][string]$Destination,
        [Parameter(Mandatory = $true)][string]$RootPrefix
    )

    Add-Type -AssemblyName System.IO.Compression | Out-Null
    Add-Type -AssemblyName System.IO.Compression.FileSystem | Out-Null

    $stream = [System.IO.File]::Open($Destination, [System.IO.FileMode]::Create)
    try {
        $archive = New-Object System.IO.Compression.ZipArchive(
            $stream,
            [System.IO.Compression.ZipArchiveMode]::Create,
            $true)
        try {
            $fixedTimestamp = [DateTimeOffset]::new(2000, 1, 1, 0, 0, 0, [TimeSpan]::Zero)
            $files = Get-ChildItem -LiteralPath $Stage -File -Recurse |
                Sort-Object FullName
            foreach ($file in $files) {
                $relative = [System.IO.Path]::GetRelativePath(
                    $Stage,
                    $file.FullName).Replace("\", "/")
                $entry = $archive.CreateEntry(
                    "$RootPrefix/$relative",
                    [System.IO.Compression.CompressionLevel]::Optimal)
                $entry.LastWriteTime = $fixedTimestamp
                $entryStream = $entry.Open()
                try {
                    $source = [System.IO.File]::OpenRead($file.FullName)
                    try {
                        $source.CopyTo($entryStream)
                    }
                    finally {
                        $source.Dispose()
                    }
                }
                finally {
                    $entryStream.Dispose()
                }
            }
        }
        finally {
            $archive.Dispose()
        }
    }
    finally {
        $stream.Dispose()
    }
}

function Assert-StagedChecksums {
    param([string]$Path)

    $checksumPath = Join-Path $Path "SHA256SUMS.txt"
    if (-not (Test-Path -LiteralPath $checksumPath)) {
        throw "The staged package has no SHA256SUMS.txt."
    }
    $entries = 0
    foreach ($line in Get-Content -LiteralPath $checksumPath) {
        if ($line -notmatch "^([0-9a-f]{64})  (.+)$") {
            throw "Invalid staged checksum entry: $line"
        }
        $expected = $Matches[1]
        $relative = $Matches[2].Replace("/", "\")
        $file = Join-Path $Path $relative
        if (-not (Test-Path -LiteralPath $file -PathType Leaf)) {
            throw "Staged checksum target is missing: $relative"
        }
        $actual = (Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash.ToLowerInvariant()
        if ($actual -ne $expected) {
            throw "Staged checksum mismatch for ${relative}: $actual != $expected"
        }
        ++$entries
    }
    if ($entries -eq 0) {
        throw "The staged package has an empty SHA256SUMS.txt."
    }
    return $entries
}

function Get-ShellIntegrationSnapshot {
    $startMenuShortcut = Join-Path `
        ([Environment]::GetFolderPath("Programs")) `
        "AMD Mobile Power Native Preview\AMD Mobile Power Native Preview.lnk"
    $startupShortcut = Join-Path `
        ([Environment]::GetFolderPath("Startup")) `
        "AMD Mobile Power Native Preview.lnk"
    $uninstallKey = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\AmdMobilePowerNativePreview"
    $uninstallVersion = $null
    if (Test-Path -LiteralPath $uninstallKey) {
        $uninstallVersion = (Get-ItemProperty `
            -LiteralPath $uninstallKey `
            -Name "DisplayVersion" `
            -ErrorAction SilentlyContinue).DisplayVersion
    }
    [pscustomobject]@{
        StartMenuExists = Test-Path -LiteralPath $startMenuShortcut
        StartMenuTimestamp = if (Test-Path -LiteralPath $startMenuShortcut) {
            (Get-Item -LiteralPath $startMenuShortcut).LastWriteTimeUtc.Ticks
        }
        else {
            $null
        }
        StartupExists = Test-Path -LiteralPath $startupShortcut
        StartupTimestamp = if (Test-Path -LiteralPath $startupShortcut) {
            (Get-Item -LiteralPath $startupShortcut).LastWriteTimeUtc.Ticks
        }
        else {
            $null
        }
        UninstallExists = Test-Path -LiteralPath $uninstallKey
        UninstallVersion = $uninstallVersion
    }
}

if (-not $NoBuild) {
    try {
        & (Join-Path $root "build.ps1") -Offline
    }
    catch {
        throw "Native build failed: $($_.Exception.Message)"
    }
}

foreach ($required in @(
    "amd-mobile-power-gui.exe",
    "amd-mobile-power-probe.exe",
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

& (Join-Path $root "check-exe-icon.ps1") `
    -Path (Join-Path $stage "amd-mobile-power-gui.exe")

# Hardware-free probe smoke test: proves the shipped binary parses its CLI and
# emits a schema-valid self-test document before any driver is installed.
$stagedProbe = Join-Path $stage "amd-mobile-power-probe.exe"
$selfTestOutput = & $stagedProbe --self-test
if ($LASTEXITCODE -ne 0) {
    throw "Staged headless probe self-test failed: $selfTestOutput"
}
$selfTest = $selfTestOutput | ConvertFrom-Json
if ($selfTest.selfTest -ne "PASS" -or
    [int]$selfTest.schemaVersion -ne 1 -or
    [string]$selfTest.reportType -ne "amd-mobile-power-native-compatibility" -or
    $selfTest.readOnlyByDefault -ne $true) {
    throw "Staged headless probe self-test returned an unexpected document."
}

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
$packagedReadme = Get-Content `
    -LiteralPath (Join-Path $stage "README.txt") `
    -Raw `
    -Encoding UTF8
foreach ($requiredReadmeText in @(
    "10 / 25 / 45 W",
    "--enable-write-controls",
    "%LOCALAPPDATA%\AmdMobilePower"
)) {
    if (-not $packagedReadme.Contains($requiredReadmeText)) {
        throw "Packaged README.txt is missing required text: $requiredReadmeText"
    }
}
Copy-Item -LiteralPath (Join-Path $root "collect-native-diagnostics.ps1") `
    -Destination (Join-Path $stage "collect-native-diagnostics.ps1") -Force
Copy-Item -LiteralPath (Join-Path $root "install-preview.ps1") `
    -Destination (Join-Path $stage "install-preview.ps1") -Force
Copy-Item -LiteralPath (Join-Path $root "install-driver-bootstrap.ps1") `
    -Destination (Join-Path $stage "install-driver-bootstrap.ps1") -Force
Copy-Item -LiteralPath (Join-Path $root "uninstall-driver-bootstrap.ps1") `
    -Destination (Join-Path $stage "uninstall-driver-bootstrap.ps1") -Force
Copy-Item -LiteralPath (Join-Path $root "uninstall-preview.ps1") `
    -Destination (Join-Path $stage "uninstall-preview.ps1") -Force

foreach ($payloadScript in @(
    "install-preview.ps1",
    "install-driver-bootstrap.ps1",
    "uninstall-driver-bootstrap.ps1",
    "uninstall-preview.ps1"
)) {
    if (-not (Test-Path -LiteralPath (Join-Path $stage $payloadScript) -PathType Leaf)) {
        throw "Native package payload is missing ${payloadScript}: $stage"
    }
}

$commit = (& git -C $repositoryRoot rev-parse HEAD).Trim()
$statusText = (& git `
    -C $repositoryRoot `
    status `
    --porcelain `
    --ignore-submodules=dirty |
    Where-Object { $_ -notmatch "^.. docs/evidence/" } |
    Out-String).Trim()
$workingTree = if ($statusText) { "Dirty" } else { "Clean" }
# The build timestamp is normalized to the source commit's committer date so
# BUILD-INFO.txt (and therefore the ZIP) is byte-identical for the same commit.
$commitDate = (& git -C $repositoryRoot log -1 --format=%cI).Trim()
@(
    "Name=$stageName"
    "Version=$Version"
    "Commit=$commit"
    "WorkingTree=$workingTree"
    "Platform=win-x64"
    "Native=True"
    "BuiltAt=$commitDate"
    "BuildTimestampSource=git-commit"
) | Set-Content -LiteralPath (Join-Path $stage "BUILD-INFO.txt") -Encoding utf8

$checksumLines = Get-ChildItem -LiteralPath $stage -File -Recurse |
    Sort-Object FullName |
    ForEach-Object {
        $relative = [System.IO.Path]::GetRelativePath($stage, $_.FullName).Replace("\", "/")
        $hash = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
        "$hash  $relative"
    }
$checksumLines | Set-Content -LiteralPath (Join-Path $stage "SHA256SUMS.txt") -Encoding ascii
$checksumCount = Assert-StagedChecksums -Path $stage

if (Test-Path -LiteralPath $zipPath) {
    Remove-Item -LiteralPath $zipPath -Force
}
New-DeterministicZip `
    -Stage $stage `
    -Destination $zipPath `
    -RootPrefix $stageName
$zipHash = (Get-FileHash -LiteralPath $zipPath -Algorithm SHA256).Hash.ToLowerInvariant()
"$zipHash  $stageName.zip" | Set-Content -LiteralPath "$zipPath.sha256" -Encoding ascii

if (-not $NoVerify) {
    $savedGuiSessions = @()
    try {
    if (-not $SkipRuntimeVerification) {
        Add-Type @"
using System;
using System.Runtime.InteropServices;
public static class PackageGuiSession {
    public delegate bool EnumProc(IntPtr hwnd, IntPtr parameter);
    [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc callback, IntPtr parameter);
    [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr hwnd, out uint pid);
    [DllImport("user32.dll")] public static extern bool PostMessageW(IntPtr hwnd, uint message, UIntPtr value, IntPtr parameter);
}
"@
        $savedGuiSessions = @(
            Get-CimInstance Win32_Process -Filter "Name = 'amd-mobile-power-gui.exe'" |
                ForEach-Object {
                    $arguments = $null
                    if ([string]$_.CommandLine -match '^\s*"[^"]+"\s*(.*)$') {
                        $arguments = $Matches[1]
                    }
                    elseif ([string]$_.CommandLine -match '^\s*\S+\s*(.*)$') {
                        $arguments = $Matches[1]
                    }
                    if ($_.ExecutablePath -and $null -ne $arguments) {
                        [pscustomobject]@{
                            Id = [int]$_.ProcessId
                            Path = $_.ExecutablePath
                            Arguments = $arguments.Trim()
                        }
                    }
                    else {
                        throw "Cannot preserve the active GUI launch context; stop verification before interrupting it."
                    }
                }
        )
        foreach ($session in $savedGuiSessions) {
            $sessionId = $session.Id
            $callback = [PackageGuiSession+EnumProc] {
                param($window, $parameter)
                $owner = 0
                [PackageGuiSession]::GetWindowThreadProcessId($window, [ref]$owner) | Out-Null
                if ($owner -eq $sessionId) {
                    [PackageGuiSession]::PostMessageW($window, 0x0111, [UIntPtr]2, [IntPtr]::Zero) | Out-Null
                }
                return $true
            }
            [PackageGuiSession]::EnumWindows($callback, [IntPtr]::Zero) | Out-Null
            $process = Get-Process -Id $session.Id -ErrorAction SilentlyContinue
            if ($process) {
                try {
                    if (-not $process.WaitForExit(15000)) {
                        throw "Active GUI did not exit gracefully; package verification stopped."
                    }
                }
                finally { $process.Dispose() }
            }
            # Older GUI verifiers can leave the original stable worker alive.
            # Restrict cleanup to the exact sibling executable of a saved GUI.
            $workerPath = Join-Path (Split-Path -Parent $session.Path) "amdmobilepower_native_worker.exe"
            foreach ($worker in @(Get-CimInstance Win32_Process -Filter "Name = 'amdmobilepower_native_worker.exe'")) {
                if ($worker.ExecutablePath -and $worker.ExecutablePath -eq $workerPath) {
                    $process = Get-Process -Id $worker.ProcessId -ErrorAction SilentlyContinue
                    if ($process) {
                        try {
                            Stop-Process -InputObject $process -Force
                            if (-not $process.WaitForExit(10000)) {
                                throw "Stable worker did not release hardware ownership."
                            }
                        }
                        finally { $process.Dispose() }
                    }
                }
            }
        }
    }
    Reset-ArtifactDirectory $verifyRoot
    Expand-Archive -LiteralPath $zipPath -DestinationPath $verifyRoot -Force
    $verifyGui = Join-Path $verifyRoot "$stageName\amd-mobile-power-gui.exe"
    if ($SkipRuntimeVerification) {
        try {
            & (Join-Path $root "verify-rust-gui.ps1") `
                -NoBuild `
                -VerifyWriteControls `
                -GuiExecutable $verifyGui
        }
        catch {
            throw "Extracted native GUI verification failed: $($_.Exception.Message)"
        }
    }
    else {
        try {
            $runtimeVerifyArguments = @{
                NoBuild = $true
                VerifyWorker = $true
                VerifyWriteControls = $true
                GuiExecutable = $verifyGui
            }
            if (-not $ReadOnlyRuntimeVerification) {
                $runtimeVerifyArguments.ExecutePolicySave = $true
            }
            & (Join-Path $root "verify-rust-gui.ps1") @runtimeVerifyArguments
        }
        catch {
            throw "Extracted native package verification failed: $($_.Exception.Message)"
        }

        $collector = Join-Path `
            $verifyRoot `
            "$stageName\collect-native-diagnostics.ps1"
        $reportPath = Join-Path $verifyRoot "native-compatibility-report.json"
        $reportMarkdownPath = Join-Path $verifyRoot "native-compatibility-report.md"
        $collectorOutput = & powershell.exe `
            -NoProfile `
            -ExecutionPolicy Bypass `
            -File $collector `
            -OutputPath $reportPath `
            -MarkdownPath $reportMarkdownPath 2>&1
        $collectorExitCode = $LASTEXITCODE
        if ($collectorExitCode -ne 0) {
            throw "Extracted native compatibility collector failed: $collectorOutput"
        }
        $reportText = Get-Content -LiteralPath $reportPath -Raw
        $report = $reportText | ConvertFrom-Json
        if ($report.collectionStatus -ne "PASS" -or
            $report.worker.hardwareInitialized -ne $true -or
            $report.worker.writeControlsEnabled -ne $false -or
            $report.platform.isSupported -ne $true -or
            $null -eq $report.platform.profile) {
            throw "Native compatibility report did not pass its schema/hardware checks."
        }
        if ($reportText -match [regex]::Escape($repositoryRoot) -or
            $reportText -match [regex]::Escape("\\.\pipe\")) {
            throw "Native compatibility report contains a local path or pipe name."
        }
        $reportMarkdown = Get-Content -LiteralPath $reportMarkdownPath -Raw
        if ($reportMarkdown -notmatch "AMD Mobile Power Compatibility Report" -or
            $reportMarkdown -match [regex]::Escape($repositoryRoot) -or
            $reportMarkdown -match [regex]::Escape("\\.\pipe\")) {
            throw "Native compatibility Markdown report failed its sanitization checks."
        }

        # Headless compatibility probe: no PowerShell, no GUI, read-only worker.
        $probePath = Join-Path `
            $verifyRoot `
            "$stageName\amd-mobile-power-probe.exe"
        $probeReportPath = Join-Path $verifyRoot "native-probe-report.json"
        $probeMarkdownPath = Join-Path $verifyRoot "native-probe-report.md"
        $probeOutput = & $probePath `
            --diagnose `
            --out $probeReportPath `
            --markdown $probeMarkdownPath 2>&1
        $probeExitCode = $LASTEXITCODE
        if ($probeExitCode -ne 0) {
            throw "Headless compatibility probe failed: $probeOutput"
        }
        $probeText = Get-Content -LiteralPath $probeReportPath -Raw
        $probeReport = $probeText | ConvertFrom-Json
        if ([int]$probeReport.schemaVersion -ne 1 -or
            [string]$probeReport.reportType -ne "amd-mobile-power-native-compatibility" -or
            [string]$probeReport.collectionStatus -ne "PASS" -or
            $probeReport.worker.hardwareInitialized -ne $true -or
            $probeReport.worker.writeControlsEnabled -ne $false -or
            $probeReport.platform.isSupported -ne $true -or
            $null -eq $probeReport.platform.profile) {
            throw "Headless compatibility probe report did not pass its schema/hardware checks."
        }
        foreach ($privacyFlag in @(
            "localPathsIncluded",
            "pipeNameIncluded",
            "processIdIncluded",
            "accountNamesIncluded",
            "serialNumbersIncluded",
            "recentLogsIncluded",
            "networkUploadPerformed"
        )) {
            if ([bool]$probeReport.privacy.$privacyFlag) {
                throw "Headless compatibility probe leaked privacy flag: $privacyFlag"
            }
        }
        if ($probeText -match [regex]::Escape($repositoryRoot) -or
            $probeText -match [regex]::Escape("\\.\pipe\")) {
            throw "Headless compatibility probe report contains a local path or pipe name."
        }
    }

    $installer = Join-Path `
        $verifyRoot `
        "$stageName\install-preview.ps1"
    $uninstaller = Join-Path `
        $verifyRoot `
        "$stageName\uninstall-preview.ps1"
    $isolatedInstall = Join-Path $verifyRoot "isolated-install"
    $shellBefore = Get-ShellIntegrationSnapshot | ConvertTo-Json -Compress
    $installOutput = & powershell.exe `
        -NoProfile `
        -ExecutionPolicy Bypass `
        -File $installer `
        -InstallDirectory $isolatedInstall `
        -NoStartup `
        -NoShellIntegration `
        -NoLaunch 2>&1
    $installExitCode = $LASTEXITCODE
    if ($installExitCode -ne 0 -or
        -not (Test-Path -LiteralPath (Join-Path $isolatedInstall "amd-mobile-power-gui.exe"))) {
        throw "Native preview isolated install failed: $installOutput"
    }
    $overwriteOutput = & powershell.exe `
        -NoProfile `
        -ExecutionPolicy Bypass `
        -File $installer `
        -InstallDirectory $isolatedInstall `
        -NoStartup `
        -NoShellIntegration `
        -NoLaunch 2>&1
    $overwriteExitCode = $LASTEXITCODE
    $installedBuildInfo = Join-Path $isolatedInstall "BUILD-INFO.txt"
    $installedVersion = $null
    if (Test-Path -LiteralPath $installedBuildInfo) {
        foreach ($line in Get-Content -LiteralPath $installedBuildInfo) {
            if ($line -match "^Version=(.+)$") {
                $installedVersion = $Matches[1].Trim()
                break
            }
        }
    }
    if ($overwriteExitCode -ne 0 -or $installedVersion -ne $Version) {
        throw "Native preview isolated overwrite install failed: $overwriteOutput"
    }
    $uninstallOutput = & powershell.exe `
        -NoProfile `
        -ExecutionPolicy Bypass `
        -File $uninstaller `
        -InstallDirectory $isolatedInstall `
        -NoStartup `
        -NoShellIntegration 2>&1
    $uninstallExitCode = $LASTEXITCODE
    if ($uninstallExitCode -ne 0 -or (Test-Path -LiteralPath $isolatedInstall)) {
        throw "Native preview isolated uninstall failed: $uninstallOutput"
    }
    $shellAfter = Get-ShellIntegrationSnapshot | ConvertTo-Json -Compress
    if ($shellBefore -ne $shellAfter) {
        throw "Isolated native preview install/uninstall touched real shell or registry integration."
    }
    }
    finally {
        foreach ($session in $savedGuiSessions) {
            if (-not (Get-Process -Id $session.Id -ErrorAction SilentlyContinue)) {
                Start-Process -FilePath $session.Path -ArgumentList $session.Arguments `
                    -WorkingDirectory (Split-Path -Parent $session.Path) -WindowStyle Hidden
            }
        }
    }
}

$result = [pscustomobject]@{
    Package = $zipPath
    SHA256 = $zipHash
    Size = (Get-Item -LiteralPath $zipPath).Length
    WorkingTree = $workingTree
    Verification = if ($NoVerify) { "Skipped" } else { "PASS" }
    ChecksumEntries = $checksumCount
    RuntimeVerification = if ($SkipRuntimeVerification) {
        "Skipped"
    }
    elseif ($NoVerify) {
        "Skipped"
    }
    else {
        "PASS"
    }
    CompatibilityCollector = if ($SkipRuntimeVerification -or $NoVerify) {
        "Skipped"
    }
    else {
        "PASS"
    }
    CompatibilityMarkdown = if ($SkipRuntimeVerification -or $NoVerify) {
        "Skipped"
    }
    else {
        "PASS"
    }
    HeadlessProbe = if ($SkipRuntimeVerification -or $NoVerify) {
        "Skipped"
    }
    else {
        "PASS"
    }
    PolicyWriteVerification = if ($SkipRuntimeVerification -or $NoVerify) {
        "Skipped"
    }
    elseif ($ReadOnlyRuntimeVerification) {
        "Skipped"
    }
    else {
        "PASS"
    }
    InstallFlow = if ($NoVerify) { "Skipped" } else { "PASS" }
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
        ChecksumEntries = $result.ChecksumEntries
        RuntimeVerification = $result.RuntimeVerification
        CompatibilityCollector = $result.CompatibilityCollector
        CompatibilityMarkdown = $result.CompatibilityMarkdown
        HeadlessProbe = $result.HeadlessProbe
        PolicyWriteVerification = $result.PolicyWriteVerification
        InstallFlow = $result.InstallFlow
        RecordedAt = (Get-Date).ToString("o")
    } |
        ConvertTo-Json -Depth 6 |
        Set-Content -LiteralPath $EvidencePath -Encoding UTF8
}

$result | Format-List
