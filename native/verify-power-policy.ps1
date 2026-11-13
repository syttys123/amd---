param(
    [switch]$NoBuild,
    [switch]$ExecuteNoChangePolicy,
    [string]$EvidencePath
)

$ErrorActionPreference = "Stop"

if ($PSVersionTable.PSVersion.Major -lt 7) {
    throw ("This verifier passes JSON to the probe. Run it with PowerShell 7 " +
        "(pwsh): Windows PowerShell 5.1 strips quotes from native-command " +
        "arguments, so --payload-json arrives malformed.")
}

$root = Split-Path -Parent $PSCommandPath
$repositoryRoot = Split-Path -Parent $root
$worker = Join-Path `
    $repositoryRoot `
    "artifacts\native-build\worker-runtime\amdmobilepower_native_worker.exe"
$probe = Join-Path `
    $root `
    "rust-probe\target\release\amd-mobile-power-probe.exe"

if (-not $NoBuild) {
    & (Join-Path $root "build.ps1") -Offline
}
if (-not (Test-Path -LiteralPath $worker)) {
    throw "Native worker was not staged: $worker"
}
if (-not (Test-Path -LiteralPath $probe)) {
    throw "Rust probe was not built: $probe"
}

function Invoke-Probe {
    param(
        [string]$PipePath,
        [string]$Command,
        [string]$PayloadJson = "null"
    )

    $arguments = @(
        "--pipe-name", $PipePath,
        "--command", $Command
    )
    if ($PayloadJson -ne "null") {
        $arguments += @("--payload-json", $PayloadJson)
    }
    $output = & $probe @arguments 2>&1
    return [pscustomobject]@{
        ExitCode = $LASTEXITCODE
        Output = ($output | Out-String).Trim()
    }
}

function Start-NativeWorker {
    param(
        [string]$PipeName,
        [switch]$EnableWriteControls
    )

    $arguments = @(
        "--pipe-name", $PipeName,
        "--enable-hardware"
    )
    if ($EnableWriteControls) {
        $arguments += "--enable-write-controls"
    }
    return Start-Process `
        -FilePath $worker `
        -WorkingDirectory (Split-Path -Parent $worker) `
        -ArgumentList $arguments `
        -WindowStyle Hidden `
        -PassThru
}

function Wait-ForHealth {
    param(
        [System.Diagnostics.Process]$Process,
        [string]$PipePath
    )

    $deadline = [DateTime]::UtcNow.AddSeconds(12)
    while ([DateTime]::UtcNow -lt $deadline) {
        $Process.Refresh()
        if ($Process.HasExited) {
            throw "Native worker exited before health: $($Process.ExitCode)"
        }
        $health = Invoke-Probe -PipePath $PipePath -Command "getHealth"
        if ($health.ExitCode -eq 0) {
            return $health.Output
        }
        Start-Sleep -Milliseconds 150
    }
    throw "Native worker did not answer getHealth."
}

function Stop-NativeWorker {
    param(
        [System.Diagnostics.Process]$Process,
        [string]$PipePath
    )

    if ($null -ne $Process) {
        try {
            $null = Invoke-Probe -PipePath $PipePath -Command "shutdown"
            $Process.WaitForExit(5000) | Out-Null
        }
        catch {
        }
        try {
            $Process.Refresh()
            if (-not $Process.HasExited) {
                $Process.Kill($true)
                $Process.WaitForExit(5000) | Out-Null
            }
        }
        catch {
        }
        $Process.Dispose()
    }
}

if (-not $ExecuteNoChangePolicy) {
    $pipeName = "AmdMobilePower.PolicyReadOnly.$([Guid]::NewGuid().ToString('N'))"
    $pipePath = "\\.\pipe\$pipeName"
    $process = $null
    try {
        $process = Start-NativeWorker -PipeName $pipeName
        $null = Wait-ForHealth -Process $process -PipePath $pipePath

        $state = Invoke-Probe -PipePath $pipePath -Command "getPowerPolicy"
        if ($state.ExitCode -ne 0) {
            throw "getPowerPolicy failed: $($state.Output)"
        }
        if ($null -ne (($state.Output | ConvertFrom-Json).settings)) {
            throw "Read-only worker returned policy settings."
        }

        $payload = '{"settings":{"enabled":true,"batteryTarget":{"stapmWatts":12,"fastWatts":12,"slowWatts":12},"acTarget":{"stapmWatts":45,"fastWatts":45,"slowWatts":45}}}'
        $rejected = Invoke-Probe `
            -PipePath $pipePath `
            -Command "setPowerPolicy" `
            -PayloadJson $payload
        if ($rejected.ExitCode -eq 0 -or
            $rejected.Output -notmatch "hardware_writes_disabled") {
            throw "Read-only power-policy write gate failed: $($rejected.Output)"
        }

        [pscustomobject]@{
            Verification = "PASS"
            GetPowerPolicy = "PASS"
            SetPowerPolicyGate = "PASS"
            WriteControls = "Not requested"
        } | Format-List
    }
    finally {
        Stop-NativeWorker -Process $process -PipePath $pipePath
    }
    return
}

