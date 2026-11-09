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
- Acquires the named process-scoped event
  `Local\AmdMobilePower.HardwareOwner.v1`. A named event is used instead of a
  mutex because asynchronous shutdown may resume on another thread, while mutex
  ownership is thread-affine.
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

The same startup deadline applies while the worker is beginning to listen on
its named pipe. A worker that hangs before accepting commands is also stopped
and enters the terminal fault state.

## Write Validation

When write controls are explicitly enabled, the worker:

- Validates the target against the profile and reported capabilities.
- Writes Fast and Slow as the required enforcement pair and treats STAPM as a
  best-effort value because firmware may manage it dynamically.
- Refreshes the PM table and reads every value back.
- Requires Fast and Slow transport success and matching read-back before
  reporting a successful application.
- Reports firmware clamps separately from transport success.
- Attempts to restore the previous three-value target after a write or
  read-back failure.

Controlled 10 W and 12 W writes completed on the development laptop on
2026-11-10 and are recorded in `HARDWARE_MATRIX.md`. The packaged `0.1.3-dev`
GUI/worker also passed the separate 12 W no-change write gate with identical
initial, requested, read-back, and final STAPM/Fast/Slow limits. See
`docs/evidence/hardware/mechrevo-wujie15-8845hs-no-change-2026-11-10.json`.

USB-C power banks are often reported by Windows as AC/external power. The
automatic battery/AC policy cannot identify that case, so a power bank will use
the AC target. Prefer manual conservative targets when operating from a power
bank.

## Process And IPC Model

- The GUI runs at the current user's privilege level.
- The worker is a hidden child process launched by the GUI.
- The named pipe uses `PipeOptions.CurrentUserOnly`.
- Commands are a fixed enum; there is no arbitrary shell execution endpoint.
- Requests and responses use versioned UTF-8 JSON Lines with request IDs.

The current implementation does not elevate the worker. RyzenAdj still requires
the WinRing0 kernel driver. The development driver helper installs a small
current-user logon task whose only action is to start the already-installed
driver service with highest privileges. The GUI and worker remain non-elevated.

## Data And Diagnostics

- UI presets and policy live in
  `%LocalAppData%\AmdMobilePower\ui-state.json`.
- Diagnostics are saved under
  `%LocalAppData%\AmdMobilePower\diagnostics` by default.
- GUI and worker lifecycle/error logs are stored under
  `%LocalAppData%\AmdMobilePower\logs` with daily files and seven-day retention.
- GUI and portable-collector diagnostics include hardware capability,
  telemetry, OS/process architecture, and runtime-file hashes.
- Public diagnostic exports exclude executable/log directories, process IDs,
  account names, and recent log excerpts. Known paths and remaining absolute
  Windows/UNC paths are replaced with privacy tokens.
- Diagnostics do not include credentials or provider secrets.

Review diagnostics before attaching them to a public issue. Device names and
firmware versions may still be sensitive even after path redaction.

## Driver And License Risk

RyzenAdj is LGPL-3.0 and is loaded as a separate shared library. Packages include
the upstream LGPL text, the canonical GPL-3.0 text referenced by LGPL-3.0, a
pinned source commit, and instructions for replacing `worker\libryzenadj.dll`
with a compatible build. The bundled InpOut32 and WinRing0 terms are recorded in
`THIRD_PARTY_NOTICES.md` and `LICENSING_REVIEW.md`.

This is an engineering redistribution review, not a legal opinion. WinRing0
remains old kernel driver software and may be blocked or unloaded by Windows
security software; license compliance does not establish runtime safety.
Current host, signature, Defender, and service evidence is recorded in
`WINDOWS_DRIVER_SECURITY.md`.

## Public-Release Gate

Do not publish or promote write-capable builds until:

- The supervised no-change write test passes. Development 8845HS passed.
- Initial and final STAPM/Fast/Slow limits match. Development 8845HS passed at
  12/12/12 W.
- Process cleanup and conflict behavior are verified.
- The driver redistribution review is complete for the package contents
  recorded in `LICENSING_REVIEW.md`.
- A recovery procedure has been tested on the target device.
