# Compatibility Report Template

Submit public reports through the repository issue form. Remove account names,
personal paths, serial numbers, and unrelated desktop content before attaching
diagnostics.

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
- SMU BIOS interface:
- PM table:
- Matched profile:
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

- Diagnostics JSON attached: yes / no
- Runtime-file hashes included: yes / no
- Sensitive information reviewed and removed: yes / no

## Stability

- Firmware clamp observed:
- Worker timeout or native crash observed:
- Reboot required after driver fault: yes / no
- Additional notes:
