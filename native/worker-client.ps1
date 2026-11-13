# Shared named-pipe client for the native worker.
#
# Windows PowerShell 5.1 strips the quotes from JSON passed as a native-command
# argument, so `probe.exe --payload-json {..}` arrives malformed. Verifiers that
# need to send a payload use this client instead and keep the JSON intact.

function Invoke-WorkerPipeRequest {
    param(
        [Parameter(Mandatory = $true)]
        [string]$PipeName,
        [Parameter(Mandatory = $true)]
        [string]$Command,
        $Payload = $null,
        [int]$ConnectTimeoutMilliseconds = 10000
    )

    $name = $PipeName
    if ($name.StartsWith("\\.\pipe\")) {
        $name = $name.Substring(9)
    }

    $client = $null
    $deadline = [DateTime]::UtcNow.AddMilliseconds($ConnectTimeoutMilliseconds)
    while ($true) {
        try {
            $client = New-Object System.IO.Pipes.NamedPipeClientStream(
                ".",
                $name,
                [System.IO.Pipes.PipeDirection]::InOut)
            $client.Connect(1000)
            break
        }
        catch {
            if ($null -ne $client) {
                try { $client.Dispose() } catch { }
                $client = $null
            }
            if ([DateTime]::UtcNow -gt $deadline) {
                throw "cannot connect to worker pipe $PipeName : $($_.Exception.Message)"
            }
            Start-Sleep -Milliseconds 100
        }
    }

    $writer = $null
    $reader = $null
    try {
        $requestId = [Guid]::NewGuid().ToString("N")
        $request = @{
            protocolVersion = 1
            requestId       = $requestId
            command         = $Command
            payload         = $Payload
        } | ConvertTo-Json -Depth 12 -Compress

        $writer = New-Object System.IO.StreamWriter($client)
        $writer.AutoFlush = $true
        $reader = New-Object System.IO.StreamReader($client)
        $writer.WriteLine($request)
        $line = $reader.ReadLine()
        if ([string]::IsNullOrWhiteSpace($line)) {
            throw "worker closed the pipe before answering $Command"
        }
        $response = $line | ConvertFrom-Json
        if ($response.protocolVersion -ne 1) {
            throw "unexpected protocol version $($response.protocolVersion) for $Command"
        }
        if ($response.requestId -ne $requestId) {
            throw "requestId mismatch for $Command"
        }

        $errorCode = $null
        $errorMessage = $null
        if (-not $response.success -and $null -ne $response.error) {
            $errorCode = [string]$response.error.code
            $errorMessage = [string]$response.error.message
        }
        return [pscustomobject]@{
            Success      = [bool]$response.success
            Payload      = $response.payload
            ErrorCode    = $errorCode
            ErrorMessage = $errorMessage
            ErrorText    = if ($errorCode) {
                "${errorCode}: $errorMessage"
            }
            elseif ($errorMessage) {
                $errorMessage
            }
            else {
                $null
            }
        }
    }
    finally {
        if ($null -ne $reader) {
            try { $reader.Dispose() } catch { }
        }
        if ($null -ne $writer) {
            try { $writer.Dispose() } catch { }
        }
        if ($null -ne $client) {
            try { $client.Dispose() } catch { }
        }
    }
}

function Invoke-ProbeProcess {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ProbePath,
        [Parameter(Mandatory = $true)]
        [string]$PipePath,
        [Parameter(Mandatory = $true)]
        [string]$Command,
        [int]$TimeoutMilliseconds = 15000
    )

    # PowerShell 5.1 turns a native command's stderr into a terminating error
    # when ErrorActionPreference is Stop, which breaks startup polling while
    # the pipe does not exist yet. Collect stdout+stderr without throwing.
    $previous = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    try {
        $output = & $ProbePath --pipe-name $PipePath --command $Command 2>&1
        $code = $LASTEXITCODE
    }
    finally {
        $ErrorActionPreference = $previous
    }
    return [pscustomobject]@{
        ExitCode = $code
        Output = ($output | Out-String).Trim()
    }
}
