# Deployment

## Directory Roles

- `D:\amd-mobile-power`: development repository and source of truth.
- `C:\RyzenAdj`: current stable-local native deployment (`1.0.7-native`) on the
  development laptop. The previous `1.0.6-native` build remains at
  `C:\RyzenAdj.before-20261112-023730`, `1.0.5-native` at
  `C:\RyzenAdj.before-20261112-022356`, `1.0.4-native` at
  `C:\RyzenAdj.before-20261112-015439`, `1.0.3-native` at
  `C:\RyzenAdj.before-20261112-011649`, `1.0.3-native` e26ede4 at
  `C:\RyzenAdj.before-20261112-005635`, `1.0.2-native` at
  `C:\RyzenAdj.before-20261112-003929`, and `1.0.1-native` at
  `C:\RyzenAdj.before-20261111-233609`, `1.0.0-native` at
  `C:\RyzenAdj.before-20261111-232010`, and the .NET `1.0.4` deployment at
  `C:\RyzenAdj.before-20261111-223017`.

## Promotion Rules

A build may be copied to `C:\RyzenAdj` only when:

1. `dotnet build AmdMobilePower.sln -c Release` passes with zero warnings.
2. `dotnet test --solution AmdMobilePower.sln -c Release` passes.
3. The release package contains no machine-specific logs or modes.
4. GUI launch, taskbar icon, tray close/reopen, and single-instance behavior pass.
5. The worker starts and reports healthy telemetry.
6. A power-mode smoke test writes a safe value and restores the previous value.
7. The previous stable deployment has a recoverable backup.

## Promotion Flow

```text
D:\amd-mobile-power
  -> build
  -> test
  -> package
  -> stage
  -> smoke test
  -> backup C:\RyzenAdj
  -> deploy to C:\RyzenAdj
  -> verify deployed package
```

No source changes are made directly in `C:\RyzenAdj`.

## Native Stable-Local Promotion

The native Rust GUI + C++ worker line uses the tested reversible helper:

```powershell
.\native\promote-stable-deployment.ps1 `
  -PackagePath .\artifacts\native-packages\amd-mobile-power-v1.0.7-native-win-x64-native-preview.zip `
  -TargetDirectory C:\RyzenAdj `
  -GuiArguments "--enable-write-controls --simple-mode --max-target-watts 10 --uniform-target-watts 10"
```

That command is a dry run. Apply only after reviewing the target, backup, and
shortcut plan:

```powershell
.\native\promote-stable-deployment.ps1 `
  -PackagePath .\artifacts\native-packages\amd-mobile-power-v1.0.7-native-win-x64-native-preview.zip `
  -TargetDirectory C:\RyzenAdj `
  -GuiArguments "--enable-write-controls --simple-mode --max-target-watts 10 --uniform-target-watts 10" `
  -Apply -NoLaunch
