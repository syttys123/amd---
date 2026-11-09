# Compatibility Report Template

Submit public reports through the repository issue form. Remove account names,
personal paths, serial numbers, and unrelated desktop content before attaching
diagnostics.

Generate the read-only report from the extracted portable package:

```powershell
powershell -ExecutionPolicy Bypass -File .\collect-diagnostics.ps1
```

The collector does not enable power-limit writes, does not upload data, and
uses a field whitelist plus path sanitization. Review the JSON before attaching
it publicly.

## Device

- Vendor and model:
- CPU name:
- BIOS version:
- Windows edition and build:
- Laptop performance/quiet mode:

## Runtime Evidence

- App version or source commit:
- Read-only snapshot works: yes / no
- Power line during test: AC / battery
- RyzenAdj family number and name:
- SMU BIOS interface:
- PM table:
- Matched profile:
- Available profile IDs:
- Hardware adapter configured: yes / no
- Worker write controls enabled: yes / no
- STAPM actual/limit:
- PPT Fast actual/limit:
- PPT Slow actual/limit:
- Temperature:

## Conflicts

- Running `RyzenPower`, `ryzenadj`, or AMD Ryzen Master: yes / no
- Legacy `\AMD\RyzenAdj*` task state:
- `Local\RyzenAdjPowerWorker` present:
- `Local\AmdMobilePower.HardwareOwner.v1` present:

## Diagnostics

- Diagnostics schema version:
- Worker/protocol version:
- Worker executable SHA256:
- Packaged read-only diagnostic export attached: yes / no
- Diagnostics JSON attached: yes / no
- `collectionStatus` is `PASS`: yes / no
- Worker write controls were disabled: yes / no
- Graceful worker shutdown reported: yes / no
- Runtime-file hashes included: yes / no
- GUI/worker log excerpts included: yes / no
- Log directory:
- Sensitive information reviewed and removed: yes / no

## Stability

- Firmware clamp observed:
- Worker timeout or native crash observed:
- Reboot required after driver fault: yes / no
- Additional notes:
