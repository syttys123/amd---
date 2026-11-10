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

Without `-ExecuteNoChangePreset`, this only checks that the controls exist.

Build and verify the portable native preview ZIP:

```powershell
.\native\build-package.ps1 -NoBuild
```

The resulting package is under `artifacts\native-packages`; the script extracts
the ZIP and reruns the GUI lifecycle, read-only worker, and write-control
button checks. It also exercises the packaged isolated install/uninstall flow
and verifies that the real Startup-folder and current-user uninstall registry
integration does not change. Install and remove the preview with
`install-preview.ps1` and `uninstall-preview.ps1` from the extracted package.

The current clean package is `0.4.0-native-preview.1`; its hash and evidence
are recorded in `docs/PACKAGING.md` and
`docs/evidence/packaging/v0.4.0-native-preview.1-clean-2026-11-10.json`.

Exercise the real Start menu, Startup shortcut, and current-user uninstall
entry without launching the GUI:

```powershell
.\native\verify-preview-shell-integration.ps1
```

The verifier refuses to overwrite an existing native-preview entry, records
the result under `docs\evidence\packaging`, and removes every created artifact
in a `finally` path. The recorded clean run is
`docs/evidence/packaging/v0.4.0-native-preview.1-shell-integration-2026-11-10.json`.

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
