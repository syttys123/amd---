param(
    [string]$OutputPath,
    [ValidateRange(5, 60)]
    [int]$StartupTimeoutSeconds = 15
)

$ErrorActionPreference = "Stop"

if (-not $IsWindows -and $PSVersionTable.PSEdition -ne "Desktop") {
    throw "This collector requires Windows PowerShell 5.1 or PowerShell 7 on Windows."
}

$packageRoot = Split-Path -Parent $PSCommandPath
$workerExecutable = Join-Path $packageRoot "worker\AmdMobilePower.Worker.exe"
if (-not (Test-Path -LiteralPath $workerExecutable)) {
    throw "Packaged worker not found: $workerExecutable"
}

function Protect-LocalText {
    param([AllowNull()][object]$Value)

    if ($null -eq $Value) {
        return $null
    }

    $text = [string]$Value
    $replacements = @(
        @{ Path = $temporaryDirectory; Token = "<diagnostics-temp>" },
        @{ Path = $packageRoot; Token = "<package-root>" },
        @{ Path = $env:LOCALAPPDATA; Token = "<local-app-data>" },
        @{ Path = $env:APPDATA; Token = "<app-data>" },
        @{ Path = $env:USERPROFILE; Token = "<user-profile>" },
        @{ Path = $env:TEMP; Token = "<temp>" },
        @{ Path = $env:TMP; Token = "<temp>" }
    )
    foreach ($replacement in $replacements) {
        if ([string]::IsNullOrWhiteSpace($replacement.Path)) {
            continue
        }
        $text = [regex]::Replace(
            $text,
            [regex]::Escape($replacement.Path),
            $replacement.Token,
            [Text.RegularExpressions.RegexOptions]::IgnoreCase)
    }

    $text = [regex]::Replace(
        $text,
        '(?i)(?<![A-Za-z0-9])[A-Z]:[\\/](?:[^\\/\r\n"''<>|]+[\\/])*[^\\/\r\n"''<>|]*',
        '<local-path>')
    $text = [regex]::Replace(
        $text,
        '(?i)(?<![A-Za-z0-9])\\\\[^\\/\r\n"''<>|]+[\\/][^\\/\r\n"''<>|]+(?:[\\/][^\\/\r\n"''<>|]*)*',
        '<network-path>')
    return $text
}

function Protect-ReportValue {
    param([AllowNull()][object]$Value)

    if ($null -eq $Value) {
        return $null
    }
    if ($Value -is [string]) {
        return Protect-LocalText $Value
    }
    if ($Value -is [System.Collections.IDictionary]) {
        $copy = [ordered]@{}
        foreach ($key in $Value.Keys) {
            $copy[$key] = Protect-ReportValue $Value[$key]
        }
        return $copy
    }
    if ($Value -is [System.Collections.IEnumerable]) {
        $items = @($Value | ForEach-Object { Protect-ReportValue $_ })
        return ,$items
    }
    if ($Value -is [pscustomobject]) {
        $copy = [ordered]@{}
        foreach ($property in $Value.PSObject.Properties) {
            $copy[$property.Name] = Protect-ReportValue $property.Value
        }
        return $copy
    }
    return $Value
}

if ([string]::IsNullOrWhiteSpace($OutputPath)) {
    $desktop = [Environment]::GetFolderPath("Desktop")
    $outputDirectory = if ($desktop -and (Test-Path -LiteralPath $desktop)) {
        $desktop
    }
    else {
        (Get-Location).Path
    }
    $OutputPath = Join-Path $outputDirectory (
        "amd-mobile-power-diagnostics-" +
        (Get-Date -Format "yyyyMMdd-HHmmss") +
        ".json")
}
elseif (-not [IO.Path]::IsPathRooted($OutputPath)) {
    $OutputPath = [IO.Path]::GetFullPath((Join-Path (Get-Location) $OutputPath))
}
else {
    $OutputPath = [IO.Path]::GetFullPath($OutputPath)
}

$outputDirectoryPath = Split-Path -Parent $OutputPath
if (-not (Test-Path -LiteralPath $outputDirectoryPath)) {
    New-Item -ItemType Directory -Path $outputDirectoryPath -Force | Out-Null
}

$runId = [Guid]::NewGuid().ToString("N")
$pipeName = "AmdMobilePower.Diagnostics.$runId"
$workerProcess = $null
$temporaryDirectory = Join-Path $env:TEMP ("amd-mobile-power-diagnostics-" + $runId)
New-Item -ItemType Directory -Path $temporaryDirectory -Force | Out-Null
$stdoutPath = Join-Path $temporaryDirectory "worker.stdout.log"
$stderrPath = Join-Path $temporaryDirectory "worker.stderr.log"
$shutdownResult = "NOT_REQUESTED"

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
        $pipeName,
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
            $writer.WriteLine(($request | ConvertTo-Json -Depth 12 -Compress))
            $responseJson = $reader.ReadLine()
            if ([string]::IsNullOrWhiteSpace($responseJson)) {
                throw "Worker closed the pipe without a response."
            }
            $response = $responseJson | ConvertFrom-Json
            if ($response.requestId -ne $requestId) {
                throw "Worker response requestId did not match."
            }
            if (-not $response.success) {
                throw "Worker command $Command failed [$($response.error.code)]: $($response.error.message)"
            }
            return $response.payload
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

