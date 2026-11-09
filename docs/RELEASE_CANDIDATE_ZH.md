# Release Candidate Review

状态：`DRAFT_FOR_HUMAN_REVIEW`

这不是公开 Release，也不是 B 站上传授权。本文汇总当前可复核资产、已验证边界
和仍需人工完成的门禁。

## Source And Package

- Repository: `https://github.com/syttys123/amd-mobile-power`
- Current source commit reviewed: `6258395`
- Package source commit: `6258395`
- Package: `artifacts/packages/amd-mobile-power-v0.1.3-dev-win-x64-lite.zip`
- Size: `593,474` bytes
- SHA256: `209faac93698bc71952f48c95568f2c6b19a570e1f1e4038b31c52ae40a2f3fd`
- Files / checksums / profiles / licenses: `40 / 39 / 9 / 4`
- Runtime: Microsoft .NET 8 Desktop Runtime x64

The ZIP was rebuilt from a clean `6258395` worktree after the dependency audit
and upgraded test toolchain were committed. Later documentation-only commits do
not change the packaged runtime files.

## Local Verification

Evidence:
`docs/evidence/packaging/v0.1.3-dev-family-matrix-2026-11-10.json`

- Build warnings / errors: `0 / 0`
- Tests: `65 passed, 0 failed`
- Formatting verification: PASS
- NuGet vulnerability audit: PASS (`6` projects, `0` direct/transitive advisories)
- Isolated install, overwrite, and uninstall: PASS
- Start menu, uninstall entry, startup fallback: PASS
- Tray menu direction: up
- Tray menu bounds and horizontal anchoring: PASS
- Graceful tray exit: PASS
- Packaged read-only diagnostics collector: PASS
- GUI and collector diagnostic field whitelist / path redaction: PASS
- RyzenAdj family `0-15` profile coverage: PASS

Machine-local release evidence lives under `artifacts/verify` and is intentionally
not committed.

## Hardware Evidence

### Verified write/read-back

- Controlled `10/10/10 W` and `12/12/12 W` writes passed on the development
  laptop.
- Earlier `25/25/25 W` and a 45 W request were recorded; firmware may clamp
  STAPM while Fast/Slow remain the enforceable limit.
- Packaged no-change write gate: `12/12/12 W -> 12/12/12 W`.

### Real battery read-only baseline

- Evidence:
  `docs/evidence/hardware/mechrevo-wujie15-8845hs-battery-preflight-2026-11-10.json`
- Power line: battery / discharging
- STAPM/Fast/Slow limits: `25/25/20 W`
- Planned target: `12/12/12 W`
- Hardware writes: `0`
- Worker shutdown: `PASS`

Dashboard capture:

```text
docs/assets/main-dashboard-battery-2026-11-10.png
```

- Dimensions: `718x547`
- SHA256: `879c817ee0a99a111de1ad0d19058d360a2da7b364101d51037d167c3529e8ff`
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
- The supervised full AC -> battery -> AC policy transition still needs a human
  operator and explicit confirmation phrase.
- At least one second AMD laptop still needs read-only compatibility evidence.
- A clean rebuild from the exact final release commit is still required.
- Project owner must review final video voice, pacing, claims, and cover.
- GitHub tag/release, Bilibili login/upload, and public publication require
  explicit human approval.

## Final Rebuild Command

```powershell
.\verify-release.ps1 `
  -Version 0.1.3-dev `
  -FrameworkDependent `
  -VerifyShellIntegration `
  -VerifyTrayMenu `
  -VerifyTrayExit `
  -VerifyDiagnostics
```

Run this only from a clean worktree. Record the resulting ZIP size, SHA256,
source commit, and interactive tray verification output before publication.
