#Requires -RunAsAdministrator
param(
    [string]$ServiceName = "WinRing0_1_2_0",
    [string]$TaskPath = "\AmdMobilePower\",
    [string]$TaskName = "StartWinRing0",
    [string]$DriverDirectory = (Join-Path $env:ProgramData "AmdMobilePower\driver")
)

$ErrorActionPreference = "Stop"

function Stop-DriverServiceAndWait {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name,
        [int]$TimeoutSeconds = 15
    )

    $service = Get-Service -Name $Name -ErrorAction Stop
    if ($service.Status -eq "Stopped") {
        return
    }
    & sc.exe stop $Name | Out-Null
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to stop driver service $Name."
    }
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    do {
        Start-Sleep -Milliseconds 250
        $service = Get-Service -Name $Name -ErrorAction SilentlyContinue
        if ($null -eq $service -or $service.Status -eq "Stopped") {
            return
        }
    } while ((Get-Date) -lt $deadline)
    throw "Timed out waiting for driver service $Name to stop; state=$($service.Status)."
}

$allowedRoot = [System.IO.Path]::GetFullPath(
    (Join-Path $env:ProgramData "AmdMobilePower"))
$resolvedDriverDirectory = [System.IO.Path]::GetFullPath($DriverDirectory)
$allowedPrefix = $allowedRoot.TrimEnd(
    [System.IO.Path]::DirectorySeparatorChar) +
    [System.IO.Path]::DirectorySeparatorChar
if (-not $resolvedDriverDirectory.StartsWith(
    $allowedPrefix,
    [System.StringComparison]::OrdinalIgnoreCase)) {
    throw "DriverDirectory must stay under $allowedRoot`: $resolvedDriverDirectory"
}
$driverTargetPath = Join-Path $resolvedDriverDirectory "WinRing0x64.sys"

$service = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
$driver = if ($null -ne $service) {
    Get-CimInstance `
        -ClassName Win32_SystemDriver `
        -Filter "Name='$ServiceName'" `
        -ErrorAction SilentlyContinue
}
else {
    $null
}
$servicePath = if ($null -ne $driver) {
    ([string]$driver.PathName) -replace "^\\\?\?\\", ""
}
else {
    $null
}
$normalizedServicePath = if ([string]::IsNullOrWhiteSpace($servicePath)) {
    $null
}
else {
    [System.IO.Path]::GetFullPath($servicePath)
}
$serviceOwnedByUs = $null -ne $normalizedServicePath -and
    $normalizedServicePath.Equals(
        [System.IO.Path]::GetFullPath($driverTargetPath),
        [System.StringComparison]::OrdinalIgnoreCase)

$serviceRemoved = $false
if ($null -ne $service -and $serviceOwnedByUs) {
    Stop-DriverServiceAndWait -Name $ServiceName
    & sc.exe delete $ServiceName | Out-Null
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to delete driver service $ServiceName."
    }
    $serviceRemoved = $true
}

$taskRemoved = $false
$task = Get-ScheduledTask `
    -TaskPath $TaskPath `
    -TaskName $TaskName `
    -ErrorAction SilentlyContinue
if ($null -ne $task) {
    Unregister-ScheduledTask `
        -TaskPath $TaskPath `
        -TaskName $TaskName `
        -Confirm:$false
    $taskRemoved = $true
}

$driverRemoved = $false
if (Test-Path -LiteralPath $driverTargetPath -PathType Leaf) {
    Remove-Item -LiteralPath $driverTargetPath -Force
    $driverRemoved = $true
}
if ((Test-Path -LiteralPath $resolvedDriverDirectory -PathType Container) -and
    -not (Get-ChildItem -LiteralPath $resolvedDriverDirectory -Force)) {
    Remove-Item -LiteralPath $resolvedDriverDirectory -Force
}

[pscustomobject]@{
    ServiceName = $ServiceName
    ServiceOwnedByUs = $serviceOwnedByUs
    ServiceRemoved = $serviceRemoved
    TaskRemoved = $taskRemoved
    DriverFileRemoved = $driverRemoved
    DriverPath = $driverTargetPath
} | Format-List
