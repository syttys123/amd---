# Packaging

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

Current `0.1.3-dev` integration candidate:

```text
artifacts/packages/amd-mobile-power-v0.1.3-dev-win-x64-lite.zip
```

- Size: 593,334 bytes.
- SHA256:
  `d9f73ff16d69ad6ab20beffed46d26b0488e2295cef3ddd3a8b71736c85c4dbb`.
- Source commit: `1732ac0`.
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
- The full local gate passed with 63/63 tests after adding a regression that
  parses GUI diagnostic JSON and rejects private fields or absolute local paths.
- GUI and worker both report product version `0.1.3-dev` and file version
  `0.1.3.0`.

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

The current verified local development package uses SHA256:

```text
d9f73ff16d69ad6ab20beffed46d26b0488e2295cef3ddd3a8b71736c85c4dbb
```

It was built from clean commit `1732ac0`.

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

The current local `v0.1.0` package was built from clean commit `cba9c91` and is
useful for development testing. It is not a public release.
