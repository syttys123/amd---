# Third-Party Notices

This file records the third-party binaries currently included in development
packages. Public releases still require the runtime and compatibility gates in
`DEV_STATUS.md`.

## RyzenAdj

- Upstream: `https://github.com/FlyGoat/RyzenAdj`
- Integration: Git submodule at `third_party/RyzenAdj`
- License: GNU Lesser General Public License v3.0
- Current reviewed commit: `5775fc3e6dbb25c7030ee2d100a1bdd6e8bf2d0a`
- Redistribution: planned as an unmodified shared `libryzenadj.dll`
- Source is retained in this repository through the submodule

Release packages include `licenses/RyzenAdj-LICENSE.txt` and a clear notice
that the application dynamically loads the RyzenAdj library.

## InpOut32 / InpOutx64

- Author and distribution:
  `https://www.highrez.co.uk/downloads/inpout32/default.htm`
- Packaged file: `inpoutx64.dll`
- File version: `1.5.0.0`
- SHA256:
  `5f27ed4d5cd58a1ee23deeb802e09e73f3a1d884ce2135f6e827f67b171269e7`
- License: MIT-style terms reproduced by Highresolution Enterprises
- Review evidence:
  - The SHA256 exactly matches the `x64/inpoutx64.dll` in the current official
    `InpOutBinaries` download.
  - The official download includes `license.txt`.
  - The upstream Highresolution page states that the 1.5.0.1 update adopted the
    standard MIT License.
- Package copy: `licenses/InpOut32-LICENSE.txt`

The copyright notice and permission notice must remain in binary
distributions.

## WinRing0

- Upstream project family: OpenLibSys WinRing0 1.3.x
- Packaged files:
  - `WinRing0x64.dll`, file version `1.3.0.18`
  - `WinRing0x64.sys`, file version `1.2.0.5`
- SHA256:
  - DLL:
    `a746fd5728e7485f741cc330a279674bc8590b1b8007d8614046c49f58698485`
  - SYS:
    `11bd2c9f9e2397c9a16e0990e4ed2cf0679498fe0fd418a3dfdac60b5c160ee5`
- License: two-clause BSD terms
- Review evidence:
  - RyzenAdj's `lib/win32/OlsDef.h` and `OlsApi.h` identify the files as
    WinRing0 1.3.x under "The modified BSD license".
  - The OpenLibSys `COPYRIGHT.txt` contains the matching two-clause BSD terms.
  - The driver is signed by Noriyuki MIYAZAKI using a 2007-2008 GlobalSign
    ObjectSign certificate.
- Package copy: `licenses/WinRing0-COPYRIGHT.txt`

This confirms redistribution permission, not runtime compatibility. WinRing0 is
old low-level driver software and may be blocked, quarantined, or unloaded by
Windows security software. Release testing must document those failures and
must not instruct users to disable security controls.

## Future Dependencies

For each additional dependency record:

- Project name and upstream URL.
- Version or commit.
- License.
- Whether source or binaries are redistributed.
- Required notices and source-offer obligations.
- Security implications.
