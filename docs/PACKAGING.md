# Packaging

## Native Rust/C++ Preview

Build a portable native preview without replacing the stable .NET deployment:

```powershell
.\native\build-package.ps1
```

The native preview contains the Rust GUI, C++ worker, RyzenAdj/WinRing0/InpOut
runtime files, third-party notices, licenses, build metadata, and SHA256
checksums. The build script extracts the ZIP into an isolated directory and
reruns the GUI lifecycle, read-only worker, write-control button, and
read-only compatibility-collector gates.
It is a migration artifact, not the stable `C:\RyzenAdj` deployment.

Current clean native preview:

```text
artifacts/native-packages/amd-mobile-power-v0.3.0-native-preview.1-win-x64-native-preview.zip
```

- Size: `414,716` bytes.
- SHA256:
  `0a5b4390c74c206376224386d88b601f4ec1886bd877ea4a52b659d5b0e43dd9`.
- Source commit: `b0bef13ff60ef35b578eaecf8146698fd839394b`.
- Working tree at build time: clean.
- Verification: package ZIP, extracted GUI lifecycle, read-only worker,
  write-control buttons, read-only compatibility collector, and all staged
  SHA256 entries passed.
- Evidence:
  `docs/evidence/packaging/v0.3.0-native-preview.1-clean-2026-11-10.json`.

## Portable ZIP

Build a self-contained Windows x64 portable package from a clean source tree:

```powershell
.\build-package.ps1 -Version 0.1.0
```

For the full release gate, use:

```powershell
.\verify-release.ps1 `
  -Version 0.1.3-dev `
  -FrameworkDependent `
  -VerifyShellIntegration `
  -VerifyTrayMenu `
  -VerifyTrayExit `
  -VerifyDashboard `
  -VerifyDiagnostics
