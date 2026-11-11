param(
    [string]$Version = "development",
    [string]$GuiExecutable,
    [string]$WorkerExecutable,
    [string]$ProbeExecutable,
    [string]$EvidencePath,
    [int]$TimeoutSeconds = 75,
    [int]$ExclusiveWaitSeconds = 15
)

$ErrorActionPreference = "Stop"

$root = Split-Path -Parent $PSCommandPath
$repositoryRoot = Split-Path -Parent $root
$runtime = Join-Path $repositoryRoot "artifacts\native-build\gui-runtime"
if (-not $GuiExecutable) {
    $GuiExecutable = Join-Path $runtime "amd-mobile-power-gui.exe"
}
if (-not $WorkerExecutable) {
    $WorkerExecutable = Join-Path $runtime "amdmobilepower_native_worker.exe"
}
if (-not $ProbeExecutable) {
    $ProbeExecutable = Join-Path $runtime "amd-mobile-power-probe.exe"
}
if (-not $EvidencePath) {
    $EvidencePath = Join-Path `
        $repositoryRoot `
        "artifacts\verify\worker-hang-$(Get-Date -Format 'yyyyMMdd-HHmmss').json"
}

function Assert-File {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,
        [Parameter(Mandatory = $true)]
        [string]$Label
    )
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "$Label is missing: $Path"
    }
    return (Resolve-Path -LiteralPath $Path).Path
}

function Get-Sha256 {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

$gui = Assert-File -Path $GuiExecutable -Label "GUI executable"
$worker = Assert-File -Path $WorkerExecutable -Label "Worker executable"
$probe = Assert-File -Path $ProbeExecutable -Label "Probe executable"

if (-not ("Native.WorkerHang" -as [type])) {
    Add-Type -Namespace Native -Name WorkerHang -MemberDefinition @'
[DllImport("ntdll.dll", SetLastError=true)]
public static extern int NtSuspendProcess(IntPtr hProcess);
[DllImport("kernel32.dll", SetLastError=true)]
public static extern IntPtr OpenProcess(uint access, bool inherit, int pid);
[DllImport("kernel32.dll", SetLastError=true)]
public static extern bool CloseHandle(IntPtr handle);
'@
}

$token = [Guid]::NewGuid().ToString("N").Substring(0, 8)
$pipeName = "AmdMobilePower.Worker.hangtest.$token"
$pipePath = "\\.\pipe\$pipeName"
$isolatedLocalAppData = Join-Path `
    $repositoryRoot `
    "artifacts\verify\worker-hang-state-$token"
New-Item -ItemType Directory -Path $isolatedLocalAppData -Force | Out-Null

$result = [ordered]@{
    SchemaVersion = 1
    Version = $Version
    Verification = "FAIL"
    Method = "NtSuspendProcess holds the isolated worker until the GUI heartbeat watchdog replaces it."
    SourceCommit = (& git -C $repositoryRoot rev-parse HEAD).Trim()
    WorkingTree = if ((& git -C $repositoryRoot status --porcelain | Out-String).Trim()) {
        "Dirty"
    }
    else {
        "Clean"
    }
    GuiSHA256 = Get-Sha256 -Path $gui
    WorkerSHA256 = Get-Sha256 -Path $worker
    ProbeSHA256 = Get-Sha256 -Path $probe
    PipeName = $pipePath
    IsolatedStateDirectory = $isolatedLocalAppData
    WatchdogThresholdSeconds = 30
    TimeoutSeconds = $TimeoutSeconds
    OldWorkerPid = $null
    NewWorkerPid = $null
    ReplacementElapsedSeconds = $null
    GuiRespondingChecks = 0
    GuiRespondingFailures = 0
    PolicyAfterReplacement = $null
    TelemetryAfterReplacement = $null
    Failure = $null
    RecordedAt = $null
}

$testGui = $null
$failure = $null
$previousLocalAppData = $env:LOCALAPPDATA

function Get-HangTestWorker {
    Get-CimInstance Win32_Process `
        -Filter "Name='amdmobilepower_native_worker.exe'" `
        -ErrorAction SilentlyContinue |
        Where-Object { $_.CommandLine -like "*$token*" }
}

function Invoke-ProbeJson {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Command
    )
    try {
        $raw = & $probe --pipe-name $pipePath --command $Command 2>&1
        if ($LASTEXITCODE -ne 0) {
            return $null
        }
        return (($raw -join "`n") | ConvertFrom-Json)
    }
    catch {
        return $null
    }
}

