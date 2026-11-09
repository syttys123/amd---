# Worker IPC Protocol

## Transport

```text
\\.\pipe\AmdMobilePower.Worker.v1
```

The pipe is restricted to the current Windows user. Both directions use UTF-8
JSON Lines:

- One request is one JSON object followed by `\n`.
- One response is one JSON object followed by `\n`.
- Unknown fields are ignored by `System.Text.Json`.
- Requests carry a unique `requestId`.
- Every response contains the same `requestId`.

## Request

```json
{
  "protocolVersion": 1,
  "requestId": "a-unique-id",
  "command": "getHealth",
  "payload": null
}
```

## Response

Success:

```json
{
  "protocolVersion": 1,
  "requestId": "a-unique-id",
  "success": true,
  "payload": {
    "status": "ok",
    "protocolVersion": 1,
    "workerVersion": "0.1.0",
    "processId": 1234,
    "startedAt": "2026-11-09T10:00:00+08:00",
    "uptimeSeconds": 4.5,
    "hardwareInitialized": false
  },
  "error": null
}
```

Failure:

```json
{
  "protocolVersion": 1,
  "requestId": "a-unique-id",
  "success": false,
  "payload": null,
  "error": {
    "code": "unsupported_command",
    "message": "Command ApplyTarget is not available yet."
  }
}
```

## Commands

| Command | Status | Hardware access |
|---|---|---|
| `getHealth` | implemented | no |
| `getCapabilities` | implemented; requires the opt-in hardware adapter | probe only |
| `getSnapshot` | implemented; requires the opt-in hardware adapter | read only |
| `applyTarget` | implemented; mock-tested, hardware smoke pending | read/write |
| `refreshTelemetry` | reserved | yes |
| `setPresets` | reserved | no |
| `exportDiagnostics` | implemented | read-only |
| `restartWorker` | reserved | no |
| `shutdown` | reserved | no |

## Development

Run the worker with an isolated pipe:

```powershell
dotnet run --project src/AmdMobilePower.Worker -- --pipe-name AmdMobilePower.Dev
```

The integration tests start an isolated pipe and verify health and structured
error responses without touching hardware.

