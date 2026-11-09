# Building

## Prerequisites

- Windows x64.
- .NET 8 SDK or a newer SDK capable of building `net8.0`.
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
dotnet test AmdMobilePower.sln -c Release
```

Run the complete local release gate, including package integrity, isolated
install/overwrite/uninstall checks, and current-user shell integration:

```powershell
.\verify-release.ps1 `
  -Version 0.1.3-dev `
  -FrameworkDependent `
  -VerifyShellIntegration
```

The verifier refuses a dirty worktree. Use `-AllowDirty` only for local
diagnostics; a dirty result is not release evidence. Omit
`-VerifyShellIntegration` on a machine where the fixed Start menu or uninstall
entry already exists; that mode only runs the isolated install checks.

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
