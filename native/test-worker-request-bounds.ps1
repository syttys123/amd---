param([string]$EvidencePath)
$ErrorActionPreference = 'Stop'
$repository = Split-Path -Parent (Split-Path -Parent $PSCommandPath)
$workerPath = Join-Path $repository 'artifacts\native-build\cpp-worker\Release\amdmobilepower_native_worker.exe'
$pipeName = "AmdMobilePower.RequestBounds.$([Guid]::NewGuid().ToString('N'))"
$worker = $null
function Send-Request([string]$Text, [switch]$ExpectDisconnect) {
    $pipe = [System.IO.Pipes.NamedPipeClientStream]::new('.', $pipeName, [System.IO.Pipes.PipeDirection]::InOut,
        [System.IO.Pipes.PipeOptions]::Asynchronous)
    try {
        $pipe.Connect(3000)
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($Text)
        $write = $pipe.WriteAsync($bytes, 0, $bytes.Length)
        try { if (-not $write.Wait(5000)) { throw 'Write timed out.' } }
        catch { if ($ExpectDisconnect) { return }; throw }
        if ($ExpectDisconnect) {
            $buffer = [byte[]]::new(1)
            try {
                $read = $pipe.ReadAsync($buffer, 0, 1)
                if (-not $read.Wait(5000)) { throw 'Oversized request was not disconnected.' }
                if ($read.Result -ne 0) { throw 'Oversized request received unexpected data.' }
            }
            catch {
                if ($_.Exception.ToString() -notmatch 'broken|closed|ended|断开|结束|关闭') { throw }
            }
            return
        }
        $reader = [System.IO.StreamReader]::new($pipe)
        try {
            $read = $reader.ReadLineAsync()
            if (-not $read.Wait(5000)) { throw 'Response timed out.' }
            $response = $read.Result | ConvertFrom-Json
            if (-not $response.success) { throw 'Health request failed.' }
        }
        finally { $reader.Dispose() }
    }
    finally { $pipe.Dispose() }
}
try {
    $worker = Start-Process -FilePath $workerPath -ArgumentList @('--pipe-name', $pipeName) -WindowStyle Hidden -PassThru
    $request = '{"protocolVersion":1,"requestId":"bounds","command":"getHealth","payload":null}'
    Send-Request ($request + "`n")
    foreach ($partial in @('', '{"command":')) {
        $slow = [System.IO.Pipes.NamedPipeClientStream]::new('.', $pipeName,
            [System.IO.Pipes.PipeDirection]::InOut, [System.IO.Pipes.PipeOptions]::Asynchronous)
        try {
            $slow.Connect(3000)
            if ($partial) {
                $bytes = [System.Text.Encoding]::UTF8.GetBytes($partial)
                $slow.Write($bytes, 0, $bytes.Length)
            }
            $timer = [System.Diagnostics.Stopwatch]::StartNew()
            $buffer = [byte[]]::new(1)
            $pending = $slow.ReadAsync($buffer, 0, 1)
            try {
                if (-not $pending.Wait(8000)) { throw 'Slow client exceeded the read deadline.' }
                if ($pending.Result -ne 0) { throw 'Incomplete request unexpectedly received data.' }
            }
            catch {
                if ($_.Exception.ToString() -notmatch 'broken|closed|ended|断开|结束|关闭') { throw }
            }
            if ($timer.Elapsed.TotalSeconds -lt 4 -or $timer.Elapsed.TotalSeconds -gt 8) {
                throw "Unexpected read deadline duration: $($timer.Elapsed.TotalSeconds)"
            }
        }
        finally { $slow.Dispose() }
        Send-Request ($request + "`n")
    }
    Send-Request (($request.TrimEnd('}') + ',"padding":"' + ('x' * 5000) + '"}') + "`n")
    Send-Request (('x' * 70000) + "`n") -ExpectDisconnect
    Send-Request ($request + "`n")
    $record = @{ Verification='PASS'; FragmentedRequestBytes=5000; OversizedRequestBytes=70000;
        HealthAfterOversize='PASS'; SlowClientDeadline='PASS'; SlowClientCases=2;
        HardwareEnabled=$false; RecordedAt=(Get-Date).ToString('o') }
}
finally {
    if ($worker) {
        try { $worker.Refresh(); if (-not $worker.HasExited) { $worker.Kill(); $worker.WaitForExit(5000) | Out-Null } }
        finally { $worker.Dispose() }
    }
}
if ($EvidencePath) { $record | ConvertTo-Json | Set-Content -LiteralPath $EvidencePath -Encoding utf8 }
$record | ConvertTo-Json