$pipeName = "AmdMobilePower.PolicyNoChange.$([Guid]::NewGuid().ToString('N'))"
$pipePath = "\\.\pipe\$pipeName"
$process = $null
try {
    $process = Start-NativeWorker -PipeName $pipeName -EnableWriteControls
    $healthOutput = Wait-ForHealth -Process $process -PipePath $pipePath
    $workerVersion = if ($healthOutput -match "worker=([^ ]+)") {
        $Matches[1]
    }
    else {
        $null
    }

    $snapshotResult = Invoke-Probe -PipePath $pipePath -Command "getSnapshot"
    if ($snapshotResult.ExitCode -ne 0) {
        throw "getSnapshot failed: $($snapshotResult.Output)"
    }
    $snapshot = $snapshotResult.Output | ConvertFrom-Json
    $powerLine = [string]$snapshot.telemetry.powerLine
    if ($powerLine -notin @("ac", "battery")) {
        throw "Power-line state is not testable: $powerLine"
    }
    $activeTarget = [ordered]@{
        stapmWatts = [int][Math]::Round([double]$snapshot.telemetry.stapmLimitWatts)
        fastWatts = [int][Math]::Round([double]$snapshot.telemetry.fastLimitWatts)
        slowWatts = [int][Math]::Round([double]$snapshot.telemetry.slowLimitWatts)
    }
    $batteryTarget = [ordered]@{
        stapmWatts = 12
        fastWatts = 12
        slowWatts = 12
    }
    $acTarget = if ($powerLine -eq "ac") {
        $activeTarget
    }
    else {
        [ordered]@{
            stapmWatts = 45
            fastWatts = 45
            slowWatts = 45
        }
    }
    if ($powerLine -eq "battery") {
        $batteryTarget = $activeTarget
    }

    $settings = [ordered]@{
        enabled = $true
        batteryTarget = $batteryTarget
        acTarget = $acTarget
    }
    $payload = @{ settings = $settings } | ConvertTo-Json -Compress -Depth 6
    $setResult = Invoke-Probe `
        -PipePath $pipePath `
        -Command "setPowerPolicy" `
        -PayloadJson $payload
    if ($setResult.ExitCode -ne 0) {
        throw "setPowerPolicy failed: $($setResult.Output)"
    }

    $state = $null
    $deadline = [DateTime]::UtcNow.AddSeconds(10)
    while ([DateTime]::UtcNow -lt $deadline) {
        $stateResult = Invoke-Probe -PipePath $pipePath -Command "getPowerPolicy"
        if ($stateResult.ExitCode -eq 0) {
            $candidate = $stateResult.Output | ConvertFrom-Json
            if ($candidate.lastAttemptSucceeded -eq $true -and
                $candidate.lastObservedPowerLine -eq $powerLine) {
                $state = $candidate
                break
            }
        }
        Start-Sleep -Milliseconds 250
    }
    if ($null -eq $state) {
        throw "Power policy did not report a successful no-change apply."
    }
    foreach ($property in @("stapmWatts", "fastWatts", "slowWatts")) {
        if ([int]$state.lastAppliedTarget.$property -ne [int]$activeTarget.$property) {
            throw "Power policy applied an unexpected $property target."
        }
    }

    $disableSettings = [ordered]@{
        enabled = $false
        batteryTarget = $batteryTarget
        acTarget = $acTarget
    }
    $disablePayload = @{ settings = $disableSettings } |
        ConvertTo-Json -Compress -Depth 6
    $disableResult = Invoke-Probe `
        -PipePath $pipePath `
        -Command "setPowerPolicy" `
        -PayloadJson $disablePayload
    if ($disableResult.ExitCode -ne 0) {
        throw "Disabling power policy failed: $($disableResult.Output)"
    }

    $commit = (& git -C $repositoryRoot rev-parse HEAD).Trim()
    $evidenceRelative = $null
    if ($EvidencePath) {
        $evidenceRelative = [System.IO.Path]::GetRelativePath(
            $repositoryRoot,
            [System.IO.Path]::GetFullPath($EvidencePath)).Replace("\", "/")
    }
    $statusLines = & git `
        -C $repositoryRoot `
        status `
        --porcelain `
        --ignore-submodules=dirty |
        ForEach-Object {
            if ($_ -match "^.. docs/evidence/" -or
                ($_ -match "^.. (.+)$" -and
                    $Matches[1] -eq $evidenceRelative)) {
                return
            }
            $_
        }
    $statusText = ($statusLines | Out-String).Trim()
    $workingTree = if ($statusText) { "Dirty" } else { "Clean" }
    $result = [ordered]@{
        SourceCommit = $commit
        WorkingTree = $workingTree
        Verification = "PASS"
        Path = "Native worker power policy -> RyzenAdj"
        WorkerVersion = $workerVersion
        Processor = $snapshot.platform.cpu.processorName.Trim()
        PowerLine = $powerLine
        RequestedTarget = "$($activeTarget.stapmWatts)/$($activeTarget.fastWatts)/$($activeTarget.slowWatts)"
        BatteryTarget = "$($batteryTarget.stapmWatts)/$($batteryTarget.fastWatts)/$($batteryTarget.slowWatts)"
        AcTarget = "$($acTarget.stapmWatts)/$($acTarget.fastWatts)/$($acTarget.slowWatts)"
        LastAppliedTarget = "$($state.lastAppliedTarget.stapmWatts)/$($state.lastAppliedTarget.fastWatts)/$($state.lastAppliedTarget.slowWatts)"
        LastAttemptSucceeded = $state.lastAttemptSucceeded
        PolicyDisabled = "PASS"
        Shutdown = "PASS"
        RecordedAt = (Get-Date).ToString("o")
    }

    if ($EvidencePath) {
        $evidenceDirectory = Split-Path -Parent $EvidencePath
        if ($evidenceDirectory) {
            New-Item -ItemType Directory -Path $evidenceDirectory -Force | Out-Null
        }
        $result |
            ConvertTo-Json -Depth 6 |
            Set-Content -LiteralPath $EvidencePath -Encoding UTF8
    }
    [pscustomobject]$result | Format-List
}
finally {
    Stop-NativeWorker -Process $process -PipePath $pipePath
}
