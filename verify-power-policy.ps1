<#
.SYNOPSIS
Verifies the AC/battery power policy on one physical AMD laptop.

.DESCRIPTION
PlanOnly performs a read-only package and hardware preflight. A full run
requires -ConfirmHardwareWrite, starts on AC power, records both AC and battery
baseline limits, tests a conservative battery target, verifies the AC
transition, and restores both baselines.

The script starts an isolated worker pipe and never attaches to a GUI worker.
The full run is intentionally interactive and must not be used in unattended CI.
#>
param(
    [string]$PackageDirectory,
    [ValidateRange(5, 60)]
    [int]$BatteryWatts = 12,
    [ValidateRange(30, 600)]
    [int]$TransitionTimeoutSeconds = 180,
    [switch]$PlanOnly,
    [switch]$ConfirmHardwareWrite
)

$ErrorActionPreference = "Stop"

if ($PSVersionTable.PSVersion.Major -lt 7) {
    throw "PowerShell 7 or newer is required."
}

$root = Split-Path -Parent $PSCommandPath
if ([string]::IsNullOrWhiteSpace($PackageDirectory)) {
    $PackageDirectory = Join-Path $root "artifacts\packages\amd-mobile-power-v0.1.3-dev-win-x64-lite"
}
$PackageDirectory = [IO.Path]::GetFullPath($PackageDirectory)

$workerExecutable = Join-Path $PackageDirectory "worker\AmdMobilePower.Worker.exe"
$runtimeFiles = @(
    $workerExecutable,
    (Join-Path $PackageDirectory "worker\libryzenadj.dll"),
    (Join-Path $PackageDirectory "worker\WinRing0x64.dll"),
    (Join-Path $PackageDirectory "worker\WinRing0x64.sys"),
    (Join-Path $PackageDirectory "worker\inpoutx64.dll"),
    (Join-Path $PackageDirectory "worker\profiles")
)
foreach ($path in $runtimeFiles) {
    if (-not (Test-Path -LiteralPath $path)) {
        throw "Package runtime item is missing: $path"
    }
}

if (-not $PlanOnly -and -not $ConfirmHardwareWrite) {
    throw "A full hardware-policy test requires -ConfirmHardwareWrite. Use -PlanOnly for read-only preflight."
}

if (-not ("AmdMobilePowerPolicyProbe" -as [type])) {
    Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class AmdMobilePowerPolicyProbe {
    [StructLayout(LayoutKind.Sequential)]
    public struct SYSTEM_POWER_STATUS {
        public byte ACLineStatus;
        public byte BatteryFlag;
        public byte BatteryLifePercent;
        public byte SystemStatusFlag;
        public uint BatteryLifeTime;
        public uint BatteryFullLifeTime;
    }

    [DllImport("kernel32.dll", SetLastError = true)]
    public static extern bool GetSystemPowerStatus(out SYSTEM_POWER_STATUS status);
}
'@
}

function Get-PowerLine {
    $status = New-Object AmdMobilePowerPolicyProbe+SYSTEM_POWER_STATUS
    if (-not [AmdMobilePowerPolicyProbe]::GetSystemPowerStatus([ref]$status)) {
        return "unknown"
    }

    switch ($status.ACLineStatus) {
        0 { return "battery" }
        1 { return "ac" }
        default { return "unknown" }
    }
}

function Format-Target {
    param([object]$Target)

    return "$($Target.stapmWatts)/$($Target.fastWatts)/$($Target.slowWatts) W"
}

function New-Target {
    param([int]$Watts)

    return [ordered]@{
        stapmWatts = $Watts
        fastWatts = $Watts
        slowWatts = $Watts
    }
}

function Get-TargetFromTelemetry {
    param([object]$Telemetry)

    return [ordered]@{
        stapmWatts = [int][Math]::Round([double]$Telemetry.stapmLimitWatts)
        fastWatts = [int][Math]::Round([double]$Telemetry.fastLimitWatts)
        slowWatts = [int][Math]::Round([double]$Telemetry.slowLimitWatts)
    }
}