```

The verifier checks build, tests, formatting, package metadata and checksums,
license files, profile count, machine-state exclusion, and isolated
install/overwrite/uninstall behavior. `-VerifyShellIntegration` additionally
checks the Start menu shortcut, current-user uninstall entry, custom-directory
uninstall command, and either the logon task or Startup-folder fallback.
`-VerifyTrayMenu` additionally checks the real tray icon and context menu on an
interactive desktop; its runtime screenshot stays under `artifacts/verify`.
`-VerifyTrayExit` also invokes the menu's Exit action and requires both GUI and
worker processes to disappear within eight seconds.
`-VerifyDashboard` opens the packaged simple dashboard, waits for live worker
telemetry, checks the unified `电源/电池` label, and requires zero
non-background pixels immediately left of `目标功耗`.
`-VerifyDiagnostics` runs the packaged collector against the packaged worker,
requires a schema-1 JSON report, read-only mode, graceful worker shutdown, and
the absence of local paths, process IDs, log excerpts, and account data.

Build the small framework-dependent variant:

```powershell
.\build-package.ps1 -Version 0.1.0 -FrameworkDependent
```

The lite package requires the Microsoft .NET 8 Desktop Runtime x64 and is
published with a `-lite` filename suffix. It keeps the same process isolation
and native runtime files, but omits the duplicated self-contained .NET runtime.

Current lite development package:

```text
artifacts/packages/amd-mobile-power-v0.1.0-win-x64-lite.zip
```

- Size: 449,612 bytes.
- SHA256:
  `e4c58b20e2efd45f4119920c3b0d7c083b0b30cfcd6061748bd3b63e3c760318`.
- Source commit: `624d959`.
- Working tree at build time: clean.

Current `0.1.1-dev` integration candidate:

```text
artifacts/packages/amd-mobile-power-v0.1.1-dev-win-x64-lite.zip
```

- Size: 464,709 bytes.
- SHA256:
  `44b0602ef43c45738b974ed0ee52b2e62023f2d0dda85e28c9ec40e25c4332f0`.
- Source commit: `4c4462a`.
- Working tree at build time: dirty; this is not release evidence.
- Framework-dependent and requires the Microsoft .NET 8 Desktop Runtime x64.
- Isolated install and uninstall passed under `artifacts`.
- Read-only package smoke passed: the packaged GUI started, the packaged
  worker connected through the named pipe, and AC telemetry reported 10W
  STAPM/Fast/Slow limits.

Current `0.1.2-dev` integration candidate:

```text
artifacts/packages/amd-mobile-power-v0.1.2-dev-win-x64-lite.zip
```

- Size: 554,191 bytes.
- SHA256:
  `38a258e9ca47a10b98593c629715e4f4912366d3fd5ced614a0c8a2b44c592cf`.
- Source commit: `4c4462a`.
- Working tree at build time: dirty; this is not release evidence.
- Framework-dependent and requires the Microsoft .NET 8 Desktop Runtime x64.
- All 30 staged SHA256 entries verified.
- Isolated install and uninstall passed under `artifacts`.
- Packaged read-only startup passed and launched the packaged worker.
- GUI and worker both report product version `0.1.2-dev` and file version
  `0.1.2.0`.

Historical `0.1.3-dev` integration candidate:

```text
artifacts/packages/amd-mobile-power-v0.1.3-dev-win-x64-lite.zip
```

- Size: 593,944 bytes.
- SHA256:
  `020d2b8d5f28955b894612020292285f821d556b22ebacd905154c933601e87b`.
- Source commit: `71be9c8`.
- Working tree at build time: clean.
- Framework-dependent and requires the Microsoft .NET 8 Desktop Runtime x64.
- All 39 staged SHA256 entries verified across 40 files.
- Includes nine conservative profiles, including seven unverified multi-
  generation family profiles.
- Includes `collect-diagnostics.ps1`, which exports a read-only compatibility
  report without opening the GUI.
- GUI diagnostics now use the same field whitelist and path-redaction boundary
  instead of serializing raw worker paths and log excerpts.
- Isolated first install, overwrite, and uninstall passed under `artifacts`.
- Start menu shortcut, current-user uninstall entry, custom-directory uninstall
  command, and Startup-folder fallback creation/removal passed.
- The clean package itself launched in read-only mode, connected to its bundled
  worker, reported `动态上限 12.0 W · 电源`, and produced zero visible boundary
  violations.
- The hidden tray menu opened upward, stayed anchored to the notification icon,
  invoked Exit, and left no GUI or worker process behind.
- Packed read-only startup passed and launched the packed worker.
- Packed diagnostics export reported schema 1, protocol 1, `Hawk Point`,
  `hawk-point-8845hs`, nine profiles, five runtime-file hashes, hardware
  adapter present, and write controls disabled.
- Packaged `collect-diagnostics.ps1` produced sanitized JSON with
  `collectionStatus=PASS`, no drive paths, no process IDs, no worker/log
  directories, no recent logs, and `shutdownProtocol=PASS`. The same collector
  passed under Windows PowerShell 5.1 and PowerShell 7.
- The full local gate passed with 71/71 tests after adding regressions for
  sanitized GUI diagnostics and complete RyzenAdj family coverage.
- The dashboard gate passed with live worker telemetry at
  `动态上限 25.0 W · 电源`; the target-left artifact pixel count was zero.
- GUI and worker both report product version `0.1.3-dev` and file version
  `0.1.3.0`.

Current `1.0.0` local stable package:

```text
artifacts/packages/amd-mobile-power-v1.0.0-win-x64-lite.zip
```

- Size: 593,857 bytes.
- SHA256:
  `8faa541d06421522119de861f252baf612ee39517e2669350623d05b39b02320`.
- Source commit: `c65611b37ef55564346a441907a9f1be3a3d932c`.
- Build SDK: .NET `10.0.400`; product assemblies still target .NET 8 APIs.
- Working tree at build time: clean.
- Contents: 40 files, 39 checksum entries, nine profiles, four license files.
- Full local gate: zero warnings, 71/71 tests, dependency audit, format,
  isolated install/overwrite/uninstall, shell integration, tray menu and
  graceful exit, read-only diagnostics, and packaged dashboard checks passed.
- Packaged battery no-change write: `25/25/20 W` requested and read back;
  live power stayed near `20 W` and worker shutdown was graceful.
- Evidence:
  `docs/evidence/packaging/v1.0.0-clean-2026-11-10.json` and
  `docs/evidence/hardware/mechrevo-wujie15-8845hs-no-change-1.0.0-2026-11-10.json`.

Current `1.0.1` local stable package:

```text
artifacts/packages/amd-mobile-power-v1.0.1-win-x64-lite.zip
```

- Size: 593,759 bytes.
- SHA256:
  `296bbc58ae400d3bfd43bd0a4665ed9c06e78bf0b3c0cdde582e21cdd11e118c`.
- Source commit: `01fd3ae40a70166e4057c02f946549fee987fd80`.
- Build SDK: .NET `10.0.400`; product assemblies still target .NET 8 APIs.
- Working tree at build time: clean.
- Contents: 40 files, 39 checksum entries, nine profiles, four license files.
- Simple mode removes the redundant bottom `详情` button, keeps the write-state
  badge and one-line status message separate, and avoids transient watt text in
  the status strip.
- Full local gate: zero warnings, 71/71 tests, dependency audit, format,
  isolated install/overwrite/uninstall, shell integration, tray menu and
  graceful exit, read-only diagnostics, and packaged dashboard checks passed.
- Packaged battery no-change write: `25/25/20 W` requested and read back; live
  power stayed near `20 W` and worker shutdown was graceful.
- Evidence:
  `docs/evidence/packaging/v1.0.1-clean-2026-11-10.json` and
  `docs/evidence/hardware/mechrevo-wujie15-8845hs-no-change-1.0.1-2026-11-10.json`.

Current `1.0.2` local stable package:

```text
artifacts/packages/amd-mobile-power-v1.0.2-win-x64-lite.zip
```

- Size: `594,482` bytes.
- SHA256:
  `ddf5d70bcfd802e1db317dbacbd40ab63eba024fc3d2c7db175829ee5d2f6f93`.
- Source commit: `9fb180a560a2b2218437345de42d78c936b9b4ea`.
- Build SDK: .NET `10.0.400`; product assemblies still target .NET 8 APIs.
- Working tree at build time: clean.
- Contents: 40 files, 39 checksum entries, nine profiles, four license files.
- Fixes tray restore re-entry that previously raised a WinForms stack overflow,
  merges restore requests through the UI message loop, and shuts down the child
  worker when the GUI parent exits.
- Full local gate: zero warnings, 71/71 tests, dependency audit, format,
  isolated install/overwrite/uninstall, shell integration, tray menu and
  graceful exit, single-click/double-click/menu restore, worker parent-exit
  cleanup, read-only diagnostics, and packaged dashboard checks passed.
- Packaged battery no-change write: `12/12/12 W` requested and read back; actual
  power remained below the ceiling and worker shutdown was graceful.
- Evidence:
  `docs/evidence/packaging/v1.0.2-clean-2026-11-10.json` and
  `docs/evidence/hardware/mechrevo-wujie15-8845hs-no-change-1.0.2-2026-11-10.json`.

Current `1.0.4` local stable package:

```text
artifacts/packages/amd-mobile-power-v1.0.4-win-x64-lite.zip
```

- Size: `594,763` bytes.
- SHA256:
  `f54558295515f875b655a2bdf420c719b907639999700988f0a5910deb033433`.
- Source commit: `b2ac5f42fefec199cc5e8267ed91219c6d5ebb5c`.
- Build SDK: .NET `10.0.400`; product assemblies still target .NET 8 APIs.
- Working tree at build time: clean.
- Contents: 40 files, 39 checksum entries, nine profiles, four license files.
- The `1.0.4` lifecycle fix removes the minimize-to-tray `Resize` re-entry
  path, keeps minimization in the taskbar, and routes every show/hide request
  through one queued, idempotent path.
- Full local gate: zero warnings, 71/71 tests, dependency audit, format,
  isolated install/overwrite/uninstall, shell integration, tray menu, graceful
  exit, UI lifecycle, worker parent-exit cleanup, read-only diagnostics, and
  packaged dashboard checks passed.
- Packaged and deployed no-change write: `45/45/45 W` requested and read back on
  AC; worker shutdown was graceful.
- Evidence:
  `docs/evidence/packaging/v1.0.4-clean-2026-11-10.json` and
  `docs/evidence/packaging/v1.0.4-deployment-2026-11-10.json`.

## Embedded Version Metadata

`Directory.Build.props` is the source of truth for product identity and version:

- Product: `AMD Mobile Power`
- Default version prefix: `0.1.1`
- Company: `AMD Mobile Power contributors`
- Copyright: `Copyright (c) 2026 AMD Mobile Power contributors`
- Application icon: `assets/amd-mobile-power.ico`
- Repository URL: `https://github.com/syttys123/amd-mobile-power`

