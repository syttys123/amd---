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

Run the isolated 1366x768/200% work-area fixture:

```powershell
.\native\verify-small-viewport.ps1 `
  -GuiExecutable .\artifacts\native-build\gui-runtime\amd-mobile-power-gui.exe
```

The fixture sets the test-only
`AMD_MOBILE_POWER_WORK_AREA_FIXTURE=1366x728` environment variable for the
child process. It never changes the Windows display configuration.

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

The GUI command line is described by `native\gui-cli-contract.json`, which is the
single source of truth shared by the Rust parser tests, the promotion helper, and
the publication-readiness gate. Current arguments:

- `--enable-write-controls` enables the write UI; the default is read-only.
- `--simple-mode` / `--advanced-mode` pick the starting view and persist it, so a
  shortcut can pin a mode.
- `--tray` starts hidden in the notification area.
- `--max-target-watts <N>` pins a per-installation hard ceiling for every
  target, preset, and saved policy.
- `--uniform-target-watts <N>` enables automatic policy with both battery and
  AC targets set to the same wattage and persists that policy in the local UI
  state.
- `--dpi-fixture <100|125|150|200>` is a test-only logical DPI override. It
  renders and lays out the UI at the requested scale without changing Windows
  display settings; it is used by the DPI screenshot gate and is not part of
  the desktop shortcut.
- `--pipe-name <name>`, `--worker-executable <path>`, and `--ui-fixture <name>`
  exist for verification and screenshot fixtures.

Unknown arguments make the GUI exit with code 1 and print the rejected token to
stderr, which is what the shortcut launch gate checks.

The native worker maps RyzenAdj families to conservative profiles. Only the
development `8845HS + 4c0009` match is marked verified; other families are
experimental and receive narrower profile ceilings until hardware evidence is
collected. `getProfiles` returns the complete catalog, including every
conservative fallback family, so compatibility reports can identify missing or
misclassified generations without enabling writes.

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

`-ExecuteNoChangePreset` requires external power and three matching live limits
within `5-60 W`. It reads the current limits from diagnostics, places that value
in an isolated preset, applies it through the simple-mode preset button, and
checks both the GUI result and fresh telemetry. It never chooses a fixed 45 W
target. Unequal limits fail before a write, because a uniform GUI preset would
otherwise change the starting state.

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
  -Version 1.0.0-native `
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
The package also includes `install-driver-bootstrap.ps1` and
`uninstall-driver-bootstrap.ps1` for the elevated WinRing0 service. The
installer stops an app-owned running driver and waits for it to stop before
replacing the `.sys` file. The
uninstaller removes `WinRing0_1_2_0` only when its binary path equals the
package's ProgramData driver.

The current stable-local candidate is `1.0.8-native`: 570,836 bytes,
SHA256
`8ce1fc66ca5fb9c087f4777cc79a9e93bfc9a3ddbf01ced4e24578b361f1e768`.
Its aggregate read-only gate is recorded in
`docs/evidence/packaging/v1.0.8-native-release-gate-2026-11-12.json`.
The current-value policy gate passed and is recorded in
`docs/evidence/hardware/v1.0.8-native-power-policy-no-change-2026-11-12.json`.

Exercise the real Start menu, Startup shortcut, and current-user uninstall
entry without launching the GUI:

```powershell
.\native\verify-preview-shell-integration.ps1
```

The verifier refuses to overwrite an existing native-preview entry, records
the result under `docs\evidence\packaging`, and removes every created artifact
in a `finally` path. The current clean run is
`docs/evidence/packaging/v1.0.0-native-shell-integration-2026-11-11.json`.

Verify a real cross-version upgrade from the previous package:

```powershell
.\native\verify-upgrade.ps1 `
  -OldPackage .\artifacts\native-packages\amd-mobile-power-v0.6.0-native-rc.17-win-x64-native-preview.zip `
  -NewPackage .\artifacts\native-packages\amd-mobile-power-v1.0.0-native-win-x64-native-preview.zip `
  -EvidencePath .\docs\evidence\packaging\v1.0.0-native-cross-version-upgrade-2026-11-11.json
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

## Headless Compatibility Probe

Every native package ships `amd-mobile-power-probe.exe`. It can produce a
compatibility report on a laptop that has never seen this project, using only
the package itself:

```powershell
.\amd-mobile-power-probe.exe --diagnose --out .\compatibility.json --markdown .\compatibility.md
```

The probe starts a private worker with read-only hardware access, collects
health, capabilities, telemetry, profiles, and policy state, and emits the same
schema that `import-compatibility-report.ps1` already validates. It never
enables write controls, never needs PowerShell or the GUI, and reports a clear
failure with host information preserved when the driver cannot be opened.

See `docs/HEADLESS_DIAGNOSTICS.md` for the schema, exit codes, privacy rules,
and release-gate coverage.

See `docs/RUST_CPP_MIGRATION.md` for the phase gates and stable-deployment
boundary.
