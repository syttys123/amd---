# Native UI Rewrite

Last updated: 2026-11-11

This document describes the current Rust native GUI. The card-stack layout used
by the earlier native preview has been removed.

## Design Direction

The application now uses one shell with two density levels:

- `简洁` is a compact power remote. It keeps only live power, target input,
  quick presets, four telemetry values, write state, and diagnostics export.
- `高级` is a maintenance workbench. It shares the same command deck and adds
  editable presets, battery/external power policy, device capability, runtime
  state, and STAPM/Fast/Slow read-back.

The visual source is the local read-only UI corpus at `D:\ui-database\corpus`.
The implementation takes principles from Apple HIG, Atlassian, Ant Design,
Primer, Fluent, Carbon, Spectrum, Paste, and React Aria. It does not copy
third-party brand assets or component code.

## Shell

The top of both modes is one continuous dark command deck:

- 56 px command bar with product identity, detected CPU/family/power line,
  `简洁` / `高级` segmented controls, and `置顶`.
- 172 px shared control area with live STAPM power, power-line badge, target
  range, fixed-width target input, primary apply action, and quick presets.
- A 2 px electric-blue rule closes the command deck before the light data area.

The live power value is the only display-scale number. The primary blue action
is unique. Selected presets use a white surface and dark text; unselected
presets remain part of the dark deck instead of becoming separate cards.

## Simple Mode

Logical client size: `640x392`.

| Region | Geometry | Purpose |
| --- | --- | --- |
| Command bar | `0..56` | identity and mode controls |
| Control deck | `56..228` | live power, target, apply, presets |
| Telemetry band | `240..320` | STAPM, PPT Fast, PPT Slow, CPU temperature |
| Status band | `332..376` | persistent write/read-back/error state |

The telemetry band is a flat ledger with vertical separators, not four cards.
The status band keeps diagnostics export available in read-only mode and
explains why write controls are disabled.

Simple mode is the default for a new UI state. Existing saved preferences still
restore the user's last selected mode.

## Advanced Mode

Logical client size: `780x680`.

Advanced mode uses the same command deck, followed by one split workspace:

- Left column:
  - editable three-preset grid and save action,
  - battery/external power policy, a `仅电池` mode that leaves AC/external
    writes untouched, and save action,
  - live STAPM/Fast/Slow read-back ledger.
- Right column:
  - processor, family, SMU, PM table, and matched profile,
  - platform write support and STAPM/Fast/Slow field support,
  - worker state, saved policy, read-back health, and privacy-safe diagnostics
    export.

The workspace uses one continuous surface and structural rules. It does not
nest cards inside cards.

## Visual Tokens

### Surfaces

| Token | Value | Use |
| --- | --- | --- |
| `canvas` | `#EEF1F6` | window background |
| `surface` | `#FFFFFF` | advanced workspace |
| `surface-muted` | `#F7F9FC` | telemetry and status bands |
| `command` | `#0D121B` | command bar and control deck |
| `border` | `#D3DAE6` | workspace boundary |
| `rule` | `#E2E7EF` | internal separators |

### Semantic Color

| Token | Value | Use |
| --- | --- | --- |
| `accent` | `#2463EB` | apply action, live marker, focus |
| `accent-pressed` | `#1648B2` | pressed primary action |
| `battery` | `#9C5207` | battery badge |
| `warning` | amber surface/text | firmware clamp and recovery |
| `error` | red surface/text | worker/platform failures |
| `success` | `#0D7551` | connected/read-back success text |

Neutral surfaces carry most of the window. Blue, amber, and red remain
semantic.

### High Contrast

The native shell reads the Windows high-contrast setting and switches the
entire custom canvas, owner-drawn controls, native edit backgrounds, focus
rings, semantic badges, and status bands to a black background with white text,
yellow structure, and black text on yellow primary actions. The test-only
`--ui-fixture high-contrast` path exercises the same palette without changing
the user's Windows accessibility settings.

### Type And Geometry

- `Consolas` is used for live power and telemetry numbers.
- `Microsoft YaHei UI` is used for Chinese labels and body text.
- Display power is 42 px bold at 96 DPI.
- Telemetry values are 18 px bold.
- Labels and status copy are 12-14 px.
- Controls use `6 px` radius, rounded surfaces use `8-12 px`.
- Primary and secondary controls retain stable geometry in normal, selected,
  pressed, disabled, and focused states.

## State And Accessibility

- Windows dialog navigation handles Tab, Shift+Tab, Enter, and Space.
- Owner-drawn buttons paint a focus ring only for the actually focused control.
- Text inputs and button windows paint their matching backdrop before rounded
  content so dark-shell corners never leak light default-control pixels.
- Read-only mode keeps editable geometry visible but disabled and states
  `只读 · 写入控制未解锁` in the persistent status band.
