# Native Release Candidate Status

Status: `INTERNAL_RC`

This document tracks the native Rust GUI + C++ worker package separately from
the already deployed .NET `1.0.4` stable package.

## Current Candidate

```text
artifacts/native-packages/amd-mobile-power-v0.6.0-native-rc.2-win-x64-native-preview.zip
```

- Size: `453,240` bytes.
- SHA256:
  `786c14bdc2e47c6386c14021ec2c2a87d745044eb0388d4501d3e8e8f46f92d4`.
- Source commit: `d571fc1b8599f5582081e71eee64364b80de1f1c`.
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

- `docs/evidence/packaging/v0.6.0-native-rc.2-release-gate-2026-11-10.json`
- `docs/evidence/packaging/v0.6.0-native-rc.2-clean-2026-11-10.json`
- `docs/evidence/packaging/v0.6.0-native-rc.2-shell-integration-2026-11-10.json`
- `docs/evidence/hardware/v0.6.0-native-rc.2-power-policy-no-change-2026-11-10.json`

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
