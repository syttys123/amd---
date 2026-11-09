# Architecture

## Processes

### AmdMobilePower.Gui

- Runs at the current user's privilege level.
- Owns the main window, tray icon, settings, presets, and notifications.
- Never accesses the hardware driver directly.
- Sends validated commands to the worker through a named pipe.
- Starts hidden with `--tray` at login.

### AmdMobilePower.Worker

- Runs from a scheduled task or service with the minimum privileges required by
  RyzenAdj.
- Owns the RyzenAdj handle and periodic hardware refresh.
- Applies AC and battery targets.
- Publishes telemetry snapshots to the GUI.
- Rejects invalid or unsupported commands.
- Restores a safe prior state when a hardware test ends.

### AmdMobilePower.Core

- Shared contracts and models.
- No WinForms dependency.
- No direct scheduled-task or tray code.
- Contains pure validation and parsing logic suitable for unit tests.

## IPC

Use a named pipe:

```text
\\.\pipe\AmdMobilePower.Worker
```

Protocol requirements:

- Versioned request and response messages.
- Explicit timeout and cancellation.
- No arbitrary command-line execution.
- Commands are limited to status, apply mode, refresh telemetry, set presets,
  restart worker, and export diagnostics.
- All commands have request IDs and structured errors.

## Data Locations

Installed mode:

```text
%ProgramData%\AmdMobilePower\config.json
%ProgramData%\AmdMobilePower\profiles\
%ProgramData%\AmdMobilePower\logs\
%LocalAppData%\AmdMobilePower\ui-state.json
```

Portable mode:

```text
<app>\data\config.json
<app>\data\logs\
```

## Development and Stable Deployment

```text
D:\amd-mobile-power    source, tests, CI, experimental builds
C:\RyzenAdj            current verified stable deployment
```

Promotion is one-way. Stable deployment files are never edited as source.

## Capability Detection

The worker reports:

- CPU family/model name.
- SMU BIOS interface version.
- PM table version.
- Supported limit fields.
- Writable and read-only parameters.
- AC and battery state.
- Requested and effective values.

The GUI must show unsupported capabilities rather than writing blindly.

## Hardware Safety

- No skin-temperature, current, voltage, or clock changes in the initial scope.
- Apply only STAPM, Fast, and Slow power limits.
- Read back every value.
- If a firmware clamp is detected, keep the command successful but surface the
  effective limit and warning.
- Use conservative defaults and a hard user-configurable ceiling.

## Packaging

- GUI and worker target Windows x64.
- Worker and hardware dependencies remain separate from the GUI executable.
- The portable ZIP includes a README and checksums.
- The installer creates the scheduled task and tray startup entry.

