# Third-Party Licensing Review

Last reviewed: 2026-11-10

This document records an engineering redistribution review of the binaries
produced by `build-package.ps1`. It is not legal advice. The project owner must
still approve the exact release package and its source-availability links.

## Reviewed Scope

| Component | Distributed form | Version or pin | Recorded license |
| --- | --- | --- | --- |
| AMD Mobile Power | GUI and worker binaries | Repository release commit | MIT |
| RyzenAdj | `worker\libryzenadj.dll`, built as a shared library | `5775fc3e6dbb25c7030ee2d100a1bdd6e8bf2d0a` | LGPL-3.0 |
| InpOut32 / InpOutx64 | `worker\inpoutx64.dll` | `1.5.0.0` | MIT-style terms |
| WinRing0 | `worker\WinRing0x64.dll`, `worker\WinRing0x64.sys` | DLL `1.3.0.18`, SYS `1.2.0.5` | Two-clause BSD |

The official license texts are retained under `third_party/licenses/` and copied
into each package's `licenses/` directory. The RyzenAdj LGPL text is copied from
the pinned upstream submodule.

## RyzenAdj LGPL-3.0

The package dynamically loads `libryzenadj.dll` from the worker directory. It is
not statically linked into the GUI or worker. This separation keeps the
application and library independently replaceable.

Package obligations and current evidence:

- Include the upstream LGPL-3.0 text:
  `licenses/RyzenAdj-LICENSE.txt`.
- Include the canonical GNU GPL-3.0 text referenced by LGPL-3.0:
  `licenses/GPL-3.0.txt`.
- Identify the library and its use:
  `THIRD_PARTY_NOTICES.md` and `README.txt`.
- Publish the pinned corresponding source and reproducible build entry point:
  `third_party/RyzenAdj` at
  `5775fc3e6dbb25c7030ee2d100a1bdd6e8bf2d0a`, built by
  `build-ryzenadj.ps1`.
- Preserve the user's ability to replace the library: the worker resolves the
  separate `libryzenadj.dll`; compatible rebuilt DLLs can replace it.

The reviewed canonical GPL-3.0 text is 35,149 bytes with SHA256:

```text
3972dc9744f6499f0f9b2dbf76696f2ae7ad8af9b23dde66d6af86c9dfb36986
```

## InpOut32

The bundled `inpoutx64.dll` is distributed with the copyright and permission
notice in `licenses/InpOut32-LICENSE.txt`. The notice must remain in binary
distributions. The recorded package hash and provenance are maintained in
`THIRD_PARTY_NOTICES.md`.

## WinRing0

The bundled WinRing0 DLL and driver are distributed under the two-clause BSD
terms in `licenses/WinRing0-COPYRIGHT.txt`. Binary redistribution requires the
copyright notice, condition list, and disclaimer in the accompanying
documentation.

This license review does not establish driver safety or compatibility. WinRing0
may be blocked, quarantined, or unloaded by Windows security software. The
application must not instruct users to disable security protections.

## Release Checklist

Before attaching a package to a public release:

- Build from a clean committed tree and record the source commit.
- Confirm all four license files are present in the ZIP.
- Confirm the RyzenAdj submodule is still pinned to the reviewed commit.
- Confirm release notes link to the corresponding repository source and state
  that `worker\libryzenadj.dll` can be replaced with a compatible build.
- Re-run `SHA256SUMS.txt` verification and record the package SHA256.
- Have the project owner review the final package and notices.

## Residual Risk

- This document is not a substitute for legal advice.
- RyzenAdj source availability depends on keeping the repository and release
  source link available for the life of the binary distribution.
- The old WinRing0 driver remains a security and compatibility risk even when
  its redistribution terms are satisfied.