- Missing numeric data renders `--`.
- Long operation results are held for five seconds so telemetry ticks do not
  erase the user's confirmation.
- Worker-offline, unsupported-platform, firmware-clamp, and long-error states can
  be rendered through the test-only `--ui-fixture` flag without starting a
  hardware worker or requesting a power write.
- The `仅电池` policy toggle is verified through the same fixture path. The
  diagnostics JSON now includes the current UI mode, topmost state, policy
  enabled/battery-only flags, and tray/taskbar icon availability, all without
  paths or process IDs.
- Switching modes preserves worker connection, presets, policy, target,
  topmost state, and diagnostics availability.

## Rendering

- The parent window paints into a compatible memory DC and blits once.
- `WS_CLIPCHILDREN` prevents parent repaint from erasing native inputs/buttons.
- Interactive text fields and owner-drawn buttons stay as native child windows
  for keyboard and accessibility support.
- The embedded application icon is used in the title bar and tray.
- Generated screenshots are captured only after confirming the target window
  is foreground. This prevents the earlier failure mode where a read-only
  capture recorded unrelated desktop content.

## Runtime Evidence

At 125% Windows scaling:

- `cargo test --manifest-path native\rust-gui\Cargo.toml --locked --offline`:
  30/30 passed.
- `cargo clippy --manifest-path native\rust-gui\Cargo.toml --locked --offline
  -- -D warnings`: PASS.
- `native\verify-rust-gui.ps1 -NoBuild -VerifyWorker -VerifyWriteControls`:
  PASS for view modes, topmost, read-only worker status, diagnostics, preset
  editing, minimize/restore, close-to-tray, tray restore, and single-instance
  wake.
- `native\verify-rust-gui.ps1 -NoBuild -VerifyWriteControls -UiFixture
  firmware-clamp`: PASS for the battery-only policy toggle through the exported
  diagnostics JSON without hardware access.
- `native\verify-rust-gui.ps1 -NoBuild -VerifyWriteControls -UiFixture
  high-contrast`: PASS with `ui.highContrast=true` in diagnostics while the
  isolated fixture keeps Windows accessibility settings unchanged.
- The same verifier checks the diagnostics `ui` block for the active
  simple/advanced mode, topmost state, `taskbarIconAvailable=true`, and
  `trayIconId=1`.
- `native\capture-rust-gui-redesign.ps1 -Fixture firmware-clamp
  -FocusControlId 316`: PASS with the target input verified as the actual
  focused child and the focus ring visible in simple and advanced captures.
- `native\capture-rust-gui-redesign.ps1 -Fixture high-contrast`: PASS for the
  complete black/white/yellow simple and advanced states.
- No power write was requested during UI verification.

Evidence and screenshots:

- `docs/evidence/ui/native-redesign-2026-11-11.json`
- `docs/evidence/ui/native-ui-failure-states-2026-11-11.json`
- `assets/native-gui-redesign-simple-2026-11-11.png` (`802x530` physical)
- `assets/native-gui-redesign-advanced-2026-11-11.png` (`977x890` physical)
- `assets/native-gui-redesign-readonly-simple-2026-11-11.png`
- `assets/native-gui-redesign-readonly-advanced-2026-11-11.png`
- `assets/native-ui-worker-offline-simple-2026-11-11.png`
- `assets/native-ui-firmware-clamp-simple-2026-11-11.png`
- `assets/native-ui-unsupported-platform-simple-2026-11-11.png`
- `assets/native-ui-long-error-simple-2026-11-11.png`
- `docs/evidence/ui/native-battery-only-policy-2026-11-11.json`
- `docs/evidence/ui/native-battery-only-capture-2026-11-11.json`
- `docs/evidence/ui/native-focus-2026-11-11.json`
- `assets/native-battery-only-simple-2026-11-11.png`
- `assets/native-battery-only-advanced-2026-11-11.png`
- `assets/native-focus-simple-2026-11-11.png`
- `assets/native-focus-advanced-2026-11-11.png`
- `docs/evidence/ui/native-high-contrast-2026-11-11.json`
- `assets/native-high-contrast-simple-2026-11-11.png`
- `assets/native-high-contrast-advanced-2026-11-11.png`
- `docs/evidence/ui/native-packaged-rc16-ui-2026-11-11.json`

Reproduction:

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass `
  -File native\capture-rust-gui-redesign.ps1 `
  -FilePrefix native-gui-redesign
```

## Remaining UI Gates

- Repeat the redesigned shell at 100% and 150% Windows scaling on machines or
  sessions configured for those scales.
- Run one supervised packaged write/read-back smoke test before promotion.

Public GitHub Release, Bilibili upload, and promotion to `C:\RyzenAdj` remain
unapproved until the release gates and hardware evidence are complete.
