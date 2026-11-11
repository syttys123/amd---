# Native Migration Workspace

This directory contains the Rust GUI/worker-client and C++ privileged-worker
migration prototypes. It does not replace `src/` or `C:\RyzenAdj`.

## Build

Run from the repository root:

```powershell
.\native\build.ps1
```

When the Cargo registry cache is already available, use
`.\native\build.ps1 -Offline`.

Run the native interoperability gate:

```powershell
.\native\verify-native.ps1
```

Run the read-only hardware gate after building the RyzenAdj runtime:

```powershell
.\native\verify-native.ps1 -NoBuild -VerifyHardware -VerifyRustGui -VerifyRustWorker -VerifyWriteGuard
```

Run the Rust GUI lifecycle gate:

```powershell
.\native\verify-rust-gui.ps1
```

The hardware gate launches only the C++ worker, reads capability and snapshot
data, and shuts it down. It does not expose or call any write function.

The script builds:

- `native\rust-gui` with Cargo and runs its lifecycle state-machine tests.
- `native\rust-probe` with Cargo.
- `native\cpp-worker` with the Visual Studio CMake toolchain.
- `native\cpp-worker`'s fake-backend power-limit policy tests.

When the RyzenAdj runtime is staged, `native\build.ps1` also creates
`artifacts\native-build\gui-runtime` with the Rust GUI, C++ worker, and required
hardware DLL/Driver files beside each other.

The native worker has no write capability unless both `--enable-hardware` and
`--enable-write-controls` are supplied. The default verification gate checks
that `applyTarget` is rejected without the write flag.

The native worker maps RyzenAdj families to conservative profiles. Only the
development `8845HS + 4c0009` match is marked verified; other families are
experimental and receive narrower profile ceilings until hardware evidence is
collected.

Check the write-enabled worker without changing power state:

```powershell
.\native\verify-write-controls.ps1 -NoBuild
```

The dry run verifies that an out-of-range target is rejected. To perform the
supervised no-change write and generate hardware evidence, explicitly pass:

```powershell
.\native\verify-write-controls.ps1 -NoBuild -ExecuteNoChangeWrite
```

The Rust GUI write controls are also opt-in:

```powershell
.\native\verify-rust-gui.ps1 -NoBuild -VerifyWorker -VerifyWriteControls `
    -ExecuteNoChangePreset `
    -GuiExecutable .\artifacts\native-build\gui-runtime\amd-mobile-power-gui.exe
```

Without `-ExecuteNoChangePreset`, the verifier edits the three quick presets in
an isolated `%LocalAppData%`, saves them, checks the rewritten button labels,
and verifies the persisted JSON. With `-ExecutePolicySave`, it also confirms
that saving the battery/AC policy does not discard those presets.

The write-control page exposes three editable quick presets, initially `12`,
`25`, and `45 W`. Saving a preset updates the radio-button labels and the
current target, with every value clamped to the active platform profile.
Right-clicking the tray icon also exposes the same presets as direct
`应用预设` commands when write controls are enabled.

The title header provides persistent `简洁`, `高级`, and `置顶` controls. Both
modes share one continuous dark command deck for live power, target input,
quick presets, and apply. Simple mode is the default UI state and adds a flat
four-column telemetry ledger plus diagnostics export. Advanced mode adds
editable presets, battery/AC policy, device capability, runtime state, and a
live STAPM/Fast/Slow read-back ledger. Clicking a preset in simple mode applies
it immediately when writes are enabled; in advanced mode it selects the value
for editing. The same mode and topmost actions are available from the tray menu.

Regenerate the reviewed simple/advanced screenshots without requesting a power
write:

```powershell
.\native\capture-rust-gui-redesign.ps1 `
  -EvidencePath .\artifacts\verify\native-redesign-capture.json
```

Add `-ReadOnly -FilePrefix native-readonly` to capture the disabled-control
state without launching the worker with write controls. The capture script
attaches to the GUI thread, verifies the target is foreground, and then copies
the DWM frame; it fails instead of recording an unrelated desktop window.

Failure-state screenshots can be reproduced without hardware access:

```powershell
.\native\capture-rust-gui-redesign.ps1 `
  -Fixture firmware-clamp `
  -FilePrefix native-ui-firmware-clamp
