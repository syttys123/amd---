param(
    [switch]$NoBuild,
    [switch]$VerifyHardware,
    [string]$ExistingWorkerDirectory = "C:\RyzenAdj\worker"
)

$ErrorActionPreference = "Stop"

$root = Split-Path -Parent $PSCommandPath
$repositoryRoot = Split-Path -Parent $root

if (-not $NoBuild) {
    & (Join-Path $root "build.ps1")
}

$cppWorker = Join-Path `
    $repositoryRoot `
    "artifacts\native-build\cpp-worker\Release\amdmobilepower_native_worker.exe"
$rustProbe = Join-Path `
    $root `
    "rust-probe\target\release\amd-mobile-power-probe.exe"
if (-not (Test-Path -LiteralPath $cppWorker)) {
    throw "C++ worker was not built: $cppWorker"
}
if (-not (Test-Path -LiteralPath $rustProbe)) {
    throw "Rust probe was not built: $rustProbe"
}

function Invoke-NativeWorkerProbe {
    param(
        [string]$Executable,
        [string]$WorkingDirectory,
        [string[]]$Arguments,
        [string]$Label
    )

    $pipeSuffix = [Guid]::NewGuid().ToString("N")
    $pipeName = "AmdMobilePower.NativeVerify.$pipeSuffix"
    $pipePath = "\\.\pipe\$pipeName"
    $processArguments = @($Arguments) + @("--pipe-name", $pipeName)
    $process = Start-Process `
        -FilePath $Executable `
        -WorkingDirectory $WorkingDirectory `
        -ArgumentList $processArguments `
        -WindowStyle Hidden `
        -PassThru
    try {
        $deadline = [DateTime]::UtcNow.AddSeconds(8)
        $health = $null
        while ([DateTime]::UtcNow -lt $deadline) {
            $process.Refresh()
            if ($process.HasExited) {
                throw "$Label worker exited before the probe: $($process.ExitCode)"
            }
            $output = & $rustProbe --pipe-name $pipePath --command getHealth 2>&1
            if ($LASTEXITCODE -eq 0) {
                $health = ($output | Out-String).Trim()
                break
            }
            Start-Sleep -Milliseconds 150
        }
        if ([string]::IsNullOrWhiteSpace($health)) {
            throw "$Label worker did not answer getHealth."
        }

        $shutdown = & $rustProbe --pipe-name $pipePath --command shutdown 2>&1
        if ($LASTEXITCODE -ne 0) {
            throw "$Label worker shutdown probe failed: $shutdown"
        }
        if (-not $process.WaitForExit(5000)) {
            throw "$Label worker did not exit after shutdown."
        }

        return [pscustomobject]@{
            Label = $Label
            Health = $health
            Shutdown = ($shutdown | Out-String).Trim()
            ExitCode = $process.ExitCode
        }
    }
    finally {
        try {
            $process.Refresh()
            if (-not $process.HasExited) {
                $process.Kill($true)
                $process.WaitForExit(5000) | Out-Null
            }
        }
        catch {
        }
        $process.Dispose()
    }
}

$cppResult = Invoke-NativeWorkerProbe `
    -Executable $cppWorker `
    -WorkingDirectory (Split-Path -Parent $cppWorker) `
    -Arguments @() `
    -Label "C++ skeleton"

$existingWorker = Join-Path $ExistingWorkerDirectory "AmdMobilePower.Worker.exe"
$existingResult = $null
if (Test-Path -LiteralPath $existingWorker) {
    $existingResult = Invoke-NativeWorkerProbe `
        -Executable $existingWorker `
        -WorkingDirectory $ExistingWorkerDirectory `
        -Arguments @() `
        -Label "Existing C# worker"
}

$hardwareResult = $null
if ($VerifyHardware) {
    $hardwareWorker = Join-Path `
        $repositoryRoot `
        "artifacts\native-build\worker-runtime\amdmobilepower_native_worker.exe"
    if (-not (Test-Path -LiteralPath $hardwareWorker)) {
        throw "Native hardware worker was not staged: $hardwareWorker"
    }

    $suffix = [Guid]::NewGuid().ToString("N")
    $pipeName = "AmdMobilePower.NativeHardware.$suffix"
    $pipePath = "\\.\pipe\$pipeName"
    $hardwareProcess = Start-Process `
        -FilePath $hardwareWorker `
        -WorkingDirectory (Split-Path -Parent $hardwareWorker) `
        -ArgumentList @("--pipe-name", $pipeName, "--enable-hardware") `
        -WindowStyle Hidden `
        -PassThru
    try {
        $deadline = [DateTime]::UtcNow.AddSeconds(8)
        $health = $null
        while ([DateTime]::UtcNow -lt $deadline) {
            $hardwareProcess.Refresh()
            if ($hardwareProcess.HasExited) {
                throw "Native hardware worker exited before the probe: $($hardwareProcess.ExitCode)"
            }
            $output = & $rustProbe --pipe-name $pipePath --command getHealth 2>&1
            if ($LASTEXITCODE -eq 0) {
                $health = ($output | Out-String).Trim()
                break
            }
            Start-Sleep -Milliseconds 150
        }
        if ([string]::IsNullOrWhiteSpace($health)) {
            throw "Native hardware worker did not answer getHealth."
        }
        if ($health -notmatch "hardware=true") {
            throw "Native hardware worker did not report an initialized hardware backend."
        }

        $capabilitiesText = & $rustProbe --pipe-name $pipePath --command getCapabilities 2>&1
        if ($LASTEXITCODE -ne 0) {
            throw "Native hardware capabilities probe failed: $capabilitiesText"
        }
        $snapshotText = & $rustProbe --pipe-name $pipePath --command getSnapshot 2>&1
        if ($LASTEXITCODE -ne 0) {
            throw "Native hardware snapshot probe failed: $snapshotText"
        }

        $capabilities = ($capabilitiesText | Out-String).Trim() | ConvertFrom-Json
        $snapshot = ($snapshotText | Out-String).Trim() | ConvertFrom-Json
        if ($capabilities.platform.isSupported -ne $true) {
            throw "Native hardware worker did not report a supported platform."
        }
        if ($capabilities.platform.limits.supportsAny -ne $true) {
            throw "Native hardware worker did not report supported limits."
        }
        if ($snapshot.telemetry.powerLine -notin @("ac", "battery")) {
            throw "Native hardware snapshot did not report AC or battery."
        }
        if ($null -eq $snapshot.telemetry.fastLimitWatts -or
            $null -eq $snapshot.telemetry.slowLimitWatts) {
            throw "Native hardware snapshot did not report Fast/Slow limits."
        }

        $shutdown = & $rustProbe --pipe-name $pipePath --command shutdown 2>&1
        if ($LASTEXITCODE -ne 0) {
            throw "Native hardware shutdown probe failed: $shutdown"
        }
        if (-not $hardwareProcess.WaitForExit(5000)) {
            throw "Native hardware worker did not exit after shutdown."
        }

        $hardwareResult = [pscustomobject]@{
            Health = $health
            Processor = $capabilities.platform.cpu.processorName
            Family = $capabilities.platform.cpu.ryzenAdjFamily
            FamilyName = $capabilities.platform.cpu.ryzenAdjFamilyName
            PmTableVersion = $capabilities.platform.cpu.pmTableVersion
            PowerLine = $snapshot.telemetry.powerLine
            StapmLimitWatts = $snapshot.telemetry.stapmLimitWatts
            FastLimitWatts = $snapshot.telemetry.fastLimitWatts
            SlowLimitWatts = $snapshot.telemetry.slowLimitWatts
            Shutdown = ($shutdown | Out-String).Trim()
        }
    }
    finally {
        try {
            $hardwareProcess.Refresh()
            if (-not $hardwareProcess.HasExited) {
                $hardwareProcess.Kill($true)
                $hardwareProcess.WaitForExit(5000) | Out-Null
            }
        }
        catch {
        }
        $hardwareProcess.Dispose()
    }
}

