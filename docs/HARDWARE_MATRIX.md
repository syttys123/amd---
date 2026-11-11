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
| MECHREVO WUJIE15 PRO | Ryzen 7 8845HS | `T153_HPT_V05` | Write/read-back evidence: 10/10/10 W, 12/12/12 W, and earlier 25/25/25 W. A 45 W request read back as 25/45/45 W. Latest clean-package read-only snapshot held required limits at 12/12/12 W. | Supervised policy transition passed: baseline `25/25/20 W`; 12 W target settled near 12 W; AC restored Fast/Slow `45/25 W`; both baselines restored. | Verified | Windows build 26300; SMU 15; PM table `4c0009`; firmware can clamp or dynamically manage STAPM while Fast/Slow remain the required package cap |

## Firmware Clamp Interpretation

The required write contract treats PPT Fast and PPT Slow as the enforceable
package-power ceiling. STAPM can be firmware-managed and is displayed separately:

- A 45 W request may read back as STAPM 25 W with Fast/Slow 45 W. This is a
  firmware clamp, not a transport failure.
- After a lower request, STAPM may remain dynamic near 25-30 W in the balanced
  BIOS profile while measured package power stays near the requested ceiling
  and Fast/Slow read back at 12 W.
- For Fast/Slow, a read-back above the request is invalid. Depending on the
  write mode, a lower competent-firmware value can be reported as clamped.
- STAPM driver errors or unavailable read-back are surfaced as warnings rather
  than silently treated as a successful exact write.
- The package-level result records `restoreAttempted`, `firmwareClamp`, and
  `stapmWarning` separately so an operator can distinguish transport, firmware,
  and restore behavior.

Additional balanced-profile test on 2026-11-09:

- STAPM limit was dynamic and observed between roughly 25 W and 40 W while the
  laptop remained on AC power.
- Fast and Slow limits read back as 45 W.
- A requested 12 W triplet initially failed under the old all-or-nothing rule,
  which restored Fast/Slow because STAPM's dynamic limit remained at 25-30 W.
- After allowing the dynamic STAPM readback while requiring Fast/Slow read-back,
  the 12 W request succeeded: actual STAPM dropped to 12 W, Fast/Slow limits
  remained 12 W, and the BIOS still reported a dynamic STAPM ceiling near 25 W.
- On the balanced BIOS profile, a 12 W write/read-back test succeeded with all
  three limits at 12 W and live package power near 12 W. A repeated 12 W apply
  also completed without restore.
- On 2026-11-10, the compact GUI applied 10 W through the named-pipe worker
  while the laptop was powered by a USB-C power bank. All three limits read
  back at 10.0 W and the GUI logged a matching read-back.
- Immediately afterward, the compact GUI applied 12 W. STAPM, Fast, and Slow
  read back at 12.0 W; live STAPM remained around 11.7-12.0 W. The host reports
  the power bank as AC/external power, so automatic AC profiles cannot
  distinguish a power bank from a wall adapter.
- On 2026-11-10 at 02:14, the packaged `0.1.3-dev` GUI/worker passed the
  controlled no-change write gate. Initial, requested, read-back, and final
  STAPM/Fast/Slow values were all 12 W. `restoreAttempted=false`,
  `hasFirmwareClamp=false`, and `hasStapmWarning=false`. The worker executable
  SHA256 was
  `f31c615f7b838a1cec6c5eee0fcc0f4c4c4c80314d987fa529a0aa697d07134a`.
  Full summary:
  `docs/evidence/hardware/mechrevo-wujie15-8845hs-no-change-2026-11-10.json`.
- On 2026-11-10 at 12:43, the supervised packaged-worker policy transition
  passed. The AC baseline was `39/45/25 W` and the battery baseline was
  `25/25/20 W`. A `12/12/12 W` battery target wrote successfully, live STAPM
  settled at about `12.52 W`, and Fast/Slow limits read back at `12 W`.
  Reconnecting AC applied the original `39/45/25 W` target and restored
  Fast/Slow to `45/25 W`; STAPM remained firmware-dynamic. The battery and AC
  baselines were then restored, the policy was disabled, and the worker used
  graceful shutdown. Evidence:
  `docs/evidence/hardware/mechrevo-wujie15-8845hs-policy-2026-11-10.json`.
