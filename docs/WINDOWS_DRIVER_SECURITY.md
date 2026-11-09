# Windows Driver Security Baseline

Last reviewed: 2026-11-10

This document records the current Windows and WinRing0 baseline on the
development laptop. It is operational evidence, not a claim that every Windows
security configuration or third-party endpoint-protection product allows the
driver.

Machine-readable evidence:
`docs/evidence/windows/winring0-baseline-2026-11-10.json`.

## Host Baseline

- Windows product string: Windows 10 Pro for Workstations.
- Display version reported by Windows: `26H2`.
- Kernel build: `26300.9711`.
- Edition: `ProfessionalWorkstation`.
- Architecture: AMD64.
- Security Center antivirus provider: Windows Defender.
- Defender antivirus and real-time protection: enabled.
- Defender signature version observed: `1.463.210.0`.

Windows product naming has historically retained compatibility strings on newer
builds. Treat the build number as the version evidence and do not infer behavior
from the product string alone.

## WinRing0 Artifacts

The package and development build use the same pinned files:

| File | Version | SHA256 |
| --- | --- | --- |
| `WinRing0x64.sys` | `1.2.0.5` | `11bd2c9f9e2397c9a16e0990e4ed2cf0679498fe0fd418a3dfdac60b5c160ee5` |
| `WinRing0x64.dll` | `1.3.0.18` | `a746fd5728e7485f741cc330a279674bc8590b1b8007d8614046c49f58698485` |
| `inpoutx64.dll` | `1.5.0.0` | `5f27ed4d5cd58a1ee23deeb802e09e73f3a1d884ce2135f6e827f67b171269e7` |

`Get-AuthenticodeSignature WinRing0x64.sys` returned `Valid` on the development
host. The signature is timestamped. The signing certificate itself expired in
2008, so validity depends on the timestamp and the Windows trust policy in use.
Do not treat signature validity as proof of runtime safety.

## Observed Driver State

- Service `WinRing0_1_2_0`: running, manual start.
- Scheduled task `\AmdMobilePower\StartWinRing0`: ready.
- Default read-only AMD Mobile Power GUI and worker: connected.
- Packaged telemetry: STAPM/Fast/Slow, temperature, and power-line state read
  successfully while the active limit was 12 W.
- No driver files or service configuration were changed during this review.

## Supported Behavior

- The application must fail closed when the worker cannot initialize hardware.
- The GUI must not repeatedly restart a worker after a hardware-read timeout.
- Diagnostics should report the WinRing0 status and runtime-file hashes.
- Users must not disable Windows Defender, tamper protection, memory integrity,
  or other endpoint protections merely to make the development package run.

## Known Failure Modes

- `WinRing0 status=2 (driver not loaded)` means the driver service is not loaded.
- Security products may block the driver file, unload the service, or deny the
  IOCTL used by RyzenAdj.
- A force-terminated worker can leave driver or SMU state unhealthy; restarting
  the service alone does not guarantee recovery.
- A 64-bit process is required for the bundled x64 driver and libraries.

## Remaining Validation

- Repeat the read-only and controlled-write procedure in a clean Windows VM or
  freshly imaged laptop with only Microsoft Defender enabled.
- Record failures under at least one common third-party endpoint-protection
  product without disabling that product.
- Verify behavior when memory integrity or other driver blocklists explicitly
  reject WinRing0.
- Keep the second physical AMD laptop gate separate from driver-security
  validation.
