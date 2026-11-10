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