- Verified a malformed pipe client that connected and disconnected before
  sending a frame no longer terminates the worker. A subsequent health request
  succeeded with `hardwareInitialized=true`.

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
- Rechecked on 2026-11-11 with the packaged rc.7 read-only collector after the
  stable GUI exited: collection `PASS`, AC power, SMU `15`, PM table `4c0009`,
  matched profile `hawk-point-8845hs [5-60 W]`, all three limit capabilities
  true, and effective limits `10/10/10 W`. No write controls were enabled.
- Rechecked again for `0.6.0-native-rc.13` after the battery-only policy
  change: AC power, SMU `15`, PM table `4c0009`, matched profile
  `hawk-point-8845hs [5-60 W]`, effective limits `25.01/45/25 W`, native
  write-control command rejected without the explicit flag, Rust GUI
  read-only/diagnostics passed, and the dry-run write guard reported
  `ExecuteNoChangeWrite=Not requested`. Evidence:
  `docs/evidence/packaging/v0.6.0-native-rc.13-release-gate-2026-11-11.json`.
- `0.6.0-native-rc.14` repeated the read-only gate after the focus/icon
  verification update: AC power, `25.22/45/25 W`, the native write gate still
  rejected writes, the Rust GUI brought up the worker read-only, diagnostics
  reported `taskbarIconAvailable=true`/`trayIconId=1`, and the dry-run guard
  passed. Evidence:
  `docs/evidence/packaging/v0.6.0-native-rc.14-release-gate-2026-11-11.json`.
- `0.6.0-native-rc.15` repeated the read-only gate after high-contrast support:
  AC power, `25/45/25 W`, the native write gate still rejected writes, the Rust
  GUI connected read-only, and the dry-run guard passed without requesting a
  no-change write. Evidence:
  `docs/evidence/packaging/v0.6.0-native-rc.15-release-gate-2026-11-11.json`.
- `0.6.0-native-rc.16` repeated the read-only gate after packaged UI evidence:
  AC power, `25.24/45/25 W`, the native write gate still rejected writes, the
  Rust GUI connected read-only, and the dry-run guard passed. Evidence:
  `docs/evidence/packaging/v0.6.0-native-rc.16-release-gate-2026-11-11.json`.
- `0.6.0-native-rc.17` passed the controlled current-value policy gate after
  the package and UI gates: AC power, requested/read-back `25/45/25 W`, policy
  disabled, worker shutdown clean, and live limits unchanged. Evidence:
  `docs/evidence/hardware/v0.6.0-native-rc.17-power-policy-no-change-2026-11-11.json`.
- `1.0.0-native` repeated the controlled current-value policy gate on the same
  AC state: requested/read-back `25/45/25 W`, policy disabled, worker shutdown
  clean, and live limits unchanged. Evidence:
  `docs/evidence/hardware/v1.0.0-native-power-policy-no-change-2026-11-11.json`.

## Required Capture

Run the packaged read-only collector from the extracted portable package; it
does not enable writes or upload anything:

```powershell
powershell -ExecutionPolicy Bypass `
  -File .\collect-native-diagnostics.ps1 `
  -OutputPath .\compatibility.json `
  -MarkdownPath .\compatibility.md
```

The JSON `host` block already fills vendor, model, BIOS version, and Windows
build, and the `privacy` block declares that no paths, process IDs, account
names, serial numbers, logs, or upload are included.

For every tested device record:

- Laptop vendor and model.
- CPU name, family, and model.
- BIOS version and power profile.
- SMU BIOS interface version.
- PM table version.
- Windows build.
- RyzenAdj version or commit.
- Per-limit capability flags (STAPM, Fast, Slow, and `supportsAny`).
- Platform supported state and, when unsupported, the reported reason.
- Matched profile id plus its minimum and maximum watts.
- Requested and effective limits.
- Temperature and stability observations.

Import reviewed reports with `native/import-compatibility-report.ps1`; the
resulting device index is `docs/COMPATIBILITY_REPORTS.md`.

