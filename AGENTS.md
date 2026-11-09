# AMD Mobile Power Maintenance Guide

## Start Every Work Session

1. Read `docs/DEV_STATUS.md`.
2. Read `docs/ROADMAP.md`.
3. Read `docs/ARCHITECTURE.md`.
4. Inspect `git status`, the current branch, and recent commits.
5. Pick one small, testable milestone. Do not reopen completed work without evidence.

## Development and Stable Deployment

- Development root: `D:\amd-mobile-power`.
- Stable deployment root: `C:\RyzenAdj`.
- All source edits, tests, and experimental builds happen under `D:\`.
- `C:\RyzenAdj` is a deployment target only. Replace it only after automated
  tests and the relevant hardware smoke test pass.
- Keep the previous stable deployment recoverable until the new package passes
  launch, worker, tray, and power-mode verification.
- Do not develop directly in `C:\RyzenAdj`.

At the end of every meaningful work session, update `docs/DEV_STATUS.md` with:

- What changed.
- What was verified.
- What remains incomplete.
- New risks or hardware observations.
- The next concrete task.

## Project Goal

Build a maintainable, open-source Windows application for controlling and
monitoring power limits on supported AMD laptops, especially thin-and-light
models. The application must detect platform capabilities, explain firmware
limits instead of pretending every write succeeded, and degrade safely on
unsupported hardware.

The project is not affiliated with AMD.

## Architecture Rules

- `AmdMobilePower.Gui` is a user-level WinForms application. It owns the window,
  tray icon, presets, and user interaction.
- `AmdMobilePower.Worker` is the privileged background process. It is the only
  component allowed to call RyzenAdj.
- `AmdMobilePower.Core` contains shared contracts, profile models, telemetry
  parsing, named pipe protocols, and validation.
- GUI and worker communicate through a named pipe. Do not add new shared text
  files as an IPC mechanism.
- Long-lived configuration belongs under `%ProgramData%\AmdMobilePower`.
  User preferences belong under `%LocalAppData%\AmdMobilePower`.
- Portable builds may use a local `data` directory only when the user explicitly
  selects portable mode.
- The current stable compatibility deployment is `C:\RyzenAdj`. It may be
  replaced by a verified package built under `D:\amd-mobile-power`.
- Closing the GUI hides it to the notification area. Only the tray `Exit`
  command terminates the GUI.

## Hardware Safety

- Never write skin temperature, current, voltage, clock, or overclock limits
  unless a concrete feature and safety review require it.
- Every write must be followed by a read-back.
- If the requested limit differs from the effective limit, report the firmware
  limit clearly.
- Hardware tests must restore the prior mode in a `finally` path.
- Unsupported CPUs, PM tables, or missing parameters must produce diagnostics,
  not blind writes.
- Do not claim support for "all AMD laptops." Maintain a verified compatibility
  matrix and distinguish verified, experimental, and unsupported platforms.

## Third-Party Components

- RyzenAdj is a third-party LGPL project. Preserve source, license, and notice
  obligations.
- `WinRing0` and similar kernel drivers may trigger antivirus/security warnings.
  Do not hide this from users.
- Before publishing release artifacts, complete `docs/THIRD_PARTY_NOTICES.md`.

## Build and Verification

Primary target is Windows x64 with .NET 8. The repository may build with newer
SDKs installed locally.

Required before merging user-visible changes:

```powershell
dotnet build AmdMobilePower.sln -c Release
dotnet test AmdMobilePower.sln -c Release
```

Hardware verification cannot run in CI. Record manual hardware evidence in
`docs/HARDWARE_MATRIX.md`.

## Git and Release

- Use focused commits with prefixes such as `feat:`, `fix:`, `docs:`, `build:`,
  and `test:`.
- Do not commit build output, logs, local configuration, or machine-specific
  telemetry.
- Push only when the working tree and verification state are understood.
- Preparing documentation, screenshots, and video assets is allowed after a
  release candidate exists.
- Final public release and Bilibili upload require a completed release checklist
  and an authenticated account session. Do not automate account login.

