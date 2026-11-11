# Installation And Recovery

## Release Status

AMD Mobile Power is not publicly released. Local packages are development
artifacts. The portable GUI and installed copy start read-only unless launched
with the explicit write-control flag.

The current native package is:

```text
amd-mobile-power-v1.0.8-native-win-x64-native-preview.zip
```

The earlier .NET `install.ps1` package is historical. Use the native
`install-preview.ps1` and driver scripts described below.

## Supported Host

- Windows 10 or Windows 11, x64.
- A supported AMD mobile CPU with a readable RyzenAdj PM table.
- No separate .NET runtime is required.

See `SUPPORTED_HARDWARE.md` for the intentionally narrow verified scope.

## Package Contents

Keep these files together after extraction:

- `amd-mobile-power-gui.exe`
- `amdmobilepower_native_worker.exe`
- `libryzenadj.dll`, `WinRing0x64.dll`, `WinRing0x64.sys`, and `inpoutx64.dll`
- `install-driver-bootstrap.ps1` and `uninstall-driver-bootstrap.ps1`
- `install-preview.ps1` and `uninstall-preview.ps1`
- `collect-native-diagnostics.ps1`
- licenses and third-party notices

Do not launch the worker directly during normal use. The GUI owns the worker
lifecycle and named-pipe connection.

## Portable Use

1. Extract the entire ZIP to a writable directory.
2. On a fresh Windows host, run the driver bootstrap from an elevated
   PowerShell in that directory.
3. Start `amd-mobile-power-gui.exe`.

Read-only launch:

```powershell
.\amd-mobile-power-gui.exe
```

Deliberate write-control launch:

```powershell
.\amd-mobile-power-gui.exe --enable-write-controls --simple-mode
```

Closing the window hides it to the notification area. Use the tray Exit command
to terminate the process.

## Driver Bootstrap

From an elevated PowerShell in the extracted package:

```powershell
.\install-driver-bootstrap.ps1
```

The helper:

- Copies `WinRing0x64.sys` to
  `%ProgramData%\AmdMobilePower\driver\WinRing0x64.sys`.
- Configures the `WinRing0_1_2_0` demand-start service.
- Reuses an existing valid WinRing0 service rather than replacing another
  installation's service path.
- Stops an app-owned running driver and waits for `Stopped` before replacing
  the `.sys` file.
- Creates the narrow `\AmdMobilePower\StartWinRing0` logon task.

The task elevates only `Start-Service`; it does not run the GUI or worker
elevated.

## Driver Cleanup

From an elevated PowerShell:

```powershell
.\uninstall-driver-bootstrap.ps1
```

The cleanup script removes the service only when its binary path equals this
package's ProgramData driver. It also removes the `StartWinRing0` task and the
ProgramData driver file. A WinRing0 service owned by another installation is
left untouched.

## User Installation

From an extracted package:

```powershell
.\install-preview.ps1
```

The preview installer:

- Stages the complete payload before switching directories.
- Copies the app to
  `%LocalAppData%\Programs\AmdMobilePowerNativePreview` by default.
- Preserves an existing marked install as a rollback directory during the
  switch.
- Creates a Start menu shortcut and current-user uninstall entry.
- Starts read-only from the Startup folder.

Use `-InstallDirectory` to choose another destination. Filesystem roots and
unmarked non-empty targets are rejected.

## Upgrade

Run the new package's `install-preview.ps1` with the same install directory.
The installer stops only AMD Mobile Power processes and preserves user state.

Do not upgrade `C:\RyzenAdj` in place as a development experiment. Stable
promotion follows `DEPLOYMENT.md` and requires a recoverable backup.

## Uninstall

Remove the installed application with:

```powershell
.\uninstall-preview.ps1
```

If this package installed the driver, also run the elevated driver cleanup
script. User data under `%LocalAppData%\AmdMobilePower` remains unless removed
explicitly.

## Recovery

If the GUI cannot start:

1. Exit `RyzenPower`, `ryzenadj`, and AMD Ryzen Master.
2. Confirm that only one AMD Mobile Power GUI is running.
3. Confirm that all runtime files are still beside the GUI.
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
GUI is not enough: the legacy logon task may still own a hidden worker. For
migration:

```powershell
Disable-ScheduledTask -TaskName "RyzenAdjWatch" -TaskPath "\AMD\"
Stop-ScheduledTask -TaskName "RyzenAdjWatch" -TaskPath "\AMD\"
```

Then reboot and verify the legacy mutex is absent before opening the new GUI.
See `MIGRATING_FROM_LEGACY.md`.

### Security software blocks the driver

RyzenAdj requires low-level Windows driver access. Security software may block
or unload WinRing0. Do not disable security controls just to make a development
build run. Record the conflict and continue on a controlled test machine.

If diagnostics report `WinRing0 status=2 (driver not loaded)`, verify:

```powershell
Get-Service WinRing0_1_2_0
Get-ScheduledTask -TaskPath "\AmdMobilePower\" -TaskName "StartWinRing0"
```

The service is demand-start and may be stopped before login. The logon task
must bring it to `Running` before the worker initializes.

### Read-only controls

The default GUI and package intentionally show locked power controls. See
`SECURITY.md`; enable write controls only after the supervised hardware gate.
