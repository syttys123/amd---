# AMD Mobile Power Compatibility Report

- Collection status: `PASS`
- Collected at: 2026-11-11T21:16:01Z
- Package version: 1.0.11-native (amd-mobile-power-v1.0.11-native-win-x64-native-preview)
- System: MECHREVO WUJIE15 PRO
- BIOS: T153_HPT_V05 (09/25/2024)
- CPU: AMD Ryzen 7 8845HS w/ Radeon 780M Graphics
- RyzenAdj family: Hawk Point (10)
- Platform supported: true
- Matched profile: Hawk Point 8845HS development profile (5 W - 60 W)

## Telemetry

- Power line: ac
- STAPM limit: 10 W
- Fast limit: 10 W
- Slow limit: 10 W

## Checks

- `worker.health` PASS: worker answered getHealth
- `worker.hardware` PASS: RyzenAdj hardware context initialized
- `worker.readOnly` PASS: worker started without --enable-write-controls
- `worker.exclusive` PASS: exclusive hardware access acquired
- `platform.supported` PASS: platform reports power-limit support
- `limits.available` PASS: stapm=true fast=true slow=true
- `telemetry.readable` PASS: powerLine=ac stapm=10.00W fast=10.00W slow=10.00W

## Privacy

This report was generated locally. It contains no local paths, pipe names, account names, serial numbers, or recent logs, and nothing was uploaded.
