# Supported Hardware

## Current Scope

AMD Mobile Power does not yet support "all AMD laptops." It has one
experimental development platform and conservative detection profiles:

| CPU | Profile | Evidence | Status |
|---|---|---|---|
| AMD Ryzen 7 8845HS | `hawk-point-8845hs` | Read-only capability and telemetry probe passed | Experimental |
| Unknown AMD mobile CPU | `default` | Capability-dependent detection only | Unverified |

Conservative family profiles now exist for Renoir/Cezanne/Lucienne,
Rembrandt/Phoenix, Mendocino, Dragon/Fire Range, Krackan/Strix Point,
Strix Halo, and older Vega-based mobile families. They improve target bounds
and diagnostics, but remain **Unverified** until device-level write, read-back,
and restore evidence is recorded.

## RyzenAdj Family Detection Versus Project Support

The pinned RyzenAdj commit contains code paths for these CPU families:

- Raven, Picasso, Renoir, Cezanne, Dali, Lucienne.
- Vangogh, Rembrandt, Mendocino.
- Phoenix, Hawk Point.
- Dragon Range, Krackan Point, Strix Point, Strix Halo, Fire Range.

This means RyzenAdj may recognize a processor family and expose some fields. It
does **not** mean AMD Mobile Power has verified the laptop, its BIOS/EC behavior,
its PM table, or its STAPM/PPT writes. Device-level evidence remains limited to
the 8845HS entry above.

Current development laptop:

- MECHREVO WUJIE15 PRO
- AMD Ryzen 7 8845HS with Radeon 780M Graphics
- BIOS `T153_HPT_V05`
- Windows 11 build 26300
- SMU BIOS interface `15`
- PM table `4c0009`

The quiet and balanced BIOS profiles expose dynamic STAPM behavior while the
PPT Fast/Slow limits remain the required effective cap. A 45 W request can
read back as a lower sustained STAPM value with Fast/Slow at 45 W, or a 12 W
request can hold live package power near 12 W with Fast/Slow at 12 W. The GUI
therefore treats Fast/Slow as required and shows STAPM separately as a
firmware-managed diagnostic/control value.

This distinction is recorded in `HARDWARE_MATRIX.md`: a lower STAPM read-back
is a firmware clamp/dynamic-management observation, while a Fast/Slow value
above the request remains an invalid write result.

## Supported Parameters

The initial scope is limited to:

- STAPM
- PPT Fast
- PPT Slow

The project does not currently write skin temperature, current, voltage, or CPU
clock controls.

## Detection

The worker reports:

- Processor name, CPUID family/model when available, and RyzenAdj family
  number/name.
- SMU BIOS interface and PM table version.
- Supported limit fields.
- AC or battery power-line state.
- Requested targets, effective limits, and firmware clamps.
- All loaded profiles, the matched profile, diagnostic schema/protocol version,
  hardware/write gates, and runtime executable hashes through diagnostics
  export.

The operating system reports many USB-C power banks as external/AC power. A
power bank therefore triggers AC-profile behavior and cannot currently be
distinguished from a wall adapter by the application. Use a manual conservative
target when the power source matters.

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
