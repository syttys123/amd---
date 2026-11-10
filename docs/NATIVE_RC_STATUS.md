# Native Release Candidate Status

Status: `INTERNAL_RC`

This document tracks the native Rust GUI + C++ worker package separately from
the already deployed .NET `1.0.4` stable package.

## Current Candidate

```text
artifacts/native-packages/amd-mobile-power-v0.6.0-native-rc.5-win-x64-native-preview.zip
```

- Size: `453,798` bytes.
- SHA256:
  `d94879ba6c1b1d508ec00868a18212480c045f1e6cc6a7fa46ca7fc9f666f50d`.
- Source commit: `358835fce7cb6f972f899077db4cc1c6b6095bab`.
- Working tree at build time: clean.

## Passed Gates

- Rust GUI lifecycle, three Win32 minimize/restore cycles, tray restore,
  close-to-tray, and single-instance wake-up.
- C++ power-limit policy and battery/AC policy tests.
- Read-only hardware capability and telemetry probe on Ryzen 7 8845HS.
- Native write-control guard and profile-aware target validation.
- GUI policy save with isolated `%LocalAppData%`.
- Packaged compatibility collector with sanitized JSON.
- Staged checksum verification for every package file.
- Isolated install and uninstall.
- Real Start menu, Startup shortcut, and uninstall-entry create/remove cycle.
- Read-only AC and battery policy plan with the write gate rejecting
  `setPowerPolicy` while writes are disabled.

Evidence:

- `docs/evidence/packaging/v0.6.0-native-rc.5-release-gate-2026-11-10.json`
- `docs/evidence/packaging/v0.6.0-native-rc.5-clean-2026-11-10.json`
- `docs/evidence/packaging/v0.6.0-native-rc.5-shell-integration-2026-11-10.json`

Superseded candidate `0.6.0-native-rc.4` kept its AC `45/45/45 W` no-change
policy write/read-back in
`docs/evidence/hardware/v0.6.0-native-rc.4-power-policy-no-change-2026-11-10.json`.

Local review bundle:

```text
artifacts/native-release-review/v0.6.0-native-rc.5
```

Generate it with `native/prepare-release-review.ps1`; the bundle is
`REVIEW_ONLY` and is not a public release.

## Open Gates

- A controlled AC session must rerun the no-change hardware policy write for
  `rc.5` at `45/45/45 W`. The `rc.4` run is preserved, but the current read-only
  plan rounds the firmware-dynamic STAPM limit, so the write test is not run
  unattended.
- At least one second physical AMD laptop must provide read-only compatibility
  evidence using `collect-native-diagnostics.ps1`.
- Windows CI must be able to run after the repository account billing or
  spending-limit issue is resolved; the local and workflow definitions are
  already in place.
- The package must not replace `C:\RyzenAdj` until the second-device evidence,
  a fresh promotion backup, and the final human review pass.
- GitHub release and Bilibili publication require explicit human approval.

## Promotion Rule

The native package is a candidate, not a stable deployment. Keep
`C:\RyzenAdj` on the verified .NET `1.0.4` package until the open gates above
are closed.