function Invoke-WorkerRequest {
    param(
        [string]$Command,
        [object]$Payload,
        [int]$TimeoutMilliseconds = 8000
    )

    $requestId = [Guid]::NewGuid().ToString("N")
    $request = [ordered]@{
        protocolVersion = 1
        requestId = $requestId
        command = $Command
        payload = $Payload
    }

    $client = [IO.Pipes.NamedPipeClientStream]::new(
        ".",
        $script:pipeName,
        [IO.Pipes.PipeDirection]::InOut,
        [IO.Pipes.PipeOptions]::Asynchronous)
    try {
        $client.Connect($TimeoutMilliseconds)
        $writer = [IO.StreamWriter]::new(
            $client,
            [Text.UTF8Encoding]::new($false),
            1024,
            $true)
        $reader = [IO.StreamReader]::new(
            $client,
            [Text.Encoding]::UTF8,
            $false,
            1024,
            $true)
        try {
            $writer.NewLine = "`n"
            $writer.AutoFlush = $true
            $writer.WriteLine(($request | ConvertTo-Json -Depth 20 -Compress))
            $responseJson = $reader.ReadLine()
            if ([string]::IsNullOrWhiteSpace($responseJson)) {
                throw "Worker closed the pipe without a response."
            }

            $response = $responseJson | ConvertFrom-Json
            if ($response.requestId -ne $requestId) {
                throw "Worker response requestId did not match."
            }
            if (-not $response.success) {
                $code = $response.error.code
                $message = $response.error.message
                throw "Worker command $Command failed [$code]: $message"
            }

            return $response
        }
        finally {
            $reader.Dispose()
            $writer.Dispose()
        }
    }
    finally {
        $client.Dispose()
    }
}

function Get-Snapshot {
    return (Invoke-WorkerRequest -Command "getSnapshot").payload
}

function Get-PowerPolicy {
    return (Invoke-WorkerRequest -Command "getPowerPolicy").payload
}

function Set-PowerPolicy {
    param(
        [bool]$Enabled,
        [object]$BatteryTarget,
        [object]$AcTarget
    )

    $payload = [ordered]@{
        settings = [ordered]@{
            enabled = $Enabled
            batteryTarget = $BatteryTarget
            acTarget = $AcTarget
        }
    }
    return (Invoke-WorkerRequest -Command "setPowerPolicy" -Payload $payload).payload
}

function Apply-Target {
    param([object]$Target)

    return (
        Invoke-WorkerRequest `
            -Command "applyTarget" `
            -Payload ([ordered]@{ target = $Target })
    ).payload
}

function Wait-WorkerHealth {
    $deadline = [DateTimeOffset]::UtcNow.AddSeconds(15)
    $lastError = $null
    while ([DateTimeOffset]::UtcNow -lt $deadline) {
        if ($script:workerProcess.HasExited) {
            throw "Worker exited during startup with code $($script:workerProcess.ExitCode)."
        }

        try {
            return (Invoke-WorkerRequest -Command "getHealth" -TimeoutMilliseconds 700).payload
        }
        catch {
            $lastError = $_
            Start-Sleep -Milliseconds 200
        }
    }

    throw "Worker did not become healthy: $($lastError.Exception.Message)"
}

function Wait-PowerLine {
    param(
        [string]$Expected,
        [string]$Instruction
    )

    Write-Host ""
    Write-Host $Instruction -ForegroundColor Cyan
    $deadline = [DateTimeOffset]::UtcNow.AddSeconds($TransitionTimeoutSeconds)
    while ([DateTimeOffset]::UtcNow -lt $deadline) {
        if ((Get-PowerLine) -eq $Expected) {
            Write-Host "Detected power line: $Expected" -ForegroundColor Green
            return
        }
        Start-Sleep -Milliseconds 500
    }

    throw "Timed out waiting for power line '$Expected'."
}

function Wait-PolicyApplied {
    param(
        [string]$ExpectedLine,
        [object]$ExpectedTarget
    )

    $deadline = [DateTimeOffset]::UtcNow.AddSeconds(15)
    $lastState = $null
    while ([DateTimeOffset]::UtcNow -lt $deadline) {
        $lastState = Get-PowerPolicy
        if ($lastState.lastAttemptSucceeded -eq $true -and
            $lastState.lastObservedPowerLine -eq $ExpectedLine -and
            $lastState.lastAppliedTarget.stapmWatts -eq $ExpectedTarget.stapmWatts -and
            $lastState.lastAppliedTarget.fastWatts -eq $ExpectedTarget.fastWatts -and
            $lastState.lastAppliedTarget.slowWatts -eq $ExpectedTarget.slowWatts) {
            return $lastState
        }
        Start-Sleep -Milliseconds 300
    }

    throw "Policy did not report the expected $ExpectedLine target $(
        Format-Target $ExpectedTarget
    ). Last state: $($lastState | ConvertTo-Json -Depth 10 -Compress)"
}

function Test-NoUpwardViolation {
    param(
        [object]$Snapshot,
        [object]$Target,
        [string]$Label
    )

    $fast = $Snapshot.telemetry.fastLimitWatts
    $slow = $Snapshot.telemetry.slowLimitWatts
    if ($null -eq $fast -or $null -eq $slow) {
        throw "$Label is missing Fast/Slow read-back."
    }
    if ([double]$fast -gt ($Target.fastWatts + 0.75) -or
        [double]$slow -gt ($Target.slowWatts + 0.75)) {
        throw "$Label read back above the requested safety cap: Fast=$fast W Slow=$slow W."
    }
}

function Test-RestoredTarget {
    param(
        [object]$Snapshot,
        [object]$Target,
        [string]$Label,
        [double]$ToleranceWatts = 1.0
    )

    $checks = @(
        @{ Name = "STAPM"; Actual = $Snapshot.telemetry.stapmLimitWatts; Expected = $Target.stapmWatts },
        @{ Name = "Fast"; Actual = $Snapshot.telemetry.fastLimitWatts; Expected = $Target.fastWatts },
        @{ Name = "Slow"; Actual = $Snapshot.telemetry.slowLimitWatts; Expected = $Target.slowWatts }
    )
    foreach ($check in $checks) {
        if ($null -eq $check.Actual) {
            throw "$Label is missing the $($check.Name) read-back."
        }
        if ([Math]::Abs([double]$check.Actual - [double]$check.Expected) -gt $ToleranceWatts) {
            throw "$Label did not restore $($check.Name): expected $($check.Expected) W, got $($check.Actual) W."
        }
    }
}

function Stop-WorkerGracefully {
    $script:shutdownResult = "NOT_REQUESTED"
    if ($null -eq $script:workerProcess) {
        return
    }

    if (-not $script:workerProcess.HasExited) {
        try {
            Invoke-WorkerRequest -Command "shutdown" -TimeoutMilliseconds 3000 | Out-Null
            if (-not $script:workerProcess.WaitForExit(5000)) {
                throw "Worker did not exit within five seconds after shutdown acknowledgement."
            }
            $script:shutdownResult = "PASS"
        }
        catch {
            Write-Warning "Graceful worker shutdown failed: $($_.Exception.Message)"
            if (-not $script:workerProcess.HasExited) {
                $script:workerProcess.Kill($true)
                $script:workerProcess.WaitForExit(5000) | Out-Null
            }
            $script:shutdownResult = "FALLBACK_PROCESS_TERMINATION"
        }
    }

    $script:workerProcess.Dispose()
    $script:workerProcess = $null
}

$runId = [Guid]::NewGuid().ToString("N")
$script:pipeName = "AmdMobilePower.PolicyVerify.$runId"
$script:workerProcess = $null
$script:shutdownResult = "NOT_REQUESTED"
$evidenceDirectory = Join-Path $root "artifacts\verify"
New-Item -ItemType Directory -Path $evidenceDirectory -Force | Out-Null
$evidencePath = Join-Path $evidenceDirectory "power-policy-$runId.json"
$evidence = [ordered]@{
    schemaVersion = 1
    startedAt = [DateTimeOffset]::Now
    mode = if ($PlanOnly) { "plan-only" } else { "hardware-write" }
    host = [ordered]@{}
    package = [ordered]@{
        directory = $PackageDirectory
        workerSha256 = (Get-FileHash -LiteralPath $workerExecutable -Algorithm SHA256).Hash.ToLowerInvariant()
    }
    baseline = [ordered]@{}
    test = [ordered]@{}
    restore = [ordered]@{}
    cleanup = [ordered]@{
        shutdownProtocol = "NOT_REQUESTED"
    }
    result = "INCOMPLETE"
    error = $null
}

$bios = Get-CimInstance Win32_BIOS -ErrorAction SilentlyContinue
$computer = Get-CimInstance Win32_ComputerSystem -ErrorAction SilentlyContinue
$evidence.host = [ordered]@{
    manufacturer = $computer.Manufacturer
    model = $computer.Model
    biosVersion = $bios.SMBIOSBIOSVersion
    os = [Environment]::OSVersion.VersionString
    powerShell = $PSVersionTable.PSVersion.ToString()
}

try {
    $startInfo = [Diagnostics.ProcessStartInfo]::new()
    $startInfo.FileName = $workerExecutable
    $startInfo.WorkingDirectory = Split-Path -Parent $workerExecutable
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true
    $startInfo.WindowStyle = [Diagnostics.ProcessWindowStyle]::Hidden
    $startInfo.ArgumentList.Add("--pipe-name")
    $startInfo.ArgumentList.Add($script:pipeName)
    $startInfo.ArgumentList.Add("--enable-hardware")
    if (-not $PlanOnly) {
        $startInfo.ArgumentList.Add("--enable-write-controls")
    }

    $script:workerProcess = [Diagnostics.Process]::Start($startInfo)
    if ($null -eq $script:workerProcess) {
        throw "Failed to start the packaged worker."
    }

    $health = Wait-WorkerHealth
    $snapshot = Get-Snapshot
    if ($snapshot.platform.isSupported -ne $true) {
        throw "Platform is unsupported: $($snapshot.platform.unsupportedReason)"
    }
    if ($null -eq $snapshot.matchedProfile) {
        throw "No matched power profile was reported."
    }
    if ($BatteryWatts -lt $snapshot.matchedProfile.minimumWatts -or
        $BatteryWatts -gt $snapshot.matchedProfile.maximumWatts) {
        throw "Battery target ${BatteryWatts}W is outside profile range $(
            $snapshot.matchedProfile.minimumWatts
        )-$($snapshot.matchedProfile.maximumWatts) W."
    }

    $currentPowerLine = [string]$snapshot.telemetry.powerLine
    if ($currentPowerLine -notin @("ac", "battery")) {
        throw "Power-line state is unknown. Connect AC or run on battery and retry."
    }
    if (-not $PlanOnly -and $currentPowerLine -ne "ac") {
        throw "Start the full test on AC power. Current worker state: $currentPowerLine."
    }

    $currentTarget = Get-TargetFromTelemetry $snapshot.telemetry
    $evidence.baseline[$currentPowerLine] = [ordered]@{
        capturedAt = [DateTimeOffset]::Now
        powerLine = $currentPowerLine
        target = $currentTarget
        telemetry = $snapshot.telemetry
    }
    $evidence.baseline.profile = $snapshot.matchedProfile
    $evidence.baseline.platform = $snapshot.platform

    Write-Host ""
    Write-Host "Device: $($computer.Manufacturer) $($computer.Model)" -ForegroundColor Cyan
    Write-Host "CPU: $($snapshot.platform.cpu.processorName)" -ForegroundColor Cyan
    Write-Host "Profile: $($snapshot.matchedProfile.id) $(
        $snapshot.matchedProfile.minimumWatts
    )-$($snapshot.matchedProfile.maximumWatts) W" -ForegroundColor Cyan
    Write-Host "Current $currentPowerLine baseline: $(Format-Target $currentTarget)" -ForegroundColor Cyan
    Write-Host "Planned battery test: $(Format-Target (New-Target $BatteryWatts))" -ForegroundColor Cyan

    if ($PlanOnly) {
        $evidence.test = [ordered]@{
            plannedBatteryTarget = New-Target $BatteryWatts
            hardwareWrites = 0
        }
        $evidence.result = "PLAN_ONLY_PASS"
        Write-Host ""
        Write-Host "Read-only policy preflight passed. No hardware writes were performed." -ForegroundColor Green
        return
    }

    $originalAc = $currentTarget
    $confirmationCode = "APPLY $BatteryWatts W BATTERY TEST"
    Write-Host ""
    Write-Warning "The full test changes Fast/Slow to $BatteryWatts W on battery and restores both baselines afterward."
    $enteredCode = Read-Host "Type '$confirmationCode' to continue"
    if ($enteredCode -cne $confirmationCode) {
        throw "Hardware-write confirmation did not match."
    }

    Set-PowerPolicy -Enabled $false -BatteryTarget (New-Target $BatteryWatts) -AcTarget $originalAc | Out-Null

    Wait-PowerLine `
        -Expected "battery" `
        -Instruction "Unplug AC power now. The script is waiting for the battery state."
    $batterySnapshot = Get-Snapshot
    $originalBattery = Get-TargetFromTelemetry $batterySnapshot.telemetry
    $evidence.baseline.battery = [ordered]@{
        capturedAt = [DateTimeOffset]::Now
        powerLine = $batterySnapshot.telemetry.powerLine
        target = $originalBattery
        telemetry = $batterySnapshot.telemetry
    }

    $batteryTarget = New-Target $BatteryWatts
    $enabledState = Set-PowerPolicy `
        -Enabled $true `
        -BatteryTarget $batteryTarget `
        -AcTarget $originalAc
    $batteryPolicy = Wait-PolicyApplied -ExpectedLine "battery" -ExpectedTarget $batteryTarget
    $batteryAppliedSnapshot = Get-Snapshot
    Test-NoUpwardViolation `
        -Snapshot $batteryAppliedSnapshot `
        -Target $batteryTarget `
        -Label "Battery policy target"
    $evidence.test = [ordered]@{
        requestedBatteryTarget = $batteryTarget
        policyAfterEnable = $enabledState
        policyBatteryApplied = $batteryPolicy
        telemetryAfterBatteryApply = $batteryAppliedSnapshot.telemetry
    }

    Wait-PowerLine `
        -Expected "ac" `
        -Instruction "Reconnect AC power now. The script will verify the automatic AC transition."
    $acPolicy = Wait-PolicyApplied -ExpectedLine "ac" -ExpectedTarget $originalAc
    $acAppliedSnapshot = Get-Snapshot
    Test-RestoredTarget `
        -Snapshot $acAppliedSnapshot `
        -Target $originalAc `
        -Label "Automatic AC transition"
    $evidence.test.policyAcApplied = $acPolicy
    $evidence.test.telemetryAfterAcTransition = $acAppliedSnapshot.telemetry

    Set-PowerPolicy `
        -Enabled $false `
        -BatteryTarget $batteryTarget `
        -AcTarget $originalAc | Out-Null

    Wait-PowerLine `
        -Expected "battery" `
        -Instruction "Unplug AC power again to restore the original battery baseline."
    (Apply-Target $originalBattery) | Out-Null
    $batteryRestoredSnapshot = Get-Snapshot
    Test-RestoredTarget `
        -Snapshot $batteryRestoredSnapshot `
        -Target $originalBattery `
        -Label "Battery baseline restore"
    $evidence.restore.battery = [ordered]@{
        restoredAt = [DateTimeOffset]::Now
        target = $originalBattery
        telemetry = $batteryRestoredSnapshot.telemetry
    }

    Wait-PowerLine `
        -Expected "ac" `
        -Instruction "Reconnect AC power for the final AC baseline restore."
    (Apply-Target $originalAc) | Out-Null
    $acRestoredSnapshot = Get-Snapshot
    Test-RestoredTarget `
        -Snapshot $acRestoredSnapshot `
        -Target $originalAc `
        -Label "AC baseline restore"
    $evidence.restore.ac = [ordered]@{
        restoredAt = [DateTimeOffset]::Now
        target = $originalAc
        telemetry = $acRestoredSnapshot.telemetry
    }

    $finalPolicy = Set-PowerPolicy `
        -Enabled $false `
        -BatteryTarget $originalBattery `
        -AcTarget $originalAc
    $evidence.restore.finalPolicy = $finalPolicy
    $evidence.result = "PASS"
    Write-Host ""
    Write-Host "Policy verification passed; both AC and battery baselines were restored." -ForegroundColor Green
}
catch {
    $evidence.error = $_.Exception.Message
    $evidence.result = "FAIL"
    Write-Error $_

    try {
        if (-not $PlanOnly -and $null -ne $script:workerProcess -and -not $script:workerProcess.HasExited) {
            Set-PowerPolicy `
                -Enabled $false `
                -BatteryTarget (New-Target $BatteryWatts) `
                -AcTarget $evidence.baseline.ac.target | Out-Null

            $currentPowerLine = Get-PowerLine
            if ($currentPowerLine -eq "ac" -and $null -ne $evidence.baseline.ac.target) {
                (Apply-Target $evidence.baseline.ac.target) | Out-Null
                $evidence.restore.failureRecoveryAc = Get-Snapshot
            }
            elseif ($currentPowerLine -eq "battery" -and
                $null -ne $evidence.baseline.battery.target) {
                (Apply-Target $evidence.baseline.battery.target) | Out-Null
                $evidence.restore.failureRecoveryBattery = Get-Snapshot
            }
        }
    }
    catch {
        $evidence.restore.failureRecoveryError = $_.Exception.Message
        Write-Warning "Failure recovery could not be completed: $($_.Exception.Message)"
    }
}
finally {
    Stop-WorkerGracefully
    $evidence.cleanup.shutdownProtocol = $script:shutdownResult
    $evidence.completedAt = [DateTimeOffset]::Now
    $evidence | ConvertTo-Json -Depth 30 | Set-Content -LiteralPath $evidencePath -Encoding utf8
    Write-Host "Evidence: $evidencePath"
}

if ($evidence.result -ne "PLAN_ONLY_PASS" -and $evidence.result -ne "PASS") {
    exit 1
}
