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
        (Join-Path $PSScriptRoot "worker\WinRing0x64.sys"),
        "C:\RyzenAdj\WinRing0x64.sys",
        "D:\amd-mobile-power\src\AmdMobilePower.Worker\bin\Release\net8.0-windows\WinRing0x64.sys"
    )
    $DriverSource = $candidates |
        Where-Object { Test-Path -LiteralPath $_ } |
        Select-Object -First 1
}

if (-not $DriverSource -or -not (Test-Path -LiteralPath $DriverSource)) {
    throw "WinRing0x64.sys was not found. Pass -DriverSource explicitly."
}

$driverSourcePath = (Resolve-Path -LiteralPath $DriverSource).Path
$driverDirectory = Join-Path $env:ProgramData "AmdMobilePower\driver"
$driverTargetPath = Join-Path $driverDirectory "WinRing0x64.sys"
New-Item -ItemType Directory -Path $driverDirectory -Force | Out-Null
Copy-Item -LiteralPath $driverSourcePath -Destination $driverTargetPath -Force

$service = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
if ($service) {
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
else {
    & sc.exe create $ServiceName type= kernel start= demand error= normal binPath= "\??\$driverTargetPath" | Out-Null
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to create driver service $ServiceName."
    }
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
