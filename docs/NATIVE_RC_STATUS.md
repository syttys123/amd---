# Native Release Candidate Status

Status: `STABLE_LOCAL_DEPLOYED`

This document tracks the native Rust GUI + C++ worker package and its
stable-local deployment. The .NET `1.0.4` package remains available as
`C:\RyzenAdj.before-20261111-223017`.

Decision (2026-11-11): the native line has a hardware-gated stable-local
candidate for the verified 8845HS platform, and `C:\RyzenAdj` now contains the
`1.0.0-native` package. Broader AMD generation support remains experimental.

Note (2026-11-11): `1.0.0-native` supersedes `rc.17`. It contains the complete
break-and-rebuild UI: one continuous dark command deck shared by simple and
advanced modes, a flat simple telemetry ledger, a split advanced workspace,
and live STAPM/Fast/Slow read-back. It also adds test-only failure-state
fixtures for worker offline, firmware clamp, unsupported platform, and long
error, with write-control state assertions. The advanced policy now supports
`仅电池`, which skips AC/external writes entirely. The new high-contrast
fixture renders the complete shell with black surfaces, white text, yellow
structure, and black text on yellow primary actions without changing Windows
accessibility settings.

## Current Candidate

```text
artifacts/native-packages/amd-mobile-power-v1.0.0-native-win-x64-native-preview.zip
```

- Size: `535,197` bytes.
- SHA256:
  `f3fd6ea1d1b0292c6ec9ea7445f191adc302066f78a728528a3722923c73a0bf`.
- Source commit: `ddb7d9cba3195f4a16df1299215a9e26cd18544f`.
- Working tree at build time: clean.
- Policy write verification: intentionally skipped in the clean package gate.

Local review bundle:

```text
artifacts/native-release-review/v1.0.0-native
```

The bundle is `REVIEW_ONLY` and is not a public release.

## Passed Gates

- Rust GUI lifecycle, three Win32 minimize/restore cycles, close-to-tray, tray
  restore, single-instance wake-up, diagnostics export, view switching,
  topmost, and editable preset persistence.
- Rust unit tests: 30/30 passed.
- Rust formatting and Clippy with `-D warnings`.
- C++ power-limit policy and battery/AC policy tests.
- Read-only hardware capability and telemetry probe on Ryzen 7 8845HS on AC:
  Hawk Point family `10`, PM table `4c0009`, profile
  `hawk-point-8845hs`, limits `25/45/25 W`.
- Native read-only write guard: invalid target rejected, no write requested.
- Battery-authorized dry-run write guard: PASS with
  `ExecuteNoChangeWrite=Not requested`.
- `1.0.0-native` clean package verification with 16 checksum entries,
  isolated install/overwrite/uninstall, extracted GUI/worker read-only
  verification, compatibility JSON/Markdown collection, and
  `PolicyWriteVerification=Skipped`.
- Real current-user Start menu, Startup shortcut, and uninstall-entry
  create/remove cycle.
- Cross-version upgrade from `rc.17` to `1.0.0-native`: installed payload matched the
  new archive, upgraded GUI/worker passed read-only verification, and uninstall
  removed the installation directory.
- Foreground-verified screenshot capture for simple, advanced, and read-only
  states at 125% Windows scaling.
- Failure-state and battery-only screenshots with machine-checked
  target/preset/diagnostics availability. No hardware worker is started for
  these fixtures.
- Focused-input captures with the actual child focus verified, plus diagnostics
  checks for active mode, topmost state, taskbar icon availability, and tray
  icon id.
- High-contrast simple and advanced captures with `ui.highContrast=true`, no
  hardware worker startup, and the same target/preset/diagnostics availability
  checks as the other write-controls fixtures.
- Extracted `1.0.0-native` packaged GUI/worker verification with GUI and worker
  hashes, three minimize/restore cycles, close-to-tray, tray restore,
  single-instance wake, `taskbarIconAvailable=true`, `trayIconId=1`, and the
  persisted `simple` to `advanced` mode transition.
- Controlled policy probe requested the live AC limits `25/45/25 W`, verified
  the worker read-back, disabled the policy, and shut down cleanly. Live limits
  remained `25/45/25 W`.
- The verified package is deployed at `C:\RyzenAdj` with the prior .NET `1.0.4`
  directory preserved at `C:\RyzenAdj.before-20261111-223017`. The deployed
  GUI/worker passed read-only worker, lifecycle, tray, single-instance, mode,
  preset, battery-only, and diagnostics checks; the desktop shortcut keeps
  `--enable-write-controls --simple-mode`.
- Added a local compatibility-report importer that rejects non-read-only,
  incomplete-privacy, path-leaking, and duplicate reports; the first rc.17
  report is archived under `docs/evidence/compatibility` and indexed in
  `docs/COMPATIBILITY_REPORTS.md`.

## Evidence

- `docs/evidence/packaging/v1.0.0-native-clean-2026-11-11.json`
- `docs/evidence/packaging/v1.0.0-native-release-gate-2026-11-11.json`
- `docs/evidence/packaging/v1.0.0-native-shell-integration-2026-11-11.json`
- `docs/evidence/packaging/v1.0.0-native-cross-version-upgrade-2026-11-11.json`
- `docs/evidence/hardware/v1.0.0-native-power-policy-no-change-2026-11-11.json`
- `docs/evidence/packaging/v1.0.0-native-deployment-2026-11-11.json`
- `docs/COMPATIBILITY_REPORTS.md`
- `docs/evidence/compatibility/index.json`
- `docs/evidence/ui/native-redesign-2026-11-11.json`
- `docs/evidence/ui/native-ui-failure-states-2026-11-11.json`
- `docs/evidence/ui/native-battery-only-policy-2026-11-11.json`
- `docs/evidence/ui/native-battery-only-capture-2026-11-11.json`
- `docs/evidence/ui/native-focus-2026-11-11.json`
- `docs/evidence/ui/native-high-contrast-2026-11-11.json`
- `docs/evidence/ui/native-packaged-1.0.0-ui-2026-11-11.json`
- `assets/native-gui-redesign-simple-2026-11-11.png`
- `assets/native-gui-redesign-advanced-2026-11-11.png`
- `assets/native-gui-redesign-readonly-simple-2026-11-11.png`
- `assets/native-gui-redesign-readonly-advanced-2026-11-11.png`
- `assets/native-battery-only-simple-2026-11-11.png`
- `assets/native-battery-only-advanced-2026-11-11.png`
- `assets/native-focus-simple-2026-11-11.png`
- `assets/native-focus-advanced-2026-11-11.png`
- `assets/native-high-contrast-simple-2026-11-11.png`
- `assets/native-high-contrast-advanced-2026-11-11.png`

Superseded candidates keep their exact historical package and evidence.

## Open Gates

- Obtain read-only compatibility evidence from a different AMD laptop or
  generation when a second device becomes available; no second machine is
  currently available.
- Repeat the UI screenshot matrix at 100% and 150% Windows scaling, plus
  focused-input states.
- Observe a successful hosted Windows CI run. The current external blocker is
  the repository account billing/spending limit.
- Verify WinRing0 behavior under a clean Windows security baseline.
- Final human review before any promotion or public release.

## Promotion Rule

The native package is stable-local for the verified 8845HS platform.
`C:\RyzenAdj` is replaced only through
`native/promote-stable-deployment.ps1`, which requires the verified package,
keeps a full pre-promotion backup, retargets the existing desktop shortcut, and
rolls back on failure.

Public GitHub Release and Bilibili upload remain unapproved.