```

The helper stops native and legacy owners, moves the current target to a
timestamped backup, installs the verified package, retargets existing desktop
shortcuts while preserving their arguments, writes deployment evidence, and
rolls back on failure.

## Current Deployment Evidence

On 2026-11-12, `1.0.7-native` replaced `1.0.6-native` at `C:\RyzenAdj`. It adds
the safe WinRing0 uninstall helper, reuses an existing valid WinRing0 service
instead of replacing another installation's binary path, and retains the
package-local bootstrap, DPI fixture gate, multi-generation profile catalog,
and 10 W uniform policy.

- Package SHA256:
  `a018e1af1a82a5be1dc1cee4fa54cf419d35a778cd056a16a5a35a34262635c4`
- Package size: `570,352` bytes
- Package source commit: `01cdb506415b0b7fc4b39d7e328f8f282c9696cf`
- Previous stable rollback directory: `C:\RyzenAdj.before-20261112-023730`
- Recoverable D: backup:
  `artifacts\deployment-backups\C-RyzenAdj-before-1.0.7-native-01cdb50-20261112-023730`
- Desktop shortcut:
  `<USER_HOME>\Desktop\功耗设置 5-60W.lnk`
- Shortcut target and arguments:
  `C:\RyzenAdj\amd-mobile-power-gui.exe --enable-write-controls --simple-mode --max-target-watts 10 --uniform-target-watts 10`
- Embedded icon: `RT_GROUP_ICON` 1 with 9 `RT_ICON` images; extracted 32x32
  matches `assets/amd-mobile-power.ico` pixel for pixel
- Launch verification: `PASS` (window title `AMD Mobile Power`)
- Deployed payload: all 18 staged files match; `install-driver-bootstrap.ps1`
  SHA256 `6f76804f1312101103fed6a1f2677feab5e7576c2a2f3ce26eb8c3b6200a5438`
  and `uninstall-driver-bootstrap.ps1` SHA256
  `4199a8fa7e68dd2216bf0b7d61151cf066d4c8f0080abe3690cdf616af2496c6`
- Uniform policy: `enabled=true`, battery and AC both `10/10/10 W`,
  `maxTargetWatts=10`; live AC read-back `10/10/10 W`
- Profile catalog: 10 entries, one verified, RyzenAdj families `0-15` each
  mapped exactly once; worker version `0.6.0-native`
- DPI layout fixtures: 100/125/150% client sizes
  `640x392`/`780x680`, `800x490`/`975x850`, and `960x588`/`1170x1020`: PASS
- Deployment evidence:
  `docs/evidence/packaging/v1.0.7-native-deployment-2026-11-12.json`
- Deployment UI evidence:
  `docs/evidence/ui/native-deployed-1.0.7-native-ui-2026-11-12.json`

The prior `1.0.6-native` deployment remains recoverable at
`C:\RyzenAdj.before-20261112-023730`. It added the package-local driver
bootstrap. The `1.0.5-native` deployment at
`C:\RyzenAdj.before-20261112-022356` introduced the test-only `--dpi-fixture`
renderer and the 100/125/150% logical layout gate.

The shell icon cache is refreshed with `SHChangeNotify(SHCNE_ASSOCCHANGED)` and
`ie4uinit.exe -show` after promotion so the new icon appears immediately.

On 2026-11-11, `1.0.2-native` replaced `1.0.1-native` at `C:\RyzenAdj`. It
embeds the application icon as a PE resource, so Explorer, the taskbar,
Alt+Tab, and the desktop shortcut show the real icon.

- Package SHA256:
  `614743257e66c002b5873e3bc5f36f57a874bf763e6a3cb728a28225eec16d9c`
- Package size: `556,027` bytes
- Package source commit: `545f6bcc2e116e667cad0f87331d97b5b9284c2a`
- Previous stable rollback directory: `C:\RyzenAdj.before-20261111-233609`
- Recoverable D: backup:
  `artifacts\deployment-backups\C-RyzenAdj-before-1.0.2-native-20261111-233609`
- Shortcut target and arguments:
  `C:\RyzenAdj\amd-mobile-power-gui.exe --enable-write-controls --simple-mode`

On 2026-11-11, `1.0.1-native` replaced `1.0.0-native` at `C:\RyzenAdj`. It fixes
the desktop shortcut exiting immediately with `unknown argument: --simple-mode`.

- Package SHA256:
  `992290ffb2337038c937932e2a4888db19946df46c2678b7a32b33285f997cad`
- Package size: `534,763` bytes
- Package source commit: `442309753f6965a4ba01ff0ae4f34e81280f34e5`
- Previous stable rollback directory: `C:\RyzenAdj.before-20261111-232010`
- Recoverable D: backup:
  `artifacts\deployment-backups\C-RyzenAdj-before-1.0.1-native-20261111-232010`
- Desktop shortcut:
  `<USER_HOME>\Desktop\功耗设置 5-60W.lnk`
- Shortcut target and arguments:
  `C:\RyzenAdj\amd-mobile-power-gui.exe --enable-write-controls --simple-mode`
- Launch verification: `PASS` (window title `AMD Mobile Power`)
- Deployment evidence:
  `docs/evidence/packaging/v1.0.1-native-deployment-2026-11-11.json`
- Deployment UI evidence:
  `docs/evidence/ui/native-deployed-1.0.1-native-ui-2026-11-11.json`

The shortcut arguments are now checked against `native/gui-cli-contract.json`.
The promotion helper drops arguments outside that contract, and the launch check
runs the promoted GUI with the real shortcut arguments plus an isolated
`%LocalAppData%` and a unique worker pipe. Nothing is written to the power
policy during that check because the isolated state has no saved policy.

On 2026-11-11, `1.0.0-native` replaced the .NET `1.0.4` directory at
`C:\RyzenAdj`.

- Package SHA256:
  `f3fd6ea1d1b0292c6ec9ea7445f191adc302066f78a728528a3722923c73a0bf`
- Package source commit: `ddb7d9cba3195f4a16df1299215a9e26cd18544f`
- Previous stable rollback directory:
  `C:\RyzenAdj.before-20261111-223017`
- Recoverable D: backup:
  `artifacts\deployment-backups\C-RyzenAdj-before-1.0.0-native-20261111-223017`
- Desktop shortcut:
  `<USER_HOME>\Desktop\功耗设置 5-60W.lnk`
- Shortcut target and arguments:
  `C:\RyzenAdj\amd-mobile-power-gui.exe --enable-write-controls --simple-mode`
- Deployment evidence:
  `docs/evidence/packaging/v1.0.0-native-deployment-2026-11-11.json`

The deployed GUI/worker passed worker connection, three minimize/restore
cycles, close-to-tray, tray restore, single-instance wake, view switching,
topmost, preset editing, battery-only toggle, and diagnostics export. No power
write was requested during deployment verification.

On 2026-11-10, the clean `1.0.4` Lite package was promoted to `C:\RyzenAdj`
after copying and hashing the complete `1.0.3` deployment to a recoverable D:
backup.

- Package SHA256:
  `f54558295515f875b655a2bdf420c719b907639999700988f0a5910deb033433`
- Package source commit: `b2ac5f42fefec199cc5e8267ed91219c6d5ebb5c`
- Previous stable rollback directory:
  `C:\RyzenAdj.before-v1.0.4-20261110-190202`
- Recoverable D: backup:
  `artifacts\deployment-backups\C-RyzenAdj-before-v1.0.4-20261110-190202`
- Local write launcher:
  `C:\RyzenAdj\启动 AMD Mobile Power（稳定写入）.lnk`
- Deployment evidence:
  `docs/evidence/packaging/v1.0.4-deployment-2026-11-10.json`

All 40 deployed file hashes matched the verified package. The dashboard
overlap/state check, complete `AMD Mobile Power` header, 78 px write-state cell,
read-only diagnostics reporting worker `1.0.4`, UI minimize/restore and
close-to-tray lifecycle, tray menu and graceful exit, and a write-enabled
GUI/worker launch from `C:\RyzenAdj` all passed. The deployed no-change write
gate wrote `45/45/45 W` back to the same values and read them back exactly.

The prior `1.0.3` promotion remains available as historical evidence:

- Package SHA256:
  `795be664e991915a38457feb8d47c41879b2baaa2db03af559032736a7595a1c`
- Package source commit: `335b42031876826567870fa7aebcdb659de578d3`
- Previous stable rollback directory:
  `C:\RyzenAdj.before-v1.0.3-20261110-163339`
- Recoverable D: backup:
  `artifacts\deployment-backups\C-RyzenAdj-before-v1.0.3-20261110-163339`
- Deployment evidence:
  `docs/evidence/packaging/v1.0.3-deployment-2026-11-10.json`

The prior `1.0.2` promotion remains available as historical evidence:

- Package SHA256:
  `ddf5d70bcfd802e1db317dbacbd40ab63eba024fc3d2c7db175829ee5d2f6f93`
- Package source commit: `9fb180a560a2b2218437345de42d78c936b9b4ea`
- Previous stable rollback directory:
  `C:\RyzenAdj.before-v1.0.2-20261110-154346`
- Recoverable D: backup:
  `artifacts\deployment-backups\C-RyzenAdj-before-v1.0.2-20261110-154346`
- Deployment evidence:
  `docs/evidence/packaging/v1.0.2-deployment-2026-11-10.json`

The prior `1.0.1` promotion remains available as historical evidence:

- Package SHA256:
  `296bbc58ae400d3bfd43bd0a4665ed9c06e78bf0b3c0cdde582e21cdd11e118c`
- Package source commit: `01fd3ae40a70166e4057c02f946549fee987fd80`
- Previous stable rollback directory:
  `C:\RyzenAdj.before-v1.0.1-20261110-135925`
- Recoverable D: backup:
  `artifacts\deployment-backups\C-RyzenAdj-before-v1.0.1-20261110-135925`
- Deployment evidence:
  `docs/evidence/packaging/v1.0.1-deployment-2026-11-10.json`

The prior `1.0.0` promotion remains available as historical evidence:

- Package SHA256:
  `8faa541d06421522119de861f252baf612ee39517e2669350623d05b39b02320`
- Package source commit: `c65611b37ef55564346a441907a9f1be3a3d932c`
- Legacy rollback directory:
  `C:\RyzenAdj.legacy-before-v1.0.0-20261110-132006`
- Recoverable D: backup:
  `artifacts\deployment-backups\C-RyzenAdj-before-v1.0.0-20261110-132006`
- Local write launcher:
  `C:\RyzenAdj\启动 AMD Mobile Power（稳定写入）.lnk`
- Deployment evidence:
  `docs/evidence/packaging/v1.0.0-deployment-2026-11-10.json`
