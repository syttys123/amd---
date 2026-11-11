# Deployment

## Directory Roles

- `D:\amd-mobile-power`: development repository and source of truth.
- `C:\RyzenAdj`: current stable-local native deployment on the development
  laptop. The previous .NET `1.0.4` deployment remains at
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
  -PackagePath .\artifacts\native-packages\amd-mobile-power-v1.0.0-native-win-x64-native-preview.zip `
  -TargetDirectory C:\RyzenAdj
```

That command is a dry run. Apply only after reviewing the target, backup, and
shortcut plan:

```powershell
.\native\promote-stable-deployment.ps1 `
  -PackagePath .\artifacts\native-packages\amd-mobile-power-v1.0.0-native-win-x64-native-preview.zip `
  -TargetDirectory C:\RyzenAdj `
  -Apply -NoLaunch
```

The helper stops native and legacy owners, moves the current target to a
timestamped backup, installs the verified package, retargets existing desktop
shortcuts while preserving their arguments, writes deployment evidence, and
rolls back on failure.

## Current Deployment Evidence

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
