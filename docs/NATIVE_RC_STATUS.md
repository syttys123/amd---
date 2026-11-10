# Native Release Candidate Status

Status: `INTERNAL_RC`

This document tracks the native Rust GUI + C++ worker package separately from
the already deployed .NET `1.0.4` stable package.

Decision (2026-11-10): the native line stays an experimental preview. The
`.NET` GUI remains the product and daily driver, and it keeps `C:\RyzenAdj`.

Note (2026-11-11): `rc.11` supersedes `rc.10`. It contains the complete
break-and-rebuild UI: one continuous dark command deck shared by simple and
advanced modes, a flat simple telemetry ledger, a split advanced workspace,
and live STAPM/Fast/Slow read-back. Fresh UI state now defaults to simple mode.

## Current Candidate

```text
artifacts/native-packages/amd-mobile-power-v0.6.0-native-rc.11-win-x64-native-preview.zip
```

- Size: `526,293` bytes.
- SHA256:
  `5ed81fdb74fdcedb9c1f145eb43ca015665467aab622205067585e28e1d92a22`.
- Source commit: `bbdf44a75930838226e4792f79cbb809ffd8a814`.
- Working tree at build time: clean.
- Policy write verification: intentionally skipped in the clean package gate.

Local review bundle:

```text
artifacts/native-release-review/v0.6.0-native-rc.11
```

The bundle is `REVIEW_ONLY` and is not a public release.

## Passed Gates

- Rust GUI lifecycle, three Win32 minimize/restore cycles, close-to-tray, tray
  restore, single-instance wake-up, diagnostics export, view switching,
  topmost, and editable preset persistence.
- Rust unit tests: 26/26 passed.
- Rust formatting and Clippy with `-D warnings`.
- C++ power-limit policy and battery/AC policy tests.
- Read-only hardware capability and telemetry probe on Ryzen 7 8845HS while on
  battery: Hawk Point family `10`, PM table `4c0009`, profile
  `hawk-point-8845hs`, limits `25/25/20 W`.
- Native read-only write guard: invalid target rejected, no write requested.
- Battery-authorized dry-run write guard: PASS with
  `ExecuteNoChangeWrite=Not requested`.
- `0.6.0-native-rc.11` clean package verification with 16 checksum entries,
  isolated install/overwrite/uninstall, extracted GUI/worker read-only
  verification, compatibility JSON/Markdown collection, and
  `PolicyWriteVerification=Skipped`.
- Real current-user Start menu, Startup shortcut, and uninstall-entry
  create/remove cycle.
- Cross-version upgrade from `rc.10` to `rc.11`: installed payload matched the
  new archive, upgraded GUI/worker passed read-only verification, and uninstall
  removed the installation directory.
- Foreground-verified screenshot capture for simple, advanced, and read-only
  states at 125% Windows scaling.

## Evidence

- `docs/evidence/packaging/v0.6.0-native-rc.11-clean-2026-11-11.json`
- `docs/evidence/packaging/v0.6.0-native-rc.11-release-gate-2026-11-11.json`
- `docs/evidence/packaging/v0.6.0-native-rc.11-shell-integration-2026-11-11.json`
- `docs/evidence/packaging/v0.6.0-native-rc.11-cross-version-upgrade-2026-11-11.json`
- `docs/evidence/ui/native-redesign-2026-11-11.json`
- `assets/native-gui-redesign-simple-2026-11-11.png`
- `assets/native-gui-redesign-advanced-2026-11-11.png`
- `assets/native-gui-redesign-readonly-simple-2026-11-11.png`
- `assets/native-gui-redesign-readonly-advanced-2026-11-11.png`

Superseded candidates keep their exact historical package and evidence.

## Open Gates

- Run the supervised `rc.11` write-enabled no-change hardware policy gate. The
  clean package gate deliberately performed no hardware write.
- Obtain read-only compatibility evidence from a second physical AMD laptop or
  a different AMD generation.
- Repeat the UI screenshot matrix at 100% and 150% Windows scaling, plus
  focused-input, firmware-clamp, worker-offline, unsupported-platform, and
  long-error states.
- Observe a successful hosted Windows CI run. The current external blocker is
  the repository account billing/spending limit.
- Verify WinRing0 behavior under a clean Windows security baseline.
- Final human review before any promotion or public release.

## Promotion Rule

The native package is a candidate, not a stable deployment. Keep
`C:\RyzenAdj` on the verified .NET `1.0.4` package until the open gates above
are closed and a fresh rollback backup exists.

Public GitHub Release and Bilibili upload remain unapproved.
