#Requires -RunAsAdministrator
param(
    [string]$DriverSource = "",
    [string]$ServiceName = "WinRing0_1_2_0",
    [string]$TaskPath = "\AmdMobilePower\",
    [string]$TaskName = "StartWinRing0"
)

$ErrorActionPreference = "Stop"

if ([string]::IsNullOrWhiteSpace($DriverSource)) {
    $candidates = @(
        (Join-Path $PSScriptRoot "WinRing0x64.sys"),
        (Join-Path $PSScriptRoot "worker\WinRing0x64.sys")
    )
    $DriverSource = $candidates |
        Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } |
        Select-Object -First 1
}

if ([string]::IsNullOrWhiteSpace($DriverSource) -or
    -not (Test-Path -LiteralPath $DriverSource -PathType Leaf)) {
    throw "WinRing0x64.sys was not found beside the package. Pass -DriverSource explicitly."
}

$driverSourcePath = (Resolve-Path -LiteralPath $DriverSource).Path
if ([System.IO.Path]::GetExtension($driverSourcePath) -ne ".sys") {
    throw "DriverSource must point to a .sys file: $driverSourcePath"
}
$driverDirectory = Join-Path $env:ProgramData "AmdMobilePower\driver"
$driverTargetPath = Join-Path $driverDirectory "WinRing0x64.sys"
New-Item -ItemType Directory -Path $driverDirectory -Force | Out-Null
Copy-Item -LiteralPath $driverSourcePath -Destination $driverTargetPath -Force

$service = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
$servicePath = $null
if ($null -ne $service) {
    $driver = Get-CimInstance `
        -ClassName Win32_SystemDriver `
        -Filter "Name='$ServiceName'" `
        -ErrorAction SilentlyContinue
    $servicePath = if ($null -ne $driver) {
        ([string]$driver.PathName) -replace "^\\\?\?\\", ""
    }
    else {
        $null
    }
}

$normalizedServicePath = if ([string]::IsNullOrWhiteSpace($servicePath)) {
    $null
}
else {
    [System.IO.Path]::GetFullPath($servicePath)
}
$normalizedTargetPath = [System.IO.Path]::GetFullPath($driverTargetPath)
$serviceUsesOurDriver = $null -ne $normalizedServicePath -and
    $normalizedServicePath.Equals(
        $normalizedTargetPath,
        [System.StringComparison]::OrdinalIgnoreCase)
$serviceIsAnotherWinRing0 = $null -ne $normalizedServicePath -and
    [System.IO.Path]::GetFileName($normalizedServicePath).Equals(
        "WinRing0x64.sys",
        [System.StringComparison]::OrdinalIgnoreCase)
if ($null -ne $service -and -not $serviceUsesOurDriver -and
    -not $serviceIsAnotherWinRing0) {
    throw (
        "Service $ServiceName already belongs to $servicePath. " +
        "Refusing to replace a non-WinRing0 service.")
}

if ($serviceUsesOurDriver) {
    if ($service.Status -ne "Stopped") {
        & sc.exe stop $ServiceName | Out-Null
        if ($LASTEXITCODE -ne 0) {
            throw "Failed to stop driver service $ServiceName."
        }
    }

    & sc.exe config $ServiceName binPath= "\??\$driverTargetPath" start= demand | Out-Null
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to configure driver service $ServiceName."
    }
}
elseif ($serviceIsAnotherWinRing0) {
    # Another installation already provides the same WinRing0 device. Reuse it
    # instead of changing its service path out from under that installation.
}
else {
    & sc.exe create $ServiceName type= kernel start= demand error= normal binPath= "\??\$driverTargetPath" | Out-Null
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to create driver service $ServiceName."
    }
}

$finalDriver = Get-CimInstance `
    -ClassName Win32_SystemDriver `
    -Filter "Name='$ServiceName'" `
    -ErrorAction SilentlyContinue
$finalServicePath = if ($null -ne $finalDriver) {
    (([string]$finalDriver.PathName) -replace "^\\\?\?\\", "")
}
else {
    $null
}
if ([string]::IsNullOrWhiteSpace($finalServicePath)) {
    throw "Driver service $ServiceName has no readable binary path."
}
$normalizedFinalServicePath = [System.IO.Path]::GetFullPath($finalServicePath)
$expectedServicePath = if ($serviceUsesOurDriver -or $null -eq $service) {
    $normalizedTargetPath
}
else {
    $normalizedServicePath
}
if (-not $normalizedFinalServicePath.Equals(
    $expectedServicePath,
    [System.StringComparison]::OrdinalIgnoreCase)) {
    throw (
        "Driver service $ServiceName points at $normalizedFinalServicePath, " +
        "expected $expectedServicePath.")
}

$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$powershellPath = Join-Path $env:SystemRoot "System32\WindowsPowerShell\v1.0\powershell.exe"
$action = New-ScheduledTaskAction `
    -Execute $powershellPath `
    -Argument "-NoProfile -WindowStyle Hidden -Command `"Start-Service -Name '$ServiceName'`""
$trigger = New-ScheduledTaskTrigger -AtLogOn -User $identity.Name
$principal = New-ScheduledTaskPrincipal `
    -UserId $identity.Name `
    -LogonType Interactive `
    -RunLevel Highest
$settings = New-ScheduledTaskSettingsSet `
    -AllowStartIfOnBatteries `
    -DontStopIfGoingOnBatteries `
    -StartWhenAvailable `
    -MultipleInstances IgnoreNew

Register-ScheduledTask `
    -TaskName $TaskName `
    -TaskPath $TaskPath `
    -Action $action `
    -Trigger $trigger `
    -Principal $principal `
    -Settings $settings `
    -Description "Start the WinRing0 driver required by AMD Mobile Power." `
    -Force | Out-Null

Start-Service -Name $ServiceName
Get-Service -Name $ServiceName | Select-Object Name,Status,StartType
Get-ScheduledTask -TaskPath $TaskPath -TaskName $TaskName |
    Select-Object TaskPath,TaskName,State
