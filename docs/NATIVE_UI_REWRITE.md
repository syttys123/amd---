# Native UI Rewrite

This document defines the clean-room native Rust GUI structure. It replaces the
incremental Win32 control layout used by `0.6.0-native-rc.9`.

## Evidence Boundary

The design is derived from the local read-only UI database:

- `D:\ui-database\corpus\DESIGN_RESEARCH.md`
- `D:\ui-database\corpus\manifests\sources.md`
- Apple HIG: box padding, hit areas, concentric geometry.
- Atlassian: role-based radius, visible focus, disabled-state explanations.
- Ant Design / Primer: tabular numbers, right-aligned comparable data.
- Paste / Carbon / Spectrum: tonal surface hierarchy before shadows.
- Fluent / React Aria: overlays, keyboard focus, forced-color boundaries.

The implementation must not copy third-party brand assets or component code.

## Product Hierarchy

The application has two modes with different jobs:

1. `简洁` is the default operator surface. It answers:
   - current package power,
   - active power target,
   - quick switch choices,
   - effective STAPM/Fast/Slow limits and temperature,
   - whether writes are available or blocked and why.
2. `高级` is the configuration and diagnostics surface. It adds:
   - editable presets,
   - battery/AC policy,
   - raw platform and firmware fields,
   - diagnostics export and detailed worker state.

The mode switch, topmost control, tray actions, target, presets, and status are
shared state. Switching modes must not restart the worker or rewrite saved
settings.

## Visual Language

### Surfaces

| Token | Value | Use |
| --- | --- | --- |
| `canvas` | `#EEF2F1` | window background |
| `surface` | `#FFFFFF` | hero, telemetry, advanced sections |
| `surface-muted` | `#F6F8F7` | preset strip, status strip |
| `header` | `#171D1E` | title/header band |
| `border` | `#D4DDDA` | structural boundaries |
| `border-strong` | `#7B8C87` | input and focus-adjacent boundary |

### Semantic Color

| Token | Value | Use |
| --- | --- | --- |
| `accent` | `#0A7F73` | primary action and live power |
| `accent-pressed` | `#08675E` | pressed/hover primary |
| `accent-soft` | `#DFF4EF` | selected preset and quiet emphasis |
| `text` | `#182220` | primary text |
| `text-muted` | `#5F6D69` | labels and units |
| `battery` | `#B86A17` | battery semantic value only |
| `warning` | `#A8580B` | clamp and recoverable warning |
| `error` | `#B42318` | failure |
| `focus` | `#FFFFFF` on header, `#08675E` on light surfaces | keyboard focus |

Do not build the window from one green monochrome palette. Neutral surfaces
carry most of the interface; accent and battery colors remain semantic.

### Type

| Token | Size / weight | Use |
| --- | --- | --- |
| `display` | 30pt bold | live package power |
| `title` | 13pt semibold | brand and advanced section titles |
| `metric` | 12pt bold | telemetry actual values |
| `body` | 9pt regular | labels and status |
| `caption` | 8.25pt regular | units, limits, platform detail |

Power, temperature, limits, and timestamps use tabular figures. Fonts never
scale from window width.

### Geometry

| Token | Value |
| --- | --- |
| `radius-control` | `6px` |
| `radius-surface` | `10px` |
| `space-1` | `4px` |
| `space-2` | `8px` |
| `space-3` | `12px` |
| `space-4` | `16px` |
| primary control | `40px` high |
| secondary control | `36px` high |
| focus ring | `2px` with at least `2px` contrast separation |

## Simple Layout

Logical client size: `640x420`. At 125% DPI the physical window may grow, but
the composition and hit areas remain the same logical geometry.

