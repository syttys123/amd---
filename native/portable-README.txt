AMD Mobile Power - Native Preview
=================================

This package is an experimental Rust GUI + C++ worker build. It is not the
stable C:\RyzenAdj deployment and it has not replaced the verified .NET 1.0.4
package.

Read-only mode
--------------

Run:

  amd-mobile-power-gui.exe

The GUI starts the adjacent native worker in read-only mode and shows CPU,
power source, STAPM/Fast/Slow limits, temperature, and firmware-clamp status.
Closing the window hides it to the notification area. Use the tray Exit menu to
terminate the application.

Write-control preview
----------------------

Run:

  amd-mobile-power-gui.exe --enable-write-controls

This exposes 12 W, 25 W, and 45 W preset buttons plus Apply. The worker only
accepts writes when the GUI starts it with the explicit write-controls flag.
Every write is followed by a read-back; Fast/Slow failures attempt to restore
the previous limits.

Driver warning
--------------

The worker loads a RyzenAdj/WinRing0 compatible kernel driver. Windows security
software may block or warn about the driver. Review THIRD_PARTY_NOTICES.md and
the licenses before distributing or using the package.

Read-only compatibility report
------------------------------

Run the packaged collector without opening the GUI or enabling writes:

  powershell -ExecutionPolicy Bypass -File .\collect-native-diagnostics.ps1

The collector starts the adjacent worker with read-only hardware access, exports
a local JSON report, and never connects to the network.

Install
-------

From an extracted package:

  powershell -ExecutionPolicy Bypass -File .\install-preview.ps1

The installer uses a separate `AmdMobilePowerNativePreview` install and
uninstall entry. It starts the GUI in read-only mode from the Startup folder
and does not replace the stable `C:\RyzenAdj` deployment. Use
`uninstall-preview.ps1` from the installed directory to remove it.

Driver bootstrap
----------------

On a fresh Windows installation, the WinRing0 kernel service must be prepared
once from an elevated PowerShell before the worker can read AMD SMU data. From
the extracted package:

  powershell -ExecutionPolicy Bypass -File .\install-driver-bootstrap.ps1

The script copies the bundled driver to
`%ProgramData%\AmdMobilePower\driver`, configures the demand-start
`WinRing0_1_2_0` service, and creates the `\AmdMobilePower\StartWinRing0`
logon task. The task elevates only driver startup; the GUI and worker remain
non-elevated. Run the script again after moving the package to another machine.
If a valid WinRing0 service already exists at another path, the installer
reuses it instead of changing that service's binary path.

To remove only the driver service, logon task, and ProgramData driver installed
by this package, run the matching elevated cleanup script:

  powershell -ExecutionPolicy Bypass -File .\uninstall-driver-bootstrap.ps1

The cleanup script deletes `WinRing0_1_2_0` only when its binary path points at
this package's ProgramData driver. A WinRing0 service owned by another
installation is left untouched.

Requirements
------------

- Windows 10 or Windows 11 x64.
- An AMD mobile platform supported by the bundled RyzenAdj family profiles.
- A one-time elevated driver bootstrap as described above.
- Run the GUI as the current interactive user; the worker is a hidden child
  process.
