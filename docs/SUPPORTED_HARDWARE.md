# Supported Hardware

## Current Scope

AMD Mobile Power does not yet support "all AMD laptops." It has one
experimental development platform and conservative detection profiles:

| CPU | Profile | Evidence | Status |
|---|---|---|---|
| AMD Ryzen 7 8845HS | `hawk-point-8845hs` | Read-only capability and telemetry probe passed | Experimental |
| Unknown AMD mobile CPU | `default` | Capability-dependent detection only | Unverified |

Current development laptop:

- MECHREVO WUJIE15 PRO
- AMD Ryzen 7 8845HS with Radeon 780M Graphics
- BIOS `T153_HPT_V05`
- Windows 11 build 26300
- SMU BIOS interface `15`
- PM table `4c0009`

The current quiet-mode firmware exposes AC limits around STAPM 25 W and
Fast/Slow 45 W. A requested 45 W can read back as STAPM 25 W with Fast/Slow
45 W because the firmware clamps sustained package power. This is why the GUI
shows actual power and the current firmware limit separately from the requested
target.

## Supported Parameters

The initial scope is limited to:

- STAPM
- PPT Fast
- PPT Slow

The project does not currently write skin temperature, current, voltage, or CPU
clock controls.

## Detection

The worker reports:

- Processor name and CPU family.
- SMU BIOS interface and PM table version.
- Supported limit fields.
- AC or battery power-line state.
- Requested targets, effective limits, and firmware clamps.

Supported capabilities do not prove stable write behavior. A platform remains
experimental until the supervised test in `HARDWARE_TEST_PROCEDURE.md` passes
and the result is recorded in `HARDWARE_MATRIX.md`.

## Evidence Classes

- **Read-only verified:** capabilities and telemetry were read on the device.
- **Write-tested:** a guarded write, read-back, and restore passed.
- **Experimental:** the application starts or reads telemetry, but write
  behavior is incomplete or firmware-clamped.
- **Unsupported:** required PM table or hardware interface is unavailable.

## Adding A Platform

1. Export diagnostics on the target device.
2. Record CPU, BIOS, SMU interface, PM table, power-line state, and firmware
   limits.
3. Add or update a conservative profile under `profiles/`.
4. Run tests and verify profile matching.
5. Perform only the supervised no-change write procedure.
6. Add the evidence and residual risks to `HARDWARE_MATRIX.md`.

Do not infer broad support from CPU family alone. Firmware and EC behavior vary
by laptop model and BIOS power profile.