function Wait-WorkerHealth {
    $deadline = [DateTimeOffset]::UtcNow.AddSeconds($StartupTimeoutSeconds)
    $lastError = $null
    while ([DateTimeOffset]::UtcNow -lt $deadline) {
        if ($workerProcess.HasExited) {
            $stderr = if (Test-Path -LiteralPath $stderrPath) {
                (Get-Content -LiteralPath $stderrPath -Raw).Trim()
            }
            else {
                ""
            }
            throw "Worker exited during startup with code $($workerProcess.ExitCode). $stderr"
        }
        try {
            return Invoke-WorkerRequest -Command "getHealth" -TimeoutMilliseconds 700
        }
        catch {
            $lastError = $_
            Start-Sleep -Milliseconds 200
        }
    }

    throw "Worker did not become healthy within $StartupTimeoutSeconds seconds: $(
        $lastError.Exception.Message
    )"
}

function Stop-Worker {
    if ($null -eq $workerProcess) {
        return
    }
    if (-not $workerProcess.HasExited) {
        try {
            Invoke-WorkerRequest -Command "shutdown" -TimeoutMilliseconds 3000 | Out-Null
            if (-not $workerProcess.WaitForExit(5000)) {
                throw "Worker did not exit within five seconds after shutdown."
            }
            $script:shutdownResult = "PASS"
        }
        catch {
            if (-not $workerProcess.HasExited) {
                $workerProcess.Kill()
                $workerProcess.WaitForExit(5000) | Out-Null
            }
            $script:shutdownResult = "FALLBACK_PROCESS_TERMINATION"
        }
    }
}

function Convert-RuntimeFile {
    param([object]$File)

    return [ordered]@{
        name = $File.name
        present = $File.present
        sizeBytes = $File.sizeBytes
        sha256 = $File.sha256
        error = $File.error
    }
}

function Convert-StringArray {
    param([AllowNull()][object]$Value)

    if ($null -eq $Value) {
        return ,([string[]]@())
    }
    return ,([string[]]@($Value))
}

function Convert-Profile {
    param([object]$Profile)

    if ($null -eq $Profile) {
        return $null
    }

    $converted = [ordered]@{
        schemaVersion = $Profile.schemaVersion
        id = $Profile.id
        displayName = $Profile.displayName
        cpuFamilyPatterns = Convert-StringArray $Profile.cpuFamilyPatterns
        processorNamePatterns = Convert-StringArray $Profile.processorNamePatterns
        pmTablePatterns = Convert-StringArray $Profile.pmTablePatterns
        minimumWatts = $Profile.minimumWatts
        maximumWatts = $Profile.maximumWatts
        defaultWatts = $Profile.defaultWatts
        supportsStapm = $Profile.supportsStapm
        supportsFast = $Profile.supportsFast
        supportsSlow = $Profile.supportsSlow
        notes = Convert-StringArray $Profile.notes
    }
    if ($null -eq $Profile.schemaVersion) {
        $converted.Remove("schemaVersion")
    }
    return $converted
}

function Convert-Platform {
    param([object]$Platform)

    if ($null -eq $Platform) {
        return $null
    }

    return [ordered]@{
        isSupported = $Platform.isSupported
        unsupportedReason = Protect-LocalText $Platform.unsupportedReason
        cpu = [ordered]@{
            processorName = $Platform.cpu.processorName
            vendor = $Platform.cpu.vendor
            family = $Platform.cpu.family
            model = $Platform.cpu.model
            ryzenAdjFamily = $Platform.cpu.ryzenAdjFamily
            ryzenAdjFamilyName = $Platform.cpu.ryzenAdjFamilyName
            smuBiosVersion = $Platform.cpu.smuBiosVersion
            pmTableVersion = $Platform.cpu.pmTableVersion
        }
        limits = [ordered]@{
            supportsStapm = $Platform.limits.supportsStapm
            supportsFast = $Platform.limits.supportsFast
            supportsSlow = $Platform.limits.supportsSlow
            supportsAny = $Platform.limits.supportsAny
        }
    }
}

function Convert-Telemetry {
    param([object]$Telemetry)

    if ($null -eq $Telemetry) {
        return $null
    }

    return [ordered]@{
        targetWatts = $Telemetry.targetWatts
        stapmValueWatts = $Telemetry.stapmValueWatts
        fastValueWatts = $Telemetry.fastValueWatts
        slowValueWatts = $Telemetry.slowValueWatts
        stapmLimitWatts = $Telemetry.stapmLimitWatts
        fastLimitWatts = $Telemetry.fastLimitWatts
        slowLimitWatts = $Telemetry.slowLimitWatts
        tctlValueCelsius = $Telemetry.tctlValueCelsius
        tctlLimitCelsius = $Telemetry.tctlLimitCelsius
        powerLine = $Telemetry.powerLine
        updatedAt = $Telemetry.updatedAt
        hasFirmwareClamp = $Telemetry.hasFirmwareClamp
    }
}

