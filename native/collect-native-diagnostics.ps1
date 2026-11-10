param(
    [string]$OutputPath
)

$ErrorActionPreference = "Stop"

$root = Split-Path -Parent $PSCommandPath
$workerExecutable = Join-Path $root "amdmobilepower_native_worker.exe"
if (-not (Test-Path -LiteralPath $workerExecutable)) {
    throw "Native worker was not found beside this collector: $workerExecutable"
}

function Invoke-NativeWorkerCommand {
    param(
        [string]$PipeName,
        [string]$Command
    )

    $pipe = [System.IO.Pipes.NamedPipeClientStream]::new(
        ".",
        $PipeName,
        [System.IO.Pipes.PipeDirection]::InOut)
    try {
        $pipe.Connect(3000)
        $utf8 = [System.Text.UTF8Encoding]::new($false)
        $writer = [System.IO.StreamWriter]::new($pipe, $utf8, 1024, $true)
        $reader = [System.IO.StreamReader]::new($pipe, $utf8, $false, 1024, $true)
        try {
            $writer.AutoFlush = $true
            $request = @{
                protocolVersion = 1
                requestId = "native-collector-$([Guid]::NewGuid().ToString('N'))"
                command = $Command
                payload = $null
            } | ConvertTo-Json -Compress
            $writer.WriteLine($request)
            $line = $reader.ReadLine()
            if ([string]::IsNullOrWhiteSpace($line)) {
                throw "Worker closed the pipe without a response for $Command."
            }
            $response = $line | ConvertFrom-Json
            if ($response.success -ne $true) {
                throw "$($response.error.code): $($response.error.message)"
            }
            return $response.payload
        }
        finally {
            $reader.Dispose()
            $writer.Dispose()
        }
    }
    finally {
        $pipe.Dispose()
    }
}

function Get-BuildInfo {
    $path = Join-Path $root "BUILD-INFO.txt"
    $result = @{}
    if (Test-Path -LiteralPath $path) {
        foreach ($line in Get-Content -LiteralPath $path) {
            if ($line -match "^([^=]+)=(.*)$") {
                $result[$Matches[1]] = $Matches[2]
            }
        }
    }
    return $result
}

$pipeName = "AmdMobilePower.NativeCollector.$([Guid]::NewGuid().ToString('N'))"
$workerProcess = Start-Process `
    -FilePath $workerExecutable `
    -WorkingDirectory $root `
    -ArgumentList @("--pipe-name", $pipeName, "--enable-hardware") `
    -WindowStyle Hidden `
    -PassThru

$health = $null
$capabilities = $null
$snapshot = $null
$collectionError = $null
try {
    $deadline = [DateTime]::UtcNow.AddSeconds(10)
    while ([DateTime]::UtcNow -lt $deadline) {
        $workerProcess.Refresh()
        if ($workerProcess.HasExited) {
            throw "Native worker exited before collection: $($workerProcess.ExitCode)"
        }
        try {
            $health = Invoke-NativeWorkerCommand -PipeName $pipeName -Command "getHealth"
            break
        }
        catch {
            Start-Sleep -Milliseconds 150
        }
    }
    if ($null -eq $health) {
        throw "Native worker did not answer getHealth."
    }

    $capabilities = Invoke-NativeWorkerCommand -PipeName $pipeName -Command "getCapabilities"
    $snapshot = Invoke-NativeWorkerCommand -PipeName $pipeName -Command "getSnapshot"
}
catch {
    $collectionError = $_.Exception.Message
}
finally {
    try {
        if ($null -ne $health) {
            $null = Invoke-NativeWorkerCommand -PipeName $pipeName -Command "shutdown"
            $workerProcess.WaitForExit(5000) | Out-Null
        }
    }
    catch {
    }
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

$build = Get-BuildInfo
$platform = if ($null -ne $capabilities) { $capabilities.platform } else { $null }
$telemetry = if ($null -ne $snapshot) { $snapshot.telemetry } else { $null }
$report = [ordered]@{
    schemaVersion = 1
    reportType = "amd-mobile-power-native-compatibility"
    collectionStatus = if ($collectionError) { "FAILED" } else { "PASS" }
    collectedAt = (Get-Date).ToString("o")
    package = [ordered]@{
        name = $build["Name"]
        version = $build["Version"]
        sourceCommit = $build["Commit"]
    }
    environment = [ordered]@{
        os = [System.Environment]::OSVersion.VersionString
        architecture = [System.Runtime.InteropServices.RuntimeInformation]::OSArchitecture.ToString()
        powerShell = $PSVersionTable.PSVersion.ToString()
    }
    worker = [ordered]@{
        status = if ($null -ne $health) { $health.status } else { $null }
        version = if ($null -ne $health) { $health.workerVersion } else { $null }
        hardwareInitialized = if ($null -ne $health) {
            $health.hardwareInitialized
        }
        else {
            $false
        }
        writeControlsEnabled = $false
    }
    platform = if ($null -ne $platform) {
        [ordered]@{
            processorName = $platform.cpu.processorName.Trim()
            vendor = $platform.cpu.vendor
            ryzenAdjFamily = $platform.cpu.ryzenAdjFamily
            ryzenAdjFamilyName = $platform.cpu.ryzenAdjFamilyName
            smuBiosVersion = $platform.cpu.smuBiosVersion
            pmTableVersion = $platform.cpu.pmTableVersion
            isSupported = $platform.isSupported
            unsupportedReason = $platform.unsupportedReason
            limits = $platform.limits
            profile = $platform.matchedProfile
        }
    }
    else {
        $null
    }
    telemetry = if ($null -ne $telemetry) {
        [ordered]@{
            powerLine = $telemetry.powerLine
            targetWatts = $telemetry.targetWatts
            stapmLimitWatts = $telemetry.stapmLimitWatts
            fastLimitWatts = $telemetry.fastLimitWatts
            slowLimitWatts = $telemetry.slowLimitWatts
            tctlValueCelsius = $telemetry.tctlValueCelsius
            tctlLimitCelsius = $telemetry.tctlLimitCelsius
            hasFirmwareClamp = $telemetry.hasFirmwareClamp
            updatedAt = $telemetry.updatedAt
        }
    }
    else {
        $null
    }
    error = $collectionError
}

if ([string]::IsNullOrWhiteSpace($OutputPath)) {
    $desktop = [Environment]::GetFolderPath("Desktop")
    $OutputPath = Join-Path `
        $desktop `
        "amd-mobile-power-native-compatibility-$((Get-Date).ToString('yyyyMMdd-HHmmss')).json"
}
$outputDirectory = Split-Path -Parent $OutputPath
if ($outputDirectory) {
    New-Item -ItemType Directory -Path $outputDirectory -Force | Out-Null
}
$report |
    ConvertTo-Json -Depth 10 |
    Set-Content -LiteralPath $OutputPath -Encoding UTF8

[pscustomobject]@{
    CollectionStatus = $report.collectionStatus
    OutputPath = $OutputPath
    Processor = if ($null -ne $platform) {
        $platform.cpu.processorName.Trim()
    }
    else {
        $null
    }
    RyzenAdjFamily = if ($null -ne $platform) {
        $platform.cpu.ryzenAdjFamily
    }
    else {
        $null
    }
    PowerLine = if ($null -ne $telemetry) { $telemetry.powerLine } else { $null }
    Error = $collectionError
} | Format-List

if ($collectionError) {
    exit 1
}