```

Supported fixtures are `worker-offline`, `firmware-clamp`,
`unsupported-platform`, and `long-error`. They use the explicit test-only
`--ui-fixture` GUI flag, do not start a hardware worker, and do not request a
power write. The capture gate also asserts whether target/preset controls are
enabled and that diagnostics remains available.

`导出诊断` is available in both read-only and write-enabled launches. It writes
a schema-1 JSON document under
`%LocalAppData%\AmdMobilePower\diagnostics\` containing the current sanitized
worker snapshot and, when available, the battery/AC policy. The report excludes
local paths, process IDs, account names, serial numbers, logs, pipe names, and
never uploads anything.

The native worker now implements the v1 `getPowerPolicy` and
`setPowerPolicy` commands. When enabled, a one-second policy loop applies the
battery or AC target after a power-line change, skips duplicate writes, and
backs off failed targets for five seconds. The controller is covered by
fake-backend tests; the read-only IPC gate is part of `verify-native.ps1`.
The Rust GUI exposes battery and AC target fields, an enable checkbox, and a
save button when write controls are enabled. Saved settings live in
`%LocalAppData%\AmdMobilePower\rust-ui-state.json` and are restored on launch.

Check the policy read-only gate or run the supervised no-change hardware path:

```powershell
.\native\verify-power-policy.ps1 -NoBuild
.\native\verify-power-policy.ps1 -NoBuild -ExecuteNoChangePolicy `
    -EvidencePath .\docs\evidence\hardware\power-policy-no-change.json
```

The no-change path reads the current limits, uses them as the active
power-line target, sets the other power-line target to 12 W, verifies the
worker-reported apply result, disables the policy, and shuts down the worker.
The clean `c81a4f8` AC no-change result is recorded in
`docs/evidence/hardware/mechrevo-wujie15-8845hs-native-power-policy-no-change-2026-11-10.json`.

Build and verify the portable native preview ZIP:

```powershell
.\native\build-package.ps1 -NoBuild
```

For a clean package gate that exercises the extracted GUI/worker and
compatibility collector without executing the policy-save write:

```powershell
.\native\build-package.ps1 -NoBuild `
  -Version 0.6.0-native-rc.14 `
  -ReadOnlyRuntimeVerification
```

The resulting package is under `artifacts\native-packages`; the script extracts
the ZIP and reruns the GUI lifecycle, read-only worker, and write-control
button checks. It also exercises the packaged isolated first-install,
same-version overwrite, and uninstall flow, and verifies that the real
Startup-folder and current-user uninstall registry integration does not change.
When the release gate is run on battery, pass `-AllowBatteryWriteGuard` to
`verify-release.ps1`; this only permits the dry-run invalid-target guard and
does not enable a real hardware write.
The installer stages every file before switching directories, preserves the
previous marked installation for rollback during the switch, and refuses to
write into an unmarked non-empty directory. Install and remove the preview with
`install-preview.ps1` and `uninstall-preview.ps1` from the extracted package.

The current internal release candidate is `0.6.0-native-rc.14`: 533,597 bytes,
SHA256
`069ed024ab30ff7cc7bf53bdd251fbbcd88080c83302f6190812d0866a770cbb`.
Its aggregate read-only gate is recorded in
`docs/evidence/packaging/v0.6.0-native-rc.14-release-gate-2026-11-11.json`.
The write-enabled no-change gate remains pending.

Exercise the real Start menu, Startup shortcut, and current-user uninstall
entry without launching the GUI:

```powershell
.\native\verify-preview-shell-integration.ps1
```

The verifier refuses to overwrite an existing native-preview entry, records
the result under `docs\evidence\packaging`, and removes every created artifact
in a `finally` path. The current clean run is
`docs/evidence/packaging/v0.6.0-native-rc.14-shell-integration-2026-11-11.json`.

Verify a real cross-version upgrade from the previous package:

```powershell
.\native\verify-upgrade.ps1 `
  -OldPackage .\artifacts\native-packages\amd-mobile-power-v0.6.0-native-rc.13-win-x64-native-preview.zip `
  -NewPackage .\artifacts\native-packages\amd-mobile-power-v0.6.0-native-rc.14-win-x64-native-preview.zip `
  -EvidencePath .\docs\evidence\packaging\v0.6.0-native-rc.14-cross-version-upgrade-2026-11-11.json
```

The upgrade gate installs the old package, upgrades in place, compares every
installed file with the new package, rejects retained superseded files, runs
the upgraded GUI/worker read-only, and uninstalls the result.

## Current Native Slice

The native slice verifies the process boundary and the existing v1 JSON-lines
protocol. The Rust probe reads health, capability, snapshot, and gated target
responses from a named pipe. The C++ worker implements read-only hardware
snapshots and a validated, read-back-verified `applyTarget` path that remains
disabled unless write controls are explicitly enabled.

When `C:\RyzenAdj\worker\AmdMobilePower.Worker.exe` exists, the verification
also runs the Rust probe against the stable C# worker. This proves that the new
transport can interoperate with the current production process boundary.

See `docs/RUST_CPP_MIGRATION.md` for the phase gates and stable-deployment
boundary.
