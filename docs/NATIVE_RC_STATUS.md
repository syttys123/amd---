# Native Release Candidate Status

Status: `INTERNAL_RC`

This document tracks the native Rust GUI + C++ worker package separately from
the already deployed .NET `1.0.4` stable package.

Decision (2026-11-10): the native line stays an experimental preview. The
`.NET` GUI remains the product and daily driver, and it keeps `C:\RyzenAdj`.

Note (2026-11-11): `rc.15` supersedes `rc.14`. It contains the complete
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
artifacts/native-packages/amd-mobile-power-v0.6.0-native-rc.15-win-x64-native-preview.zip
```

- Size: `535,408` bytes.
- SHA256:
  `e2940853e82d5aa459b6f5e3f99d680bb29a485fcb3071374ddee395f28948fd`.
- Source commit: `c85a0c951f5a36311ebfb176a6e2ea60c2cf29d1`.
- Working tree at build time: clean.
- Policy write verification: intentionally skipped in the clean package gate.

Local review bundle:

```text
artifacts/native-release-review/v0.6.0-native-rc.15
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
- `0.6.0-native-rc.15` clean package verification with 16 checksum entries,
  isolated install/overwrite/uninstall, extracted GUI/worker read-only
  verification, compatibility JSON/Markdown collection, and
  `PolicyWriteVerification=Skipped`.
- Real current-user Start menu, Startup shortcut, and uninstall-entry
  create/remove cycle.
- Cross-version upgrade from `rc.14` to `rc.15`: installed payload matched the
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

## Evidence

- `docs/evidence/packaging/v0.6.0-native-rc.15-clean-2026-11-11.json`
- `docs/evidence/packaging/v0.6.0-native-rc.15-release-gate-2026-11-11.json`
- `docs/evidence/packaging/v0.6.0-native-rc.15-shell-integration-2026-11-11.json`
- `docs/evidence/packaging/v0.6.0-native-rc.15-cross-version-upgrade-2026-11-11.json`
- `docs/evidence/ui/native-redesign-2026-11-11.json`
- `docs/evidence/ui/native-ui-failure-states-2026-11-11.json`
- `docs/evidence/ui/native-battery-only-policy-2026-11-11.json`
- `docs/evidence/ui/native-battery-only-capture-2026-11-11.json`
- `docs/evidence/ui/native-focus-2026-11-11.json`
- `docs/evidence/ui/native-high-contrast-2026-11-11.json`
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

- Run the supervised `rc.15` write-enabled no-change hardware policy gate. The
  clean package gate deliberately performed no hardware write.
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

The native package is a candidate, not a stable deployment. Keep
`C:\RyzenAdj` on the verified .NET `1.0.4` package until the open gates above
are closed and a fresh rollback backup exists.

Public GitHub Release and Bilibili upload remain unapproved.
