# Release Candidate Review

状态：`DRAFT_FOR_HUMAN_REVIEW`

这不是公开 Release，也不是 B 站上传授权。本文汇总当前可复核资产、已验证边界
和仍需人工完成的门禁。

## Source And Package

- Repository: `https://github.com/syttys123/amd-mobile-power`
- Current runtime source commit reviewed: `b2ac5f4`
- Package source commit: `b2ac5f4`
- Package: `artifacts/packages/amd-mobile-power-v1.0.4-win-x64-lite.zip`
- Size: `594,763` bytes
- SHA256: `f54558295515f875b655a2bdf420c719b907639999700988f0a5910deb033433`
- Files / checksums / profiles / licenses: `40 / 39 / 9 / 4`
- Runtime: Microsoft .NET 8 Desktop Runtime x64

The ZIP was rebuilt from a clean `b2ac5f4` worktree with .NET SDK `10.0.400`,
matching the pinned CI toolchain. The package includes the complete
taskbar/notification-area lifecycle fix, queued single-instance restore, and
worker cleanup.
Later documentation-only commits do not change the packaged runtime files.

## Local Verification

Evidence:
`docs/evidence/packaging/v1.0.4-clean-2026-11-10.json`

- Build warnings / errors: `0 / 0`
- SDK: `10.0.400`
- Tests: `71 passed, 0 failed`
- Formatting verification: PASS
- NuGet dependency audit: PASS (`6` projects, `0` advisories, `0` deprecated packages)
- Isolated install, overwrite, and uninstall: PASS
- Start menu, uninstall entry, startup fallback: PASS
- Tray menu direction: up
- Tray menu bounds and horizontal anchoring: PASS
- Tray single-click, double-click, and menu restore: PASS
- Tray ghost-icon retry protection: PASS
- GUI parent exit leaves no orphaned worker: PASS
- Graceful tray exit: PASS
- Win32 minimize/restore, close-to-tray, and second-instance wake-up: PASS
- Windows Application crash events during lifecycle verification: `0`
- Packaged simple dashboard gray-dot and power-line check: PASS
- Bottom `详情` button absent and write-state/status bounds overlap check: PASS
- Complete `AMD Mobile Power` header and 78 px status-cell check: PASS
- Packaged read-only diagnostics collector: PASS
- Packaged stable-package no-change hardware write: PASS
- Local deployment to `C:\RyzenAdj`: PASS
- Deployed tray single-click restore and graceful menu exit: PASS
- GUI and collector diagnostic field whitelist / path redaction: PASS
- RyzenAdj family `0-15` profile coverage: PASS

Machine-local release evidence lives under `artifacts/verify` and is intentionally
not committed.

Generate the no-upload human-review bundle with
`.\prepare-release-review.ps1`. It writes the ZIP, video, cover, captions,
launch copy, safety documents, manifest, and SHA256 list under
`artifacts/release-review`.

## Hardware Evidence

### Verified write/read-back

- Controlled `10/10/10 W` and `12/12/12 W` writes passed on the development
  laptop.
- Earlier `25/25/25 W` and a 45 W request were recorded; firmware may clamp
  STAPM while Fast/Slow remain the enforceable limit.
- Packaged no-change write gate: `45/45/45 W -> 45/45/45 W` on AC.
- `1.0.4` packaged and deployed no-change write:
  `45/45/45 W -> 45/45/45 W`, with graceful shutdown.

### Real battery read-only baseline

- Evidence:
  `docs/evidence/hardware/mechrevo-wujie15-8845hs-battery-preflight-2026-11-10.json`
- Power line: battery / discharging
- STAPM/Fast/Slow limits: `25/25/20 W`
- Planned target: `12/12/12 W`
- Hardware writes: `0`
- Worker shutdown: `PASS`

### Supervised battery policy transition

- Evidence:
  `docs/evidence/hardware/mechrevo-wujie15-8845hs-policy-2026-11-10.json`
- AC baseline: `39/45/25 W`
- Battery baseline: `25/25/20 W`
- Battery target: `12/12/12 W`
- Fast/Slow read-back: `12/12 W`
- Settled live STAPM: about `12.52 W`
- AC restore: Fast/Slow `45/25 W`
- Final restore and worker shutdown: `PASS`

Dashboard capture:

```text
artifacts/verify/deployed-dashboard-v1.0.4-20261110-190306.png
```

- Dimensions: `574x438`
- SHA256: `095afa9c7aafa5b71c730a7c881f9fb5f9dc967111dd3178f1a1f0e14c121e21`
- Header: complete `AMD Mobile Power`
- Header-to-mode-control gap: `245 px`
- Write-state cell width: `78 px`
- Bottom `详情` button: absent
- Write-state/status overlap: PASS
- Visible boundary violations: `0`

## Media And Launch Copy

### Promotional video draft

```text
artifacts/media/amd-mobile-power-promo-draft-2026-11-10/amd-mobile-power-intro-draft-2026-11-10.mp4
```

- Duration: `77.1 s`
- Video: `1920x1080`, 25 fps, H.264
- Audio: AAC stereo, mean `-21.2 dB`, peak `-1.3 dB`
- Full decode: PASS
- Text safe-width and audio gates: PASS
- SHA256: `5fa82dabe9030f0328095023d80413f281e48f9b876ae7c68d715ea14e334380`
- Status: `DRAFT_FOR_HUMAN_REVIEW`

Verify with:

```powershell
.\verify-media.ps1
```

### Bilibili cover

```text
docs/assets/bilibili-cover-2026-11-10.png
```

- Dimensions: `1146x717`
- SHA256: `37dd6ea5f670ac70ff8c5b730139dd51a46eaba58b708e3180b1f3e47eead1dd`
- Text-safe-width, dimensions, nonblank, and source hashes: PASS

### Copy

- GitHub release and Bilibili copy:
  `docs/LAUNCH_COPY_ZH.md`
- Chinese project introduction:
  `docs/INTRODUCTION_ZH.md`

## Open Gates

- GitHub Actions cannot be used as release evidence until the repository
  account billing/spending-limit issue is resolved.
- At least one second AMD laptop still needs read-only compatibility evidence.
- Any runtime or packaging change after `b2ac5f4` requires a new clean package,
  SHA256, and release evidence.
- Project owner must review final video voice, pacing, claims, and cover.
- GitHub tag/release, Bilibili login/upload, and public publication require
  explicit human approval.

## Final Rebuild Command

```powershell
.\verify-release.ps1 `
  -Version 1.0.4 `
  -FrameworkDependent `
  -VerifyShellIntegration `
  -VerifyTrayMenu `
  -VerifyTrayExit `
  -VerifyUiLifecycle `
  -VerifyDashboard `
  -VerifyDiagnostics
```

Run this only from a clean worktree. Record the resulting ZIP size, SHA256,
source commit, and interactive tray verification output before publication.
