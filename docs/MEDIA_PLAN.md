# Release Media Plan

## Audience

- AMD thin-and-light laptop owners.
- Students and users who frequently switch between battery, charger, and power
  banks.
- Users who want a native, readable alternative to command-line RyzenAdj
  workflows.

## Core Message

AMD Mobile Power is a safety-focused native Windows front end for inspecting and,
after validation, controlling STAPM/PPT limits on supported AMD laptops. It is
not a claim of universal AMD laptop support.

## 60-90 Second Video Outline

### 0-8 seconds: Problem

Show a normal laptop desktop, then the power dashboard. Narration:

> 宿舍断电、充电宝识别、插电模式频繁切换时，AMD 轻薄本的功耗策略经常和实际需求
> 不一致。这个项目把 RyzenAdj 的底层能力做成看得见、可回读的原生桌面工具。

### 8-22 seconds: Dashboard

Capture:

- Live STAPM power.
- STAPM/Fast/Slow "实际 / 上限".
- AC or battery badge.
- Temperature and matched profile.

Explain that target values and firmware limits are separate.

### 22-38 seconds: Presets And Editing

Capture:

- 12 W, 25 W, 45 W buttons.
- Preset editor.
- Read-only lock state.

Do not imply public write support before the hardware gate passes.

### 38-52 seconds: Safety Architecture

Capture:

- Worker-connected badge.
- Conflict message for a legacy hardware owner.
- Diagnostics export dialog.

Explain named-pipe isolation, single hardware owner, read-back verification, and
fail-closed timeout behavior without showing terminals.

### 52-68 seconds: Tray Workflow

Capture:

- Close window to tray.
- Reopen from tray or second launch.
- Single-instance wake-up.

Keep taskbar and notification-area icons visible.

### 68-82 seconds: Compatibility

Capture:

- 8845HS platform header.
- SMU/PMT identifiers.
- Supported-hardware table or README page.

State clearly that the current build is experimental and one-device evidence is
not universal support.

### 82-90 seconds: Close

Narration:

> 项目继续在 GitHub 维护。默认只读，危险写入留在受控验证之后。欢迎提交同型号诊断
> 和兼容性证据，但不要为了运行开发版而关闭系统安全防护。

## Capture Checklist

- Desktop 1920x1080, 100% or supported Windows scaling.
- No personal paths, account names, notifications, or unrelated windows.
- No black console windows.
- Include a real connected-worker state when hardware validation is available.
- Capture AC and battery states separately.
- Capture one editable preset flow.
- Capture one conflict/error state to show fail-closed behavior.
- Capture tray close and reopen.
- Record cursor movement only where it explains an action.

## Screenshot Set For Repository

- `assets/main-dashboard-clean-package-2026-11-10.png` - captured from the clean
  package
- `assets/main-dashboard-external-power-2026-11-10.png` - captured
- `assets/main-dashboard-battery-2026-11-10.png` - captured on real battery
  power with a read-only worker
- `assets/preset-editor-2026-11-10.png` - captured
- `assets/worker-conflict-2026-11-10.png` - captured with a temporary mutex
- `assets/diagnostics-export-2026-11-10.png` - captured save dialog crop
- `assets/tray-menu-clean-package-2026-11-10.png` - captured and reproducible
  with `verify-tray-menu.ps1`
- `assets/bilibili-cover-2026-11-10.png` - generated at 1146x717 from the
  verified clean-package screenshot and reviewed cover copy

See `UI_SCREENSHOT_EVIDENCE.md` for dimensions, hashes, safety boundaries, and
remaining captures.

Replace the current development screenshot only after these states can be
captured against a healthy read-only worker.

## Bilibili Draft

Title:

```text
给 AMD 轻薄本做一个原生功耗面板：实时功耗、预设与安全回读
```

Description:

```text
AMD Mobile Power 是一个正在开发中的开源 Windows 工具，目标是为支持的 AMD
轻薄本提供原生功耗监控、可编辑预设和经过验证的 STAPM/PPT 控制。

当前版本默认只读，硬件写入仍处于受控验证阶段；目前只有 Ryzen 7 8845HS
开发机证据，不代表所有 AMD 笔记本都支持。

项目地址：
https://github.com/syttys123/amd-mobile-power

请勿为了运行开发版关闭 Windows 安全防护。
```

## Publication Gates

- Real hardware write test passed and recorded.
- Healthy read-only screenshots captured.
- Supported-hardware wording reviewed.
- Third-party notices present in the package.
- No secrets, personal paths, or unrelated desktop content in media.
- Final video reviewed by the project owner.
- GitHub release and Bilibili login/upload performed with explicit human
  confirmation.

## Reproducible Draft

`render-promo.ps1` reads `media/promo/storyboard.json`, renders 1920x1080 slides
from the reviewed screenshots, generates Chinese narration with the installed
Windows voice, burns no terminal footage, and produces an MP4 plus an SRT and a
hash manifest under `artifacts/media`.

The output is intentionally marked `DRAFT_FOR_HUMAN_REVIEW`. Rendering the file
does not satisfy the publication gate and does not log in to GitHub or Bilibili.

Current draft status: the native `1.0.8` 10 W draft is rendered at 78.2 seconds
in 1920x1080 with Chinese narration and captions. The native cover and
contact-sheet review assets are committed; the MP4 remains under ignored
`artifacts/media`. Project-owner review is still pending.

Review-ready GitHub Release and Bilibili title, description, tag, pinned-comment,
and cover-text drafts are kept in `LAUNCH_COPY_ZH.md`. That document is marked
`DRAFT_FOR_HUMAN_REVIEW` and is not authorization to publish.

`prepare-release-review.ps1` gathers the reviewed package, MP4, captions,
Bilibili cover, launch copy, and safety documents into a local
`artifacts/release-review` bundle with a manifest and complete SHA256 list. It
does not log in or upload.
