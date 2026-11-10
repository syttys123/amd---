# Native Release Candidate Status

Status: `INTERNAL_RC`

This document tracks the native Rust GUI + C++ worker package separately from
the already deployed .NET `1.0.4` stable package.

## Current Candidate

```text
artifacts/native-packages/amd-mobile-power-v0.6.0-native-rc.3-win-x64-native-preview.zip
```

- Size: `453,241` bytes.
- SHA256:
  `d4b686e8e8220e8fb69fac796e85d0a3d5c9d4ffe080b578baab1692a98dd121`.
- Source commit: `103603d92df8eb451c102c6d933eabaa4a1e4501`.
- Working tree at build time: clean.

## Passed Gates

- Rust GUI lifecycle, tray restore, close-to-tray, and single-instance wake-up.
- C++ power-limit policy and battery/AC policy tests.
- Read-only hardware capability and telemetry probe on Ryzen 7 8845HS.
- Native write-control guard and profile-aware target validation.
- GUI policy save with isolated `%LocalAppData%`.
- Packaged compatibility collector with sanitized JSON.
- Staged checksum verification for every package file.
- Isolated install and uninstall.
- Real Start menu, Startup shortcut, and uninstall-entry create/remove cycle.
- AC `45/45/45 W` no-change policy write/read-back, disable, and graceful
  worker shutdown.

Evidence:

- `docs/evidence/packaging/v0.6.0-native-rc.3-release-gate-2026-11-10.json`
- `docs/evidence/packaging/v0.6.0-native-rc.3-clean-2026-11-10.json`
- `docs/evidence/packaging/v0.6.0-native-rc.3-shell-integration-2026-11-10.json`
- `docs/evidence/hardware/v0.6.0-native-rc.3-power-policy-no-change-2026-11-10.json`

Local review bundle:

```text
artifacts/native-release-review/v0.6.0-native-rc.3
```

Generate it with `native/prepare-release-review.ps1`; the bundle is
`REVIEW_ONLY` and is not a public release.

## Open Gates

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
