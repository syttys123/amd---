# Native Release Candidate Status

Status: `INTERNAL_RC`

This document tracks the native Rust GUI + C++ worker package separately from
the already deployed .NET `1.0.4` stable package.

Decision (2026-11-10): the native line stays an experimental preview. The
`.NET` GUI remains the product and daily driver, and it keeps `C:\RyzenAdj`.
The native package is not a drop-in replacement and will only be considered
for promotion if it reaches feature and UI parity without regressing the
current experience.

Note (2026-11-11): `rc.8` supersedes `rc.7`. It keeps the Chinese dashboard and
title header, then adds three editable quick presets with backward-compatible
state persistence and direct tray-menu preset commands. Earlier evidence stays
valid for the exact bytes each candidate describes.

## Current Candidate

```text
artifacts/native-packages/amd-mobile-power-v0.6.0-native-rc.8-win-x64-native-preview.zip
```

- Size: `459,023` bytes.
- SHA256:
  `3938c1853703b03c5c914d449d1e6319c202e478cb1113ec60a8a1cd5532fadd`.
- Source commit: `c00836b0ded53446e5c20080ab94a4f93870dd42`.
- Working tree at build time: clean.

## Passed Gates

- Rust GUI lifecycle, three Win32 minimize/restore cycles, tray restore,
  close-to-tray, and single-instance wake-up.
- C++ power-limit policy and battery/AC policy tests.
- Read-only hardware capability and telemetry probe on Ryzen 7 8845HS.
- Native write-control guard and profile-aware target validation.
- Editable `11/24/43 W` presets in an isolated `%LocalAppData%`: labels and
  JSON persistence verified, then policy save verified without losing the
  presets.
- GUI policy save with isolated `%LocalAppData%`.
- Packaged compatibility collector with sanitized JSON.
- Staged checksum verification for every package file.
- Isolated install and uninstall.
- Real Start menu, Startup shortcut, and uninstall-entry create/remove cycle.
- Read-only AC and battery policy plan with the write gate rejecting
  `setPowerPolicy` while writes are disabled.
- Chinese dashboard and title header verified through `verify-rust-gui.ps1`
  `-VerifyWorker`, which reads `WorkerReadOnly = PASS` and the localized
  `已连接 worker` / `供电` / `Fast 上限` fields.
- Controlled AC no-change power-policy write: requested the live `10/10/10 W`
  state, applied and verified, policy disabled, worker shut down through the
  graceful protocol.

Evidence:

- `docs/evidence/packaging/v0.6.0-native-rc.8-release-gate-2026-11-11.json`
- `docs/evidence/packaging/v0.6.0-native-rc.8-clean-2026-11-11.json`
- `docs/evidence/packaging/v0.6.0-native-rc.8-shell-integration-2026-11-11.json`
- `docs/evidence/hardware/v0.6.0-native-rc.8-power-policy-no-change-2026-11-11.json`
- `docs/evidence/ui/native-gui-editable-presets-2026-11-11.json`

Superseded candidates `0.6.0-native-rc.7` and earlier keep their own evidence.

Local review bundle:

```text
artifacts/native-release-review/v0.6.0-native-rc.8
```

Generate it with `native/prepare-release-review.ps1`; the bundle is
`REVIEW_ONLY` and is not a public release.

## Open Gates

- Feature and UI parity with the `.NET` GUI: the native preview still lacks the
  `.NET` simple/advanced mode switch, packaged diagnostics export from the GUI,
  and the final structured layout.
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
