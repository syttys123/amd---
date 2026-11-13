param(
    [switch]$NoBuild,
    [switch]$ExecuteNoChangeWrite,
    [switch]$AllowBattery,
    [string]$WorkerRuntimeDirectory = "artifacts\native-build\worker-runtime"
)

$ErrorActionPreference = "Stop"

. (Join-Path $PSScriptRoot "worker-client.ps1")

$root = Split-Path -Parent $PSCommandPath
$repositoryRoot = Split-Path -Parent $root
$workerExecutable = Join-Path `
    $repositoryRoot `
    "$WorkerRuntimeDirectory\amdmobilepower_native_worker.exe"
$probe = Join-Path `
    $root `
    "rust-probe\target\release\amd-mobile-power-probe.exe"

if (-not $NoBuild) {
    & (Join-Path $root "build.ps1") -Offline
    if ($LASTEXITCODE -ne 0) {
        throw "Native build failed."
    }
}

if (-not (Test-Path -LiteralPath $workerExecutable)) {
    throw "Native worker runtime was not staged: $workerExecutable"
}
if (-not (Test-Path -LiteralPath $probe)) {
    throw "Rust probe was not built: $probe"
}

function Wait-ForWorker {
    param(
        [System.Diagnostics.Process]$Process,
        [string]$PipePath,
        [int]$TimeoutMilliseconds = 10000
    )

    $deadline = [DateTime]::UtcNow.AddMilliseconds($TimeoutMilliseconds)
    while ([DateTime]::UtcNow -lt $deadline) {
        $Process.Refresh()
        if ($Process.HasExited) {
            throw "Native worker exited before becoming ready: $($Process.ExitCode)"
        }
        $health = Invoke-ProbeProcess `
            -ProbePath $probe `
            -PipePath $PipePath `
            -Command "getHealth"
        if ($health.ExitCode -eq 0) {
            return $health.Output
        }
        Start-Sleep -Milliseconds 150
    }
    throw "Native worker did not become ready."
}

function Read-Snapshot {
    param(
        [string]$PipePath
    )

    $snapshot = Invoke-ProbeProcess `
        -ProbePath $probe `
        -PipePath $PipePath `
        -Command "getSnapshot"
    if ($snapshot.ExitCode -ne 0) {
        throw "Native snapshot failed: $($snapshot.Output)"
    }
    return $snapshot.Output | ConvertFrom-Json
}

function Assert-Close {
    param(
        [double]$Actual,
        [double]$Expected,
        [string]$Name,
        [double]$Tolerance = 0.75
    )

    if ([Math]::Abs($Actual - $Expected) -gt $Tolerance) {
        throw "$Name expected $Expected W but read back $Actual W."
    }
}

$pipeName = "AmdMobilePower.NativeWriteControls.$([Guid]::NewGuid().ToString('N'))"
$pipePath = "\\.\pipe\$pipeName"
$workerProcess = Start-Process `
    -FilePath $workerExecutable `
    -WorkingDirectory (Split-Path -Parent $workerExecutable) `
    -ArgumentList @(
        "--pipe-name",
        $pipeName,
        "--enable-hardware",
        "--enable-write-controls"
    ) `
    -WindowStyle Hidden `
    -PassThru

$shutdown = $null
try {
    $health = Wait-ForWorker -Process $workerProcess -PipePath $pipePath
    if ($health -notmatch "hardware=true") {
        throw "Native worker did not initialize hardware: $health"
    }

    $before = Read-Snapshot -PipePath $pipePath
    if (-not $AllowBattery -and $before.telemetry.powerLine -ne "ac") {
        throw "No-change write requires AC power; pass -AllowBattery to override."
    }

    $target = @{
        stapmWatts = [int][Math]::Round($before.telemetry.stapmLimitWatts)
        fastWatts = [int][Math]::Round($before.telemetry.fastLimitWatts)
        slowWatts = [int][Math]::Round($before.telemetry.slowLimitWatts)
    }
    foreach ($key in @("stapmWatts", "fastWatts", "slowWatts")) {
        $watts = $target[$key]
        if ($watts -lt 5 -or $watts -gt 60) {
            throw "Current $key is outside the safe no-change range: $watts W"
        }
    }

    $invalidResult = Invoke-WorkerPipeRequest `
        -PipeName $pipePath `
        -Command "applyTarget" `
        -Payload @{ target = @{ stapmWatts = 4; fastWatts = 12; slowWatts = 12 } }
    if ($invalidResult.Success) {
        throw "Out-of-range target was accepted by the native worker."
    }
    if ($invalidResult.ErrorText -notmatch "invalid_target") {
        throw "Out-of-range target returned an unexpected error: $($invalidResult.ErrorText)"
    }

    if (-not $ExecuteNoChangeWrite) {
        [pscustomobject]@{
            Verification = "DRY RUN PASS"
            PowerLine = $before.telemetry.powerLine
            Processor = $before.platform.cpu.processorName
            PreviousTargetWatts = "$($target.stapmWatts)/$($target.fastWatts)/$($target.slowWatts)"
            InvalidTargetGuard = "PASS"
            ExecuteNoChangeWrite = "Not requested"
        } | Format-List
        return
    }

    $applyResult = Invoke-WorkerPipeRequest `
        -PipeName $pipePath `
        -Command "applyTarget" `
        -Payload @{ target = $target }
    if (-not $applyResult.Success) {
        throw "Native no-change apply failed: $($applyResult.ErrorText)"
    }
    if ($applyResult.Payload.isSuccessful -ne $true) {
        throw "Native no-change apply returned an unsuccessful result."
    }
    if ($applyResult.Payload.restoreAttempted -eq $true) {
        throw "Native no-change apply unexpectedly attempted restore."
    }

    $after = Read-Snapshot -PipePath $pipePath
    Assert-Close `
        -Actual ([double]$after.telemetry.fastLimitWatts) `
        -Expected ([double]$target.fastWatts) `
        -Name "Fast limit"
    Assert-Close `
        -Actual ([double]$after.telemetry.slowLimitWatts) `
        -Expected ([double]$target.slowWatts) `
        -Name "Slow limit"

    $shutdown = Invoke-ProbeProcess `
        -ProbePath $probe `
        -PipePath $pipePath `
        -Command "shutdown"
    if ($shutdown.ExitCode -ne 0) {
        throw "Native worker shutdown failed: $($shutdown.Output)"
    }
    if (-not $workerProcess.WaitForExit(5000)) {
        throw "Native worker did not exit after shutdown."
    }

    $timestamp = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH-mm-ssZ")
    $evidenceDirectory = Join-Path $repositoryRoot "docs\evidence\hardware"
    New-Item -ItemType Directory -Path $evidenceDirectory -Force | Out-Null
    $evidencePath = Join-Path `
        $evidenceDirectory `
        "mechrevo-wujie15-8845hs-native-no-change-$timestamp.json"
    $evidence = [pscustomobject]@{
        SourceCommit = (git -C $repositoryRoot rev-parse HEAD).Trim()
        Verification = "PASS"
        Processor = $before.platform.cpu.processorName
        RyzenAdjFamily = $before.platform.cpu.ryzenAdjFamily
        RyzenAdjFamilyName = $before.platform.cpu.ryzenAdjFamilyName
        PmTableVersion = $before.platform.cpu.pmTableVersion
        PowerLine = $before.telemetry.powerLine
        TargetWatts = $target
        BeforeLimitsWatts = @{
            stapm = $before.telemetry.stapmLimitWatts
            fast = $before.telemetry.fastLimitWatts
            slow = $before.telemetry.slowLimitWatts
        }
        AfterLimitsWatts = @{
            stapm = $after.telemetry.stapmLimitWatts
            fast = $after.telemetry.fastLimitWatts
            slow = $after.telemetry.slowLimitWatts
        }
        ApplyResult = $applyResult
        InvalidTargetGuard = "PASS"
        Shutdown = ($shutdown | Out-String).Trim()
        RecordedAt = (Get-Date).ToString("o")
    }
    $evidence |
        ConvertTo-Json -Depth 12 |
        Set-Content -LiteralPath $evidencePath -Encoding UTF8

    [pscustomobject]@{
        Verification = "PASS"
        Evidence = $evidencePath
        TargetWatts = "$($target.stapmWatts)/$($target.fastWatts)/$($target.slowWatts)"
        ReadbackWatts = "$($after.telemetry.stapmLimitWatts)/$($after.telemetry.fastLimitWatts)/$($after.telemetry.slowLimitWatts)"
        InvalidTargetGuard = "PASS"
        RestoreAttempted = $applyResult.restoreAttempted
    } | Format-List
}
finally {
    try {
        $workerProcess.Refresh()
        if (-not $workerProcess.HasExited) {
            $workerProcess.Kill($true)
            $workerProcess.WaitForExit(5000) | Out-Null
        }
    }
    catch {
    }
    $workerProcess.Dispose()
}
