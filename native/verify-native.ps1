param(
    [switch]$NoBuild,
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
} | Format-List
