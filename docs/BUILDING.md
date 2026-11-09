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

Run the complete local release gate, including package integrity and isolated
install/overwrite/uninstall checks:

```powershell
.\verify-release.ps1 -Version 0.1.3-dev -FrameworkDependent
```

The verifier refuses a dirty worktree. Use `-AllowDirty` only for local
diagnostics; a dirty result is not release evidence.

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
