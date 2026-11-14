param([string]$EvidencePath)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSCommandPath
$repository = Split-Path -Parent $root
$worker = Join-Path $repository 'artifacts\native-build\gui-runtime\amdmobilepower_native_worker.exe'
$gui = Join-Path $root 'rust-gui\target\release\amd-mobile-power-gui.exe'
$shell = (Get-Process -Id $PID).Path
$verify = $null
$sentinel = $null
$pipe = "AmdMobilePower.ScopeTest.$([Guid]::NewGuid().ToString('N'))"
try {
    $arguments = @('-NoProfile', '-File', (Join-Path $root 'verify-rust-gui.ps1'),
        '-NoBuild', '-VerifyWriteControls', '-UiFixture', 'firmware-clamp',
        '-VerifyResourceStability')
    $verify = Start-Process -FilePath $shell -ArgumentList $arguments -WindowStyle Hidden -PassThru
    $deadline = [DateTime]::UtcNow.AddSeconds(30)
    $observed = $false
    while ([DateTime]::UtcNow -lt $deadline) {
        $observed = [bool]@(Get-CimInstance Win32_Process -Filter "Name = 'amd-mobile-power-gui.exe'" |
            Where-Object { $_.ExecutablePath -eq $gui -and $_.ParentProcessId -eq $verify.Id }).Count
        if ($observed) { break }
        $verify.Refresh()
        if ($verify.HasExited) { throw 'Verifier exited before its isolated GUI started.' }
        Start-Sleep -Milliseconds 100
    }
    if (-not $observed) { throw 'Timed out observing the isolated verification GUI.' }
    # Starts after the verifier snapshots existing workers. No hardware flags.
    $sentinel = Start-Process -FilePath $worker -ArgumentList @('--pipe-name', $pipe) `
        -WindowStyle Hidden -PassThru
    Start-Sleep -Milliseconds 300
    $sentinel.Refresh()
    if ($sentinel.HasExited) { throw 'Independent worker failed to start.' }
    if (-not $verify.WaitForExit(120000)) { throw 'GUI verifier timed out.' }
    if ($verify.ExitCode -ne 0) { throw "GUI verifier failed: $($verify.ExitCode)" }
    $sentinel.Refresh()
    if ($sentinel.HasExited) { throw 'Verifier cleanup killed the unrelated concurrent worker.' }
    $record = [ordered]@{
        Verification = 'PASS'
        ConcurrentWorkerStartedAfterGui = $true
        ConcurrentWorkerSurvivedCleanup = $true
        HardwareEnabled = $false
        RecordedAt = (Get-Date).ToString('o')
    }
}
finally {
    foreach ($process in @($sentinel, $verify)) {
        if ($null -ne $process) {
            try {
                $process.Refresh()
                if (-not $process.HasExited) {
                    $process.Kill($true)
                    if (-not $process.WaitForExit(10000)) { throw 'Test process did not exit.' }
                }
            }
            finally { $process.Dispose() }
        }
    }
}
if ($EvidencePath) {
    $parent = Split-Path -Parent $EvidencePath
    if ($parent) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
    $record | ConvertTo-Json | Set-Content -LiteralPath $EvidencePath -Encoding utf8
}
$record | ConvertTo-Json
