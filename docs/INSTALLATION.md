# Installation And Recovery

## Release Status

AMD Mobile Power is not publicly released. Local packages are development
artifacts. The normal executable, installed copy, and portable package run in
read-only mode and must not be presented as production write-control software.

## Supported Host

- Windows 10 or Windows 11, x64.
- A supported AMD mobile CPU with a readable RyzenAdj PM table.
- No separate .NET runtime is required for the self-contained package.

See `SUPPORTED_HARDWARE.md` for the current, intentionally narrow hardware
scope.

## Portable Use

1. Extract the entire ZIP to a writable directory.
2. Run `AmdMobilePower.exe`.
3. Keep `worker`, `profiles`, and the RyzenAdj DLL/driver files beside the GUI.

The GUI starts the worker as a hidden child process. Do not launch the worker
directly during normal use.

## User Installation

From an extracted package:

```powershell
.\install.ps1
```

The install script:

- Copies the package to
  `%LocalAppData%\Programs\AmdMobilePower` by default.
- Creates a Start menu shortcut.
- Creates a current-user logon task named `AmdMobilePower`.
- Falls back to a Startup shortcut if task creation fails.
- Registers a current-user uninstall entry.
- Preserves `%LocalAppData%\AmdMobilePower\ui-state.json` during upgrades.

Use `-InstallDirectory` to select another destination. Paths at a filesystem
root or with fewer than two segments below the root are rejected.

## Upgrade

Run the new package's `install.ps1`. It stops only AMD Mobile Power processes
whose executable paths are inside the selected install directory, replaces the
application files, and preserves user state.

Do not upgrade `C:\RyzenAdj` in place. Development upgrades stay under
`D:\amd-mobile-power`; stable promotion follows `DEPLOYMENT.md` and requires a
recoverable backup.

## Uninstall

```powershell
.\uninstall.ps1
```

The uninstaller removes the install directory, logon task, Start menu shortcut,
Startup shortcut, and current-user uninstall entry.

User data under `%LocalAppData%\AmdMobilePower` remains unless
`-RemoveUserData` is supplied. Diagnostics files are also user data.

## Recovery

If the new GUI cannot start:

1. Exit `RyzenPower`, `ryzenadj`, and AMD Ryzen Master.
2. Confirm that only one AMD Mobile Power GUI is running.
3. Check that the worker directory contains all runtime files.
4. Revert to the last known stable deployment instead of editing stable files.
5. Record the error and diagnostics export before changing the test state.

If a hardware write test fails, follow the abort criteria in
`HARDWARE_TEST_PROCEDURE.md`. Do not continue changing limits.

## Troubleshooting

### Hardware owner conflict

The GUI reports a process such as `RyzenPower` when another tool already owns
the RyzenAdj hardware interface. Exit that tool before retrying. Do not run two
RyzenAdj-based owners concurrently.

If the message names `RyzenAdjPowerWorker` or `RyzenAdjWatch`, closing the old
GUI was not enough: the legacy logon task still has a hidden worker. Stop the
task before retrying:

```powershell
Stop-ScheduledTask -TaskName "RyzenAdjWatch" -TaskPath "\AMD\"
```

Stopping a task changes the legacy tool's behavior. Preserve its directory and
configuration, and restore the task explicitly if you need to return to the old
deployment.

### Security software blocks the driver

RyzenAdj requires low-level Windows driver access. Security software may block
or unload WinRing0. Do not disable security controls just to make a development
build run. Record the conflict and continue on a controlled test machine.

### Read-only controls

The default GUI and package intentionally show locked power controls. See
`SECURITY.md`; ordinary users should not enable write controls before the
supervised hardware gate is complete.
