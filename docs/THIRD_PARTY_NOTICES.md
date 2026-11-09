# Third-Party Notices

This file must be completed before any public binary release.

## RyzenAdj

- Upstream: `https://github.com/FlyGoat/RyzenAdj`
- Integration: Git submodule at `third_party/RyzenAdj`
- License: GNU Lesser General Public License v3.0
- Current reviewed commit: `5775fc3e6dbb25c7030ee2d100a1bdd6e8bf2d0a`
- Redistribution: planned as an unmodified shared `libryzenadj.dll`
- Source is retained in this repository through the submodule

Release packages must include the RyzenAdj LGPL license and a clear notice that
the application dynamically uses the RyzenAdj library.

## Windows Driver Components

RyzenAdj's upstream Windows directory includes:

- `WinRing0x64.dll`
- `WinRing0x64.sys`
- `inpoutx64.dll`

These components may be blocked by Windows security software and require
separate redistribution and safety review. The upstream repository currently
does not make their licensing status sufficiently clear in this project's
review notes. Do not publish binaries until this item is resolved.

## Future Dependencies

For each additional dependency record:

- Project name and upstream URL.
- Version or commit.
- License.
- Whether source or binaries are redistributed.
- Required notices and source-offer obligations.
- Security implications.

Do not publish release binaries until this document is complete.