```text
┌──────────────────────────────────────────────────────────┐
│ AMD Mobile Power                     [简洁|高级]  [置顶] │ 56
│ Ryzen 7 8845HS · AC                                     │
├──────────────────────────────────────────────────────────┤
│ 实时功耗                                    目标功耗     │
│ 10.0 W  [电源]                          [ 12 ] W [应用] │ 96
├──────────────────────────────────────────────────────────┤
│ 快捷功耗        [12 W] [25 W] [45 W]             [编辑] │ 44
├──────────────────────────────────────────────────────────┤
│ STAPM        Fast         Slow          CPU 温度         │
│ 10.0 W       10.0 W       10.0 W        43.0 °C          │
│ 上限 10.0W   上限 10.0W   上限 10.0W    上限 95.0°C      │
├──────────────────────────────────────────────────────────┤
│ [写入已解锁]  当前目标 10 W · 回读一致        [诊断]    │ 40
└──────────────────────────────────────────────────────────┘
```

The hero, telemetry matrix, and status use surfaces and spacing. Do not nest
cards inside cards. The only separate rounded surfaces are the hero,
preset/telemetry surface, and status surface.

## Advanced Layout

Logical client size: `760x620`, with a vertically scrollable content region if
needed. Sections:

1. Shared identity and mode header.
2. Live power + target controls.
3. Editable preset grid with validation.
4. Battery/AC policy section.
5. Platform capabilities and raw telemetry table.
6. Diagnostics and worker lifecycle actions.

Section headers use `title` with one caption line. Inputs and buttons align on
an 8px grid. No control may expand because its current value becomes longer.

## Component Contracts

### `ModeHeader`

- Inputs: product name, CPU, SMU, mode, topmost.
- Outputs: switch mode, toggle topmost.
- Must expose selected state through a visible marker and standard button state.
- Dark header focus ring uses white.

### `LivePower`

- Inputs: live STAPM, effective STAPM limit, power line.
- Missing value renders `--`, never blank or `NaN`.
- One display-scale value only.
- Power line is a text badge; color never carries the meaning alone.

### `TargetControl`

- Input: integer watts, profile range, write availability.
- Output: apply target.
- Input width remains stable for `5` through `255`.
- Disabled state retains geometry and an adjacent reason.

### `PresetStrip`

- Three explicit values; simple mode applies directly, advanced mode edits.
- Selected state uses `accent-soft` and a visible marker.
- Invalid/out-of-range values remain visible with an error explanation.

### `TelemetryMatrix`

- Four equal columns: STAPM, Fast, Slow, temperature.
- Each column has label, actual value, and limit.
- Values use tabular figures and a common decimal contract.
- One surface, no independent card border for every cell.

### `StatusBanner`

- Structured status code, severity, short message, and next action.
- No `Contains()`-based inference in the paint layer.
- Long text truncates with a tooltip/accessible name; the first line always
  contains the problem or action.

## State And Rendering Boundary

The worker remains the only hardware owner. UI state is split into:

- `AppModel`: worker snapshot, policy, mode, topmost, presets, selected target,
  in-flight operations, and structured status.
- `SimpleViewModel`: display-ready strings and semantic status.
- `AdvancedViewModel`: editable values and validation state.

Rendering consumes immutable view models. Input handlers emit commands; they do
not write hardware or persist state directly.

The rewrite may retain Win32 child controls where they provide accessibility
and text editing, but visual structure must not be derived from default system
control styling. Display surfaces, headers, telemetry, and status are
custom-painted with double buffering.

## Required Verification

- 100%, 125%, and 150% DPI screenshots for simple and advanced modes.
- No text clipping for CPU names, `105.0 / 105.0 °C`, long worker errors, and
  three-digit target values.
- Simple/advanced switches preserve target, presets, policy, topmost, and
  worker connection.
- Keyboard Tab order, focus rings, Enter/Space activation, and Escape behavior.
- Read-only, unsupported, worker-offline, applying, success, clamp, warning,
  and error states.
- Double-buffer check with rapid one-second telemetry updates and no flicker.
- Tray menu mode/topmost/preset states stay synchronized with the window.
- Diagnostics export remains path/PID/account/log free.

