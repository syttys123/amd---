# Building

## Prerequisites

- Windows x64.
- .NET 10 SDK. CI and the release gate are verified with SDK `10.0.400`.
  Projects continue to target .NET 8 runtime APIs.
- Visual Studio with the MSVC C++ toolchain.
- CMake, either on `PATH` or from the Visual Studio CMake component.
- Git with submodule support.

## Restore Submodules

```powershell
git submodule update --init --recursive
```

## Build the .NET Application

```powershell
dotnet build AmdMobilePower.sln -c Release
dotnet test --solution AmdMobilePower.sln -c Release
```

Product code enforces selected .NET analyzers as errors through
`src/.editorconfig`: null validation, culture-stable formatting, explicit string
comparison, and safe P/Invoke library search paths.

Audit direct and transitive NuGet dependencies for known vulnerabilities and
deprecated packages:

```powershell
.\verify-dependencies.ps1
```

The command requests machine-readable NuGet vulnerability and deprecation
reports, verifies that every solution project was covered, and fails if any
direct or transitive package has an advisory or is marked legacy/deprecated. The
script is verified in Windows PowerShell 5.1 and PowerShell 7. The release gate
runs this audit automatically.

Run the complete local release gate, including package integrity, isolated
install/overwrite/uninstall checks, and current-user shell integration:

```powershell
.\verify-release.ps1 `
  -Version 1.0.2 `
  -FrameworkDependent `
  -VerifyShellIntegration `
  -VerifyTrayMenu `
  -VerifyDashboard `
  -VerifyDiagnostics
```

The verifier refuses a dirty worktree. Use `-AllowDirty` only for local
diagnostics; a dirty result is not release evidence. Omit
`-VerifyShellIntegration` on a machine where the fixed Start menu or uninstall
entry already exists. `-VerifyTrayMenu` requires an interactive desktop and
writes its runtime screenshot under `artifacts/verify`, not into tracked media.
`-VerifyDiagnostics` launches the packaged worker in read-only mode, exports a
sanitized compatibility report through the packaged collector, and requires
graceful shutdown. `-VerifyDashboard` validates the packaged simple-mode
dashboard with live worker telemetry and checks the target-power left region
for the historical gray `--` artifact.

Prepare a local, upload-review-only bundle after the package and media gates
pass:

```powershell
.\prepare-release-review.ps1
```

The command requires a clean worktree, verifies the package hash and embedded
source commit, rejects runtime-sensitive changes made after that commit, reruns
the media gate, copies the ZIP, video, cover, captions, launch copy, security,
installation, and notice documents into `artifacts/release-review`, then writes
a manifest and complete SHA256 list. It performs no login or network upload.

Run the shell-integration gate by itself:

```powershell
.\verify-shell-integration.ps1
```

It refuses to overwrite existing shell integration, creates the normal Start
menu shortcut and uninstall entry, verifies either the logon task or its
Startup-folder fallback, then uninstalls and confirms that the install
directory, shortcuts, registry entry, and task were removed.

Run the interactive tray-menu media gate:

```powershell
.\verify-tray-menu.ps1
```

It verifies the real hidden-tray icon, opens the context menu, checks all
primary actions and three editable presets, validates the upward placement
against the screen bounds, captures the media asset, closes the menu without
invoking an action, and stops only the processes it started. This check needs
an interactive Windows desktop and is not part of headless CI.

## Build RyzenAdj

```powershell
.\build-ryzenadj.ps1
```

Output:

```text
artifacts/ryzenadj-runtime/
  libryzenadj.dll
  WinRing0x64.dll
  WinRing0x64.sys
  inpoutx64.dll
  BUILD-INFO.txt
```

The worker build automatically copies the staged RyzenAdj runtime and profile
JSON files into its output directory when they exist.

`build-ryzenadj.ps1` uses `vswhere` to locate the installed Visual Studio C++
toolchain and selects the matching CMake generator for Visual Studio 2019,
2022, or 2026.

Build output is intentionally ignored by Git.
