# Security And Hardware Safety

## Current Boundary

AMD Mobile Power changes firmware-facing CPU power limits through RyzenAdj and
low-level Windows driver interfaces. Incorrect values can cause overheating,
instability, shutdowns, battery wear, data loss, or hardware damage.

Public releases are blocked until the third-party driver redistribution review
is resolved. Development packages are not production-ready.

## Default Read-Only Mode

The GUI defaults to read-only. Hardware writes require both:

- `AmdMobilePower.Gui.exe --enable-write-controls`
- The GUI passing `--enable-write-controls` to the worker

The worker also requires `--enable-hardware`. A normal package launch passes
only `--enable-hardware`, so `applyTarget` and policy writes are rejected.

This is a deliberate double gate, not a claim that the GUI cannot display
writable capabilities.

## Single Hardware Owner

The worker:

- Detects known owners including `RyzenPower`, `ryzenadj`, and AMD Ryzen Master.
- Detects the legacy `Local\RyzenAdjPowerWorker` mutex used by the PowerShell
  worker.
- Detects running legacy scheduled tasks including `\AMD\RyzenAdjWatch`,
  `\AMD\RyzenAdj`, `\AMD\RyzenAdjApply`, and `\AMD\RyzenAdjToggle`.
- Acquires `Local\AmdMobilePower.HardwareOwner.v1`.
- Refuses to start when another known owner or AMD Mobile Power worker exists.

Do not bypass this protection. Concurrent RyzenAdj owners have caused an
uncatchable native access violation during development. Closing the legacy GUI
is not sufficient when its logon task still has a hidden worker running.

If an owning worker must be force-terminated, treat the WinRing0/inpout/SMU
state as tainted. Reboot before probing or writing again; repeated calls can
raise `AccessViolationException` inside `init_ryzenadj`.

Restarting the WinRing0 and inpout services does not reliably clear this state.
On the development laptop both services restarted successfully, but
`ryzenadj.exe --info` still hung in SMU polling.

The GUI treats a hardware-read timeout as a terminal worker fault for the
current application session. It stops the unresponsive worker and does not
automatically relaunch it, preventing a crash/restart loop.

## Write Validation

When write controls are explicitly enabled, the worker:

- Validates the target against the profile and reported capabilities.
- Writes STAPM, Fast, and Slow together.
- Refreshes the PM table and reads every value back.
- Reports firmware clamps separately from transport success.
- Attempts to restore the previous three-value target after a write or
  read-back failure.

The first real hardware write test must use the current limit triplet, so a
successful test does not intentionally change the power profile. See
`HARDWARE_TEST_PROCEDURE.md`.

## Process And IPC Model

- The GUI runs at the current user's privilege level.
- The worker is a hidden child process launched by the GUI.
- The named pipe uses `PipeOptions.CurrentUserOnly`.
- Commands are a fixed enum; there is no arbitrary shell execution endpoint.
- Requests and responses use versioned UTF-8 JSON Lines with request IDs.

The current implementation does not install a privileged Windows service or
elevate the worker.

## Data And Diagnostics

- UI presets and policy live in
  `%LocalAppData%\AmdMobilePower\ui-state.json`.
- Diagnostics are saved under
  `%LocalAppData%\AmdMobilePower\diagnostics` by default.
- Diagnostics include hardware capability, telemetry, OS/process architecture,
  executable directory, and runtime-file hashes.
- Diagnostics do not include credentials or provider secrets.

Review diagnostics before attaching them to a public issue. Device names, paths,
and firmware versions may still be sensitive.

## Driver And License Risk

RyzenAdj is LGPL-3.0. The Windows driver components bundled by its upstream
project require separate redistribution and safety review. Review
`THIRD_PARTY_NOTICES.md` before publishing a binary.

## Public-Release Gate

Do not publish or promote write-capable builds until:

- The supervised no-change write test passes.
- Initial and final STAPM/Fast/Slow limits match.
- Process cleanup and conflict behavior are verified.
- The driver redistribution review is complete.
- A recovery procedure has been tested on the target device.