[pscustomobject]@{
    Verification = "PASS"
    CppWorker = $cppResult.Health
    CppShutdown = $cppResult.Shutdown
    ExistingWorker = if ($existingResult) {
        $existingResult.Health
    }
    else {
        "Not found"
    }
    ExistingShutdown = if ($existingResult) {
        $existingResult.Shutdown
    }
    else {
        "Not run"
    }
    NativeHardware = if ($hardwareResult) { "PASS" } else { "Not requested" }
    HardwareProcessor = if ($hardwareResult) {
        $hardwareResult.Processor
    }
    else {
        $null
    }
    HardwareFamily = if ($hardwareResult) {
        "$($hardwareResult.Family) $($hardwareResult.FamilyName)"
    }
    else {
        $null
    }
    HardwarePmTable = if ($hardwareResult) {
        $hardwareResult.PmTableVersion
    }
    else {
        $null
    }
    HardwarePowerLine = if ($hardwareResult) {
        $hardwareResult.PowerLine
    }
    else {
        $null
    }
    HardwareLimitsWatts = if ($hardwareResult) {
        "$($hardwareResult.StapmLimitWatts)/$($hardwareResult.FastLimitWatts)/$($hardwareResult.SlowLimitWatts)"
    }
    else {
        $null
    }
    HardwareShutdown = if ($hardwareResult) {
        $hardwareResult.Shutdown
    }
    else {
        "Not run"
    }
} | Format-List
