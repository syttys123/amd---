# Deployment

## Directory Roles

- `D:\amd-mobile-power`: development repository and source of truth.
- `C:\RyzenAdj`: current stable deployment on the development laptop.

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

## Current Deployment Evidence

On 2026-11-10, the clean `1.0.2` Lite package was promoted to `C:\RyzenAdj`
after copying and hashing the complete `1.0.1` deployment to a recoverable D:
backup.

- Package SHA256:
  `ddf5d70bcfd802e1db317dbacbd40ab63eba024fc3d2c7db175829ee5d2f6f93`
- Package source commit: `9fb180a560a2b2218437345de42d78c936b9b4ea`
- Previous stable rollback directory:
  `C:\RyzenAdj.before-v1.0.2-20261110-154346`
- Recoverable D: backup:
  `artifacts\deployment-backups\C-RyzenAdj-before-v1.0.2-20261110-154346`
- Local write launcher:
  `C:\RyzenAdj\启动 AMD Mobile Power（稳定写入）.lnk`
- Deployment evidence:
  `docs/evidence/packaging/v1.0.2-deployment-2026-11-10.json`

All 40 deployed file hashes matched the verified package. The dashboard
overlap/state check, read-only diagnostics reporting worker `1.0.2`, and a
write-enabled GUI/worker launch from `C:\RyzenAdj` all passed. Single-click tray
restore, graceful tray exit, and GUI-parent-exit worker cleanup also passed.

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