$bios = Get-CimInstance Win32_BIOS -ErrorAction SilentlyContinue
$computer = Get-CimInstance Win32_ComputerSystem -ErrorAction SilentlyContinue
$operatingSystem = Get-CimInstance Win32_OperatingSystem -ErrorAction SilentlyContinue
$report = [ordered]@{
    schemaVersion = 1
    evidenceType = "amd-mobile-power-compatibility-diagnostics"
    generatedAt = [DateTimeOffset]::Now
    collectionStatus = "INCOMPLETE"
    error = $null
    privacy = [ordered]@{
        localPathsIncluded = $false
        processIdIncluded = $false
        accountNamesIncluded = $false
        serialNumbersIncluded = $false
        recentLogsIncluded = $false
        networkUploadPerformed = $false
    }
    host = [ordered]@{
        manufacturer = $computer.Manufacturer
        model = $computer.Model
        biosVersion = $bios.SMBIOSBIOSVersion
        windowsEdition = $operatingSystem.Caption
        windowsVersion = $operatingSystem.Version
        windowsBuild = $operatingSystem.BuildNumber
        powerShell = $PSVersionTable.PSVersion.ToString()
    }
    worker = [ordered]@{}
    platform = $null
    matchedProfile = $null
    telemetry = $null
    runtimeFiles = @()
    profiles = @()
    notes = @()
    cleanup = [ordered]@{
        shutdownProtocol = "NOT_REQUESTED"
    }
    submission = [ordered]@{
        instructions = "Review the JSON, then attach it to a compatibility issue. This collector never uploads data."
        template = "https://github.com/syttys123/amd-mobile-power/blob/main/docs/COMPATIBILITY_REPORT_TEMPLATE.md"
        issueUrl = "https://github.com/syttys123/amd-mobile-power/issues"
    }
}

try {
    $arguments = "--pipe-name `"$pipeName`" --enable-hardware"
    $workerProcess = Start-Process `
        -FilePath $workerExecutable `
        -WorkingDirectory (Split-Path -Parent $workerExecutable) `
        -ArgumentList $arguments `
        -WindowStyle Hidden `
        -RedirectStandardOutput $stdoutPath `
        -RedirectStandardError $stderrPath `
        -PassThru
    if ($null -eq $workerProcess) {
        throw "Could not start the packaged worker."
    }

    $health = Wait-WorkerHealth
    $diagnostics = Invoke-WorkerRequest -Command "exportDiagnostics" -TimeoutMilliseconds 12000

    $report.worker = [ordered]@{
        version = $diagnostics.workerVersion
        architecture = $diagnostics.processArchitecture
        operatingSystem = $diagnostics.operatingSystem
        schemaVersion = $diagnostics.schemaVersion
        protocolVersion = $diagnostics.protocolVersion
        hardwareAdapterConfigured = $diagnostics.hardwareAdapterConfigured
        writeControlsEnabled = $diagnostics.writeControlsEnabled
        workerExecutableSha256 = $diagnostics.workerExecutableSha256
        healthStatus = $health.status
    }
    $report.platform = Convert-Platform $diagnostics.platform
    $report.matchedProfile = Convert-Profile $diagnostics.matchedProfile
    $report.telemetry = Convert-Telemetry $diagnostics.telemetry
    $report.runtimeFiles = @(
        $diagnostics.runtimeFiles |
            ForEach-Object { Convert-RuntimeFile $_ }
    )
    $report.profiles = @(
        $diagnostics.profiles |
            ForEach-Object { Convert-Profile $_ }
    )
    $notes = @(
        $diagnostics.notes |
            ForEach-Object { Protect-LocalText $_ }
    )
    $report.notes = Convert-StringArray $notes
    if ($diagnostics.writeControlsEnabled) {
        throw "The diagnostic worker unexpectedly enabled hardware writes."
    }
    $report.collectionStatus = "PASS"
}
catch {
    $report.collectionStatus = "FAIL"
    $report.error = $_.Exception.Message
}
finally {
    Stop-Worker
    $report.cleanup.shutdownProtocol = $shutdownResult
    $report = Protect-ReportValue $report
    $json = $report | ConvertTo-Json -Depth 20
    [IO.File]::WriteAllText(
        $OutputPath,
        $json,
        [Text.UTF8Encoding]::new($false))
    if (Test-Path -LiteralPath $temporaryDirectory) {
        Remove-Item -LiteralPath $temporaryDirectory -Recurse -Force
    }
}

[pscustomobject]@{
    Result = $report.collectionStatus
    Output = $OutputPath
    PlatformSupported = $report.platform.isSupported
    HardwareAdapterConfigured = $report.worker.hardwareAdapterConfigured
    WriteControlsEnabled = $report.worker.writeControlsEnabled
    ShutdownProtocol = $report.cleanup.shutdownProtocol
    Error = $report.error
} | Format-List

if ($report.collectionStatus -ne "PASS") {
    exit 1
}

exit 0
