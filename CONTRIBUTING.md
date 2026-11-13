# Contributing

Thanks for helping AMD Mobile Power cover more laptops safely.

## Safety First

- The application is read-only by default. Do not add code paths that write
  power limits without an explicit user unlock or a documented test flag.
- Hardware tests need the owner's consent and a supervised session. Use the
  current-value no-change flow in `docs/HARDWARE_TEST_PROCEDURE.md`; never pick
  a fixed "safe" wattage for an unknown device.
- Do not ask users to disable Windows security controls, patch drivers, or
  bypass firmware checks to make a build run.
- Diagnostics must stay sanitized: no account names, serial numbers, local
  paths, process IDs, logs, or unrelated desktop content.

## Report A New Laptop

1. Extract the portable ZIP and run the read-only collector:

   ```powershell
   .\amd-mobile-power-probe.exe --diagnose --out compatibility.json --markdown compatibility.md
   ```

   Exit AMD Mobile Power from the tray first so the private worker can read
   live limits.

2. Read the JSON and Markdown once more before attaching them.
3. Open the "AMD laptop compatibility report" issue template and attach the
   report plus the requested STAPM / Fast / Slow values.
4. Only after a maintainer confirms the profile should work, run a supervised
   first write from `docs/HARDWARE_TEST_PROCEDURE.md`. Keep the original limits
   and restore them afterwards.

## Build And Test

```powershell
.\native\build.ps1 -Offline
.\native\verify-native.ps1
.\native\verify-docs.ps1
```

Before a release candidate:

```powershell
.\native\verify-release.ps1 `
  -Version <version> `
  -VerifyReproducibility `
  -VerifyShellIntegration `
  -ExecuteNoChangePolicy `
  -VerifyWorkerHang
```

The release gate expects a clean tracked worktree and writes evidence under
`docs/evidence/`. Hardware-dependent steps must run on a supported machine; CI
covers the build, tests, packaging, reproducibility, and probe self-test.

## Code Conventions

- The C++ worker owns all hardware access. The Rust GUI only talks to it over
  the named-pipe contract in `docs/IPC.md`.
- Keep platform detection capability-based. Add conservative family fallbacks
  instead of assuming one BIOS layout.
- Preserve the double-buffered drawing, tray lifecycle, and single-instance
  behavior covered by `native/verify-rust-gui.ps1`.
- Prefer small focused commits with a scope prefix such as
  `fix(native-gui):`, `test(native):`, or `docs:` and state the root cause.
- Run `cargo fmt` and Clippy with `-D warnings` before pushing.

## Publication

Public GitHub Releases, tags, Bilibili uploads, and account logins require the
project owner's explicit approval. A green local gate means "ready for human
review", not "approved to publish".