## Migration Order

1. Introduce semantic token and paint primitives.
2. Custom-paint the shared header, simple hero, target row, telemetry matrix,
   and status while preserving current worker commands.
3. Move simple preset actions onto the new target/preset components.
4. Rebuild advanced mode from the same component library.
5. Delete the old dashboard text block and ad-hoc control positions.
6. Add the full DPI, keyboard, and failure-state gate before any stable
   promotion.

## Implementation Status (2026-11-11)

The clean-room layout is now implemented in the native Rust preview. It is no
longer an incremental resize of the old dashboard.

### Rendering Boundary

- The window owns one double-buffered custom-painted canvas.
- Default Win32 `STATIC` controls are no longer the visual layout source. Their
  text remains only as an off-screen automation/accessibility bridge.
- Only text fields and owner-drawn buttons remain as interactive child
  controls.
- `WS_CLIPCHILDREN` prevents parent repaints from erasing child fields and
  buttons during the one-second telemetry refresh.
- The title bar and window icon now use the embedded
  `assets/amd-mobile-power.ico`; the tray icon uses the same small icon.
- The title bar requests Windows dark-titlebar mode when supported.

### Simple Mode

- Fixed client composition: `640x438`.
- Header: product name, detected CPU/family/power line, mode segmented control,
  and topmost toggle.
- Hero: live STAPM power, dynamic ceiling, power-line badge, fixed-width target
  input, and primary apply action.
- Quick power strip: three direct-apply presets plus an edit entry that switches
  to advanced editing and focuses the first preset field.
- Telemetry: one surface with four equal columns for STAPM, Fast, Slow, and CPU
  temperature. Numeric values use tabular figures.
- Status: persistent semantic chip, one-line result/error message, and
  diagnostics action.

### Advanced Mode

- Fixed client composition: `760x680`.
- Shared hero and target control.
- Left panel: quick presets, editable preset values, and battery/external power
  policy controls.
- Right panel: detected processor, RyzenAdj family, SMU/PM table, compact
  matched-profile name, platform capability, and supported-limit states.
- Bottom panel: worker health, saved policy summary, diagnostics privacy note,
  and export action.

### Interaction And Accessibility

- `IsDialogMessageW` provides Windows dialog keyboard navigation for Tab,
  Shift+Tab, Enter, and Space.
- Borderless numeric inputs paint their own focus border through
  `WM_COMMAND` focus notifications.
- Owner-drawn buttons retain a high-contrast focus ring and do not resize across
  normal, selected, pressed, or disabled states.
- Read-only mode keeps the layout visible while disabling writes and explaining
  the state in the status banner.

### Runtime Evidence

At 125% Windows scaling:

- Machine-readable evidence:
  `docs/evidence/ui/native-redesign-2026-11-11.json`.
- Reproducible capture:
  `native\capture-rust-gui-redesign.ps1 -EvidencePath <artifact-json>`.
- Simple screenshot:
  `assets/native-gui-redesign-simple-2026-11-11.png` (`820x596` physical).
- Advanced screenshot:
  `assets/native-gui-redesign-advanced-2026-11-11.png` (`970x899` physical).
- `cargo test --manifest-path native\rust-gui\Cargo.toml --locked --offline`:
  26/26 passed.
- `native\verify-rust-gui.ps1 -NoBuild -VerifyWorker -VerifyWriteControls`:
  PASS for minimize/restore, close-to-tray, tray restore, single-instance wake,
  read-only worker connection, diagnostics export, mode switching, topmost,
  write controls, and preset editing.

### Remaining UI Gates

- Repeat screenshots at 100% and 150% system scaling.
- Capture focused input, long error, firmware-clamp, worker-offline, and
  unsupported-platform states.
- Verify the tray menu and taskbar icon in a packaged build.
- Perform one packaged write/read-back smoke test before promoting this UI.
