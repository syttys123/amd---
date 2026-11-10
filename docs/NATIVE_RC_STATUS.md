# Native Release Candidate Status

Status: `INTERNAL_RC`

This document tracks the native Rust GUI + C++ worker package separately from
the already deployed .NET `1.0.4` stable package.

Decision (2026-11-10): the native line stays an experimental preview. The
`.NET` GUI remains the product and daily driver, and it keeps `C:\RyzenAdj`.
The native package is not a drop-in replacement and will only be considered
for promotion if it reaches feature and UI parity without regressing the
current experience.

Note (2026-11-11): `rc.10` supersedes `rc.9`. It replaces the incremental native
dashboard with a clean-room double-buffered UI, adds packaged read-only runtime
verification that never enables a policy write, and closes the native simple/
advanced UI parity gate. Earlier evidence stays valid for the exact bytes each
candidate describes.

## Current Candidate

```text
artifacts/native-packages/amd-mobile-power-v0.6.0-native-rc.10-win-x64-native-preview.zip
```

- Size: `524,700` bytes.
- SHA256:
  `112cc0eb0af0de8f9ac8f77673fb482f127f53da35362db0230c35702c09c6bc`.
- Source commit: `466c3b273564becaad4af3f94f4beea5192d49ec`.
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
- GUI diagnostics export in read-only and write-enabled modes: schema-1 JSON
  parsed on the 8845HS AC snapshot, privacy fields verified, and no local path
  or pipe name present.
- Clean-room native UI with a double-buffered custom canvas, four-region simple
  mode, three-panel advanced mode, stable tabular telemetry, keyboard
  navigation, focus rings, and the embedded title/taskbar/tray icon.
- `0.6.0-native-rc.10` clean package verification with 16 checksum entries,
  isolated install/uninstall, extracted GUI/worker read-only verification,
  compatibility JSON/Markdown collection, and no policy write:
  `PolicyWriteVerification=Skipped`.
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

- `docs/evidence/packaging/v0.6.0-native-rc.10-clean-2026-11-11.json`
- `docs/evidence/packaging/v0.6.0-native-rc.10-release-gate-2026-11-11.json`
- `docs/evidence/packaging/v0.6.0-native-rc.10-shell-integration-2026-11-11.json`
- `docs/evidence/hardware/v0.6.0-native-rc.9-power-policy-no-change-2026-11-11.json`
- `docs/evidence/ui/native-gui-editable-presets-2026-11-11.json`
- `docs/evidence/ui/native-gui-diagnostics-export-2026-11-11.json`
- `docs/evidence/ui/native-redesign-2026-11-11.json`

Superseded candidates `0.6.0-native-rc.9` and earlier keep their own evidence.

Local review bundle:

```text
artifacts/native-release-review/v0.6.0-native-rc.10
```

Generate it with `native/prepare-release-review.ps1`; the bundle is
`REVIEW_ONLY` and is not a public release.

## Open Gates

- At least one second physical AMD laptop must provide read-only compatibility
  evidence using `collect-native-diagnostics.ps1`.
- Run the supervised `rc.10` no-change hardware policy/write gate with the
  normal write-enabled release verifier before treating the UI redesign as
  hardware-promotable. The current clean package gate deliberately skipped
  policy writes.
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
