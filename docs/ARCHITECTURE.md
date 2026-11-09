# Architecture

This document separates the current implementation from the longer-term target.
`DEV_STATUS.md` and the source tree remain authoritative when behavior differs.

## Processes

### AmdMobilePower.Gui

- Runs at the current user's privilege level.
- Owns the main window, tray icon, settings, presets, and notifications.
- Never accesses the hardware driver directly.
- Sends validated commands to the worker through a named pipe.
- Starts visibly on a normal launch or hidden with `--tray` at login.
- Defaults to read-only. `--enable-write-controls` is a development-only
  override.
- Starts the worker as a hidden child process when a pipe command cannot reach
  an existing worker.

### AmdMobilePower.Worker

- Currently runs as a hidden child of the GUI at the current user's privilege
  level. A privileged service or scheduled-task worker is a future deployment
  option, not current behavior.
- Owns the RyzenAdj handle and periodic hardware refresh.
- Applies validated STAPM, PPT Fast, and PPT Slow targets when both hardware and
  write-control flags are enabled.
- Publishes telemetry snapshots to the GUI.
- Rejects invalid or unsupported commands.
- Detects known hardware owners and holds
  `Local\AmdMobilePower.HardwareOwner.v1`.
- Attempts to restore all three previous limits when a write or read-back
  fails.

### AmdMobilePower.Core

- Shared contracts and models.
- No WinForms dependency.
- No direct scheduled-task or tray code.
- Contains pure validation and parsing logic suitable for unit tests.
- Contains the named-pipe client, hardware conflict detection, profiles, and
  telemetry parsing.

## IPC

Use a named pipe:

```text
\\.\pipe\AmdMobilePower.Worker.v1
```

Protocol requirements:

- Versioned request and response messages.
- Explicit timeout and cancellation.
- No arbitrary command-line execution.
- The pipe uses `PipeOptions.CurrentUserOnly`.
- All commands have request IDs and structured errors.

Implemented commands:

- `getHealth`
- `getCapabilities`
- `getSnapshot`
- `applyTarget` when the worker write flag is enabled
- `getPowerPolicy`
- `setPowerPolicy` when the worker write flag is enabled
- `exportDiagnostics`

`refreshTelemetry`, `setPresets`, `restartWorker`, and `shutdown` are reserved
protocol names but are not implemented commands. See `IPC.md`.

## Data Locations

Current installed and portable mode:

```text
%LocalAppData%\AmdMobilePower\ui-state.json
%LocalAppData%\AmdMobilePower\diagnostics\
```

RyzenAdj profiles are read from `worker\profiles` in packaged builds. The
current implementation has no persistent worker config, ProgramData directory,
or diagnostic log file.

Future service or machine-wide deployment may use:

```text
%ProgramData%\AmdMobilePower\config.json
%ProgramData%\AmdMobilePower\profiles\
%ProgramData%\AmdMobilePower\logs\
<app>\data\config.json
<app>\data\logs\
```

## Development and Stable Deployment

```text
D:\amd-mobile-power    source, tests, CI, experimental builds
C:\RyzenAdj            legacy stable deployment and current hardware owner
```

Promotion is one-way and is currently blocked by the supervised hardware-write,
driver-license, and runtime-verification gates. Stable deployment files are
never edited as source.

## Capability Detection

The worker reports:

- CPU family/model name.
- SMU BIOS interface version.
- PM table version.
- Supported limit fields.
- AC and battery state.
- Requested and effective values.
- Separate firmware-limit readback for STAPM, Fast, and Slow.

The GUI must show unsupported capabilities rather than writing blindly.

## Hardware Safety

- No skin-temperature, current, voltage, or clock changes in the initial scope.
- Apply only STAPM, Fast, and Slow power limits.
- Read back every value.
- If a firmware clamp is detected, keep the command successful but surface the
  effective limit and warning.
- Use conservative defaults and a hard user-configurable ceiling.
- Refuse concurrent ownership with known RyzenAdj-based tools or another
  AMD Mobile Power worker.

## Packaging

- GUI and worker target Windows x64.
- Worker and hardware dependencies remain separate from the GUI executable.
- The portable ZIP includes a README and checksums.
- The installer creates the current-user logon task and tray startup entry.
- Development packages launch read-only by default.

