param(
    [string]$OutputPath,
    [string]$MarkdownPath
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
$profiles = $null
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
    $profiles = Invoke-NativeWorkerCommand -PipeName $pipeName -Command "getProfiles"
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
$computer = Get-CimInstance Win32_ComputerSystem -ErrorAction SilentlyContinue
$bios = Get-CimInstance Win32_BIOS -ErrorAction SilentlyContinue
$operatingSystem = Get-CimInstance Win32_OperatingSystem -ErrorAction SilentlyContinue
$report = [ordered]@{
    schemaVersion = 1
    reportType = "amd-mobile-power-native-compatibility"
    collectionStatus = if ($collectionError) { "FAILED" } else { "PASS" }
    collectedAt = (Get-Date).ToString("o")
    privacy = [ordered]@{
        localPathsIncluded = $false
        processIdIncluded = $false
        accountNamesIncluded = $false
        serialNumbersIncluded = $false
        recentLogsIncluded = $false
        networkUploadPerformed = $false
    }
    host = [ordered]@{
        manufacturer = if ($null -ne $computer) { $computer.Manufacturer } else { $null }
        model = if ($null -ne $computer) { $computer.Model } else { $null }
        biosVersion = if ($null -ne $bios) { $bios.SMBIOSBIOSVersion } else { $null }
        windowsEdition = if ($null -ne $operatingSystem) { $operatingSystem.Caption } else { $null }
        windowsVersion = if ($null -ne $operatingSystem) { $operatingSystem.Version } else { $null }
        windowsBuild = if ($null -ne $operatingSystem) { $operatingSystem.BuildNumber } else { $null }
    }
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
    profileCatalog = $profiles
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

if (-not [string]::IsNullOrWhiteSpace($MarkdownPath)) {
    $markdownDirectory = Split-Path -Parent $MarkdownPath
    if ($markdownDirectory) {
        New-Item -ItemType Directory -Path $markdownDirectory -Force | Out-Null
    }
    $processorName = if ($null -ne $platform) {
        $platform.cpu.processorName.Trim()
    }
    else {
        "Unavailable"
    }
    $familyName = if ($null -ne $platform) {
        "$($platform.cpu.ryzenAdjFamily) $($platform.cpu.ryzenAdjFamilyName)"
    }
    else {
        "Unavailable"
    }
    $profileName = if ($null -ne $platform -and $null -ne $platform.matchedProfile) {
        "$($platform.matchedProfile.id) [$($platform.matchedProfile.minimumWatts)-$($platform.matchedProfile.maximumWatts) W]"
    }
    else {
        "Unavailable"
    }
    $systemName = if ($null -ne $computer) {
        "$($computer.Manufacturer) $($computer.Model)".Trim()
    }
    else {
        "Unavailable"
    }
    $limitCapabilities = if ($null -ne $platform) {
        "STAPM=$($platform.limits.supportsStapm) Fast=$($platform.limits.supportsFast) " +
            "Slow=$($platform.limits.supportsSlow) any=$($platform.limits.supportsAny)"
    }
    else {
        "Unavailable"
    }
    $profileCatalogSummary = if ($null -ne $profiles) {
        $profileCount = @($profiles.profiles).Count
        $verifiedCount = @($profiles.profiles | Where-Object { $_.isVerified }).Count
        "$profileCount profiles, $verifiedCount verified"
    }
    else {
        "Unavailable"
    }
    $lines = @(
        "# AMD Mobile Power Compatibility Report",
        "",
        "- Collection status: ``$($report.collectionStatus)``",
        "- Collected at: $($report.collectedAt)",
        "- Package version: $($report.package.version)",
        "- Package source commit: $($report.package.sourceCommit)",
        "- System: $systemName",
        "- BIOS: $($report.host.biosVersion)",
        "- Windows: $($report.host.windowsEdition) $($report.host.windowsBuild)",
        "- CPU: $processorName",
        "- RyzenAdj family: $familyName",
        "- SMU BIOS interface: $(if ($null -ne $platform) { $platform.cpu.smuBiosVersion } else { 'Unavailable' })",
        "- PM table: $(if ($null -ne $platform) { $platform.cpu.pmTableVersion } else { 'Unavailable' })",
        "- Matched profile: $profileName",
        "- Profile catalog: $profileCatalogSummary",
        "- Platform supported: $(if ($null -ne $platform) { $platform.isSupported } else { $false })",
        "- Unsupported reason: $(if ($null -ne $platform -and $platform.unsupportedReason) { $platform.unsupportedReason } else { 'None' })",
        "- Limit capabilities: $limitCapabilities",
        "- Power line: $(if ($null -ne $telemetry) { $telemetry.powerLine } else { 'Unavailable' })",
        "- Worker version: $($report.worker.version)",
        "- Hardware initialized: $($report.worker.hardwareInitialized)",
        "- Write controls enabled: ``$($report.worker.writeControlsEnabled)``",
        "- STAPM limit: $(if ($null -ne $telemetry) { $telemetry.stapmLimitWatts } else { 'Unavailable' }) W",
        "- Fast limit: $(if ($null -ne $telemetry) { $telemetry.fastLimitWatts } else { 'Unavailable' }) W",
        "- Slow limit: $(if ($null -ne $telemetry) { $telemetry.slowLimitWatts } else { 'Unavailable' }) W",
        "- Temperature: $(if ($null -ne $telemetry) { $telemetry.tctlValueCelsius } else { 'Unavailable' }) C",
        "- Firmware clamp: $(if ($null -ne $telemetry) { $telemetry.hasFirmwareClamp } else { 'Unavailable' })",
        "- Error: $(if ($collectionError) { $collectionError } else { 'None' })",
        "",
        "This report was collected read-only. Review it for personal information before attaching it to a public issue."
    )
    $lines |
        Set-Content -LiteralPath $MarkdownPath -Encoding UTF8
}

[pscustomobject]@{
    CollectionStatus = $report.collectionStatus
    System = "$($report.host.manufacturer) $($report.host.model)".Trim()
    BiosVersion = $report.host.biosVersion
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
    ProfileCatalogCount = if ($null -ne $profiles) { @($profiles.profiles).Count } else { $null }
    MarkdownPath = $MarkdownPath
    Error = $collectionError
} | Format-List

if ($collectionError) {
    exit 1
}
