# Migrating From The Legacy RyzenPower Worker

The `C:\RyzenAdj` development deployment predates the native GUI. Its visible
GUI and hidden worker use different lifetimes, so closing the window is not
enough to release the hardware owner.

## Why A Simple Stop Is Not Enough

The legacy deployment uses:

- `RyzenPower.exe` for the visible GUI.
- `\AMD\RyzenAdjWatch` as an enabled logon task.
- `wscript.exe` and a hidden elevated `pwsh.exe` for the persistent worker.
- `Local\RyzenAdjPowerWorker` as its hardware-owner mutex.

On the development laptop, `Stop-ScheduledTask` left the hidden `pwsh.exe`
alive. Force-terminating that child removed the mutex, but subsequent old and
new RyzenAdj probes both failed with `Unable to get MP1 SMU Obj` and could raise
a native access violation. Restarting the WinRing0 and inpout services did not
repair the state.

## Safe Migration Procedure

Stop all RyzenAdj-based applications first. Then use an elevated PowerShell
session:

```powershell
$taskPath = "\AMD\"
$taskName = "RyzenAdjWatch"

Disable-ScheduledTask -TaskName $taskName -TaskPath $taskPath
Stop-ScheduledTask -TaskName $taskName -TaskPath $taskPath

Get-ScheduledTask -TaskName $taskName -TaskPath $taskPath |
    Select-Object TaskName, TaskPath, State
```

The repository includes the same operation as a preview-first helper:

```powershell
.\packaging\migrate-legacy-owner.ps1
.\packaging\migrate-legacy-owner.ps1 -Apply
```

Without `-Apply`, the helper only prints current state. With `-Apply`, it
requires elevation, disables the logon task, and stops the running task. It does
not delete the task or files and does not reboot automatically.

The expected task state is `Disabled`. Reboot Windows next. The reboot:

- Terminates any hidden legacy task child.
- Releases the old hardware owner and driver state.
- Resets temporary RyzenAdj power limits to the BIOS or vendor defaults.

Verified on the development laptop: rebooting with the task still enabled
restarted `RyzenPower.exe`, the hidden task child, and the legacy hardware-owner
mutex immediately at logon. Disabling the task before reboot is required.

After reboot, verify that `Local\RyzenAdjPowerWorker` is absent and that no
`RyzenPower`, `ryzenadj`, or legacy scheduled task is running before starting
the new GUI.

## Restoring The Legacy Deployment

Do not restore it while the new worker is running. From an elevated PowerShell
session:

```powershell
Enable-ScheduledTask -TaskName "RyzenAdjWatch" -TaskPath "\AMD\"
Start-ScheduledTask -TaskName "RyzenAdjWatch" -TaskPath "\AMD\"
```

This changes task state only. It does not delete `C:\RyzenAdj` files or settings.

## Failure Rules

- Do not run old and new hardware owners concurrently.
- Do not repeatedly force-kill a native worker.
- Do not treat a running WinRing0 service as proof that SMU access is healthy.
- If `ryzenadj.exe --info` hangs or reports `Unable to get MP1 SMU Obj`, reboot
  before another probe or write.
