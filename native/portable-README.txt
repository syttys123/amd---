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

Requirements
------------

- Windows 10 or Windows 11 x64.
- An AMD mobile platform supported by the bundled RyzenAdj family profiles.
- Run the GUI as the current interactive user; the worker is a hidden child
  process.
