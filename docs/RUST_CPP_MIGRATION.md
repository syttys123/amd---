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
  explicit exit. The Win32 shell now uses that state machine for a real window,
  notification-area icon, tray menu, and second-instance wake-up. Unit tests
  cover the state machine and `verify-rust-gui.ps1` covers the live lifecycle.
  The GUI also contains a v1 named-pipe worker client and a one-second
  read-only status loop. It normalizes short pipe names to `\\.\pipe\...`,
  starts the C++ worker from the executable directory when present, displays
  CPU/family/PM table/power source/STAPM/Fast/Slow/temperature, and never
  exposes a hardware write command.
- `native/cpp-worker`: the worker now has a pure `power_limit_policy` layer
  that validates 5-60 W targets, requires Fast/Slow support, performs
  read-back verification, tolerates independently rejected STAPM, and restores
  the previous limits when a required write or read-back fails. The policy tests
  use a fake backend and cover eight success, clamp, partial-write, read-back,
  restore-failure, invalid-target, unsupported-platform, and invalid-previous
  state cases.
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

`native/build.ps1` stages a development `gui-runtime` directory containing the
Rust GUI, C++ worker, RyzenAdj DLL, WinRing0 DLL/SYS, and InpOut DLL. The
`-VerifyWorker` gate starts the staged pair and verifies the GUI displays a live
read-only snapshot.

The native worker's `applyTarget` command is implemented but disabled unless
`--enable-write-controls` is passed in addition to `--enable-hardware`.
Out-of-range targets are rejected before any DLL write call. A real hardware
write/read-back gate is separate from the read-only migration gate. The first
supervised no-change test on the 8845HS wrote the current AC `45/45/45 W` state
back, read back `45/45/45 W`, and shut down without restore; see
`docs/evidence/hardware/mechrevo-wujie15-8845hs-native-no-change-2026-11-10T12-16-14Z.json`.

The Rust GUI now exposes the same gate: without `--enable-write-controls` it is
read-only. With the flag it shows 12 W, 25 W, and 45 W presets plus Apply, and
runs the write in a background thread so the window and tray remain responsive.
The 45 W preset was exercised as a supervised no-change apply on the 8845HS;
see
`docs/evidence/hardware/mechrevo-wujie15-8845hs-native-gui-no-change-2026-11-10T12-24-30Z.json`.

`native/build-package.ps1` creates a portable native preview ZIP with the GUI,
C++ worker, runtime DLL/SYS files, notices, licenses, build metadata, and
checksums. It extracts the ZIP and reruns the lifecycle/read-only/write-control
UI gates before reporting success.