`build-package.ps1 -Version <version>` overrides the SDK `Version` for both GUI
and worker publishes. The SDK derives `FileVersion` from that value. The GUI
footer reads `Application.ProductVersion`, so it does not require another
hardcoded version string.

Output:

```text
artifacts/packages/amd-mobile-power-v0.1.0-win-x64/
artifacts/packages/amd-mobile-power-v0.1.0-win-x64.zip
artifacts/packages/amd-mobile-power-v0.1.0-win-x64.zip.sha256
```

Package layout:

```text
AmdMobilePower.exe
assets/
collect-diagnostics.ps1
install.ps1
uninstall.ps1
migrate-legacy-owner.ps1
MIGRATING-FROM-LEGACY.md
RELEASE-CHECKLIST.md
worker/
  AmdMobilePower.Worker.exe
  libryzenadj.dll
  WinRing0x64.dll
  WinRing0x64.sys
  inpoutx64.dll
  profiles/
licenses/
  GPL-3.0.txt
  InpOut32-LICENSE.txt
  RyzenAdj-LICENSE.txt
  WinRing0-COPYRIGHT.txt
README.txt
THIRD_PARTY_NOTICES.md
BUILD-INFO.txt
SHA256SUMS.txt
```

The default package is self-contained and does not require a separate .NET
runtime installation. The `-FrameworkDependent` Lite package requires the
Microsoft .NET 8 Desktop Runtime x64 and appends that requirement to
`README.txt`.

## Read-Only Compatibility Collection

