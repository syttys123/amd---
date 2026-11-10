<#
.SYNOPSIS
Verifies a packaged worker with a no-change hardware write.

.DESCRIPTION
Starts an isolated packaged worker with hardware writes enabled, reads the
current STAPM/Fast/Slow limits, writes that same target back, verifies the
required Fast/Slow read-back, restores the baseline if the write fails, and
shuts the worker down through the protocol.
#>
param(
    [string]$PackageDirectory,
    [ValidateRange(0, 15)]
    [int]$SettleSeconds = 2,
    [switch]$ConfirmHardwareWrite
)

$ErrorActionPreference = "Stop"

if ($PSVersionTable.PSVersion.Major -lt 7) {
    throw "PowerShell 7 or newer is required."
}

if (-not $ConfirmHardwareWrite) {
    throw "A no-change hardware-write test requires -ConfirmHardwareWrite."
}

$root = Split-Path -Parent $PSCommandPath
if ([string]::IsNullOrWhiteSpace($PackageDirectory)) {
    $PackageDirectory = Join-Path $root "artifacts\packages\amd-mobile-power-v1.0.0-win-x64-lite"
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

function Test-RequiredReadback {
    param(
        [object]$Result,
        [object]$Target
    )

    if ($Result.isSuccessful -ne $true) {
        throw "No-change write failed: $($Result.error)"
    }
    if ($Result.restoreAttempted -eq $true) {
        throw "No-change write unexpectedly attempted a restore."
    }

    foreach ($required in @(
        @{ Key = "fast"; Name = "Fast"; Requested = $Target.fastWatts },
        @{ Key = "slow"; Name = "Slow"; Requested = $Target.slowWatts }
    )) {
        $readback = @($Result.readbacks) |
            Where-Object { $_.kind -eq $required.Key } |
            Select-Object -First 1
        if ($null -eq $readback) {
            throw "No-change write is missing the $($required.Name) read-back."
        }
        if ($readback.driverResultCode -ne 0) {
            throw "No-change write $($required.Name) returned driver code $(
                $readback.driverResultCode
            )."
        }
        if ($null -eq $readback.effectiveWatts -or
            [double]$readback.effectiveWatts -le 0 -or
            [Math]::Abs(
                [double]$readback.effectiveWatts - [double]$required.Requested
            ) -gt 0.75) {
            throw "No-change write $($required.Name) requested $(
                $required.Requested
            ) W but read back $($readback.effectiveWatts) W."
        }
    }
}