try {
    # The hardware owner mutex is exclusive. Never start a second worker and
    # never kill an owner this script did not create.
    $deadline = [DateTime]::UtcNow.AddSeconds($ExclusiveWaitSeconds)
    while ([DateTime]::UtcNow -lt $deadline) {
        $owners = @(
            Get-CimInstance Win32_Process `
                -Filter "Name='amdmobilepower_native_worker.exe'" `
                -ErrorAction SilentlyContinue |
                Where-Object { $_.CommandLine -match "--enable-hardware" }
        )
        if ($owners.Count -eq 0) {
            break
        }
        Start-Sleep -Milliseconds 500
    }
    if ($owners.Count -gt 0) {
        throw ("A hardware worker is already running (PID " +
            (($owners | ForEach-Object { $_.ProcessId }) -join ", ") +
            "). Exit the tray app before running this check.")
    }

    $arguments = @(
        "--enable-write-controls",
        "--simple-mode",
        "--pipe-name `"$pipePath`"",
        "--worker-executable `"$worker`"",
        "--max-target-watts 10",
        "--uniform-target-watts 10"
    ) -join " "
    $env:LOCALAPPDATA = $isolatedLocalAppData
    $testGui = Start-Process `
        -FilePath $gui `
        -ArgumentList $arguments `
        -WorkingDirectory (Split-Path -Parent $gui) `
        -PassThru

    $snapshot = $null
    $readyDeadline = [DateTime]::UtcNow.AddSeconds(30)
    while ([DateTime]::UtcNow -lt $readyDeadline) {
        $snapshot = Invoke-ProbeJson -Command "getSnapshot"
        if ($null -ne $snapshot -and $null -ne $snapshot.telemetry) {
            break
        }
        if ($testGui.HasExited) {
            throw "The isolated GUI exited before the worker became ready."
        }
        Start-Sleep -Milliseconds 500
    }
    if ($null -eq $snapshot -or $null -eq $snapshot.telemetry) {
        throw "The isolated worker did not answer getSnapshot within 30 s."
    }

    $oldWorker = Get-HangTestWorker | Select-Object -First 1
    if (-not $oldWorker) {
        throw "The isolated worker process was not found."
    }
    $result.OldWorkerPid = [int]$oldWorker.ProcessId

    $handle = [Native.WorkerHang]::OpenProcess(
        0x0800,
        $false,
        [int]$oldWorker.ProcessId)
    if ($handle -eq [IntPtr]::Zero) {
        throw "OpenProcess(PROCESS_SUSPEND_RESUME) failed."
    }
    try {
        $ntStatus = [Native.WorkerHang]::NtSuspendProcess($handle)
    }
    finally {
        [void][Native.WorkerHang]::CloseHandle($handle)
    }
    if ($ntStatus -ne 0) {
        throw "NtSuspendProcess failed with NTSTATUS $ntStatus."
    }
    $suspendedAt = Get-Date

    $newWorker = $null
    $replacementDeadline = $suspendedAt.AddSeconds($TimeoutSeconds)
    while ([DateTime]::Now -lt $replacementDeadline) {
        Start-Sleep -Seconds 1
        $testGui.Refresh()
        if ($testGui.HasExited) {
            throw "The isolated GUI exited while the worker was being replaced."
        }
        $result.GuiRespondingChecks += 1
        if (-not $testGui.Responding) {
            $result.GuiRespondingFailures += 1
        }
        $newWorker = Get-HangTestWorker |
            Where-Object { $_.ProcessId -ne $oldWorker.ProcessId } |
            Select-Object -First 1
        if ($newWorker) {
            break
        }
    }
    if (-not $newWorker) {
        throw "The worker was not replaced within $TimeoutSeconds s."
    }
    $result.NewWorkerPid = [int]$newWorker.ProcessId
    $result.ReplacementElapsedSeconds =
        [math]::Round(((Get-Date) - $suspendedAt).TotalSeconds, 1)
    if ($result.GuiRespondingFailures -ne 0) {
        throw "The GUI stopped responding $($result.GuiRespondingFailures) time(s)."
    }

    $policy = $null
    $policyDeadline = [DateTime]::UtcNow.AddSeconds(20)
    while ([DateTime]::UtcNow -lt $policyDeadline) {
        $policy = Invoke-ProbeJson -Command "getPowerPolicy"
        if ($null -ne $policy -and
            $policy.lastAttemptSucceeded -eq $true -and
            $policy.settings.enabled -eq $true -and
            $policy.settings.batteryTarget.stapmWatts -eq 10 -and
            $policy.settings.acTarget.stapmWatts -eq 10) {
            break
        }
        $policy = $null
        Start-Sleep -Milliseconds 500
    }
    if ($null -eq $policy) {
        throw "The replacement worker did not restore the saved 10 W policy."
    }
    $result.PolicyAfterReplacement = [ordered]@{
        enabled = $policy.settings.enabled
        batteryEnabled = $policy.settings.batteryEnabled
        acEnabled = $policy.settings.acEnabled
        batteryTargetWatts = (
            "$($policy.settings.batteryTarget.stapmWatts)/" +
            "$($policy.settings.batteryTarget.fastWatts)/" +
            "$($policy.settings.batteryTarget.slowWatts)")
        acTargetWatts = (
            "$($policy.settings.acTarget.stapmWatts)/" +
            "$($policy.settings.acTarget.fastWatts)/" +
            "$($policy.settings.acTarget.slowWatts)")
        lastAttemptSucceeded = $policy.lastAttemptSucceeded
    }

    $snapshot = Invoke-ProbeJson -Command "getSnapshot"
    if ($null -eq $snapshot -or $null -eq $snapshot.telemetry) {
        throw "The replacement worker did not answer getSnapshot."
    }
    $result.TelemetryAfterReplacement = [ordered]@{
        powerLine = $snapshot.telemetry.powerLine
        stapmLimitWatts = $snapshot.telemetry.stapmLimitWatts
        fastLimitWatts = $snapshot.telemetry.fastLimitWatts
        slowLimitWatts = $snapshot.telemetry.slowLimitWatts
        stapmValueWatts = $snapshot.telemetry.stapmValueWatts
        fastValueWatts = $snapshot.telemetry.fastValueWatts
        slowValueWatts = $snapshot.telemetry.slowValueWatts
        tctlValueCelsius = $snapshot.telemetry.tctlValueCelsius
    }
    $result.Verification = "PASS"
}
catch {
    $failure = $_.Exception.Message
    $result.Failure = $failure
}
finally {
    if ($null -ne $testGui -and -not $testGui.HasExited) {
        Stop-Process -Id $testGui.Id -Force -ErrorAction SilentlyContinue
    }
    Get-HangTestWorker | ForEach-Object {
        Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue
    }
    $env:LOCALAPPDATA = $previousLocalAppData
    $result.RecordedAt = (Get-Date).ToString("o")
}

$evidenceDirectory = Split-Path -Parent $EvidencePath
if ($evidenceDirectory) {
    New-Item -ItemType Directory -Path $evidenceDirectory -Force | Out-Null
}
$result |
    ConvertTo-Json -Depth 10 |
    Set-Content -LiteralPath $EvidencePath -Encoding UTF8
$result | Format-List

if ($failure) {
    throw "Worker hang verification failed: $failure"
}
