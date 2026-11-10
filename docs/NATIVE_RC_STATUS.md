# Native Release Candidate Status

Status: `INTERNAL_RC`

This document tracks the native Rust GUI + C++ worker package separately from
the already deployed .NET `1.0.4` stable package.

Decision (2026-11-10): the native line stays an experimental preview. The
`.NET` GUI remains the product and daily driver, and it keeps `C:\RyzenAdj`.
The native package is not a drop-in replacement and will only be considered
for promotion if it reaches feature and UI parity without regressing the
current experience.

## Current Candidate

```text
artifacts/native-packages/amd-mobile-power-v0.6.0-native-rc.5-win-x64-native-preview.zip
```

- Size: `453,794` bytes.
- SHA256:
  `8e832f8b0c5f8f764fffd4616ea06b404cb513b0c5a77dc1d68d6e8e58fc7b66`.
- Source commit: `75c072881e34a30efee6c88890dec34f49b98aa0`.
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
- Controlled AC no-change power-policy write: requested `44/45/45 W` from the
  live firmware-dynamic state, applied and verified, policy disabled, worker
  shut down through the graceful protocol.

Evidence:

- `docs/evidence/packaging/v0.6.0-native-rc.5-release-gate-2026-11-10.json`
- `docs/evidence/packaging/v0.6.0-native-rc.5-clean-2026-11-10.json`
- `docs/evidence/packaging/v0.6.0-native-rc.5-shell-integration-2026-11-10.json`
- `docs/evidence/hardware/v0.6.0-native-rc.5-power-policy-no-change-2026-11-10.json`

Superseded candidates `0.6.0-native-rc.4` and earlier keep their own evidence.

Local review bundle:

```text
artifacts/native-release-review/v0.6.0-native-rc.5
```

Generate it with `native/prepare-release-review.ps1`; the bundle is
`REVIEW_ONLY` and is not a public release.

## Open Gates

- Feature and UI parity with the `.NET` GUI (simple/advanced modes, localized
  copy, tray/taskbar behavior, diagnostics) before any promotion discussion.
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
