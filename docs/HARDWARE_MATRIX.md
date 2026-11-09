# Hardware Matrix

This file records manual hardware evidence. Automated CI cannot verify firmware
behavior.

## Status Definitions

- Verified: launch, worker, telemetry, safe write, read-back, and restore passed.
- Experimental: launches and reads telemetry, but write behavior is incomplete.
- Unsupported: required PM table or hardware interface is unavailable.

## Current Evidence

| Device | CPU | BIOS | AC result | Battery result | Status | Notes |
|---|---|---|---|---|---|---|
| Development laptop | Ryzen 7 8845HS | Pending capture | 25 W verified; 45 W request read back 25 W STAPM and 45 W Fast/Slow | Pending current validation | Experimental | Firmware clamps sustained STAPM in the current quiet-mode profile |

## Required Capture

For every tested device record:

- Laptop vendor and model.
- CPU name, family, and model.
- BIOS version and power profile.
- SMU BIOS interface version.
- PM table version.
- Windows build.
- RyzenAdj version or commit.
- Requested and effective limits.
- Temperature and stability observations.