function Test-SettledRequiredLimits {
    param(
        [object]$Snapshot,
        [object]$Target
    )

    if ($Snapshot.telemetry.powerLine -notin @("ac", "battery")) {
        throw "Power-line state is unknown after the no-change write."
    }
    if ($null -eq $Snapshot.telemetry.fastLimitWatts -or
        [double]$Snapshot.telemetry.fastLimitWatts -gt ($Target.fastWatts + 0.75)) {
        throw "Fast limit drifted above the no-change target."
    }
    if ($null -eq $Snapshot.telemetry.slowLimitWatts -or
        [double]$Snapshot.telemetry.slowLimitWatts -gt ($Target.slowWatts + 0.75)) {
        throw "Slow limit drifted above the no-change target."
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
$script:pipeName = "AmdMobilePower.NoChange.$runId"
$script:workerProcess = $null
$script:shutdownResult = "NOT_REQUESTED"
$evidenceDirectory = Join-Path $root "artifacts\verify"
New-Item -ItemType Directory -Path $evidenceDirectory -Force | Out-Null
$evidencePath = Join-Path $evidenceDirectory "no-change-$runId.json"
$failureError = $null
$baseline = $null
$workerReady = $false
$evidence = [ordered]@{
    schemaVersion = 1
    evidenceType = "packaged-no-change-write"
    startedAt = [DateTimeOffset]::Now
    package = [ordered]@{
        directory = $PackageDirectory
        workerSha256 = (Get-FileHash -LiteralPath $workerExecutable -Algorithm SHA256).Hash.ToLowerInvariant()
    }
    platform = $null
    baseline = $null
    applyResult = $null
    settledTelemetry = $null
    cleanup = [ordered]@{
        shutdownProtocol = "NOT_REQUESTED"
    }
    result = "INCOMPLETE"
    error = $null
    completedAt = $null
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
    $startInfo.ArgumentList.Add("--enable-write-controls")

    $script:workerProcess = [Diagnostics.Process]::Start($startInfo)
    if ($null -eq $script:workerProcess) {
        throw "Failed to start the packaged worker."
    }

    $health = Wait-WorkerHealth
    $workerReady = $true
    $snapshot = Get-Snapshot
    if ($snapshot.platform.isSupported -ne $true) {
        throw "Platform is unsupported: $($snapshot.platform.unsupportedReason)"
    }
    if ($null -eq $snapshot.matchedProfile) {
        throw "No matched power profile was reported."
    }
    if ($snapshot.telemetry.powerLine -notin @("ac", "battery")) {
        throw "Power-line state is unknown. Retry when AC or battery is available."
    }

    $baseline = Get-TargetFromTelemetry $snapshot.telemetry
    $minimum = [Math]::Min(
        $baseline.stapmWatts,
        [Math]::Min($baseline.fastWatts, $baseline.slowWatts))
    $maximum = [Math]::Max(
        $baseline.stapmWatts,
        [Math]::Max($baseline.fastWatts, $baseline.slowWatts))
    if ($minimum -lt $snapshot.matchedProfile.minimumWatts -or
        $maximum -gt $snapshot.matchedProfile.maximumWatts) {
        throw "Current limit triplet is outside the matched profile range."
    }

    $evidence.platform = $snapshot.platform
    $evidence.baseline = [ordered]@{
        target = $baseline
        telemetry = $snapshot.telemetry
    }

    Write-Host ""
    Write-Host "Package worker: $workerExecutable" -ForegroundColor Cyan
    Write-Host "No-change target: $($baseline.stapmWatts)/$(
        $baseline.fastWatts
    )/$($baseline.slowWatts) W" -ForegroundColor Cyan
    Write-Host "Power line: $($snapshot.telemetry.powerLine)" -ForegroundColor Cyan

    $applyResult = Apply-Target $baseline
    Test-RequiredReadback -Result $applyResult -Target $baseline
    Start-Sleep -Seconds $SettleSeconds
    $settled = Get-Snapshot
    Test-SettledRequiredLimits -Snapshot $settled -Target $baseline

    $evidence.applyResult = $applyResult
    $evidence.settledTelemetry = $settled.telemetry
    $evidence.result = "PASS"
    Write-Host "Packaged no-change write passed." -ForegroundColor Green
}
catch {
    $failureError = $_
    $evidence.error = $_.Exception.Message
    $evidence.result = "FAIL"

    if ($workerReady -and $null -ne $baseline) {
        try {
            $restoreResult = Apply-Target $baseline
            $evidence.failureRecovery = $restoreResult
            Test-RequiredReadback -Result $restoreResult -Target $baseline
        }
        catch {
            $evidence.error = "$($evidence.error) Recovery error: $($_.Exception.Message)"
            Write-Warning "Failure recovery could not be verified: $($_.Exception.Message)"
        }
    }
}
finally {
    Stop-WorkerGracefully
    $evidence.cleanup.shutdownProtocol = $script:shutdownResult
    $evidence.completedAt = [DateTimeOffset]::Now
    $evidence | ConvertTo-Json -Depth 30 | Set-Content -LiteralPath $evidencePath -Encoding utf8
    Write-Host "Evidence: $evidencePath"
}

if ($evidence.result -ne "PASS") {
    if ($null -ne $failureError) {
        Write-Error $failureError
    }
    exit 1
}
