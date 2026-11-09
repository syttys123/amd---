# Packaging

## Portable ZIP

Build a self-contained Windows x64 portable package from a clean source tree:

```powershell
.\build-package.ps1 -Version 0.1.0
```

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
README.txt
THIRD_PARTY_NOTICES.md
BUILD-INFO.txt
SHA256SUMS.txt
```

The package is self-contained and does not require a separate .NET runtime
installation.

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

The verified local development package uses SHA256:

```text
3428c33d4967c7c5e7d06abe98b97198e2c0f3fbbc4cfc6bbdc09bd13f74bcf0
```

It was built from clean commit `8a750d5`.

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

The current local `v0.1.0` package was built from clean commit `8a750d5` and is
useful for development testing. It is not a public release.