The portable package includes `collect-diagnostics.ps1`, allowing a tester to
produce a compatibility report without opening the GUI:

```powershell
powershell -ExecutionPolicy Bypass -File .\collect-diagnostics.ps1
```

The collector starts the packaged worker hidden with `--enable-hardware` only.
It never passes `--enable-write-controls`, exports the worker's read-only
diagnostics through an isolated named pipe, and requests a graceful shutdown.
The JSON file is written to the desktop by default or to an explicit
`-OutputPath`.

The collector uses a field whitelist and recursively replaces known user,
package, temporary, drive, and network paths before writing JSON. It excludes
worker process IDs, executable/log directories, recent logs, and pipe names.
It does not connect to the network or upload the report. Inspect the JSON before
attaching it to a compatibility issue.

## User Installation

Run `install.ps1` from the extracted portable package:

```powershell
.\install.ps1
```

The default installation:

- Copies the application to
  `%LocalAppData%\Programs\AmdMobilePower`.
- Creates a current-user logon scheduled task for `--tray`.
- Falls back to a Startup shortcut if the scheduled task cannot be created.
- Creates an AMD Mobile Power Start menu shortcut.
- Registers an uninstall entry under the current user.
- Preserves `%LocalAppData%\AmdMobilePower\ui-state.json` during upgrades.

Test an install without changing startup entries or launching the application:

```powershell
.\install.ps1 `
  -InstallDirectory D:\amd-mobile-power\artifacts\test-install `
  -NoStartup `
  -NoLaunch `
  -NoShellIntegration
```

Test uninstall from the package:

```powershell
.\uninstall.ps1 `
  -InstallDirectory D:\amd-mobile-power\artifacts\test-install `
  -NoShellIntegration
```

Verify the complete current-user shell integration on a clean test host:

```powershell
.\verify-shell-integration.ps1 `
  -PackageDirectory artifacts\packages\amd-mobile-power-v0.1.3-dev-win-x64-lite
```

The script refuses to start if `AMD Mobile Power` shortcuts or the uninstall
entry already exist. It uses a unique directory below `artifacts\verify`,
verifies installation and fallback behavior, then removes every artifact it
created.

Regenerate the tray-menu release screenshot on an interactive Windows desktop:

```powershell
.\verify-tray-menu.ps1 `
  -PackageDirectory artifacts\packages\amd-mobile-power-v0.1.3-dev-win-x64-lite `
  -VerifyGracefulExit
```

The verifier locates the real hidden-tray icon, checks the tooltip, opens the
upward context menu, validates all primary actions and three editable presets,
enforces screen bounds and horizontal tray anchoring, captures the screenshot,
and closes the menu without clicking a power action. With
`-VerifyGracefulExit`, it invokes `退出` after the screenshot and verifies clean
GUI/worker teardown.

Verify the taskbar and notification-area lifecycle against a packaged build:

```powershell
.\verify-ui-lifecycle.ps1 `
  -PackageDirectory artifacts\packages\amd-mobile-power-v1.0.4-win-x64-lite
```

The script launches the package in read-only mode and verifies three
minimize/restore cycles, close-to-tray, second-instance wake-up, and the absence
of new `AmdMobilePower.exe` crash events. It requires an interactive desktop
and refuses to run while another GUI instance is active.

The current verified local stable package uses SHA256:

```text
f54558295515f875b655a2bdf420c719b907639999700988f0a5910deb033433
```

It was built from clean commit `b2ac5f4` with .NET SDK `10.0.400`.

Rebuilds may produce a different hash because embedded timestamps can change.
Always use the hash generated with the current build.

## Release Gate

A locally generated package is not a public release. Do not publish the ZIP
until:

- The controlled hardware write test passes.
- The bundled third-party license files match `THIRD_PARTY_NOTICES.md`.
- Portable startup, tray lifecycle, worker startup, upgrade, and uninstall are
  verified.
- The release artifact is rebuilt from the current clean commit.
- The release artifact hash, source commit, and clean/dirty state are recorded.

Prepare the local human-review bundle after the package and media gates pass:

```powershell
.\prepare-release-review.ps1
```

The bundle is written under `artifacts\release-review\<version>-<head>` and
contains the portable ZIP, video, Bilibili cover, captions, launch copy, safety
documents, a release-review manifest, and `SHA256SUMS.txt`. The script refuses a
dirty worktree, a mismatched ZIP sidecar, a package commit outside the current
branch, runtime-sensitive changes after the package commit, or a failed media
gate. It never logs in or uploads.

The `v0.1.0`, `v0.1.3-dev`, `v1.0.0`, `v1.0.1`, `v1.0.2`, and `v1.0.3` packages are
retained as historical development/stable artifacts. The current `v1.0.4`
package is a locally verified stable deployment for one physical AMD laptop,
not a public release. Public hardware support still needs a second AMD platform
and the remaining human gates.
