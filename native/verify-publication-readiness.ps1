param(
    [string]$Version = "1.0.0-native",
    [string]$EvidencePath
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
    return Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
}

function Test-ShortcutArgumentsAgainstContract {
    param(
        [AllowEmptyString()]
        [string]$Arguments,
        [Parameter(Mandatory = $true)]
        $Contract
    )

    $unsupported = New-Object System.Collections.Generic.List[string]
    if (-not [string]::IsNullOrWhiteSpace($Arguments)) {
        $tokens = @(
            $Arguments -split "\s+" |
                Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
        $index = 0
        while ($index -lt $tokens.Count) {
            $token = $tokens[$index]
            $entry = $Contract.arguments.PSObject.Properties[$token]
            if ($null -eq $entry) {
                $unsupported.Add($token)
                $index += 1
                continue
            }
            if ([bool]$entry.Value.takesValue) {
                if ($index + 1 -ge $tokens.Count) {
                    $unsupported.Add("$token (missing value)")
                    break
                }
                $index += 2
                continue
            }
            $index += 1
        }
    }
    return [pscustomobject]@{
        Supported = ($unsupported.Count -eq 0)
        Unsupported = @($unsupported)
    }
}

# Launches the deployed GUI with the exact shortcut arguments under an
# isolated LOCALAPPDATA and a unique worker pipe. This is the check that
# catches argument-parser drift before a release gate claims readiness.
function Test-ShortcutGuiLaunch {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Executable,
        [AllowEmptyString()]
        [string]$Arguments
    )

    $isolatedLocalAppData = [System.IO.Path]::GetFullPath(
        (Join-Path $artifactsRoot "publication-launch-$([Guid]::NewGuid().ToString('N'))"))
    if (-not $isolatedLocalAppData.StartsWith(
        $artifactsRoot + [System.IO.Path]::DirectorySeparatorChar,
        [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Unsafe launch-check directory: $isolatedLocalAppData"
    }
    $pipeName = "AmdMobilePower.Worker.readiness.$([Guid]::NewGuid().ToString('N').Substring(0, 8))"
    $stderrPath = Join-Path $isolatedLocalAppData "gui-stderr.txt"
    $argumentList = @()
    if (-not [string]::IsNullOrWhiteSpace($Arguments)) {
        $argumentList += @(
            $Arguments -split "\s+" |
                Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    }
    $argumentList += @("--pipe-name", $pipeName)
    $previousLocalAppData = $env:LOCALAPPDATA
    $process = $null
    try {
        New-Item -ItemType Directory -Path $isolatedLocalAppData -Force | Out-Null
        $env:LOCALAPPDATA = $isolatedLocalAppData
        $process = Start-Process `
            -FilePath $Executable `
            -WorkingDirectory (Split-Path -Parent $Executable) `
            -ArgumentList $argumentList `
            -RedirectStandardError $stderrPath `
            -PassThru
        $windowReady = $false
        $exitedEarly = $false
        $exitCode = $null
        $deadline = [DateTime]::UtcNow.AddSeconds(12)
        while ([DateTime]::UtcNow -lt $deadline) {
            $process.Refresh()
            if ($process.HasExited) {
                $exitedEarly = $true
                $exitCode = $process.ExitCode
                break
            }
            if ($process.MainWindowHandle -ne [IntPtr]::Zero -and
                $process.MainWindowTitle -like "AMD Mobile Power*") {
                $windowReady = $true
                break
            }
            Start-Sleep -Milliseconds 250
        }
        $stderrText = ""
        if (Test-Path -LiteralPath $stderrPath -PathType Leaf) {
            # In PowerShell 7, [string]$null stays $null, so an empty stderr file
            # would otherwise throw on .Trim().
            $rawStderr = Get-Content -LiteralPath $stderrPath -Raw
            if ($null -ne $rawStderr) {
                $stderrText = ([string]$rawStderr).Trim()
            }
        }
        return [pscustomobject]@{
            Arguments = ($argumentList -join " ")
            WindowReady = $windowReady
            ExitedEarly = $exitedEarly
            ExitCode = $exitCode
            StandardError = $stderrText
            Note = if ($windowReady) {
                "GUI window observed."
            }
            elseif ($exitedEarly) {
                "GUI exited immediately; exit code 0 means the arguments parsed and another instance owns the single-instance mutex."
            }
            else {
                "GUI stayed alive but no window appeared within the timeout."
            }
        }
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
            Remove-Item `
                -LiteralPath $isolatedLocalAppData `
                -Recurse `
                -Force `
                -ErrorAction SilentlyContinue
        }
    }
}

function Read-JsonFile {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "Required JSON file is missing: $Path"
    }
    return Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
}

function Get-Sha256 {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).
        Hash.ToLowerInvariant()
}

function Get-BuildInfo {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    $values = @{}
    foreach ($line in Get-Content -LiteralPath $Path) {
        if ($line -match "^([^=]+)=(.*)$") {
            $values[$Matches[1]] = $Matches[2]
        }
    }
    return $values
}

if (-not $EvidencePath) {
    $EvidencePath = Join-Path `
        $repositoryRoot `
        "docs\evidence\release\native-publication-readiness-$(Get-Date -Format 'yyyy-MM-dd').json"
}

$packageName = "amd-mobile-power-v$Version-win-x64-native-preview.zip"
$packagePath = Join-Path `
    (Join-Path $artifactsRoot "native-packages") `
    $packageName
$releaseGatePath = Join-Path `
    $repositoryRoot `
    "docs\evidence\packaging\v$Version-release-gate-$(Get-Date -Format 'yyyy-MM-dd').json"
$cleanEvidencePath = Join-Path `
    $repositoryRoot `
    "docs\evidence\packaging\v$Version-clean-$(Get-Date -Format 'yyyy-MM-dd').json"
$deploymentEvidencePath = Join-Path `
    $repositoryRoot `
    "docs\evidence\packaging\v$Version-deployment-$(Get-Date -Format 'yyyy-MM-dd').json"
$policyEvidencePath = Join-Path `
    $repositoryRoot `
    "docs\evidence\hardware\v$Version-power-policy-no-change-$(Get-Date -Format 'yyyy-MM-dd').json"
$packagedUiEvidencePath = Join-Path `
    $repositoryRoot `
    "docs\evidence\ui\native-packaged-$Version-ui-$(Get-Date -Format 'yyyy-MM-dd').json"
$mediaEvidencePath = Join-Path `
    $repositoryRoot `
    "docs\evidence\media\native-promo-draft-$(Get-Date -Format 'yyyy-MM-dd').json"
$compatibilityIndexPath = Join-Path `
    $repositoryRoot `
    "docs\evidence\compatibility\index.json"
$reviewBundle = Join-Path `
    $artifactsRoot `
    "native-release-review\v$Version"

if (-not (Test-Path -LiteralPath $packagePath -PathType Leaf)) {
    throw "Native package is missing: $packagePath"
}
$packageHash = Get-Sha256 $packagePath
$releaseGate = Read-JsonFile $releaseGatePath
$cleanEvidence = Read-JsonFile $cleanEvidencePath
$deployment = Read-JsonFile $deploymentEvidencePath
$policyEvidence = Read-JsonFile $policyEvidencePath
$packagedUi = Read-JsonFile $packagedUiEvidencePath
$media = Read-JsonFile $mediaEvidencePath
$compatibilityIndex = Read-JsonFile $compatibilityIndexPath

$checks = [ordered]@{}
$blockers = New-Object System.Collections.Generic.List[string]

$checks.PackageHash = (
    $releaseGate.SHA256 -eq $packageHash -and
    $cleanEvidence.SHA256 -eq $packageHash -and
    $releaseGate.Version -eq $Version
)
if (-not $checks.PackageHash) {
    $blockers.Add("Package hash or version does not match the clean/release evidence.")
}

$checks.PackageVerification = (
    $cleanEvidence.Verification -eq "PASS" -and
    $cleanEvidence.ChecksumEntries -ge 16 -and
    $cleanEvidence.RuntimeVerification -eq "PASS"
)
if (-not $checks.PackageVerification) {
    $blockers.Add("Clean package verification is incomplete.")
}

$checks.NoChangePolicy = (
    $releaseGate.NoChangePolicy -eq "PASS" -and
    $policyEvidence.Verification -eq "PASS" -and
    $policyEvidence.PolicyDisabled -eq "PASS" -and
    $policyEvidence.Shutdown -eq "PASS"
)
if (-not $checks.NoChangePolicy) {
    $blockers.Add("Controlled current-value policy evidence is incomplete.")
}

$checks.PackagedUi = (
    $packagedUi.Verification -eq "PASS" -and
    $packagedUi.TaskbarIconAvailable -eq $true -and
    $packagedUi.TrayIconId -eq 1 -and
    $packagedUi.CloseToTray -eq "PASS" -and
    $packagedUi.TrayRestore -eq "PASS" -and
    $packagedUi.SingleInstanceWake -eq "PASS" -and
    $packagedUi.InitialUiMode -eq "simple" -and
    $packagedUi.FinalUiMode -eq "advanced"
)
if (-not $checks.PackagedUi) {
    $blockers.Add("Packaged GUI/tray/mode evidence is incomplete.")
}

$deployedBuildInfo = Get-BuildInfo (Join-Path "C:\RyzenAdj" "BUILD-INFO.txt")
$deployedGuiPath = Join-Path "C:\RyzenAdj" "amd-mobile-power-gui.exe"
$deployedWorkerPath = Join-Path "C:\RyzenAdj" "amdmobilepower_native_worker.exe"
$checks.LocalDeployment = (
    (Test-Path -LiteralPath $deployedGuiPath -PathType Leaf) -and
    (Test-Path -LiteralPath $deployedWorkerPath -PathType Leaf) -and
    $deployedBuildInfo["Version"] -eq $Version -and
    (Get-Sha256 $deployedGuiPath) -eq $deployment.DeployedGuiSHA256 -and
    (Get-Sha256 $deployedWorkerPath) -eq $deployment.DeployedWorkerSHA256 -and
    $deployment.UiVerification -eq "PASS"
)
if (-not $checks.LocalDeployment) {
    $blockers.Add("C:\RyzenAdj does not match the recorded deployment evidence.")
}

$checks.DeployedIcon = $false
if (Test-Path -LiteralPath $deployedGuiPath -PathType Leaf) {
    try {
        $null = & (Join-Path $root "check-exe-icon.ps1") -Path $deployedGuiPath
        $checks.DeployedIcon = $true
    }
    catch {
        $blockers.Add(
            "Deployed GUI has no embedded application icon: $($_.Exception.Message)")
    }
}
else {
    $blockers.Add("Deployed GUI is missing, so its icon resource cannot be verified.")
}

$shortcutPath = "<USER_HOME>\Desktop\功耗设置 5-60W.lnk"
$deployedGui = Join-Path "C:\RyzenAdj" "amd-mobile-power-gui.exe"
$shortcutArguments = ""
$checks.DesktopShortcut = $false
if (Test-Path -LiteralPath $shortcutPath -PathType Leaf) {
    $shell = New-Object -ComObject WScript.Shell
    $shortcut = $shell.CreateShortcut($shortcutPath)
    $shortcutArguments = [string]$shortcut.Arguments
    $checks.DesktopShortcut = (
        $shortcut.TargetPath -eq $deployedGui -and
        $shortcut.WorkingDirectory -eq "C:\RyzenAdj"
    )
}
if (-not $checks.DesktopShortcut) {
    $blockers.Add("Desktop shortcut target or arguments do not match the deployment.")
}

$argumentAudit = $null
$checks.ShortcutArguments = $false
if (Test-Path -LiteralPath $guiArgumentContractPath -PathType Leaf) {
    $guiContract = Get-GuiArgumentContract -Path $guiArgumentContractPath
    $argumentAudit = Test-ShortcutArgumentsAgainstContract `
        -Arguments $shortcutArguments `
        -Contract $guiContract
    $checks.ShortcutArguments = $argumentAudit.Supported
}
if (-not $checks.ShortcutArguments) {
    $rejected = @($argumentAudit.Unsupported) -join ", "
    $blockers.Add("Desktop shortcut passes arguments the native GUI rejects: $rejected")
}

$launchAudit = $null
$checks.ShortcutLaunch = $false
if ($checks.DesktopShortcut) {
    $launchAudit = Test-ShortcutGuiLaunch `
        -Executable $deployedGui `
        -Arguments $shortcutArguments
    $checks.ShortcutLaunch = (
        $launchAudit.WindowReady -or
        ($launchAudit.ExitedEarly -and
            $launchAudit.ExitCode -eq 0 -and
            [string]::IsNullOrWhiteSpace($launchAudit.StandardError))
    )
}
if (-not $checks.ShortcutLaunch) {
    $blockers.Add(
        "Desktop shortcut does not launch the native GUI: $($launchAudit.StandardError)")
}

$checks.CompatibilityIndex = (
    $null -ne $compatibilityIndex -and
    @($compatibilityIndex).Count -ge 1
)
if (-not $checks.CompatibilityIndex) {
    $blockers.Add("No sanitized compatibility report is indexed.")
}

$videoPath = Join-Path `
    $repositoryRoot `
    "artifacts\media\amd-mobile-power-native-promo-draft-2026-11-11\amd-mobile-power-native-intro-draft-2026-11-11.mp4"
$checks.MediaDraft = (
    (Test-Path -LiteralPath $videoPath -PathType Leaf) -and
    (Get-Sha256 $videoPath) -eq $media.video.sha256 -and
    $media.status -eq "DRAFT_FOR_HUMAN_REVIEW" -and
    $media.verification.ffmpegFullDecode -eq "PASS"
)
if (-not $checks.MediaDraft) {
    $blockers.Add("Native promotional-video draft or media evidence is incomplete.")
}

$checks.ReviewBundle = $false
$bundleChecksums = Join-Path $reviewBundle "SHA256SUMS.txt"
if (Test-Path -LiteralPath $bundleChecksums -PathType Leaf) {
    $checks.ReviewBundle = $true
    foreach ($line in Get-Content -LiteralPath $bundleChecksums) {
        if ($line -notmatch "^([a-f0-9]{64})  (.+)$") {
            $checks.ReviewBundle = $false
            break
        }
        $bundleFile = Join-Path $reviewBundle $Matches[2]
        if (-not (Test-Path -LiteralPath $bundleFile -PathType Leaf) -or
            (Get-Sha256 $bundleFile) -ne $Matches[1]) {
            $checks.ReviewBundle = $false
            break
        }
    }
}
if (-not $checks.ReviewBundle) {
    $blockers.Add("Native review bundle checksums are incomplete or invalid.")
}

$openGates = [ordered]@{
    SecondAmdDevice = "PENDING"
    Dpi100And150 = "PENDING"
    HostedWindowsCi = "PENDING"
    CleanWindowsWinRing0Baseline = "PENDING"
    HumanVideoAndClaimReview = "PENDING"
    ExplicitPublicReleaseApproval = "PENDING"
    BilibiliAuthenticatedUpload = "PENDING"
}

$localChecksPass = -not ($checks.Values -contains $false)
$result = [ordered]@{
    SchemaVersion = 1
    Version = $Version
    Package = $packageName
    PackageSHA256 = $packageHash
    LocalDeployment = "C:\RyzenAdj"
    Checks = $checks
    LocalReadiness = if ($localChecksPass) { "PASS" } else { "FAIL" }
    PublicReleaseReadiness = if ($localChecksPass) {
        "READY_FOR_HUMAN_REVIEW"
    }
    else {
        "BLOCKED_BY_LOCAL_CHECKS"
    }
    DesktopShortcut = [ordered]@{
        Path = $shortcutPath
        Arguments = $shortcutArguments
        RejectedArguments = @($argumentAudit.Unsupported)
        Launch = $launchAudit
    }
    OpenGates = $openGates
    BlockersFromLocalChecks = @($blockers)
    Note = "No GitHub login, Bilibili login, upload, publication, or power write was performed by this check. The shortcut launch audit runs the deployed GUI with an isolated LOCALAPPDATA and a unique worker pipe, then stops it."
    RecordedAt = (Get-Date).ToString("o")
}

$evidenceDirectory = Split-Path -Parent $EvidencePath
if ($evidenceDirectory) {
    New-Item -ItemType Directory -Path $evidenceDirectory -Force | Out-Null
}
$result | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $EvidencePath -Encoding UTF8
$result | Format-List

if (-not $localChecksPass) {
    exit 1
}
