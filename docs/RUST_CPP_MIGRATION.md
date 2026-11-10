# Rust GUI + C++ Worker Migration

Status: `IN_PROGRESS`

This document records the migration away from the current C# WinForms GUI and
C# worker. The current verified deployment remains `C:\RyzenAdj` version
`1.0.4`; migration work must not modify that directory or replace it until the
native build passes the same release and hardware gates.

## Target Split

- Rust owns the GUI process, window lifecycle, tray/notification area,
  single-instance behavior, user preferences, and the named-pipe client.
- C++ owns the privileged worker process, RyzenAdj/WinRing0 calls, hardware
  capability probing, read-back verification, and safe restoration.
- The existing version 1 JSON-lines named-pipe contract remains the migration
  contract until a versioned replacement is explicitly designed and tested.
- The C# implementation remains the stable fallback during migration.

## Migration Phases

1. Build and test a Rust named-pipe client against the current v1 worker.
2. Build a C++ worker skeleton with `getHealth` and graceful `shutdown`.
3. Port capability and snapshot reads to C++ with no hardware writes.
4. Port validated target application with mandatory read-back and restore.
5. Implement the Rust GUI and tray lifecycle against the C++ worker.
6. Package both native executables and run the existing release gates.
7. Promote only after the same no-change hardware test, UI lifecycle checks,
   diagnostics, and rollback backup pass.

## Non-Negotiable Gates

- No GUI or worker migration change may weaken the current read-only default.
- Hardware writes remain behind both the worker flag and a user action.
- Every write requires read-back verification and a recovery path.
- The worker must reject unsupported platforms instead of probing blindly.
- The Rust lifecycle must pass three minimize/restore cycles, close-to-tray,
  second-instance wake-up, and zero new application crash events.
- The packaged native build must preserve third-party notices and checksums.

## Current Slice

The first migration slice adds:

- `native/rust-gui`: a dependency-free lifecycle state machine for window
  visibility, taskbar/tray behavior, queued single-instance wake-up, and
  explicit exit. It is covered by unit tests before any Win32 calls are added.
- `native/rust-probe`: a dependency-light Rust named-pipe client that sends
  `getHealth` and parses the v1 response.
- `native/cpp-worker`: a Windows named-pipe worker skeleton that implements
  `getHealth`, read-only `getCapabilities`/`getSnapshot`, structured
  unsupported-command responses, and `shutdown`.
- `native/build.ps1`: locates the Visual Studio CMake toolchain and builds both
  native components.
- `native/verify-native.ps1`: proves the Rust probe can talk to the C++ skeleton
  and, when present, the stable C# worker. `-VerifyHardware` additionally proves
  the C++ worker can perform a read-only RyzenAdj capability and telemetry read
  with graceful shutdown.

The C++ skeleton intentionally has no hardware adapter yet. It is a transport
and process-boundary milestone, not a replacement for the stable worker.

The Rust GUI lifecycle layer intentionally separates `MinimizeWindow` from
`HideWindow`. A minimized window remains in the taskbar; only close, `--tray`,
or an explicit hide request moves it to the notification area. A second
instance queues a wake request for the UI thread instead of manipulating the
window from the pipe callback thread.
