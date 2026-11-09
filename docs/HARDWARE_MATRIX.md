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
| MECHREVO WUJIE15 PRO | Ryzen 7 8845HS | `T153_HPT_V05` | Read-only snapshot: limits 25/45/45 W; values 25.00/25.39/24.95 W. Earlier writes verified 25/25/25 W; a 45 W request read back 25/45/45 W. | Pending controlled validation | Experimental | Windows 11 build 26300; SMU 15; PM table `4c0009`; firmware clamps sustained STAPM in the current quiet-mode profile |

## Read-Only Probe Evidence

The clean Release worker was started with `--enable-hardware` and a dedicated
pipe name. Only `getCapabilities` and `getSnapshot` were called.

Verified on 2026-11-09:

- CPU identity: `AMD Ryzen 7 8845HS w/ Radeon 780M Graphics`.
- RyzenAdj commit: `5775fc3e6dbb25c7030ee2d100a1bdd6e8bf2d0a`.
- SMU BIOS interface: `15`.
- PM table: `4c0009`.
- STAPM, Fast, and Slow capabilities reported as supported.
- Matched profile: `hawk-point-8845hs`.
- Power line reported as AC during the probe.
- No hardware power-limit write was performed by the probe.

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

