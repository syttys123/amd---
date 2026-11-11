# UI Screenshot Evidence

Last captured: 2026-11-11

Machine-readable evidence:
`docs/evidence/ui/screenshot-baseline-2026-11-10.json`.
The deployed `1.0.1` status-bar fix has separate evidence:
`docs/evidence/ui/v1.0.1-dashboard-2026-11-10.json`.
The current deployed `1.0.4` compact layout and lifecycle check is recorded in
`docs/evidence/packaging/v1.0.4-deployment-2026-11-10.json`.

## Captured States

| State | Asset | Evidence |
| --- | --- | --- |
| Healthy read-only external power | `assets/main-dashboard-external-power-2026-11-10.png` | GUI online, worker connected, live telemetry, read-only apply disabled, zero visible boundary violations |
| Preset editor | `assets/preset-editor-2026-11-10.png` | 12/25/45 W inputs, save/cancel controls, zero visible boundary violations, cancelled without saving |
| Legacy hardware conflict | `assets/worker-conflict-2026-11-10.png` | `旧版 RyzenAdj 正在占用，退出后再试`, zero worker processes, zero visible boundary violations |
| Diagnostics export | `assets/diagnostics-export-2026-11-10.png` | Generic diagnostics filename, save type, save/cancel bottom crop; address bar and personal path excluded |
| Clean-package dashboard | `assets/main-dashboard-clean-package-2026-11-10.png` | Packaged read-only GUI connected to its bundled worker, `动态上限 12.0 W · 电源`, zero visible boundary violations |
| Real battery dashboard | `assets/main-dashboard-battery-2026-11-10.png` | Packaged read-only GUI and worker on battery, `动态上限 25.0 W · 电池`, zero visible boundary violations |
| Deployed `1.0.1` status bar | `assets/main-dashboard-v1.0.1-status-2026-11-10.png` | `C:\RyzenAdj` package on battery, `动态上限 25.0 W · 电池`, bottom `详情` absent, write-state/status non-overlap PASS, target-left artifact pixels 0 |
| Deployed `1.0.4` compact header/status | `artifacts/verify/deployed-dashboard-v1.0.4-20261110-190306.png` | Complete `AMD Mobile Power` header, 245 px right gap, 78 px write-state cell, status overlap PASS, target-left artifact pixels 0 |
| Tray context menu | `assets/tray-menu-clean-package-2026-11-10.png` | `verify-tray-menu.ps1` found the real hidden-tray icon, opened the upward anchored menu, read 11 items, captured the visible bounds, invoked Exit, and confirmed no GUI/worker remained |
| Simple mode, DPI-aware capture | `assets/main-dashboard-simple-dpi-2026-11-10.png` | Full `718x547` window at 125% scaling after `verify-dashboard.ps1` became per-monitor DPI aware; `简洁/高级/置顶` header controls and write-state cell are inside the capture, `快捷功耗` renders on one line, status overlap PASS, target-left artifact pixels 0 |

All screenshots were captured on the development laptop at 125% scaling.
Coordinates were checked with UI Automation using the root window rectangle.
`verify-dashboard.ps1` now calls `SetProcessDpiAwarenessContext` with
`PER_MONITOR_AWARE_V2` before launching the GUI, so `GetWindowRect` and
`CopyFromScreen` operate in physical pixels. Earlier captures used the
DPI-virtualized rectangle and silently cropped the right edge of the window,
which excluded the header mode controls from the automated checks.

Runtime layout checks also passed for compact and advanced mode:

- Compact mode: advanced footer is hidden, 0 visible boundary violations.
- Advanced mode: `导出诊断` is present, 0 visible boundary violations at
  `1268x922`.

## Safety Boundary

- The main dashboard capture used the default read-only process.
- The preset editor was cancelled; no preset was changed.
- The conflict capture used a temporary `Local\RyzenAdjPowerWorker` mutex and
  did not start a hardware worker.
- The diagnostics save dialog was cancelled; no diagnostics JSON was written.
- The clean-package tray check invoked only Exit; no preset or power-limit write was invoked.
- The real-battery dashboard was captured with the default read-only process;
  no policy was enabled and no power-limit write was invoked.
- The tray screenshot can be reproduced with `verify-tray-menu.ps1` on an
  interactive Windows desktop.
- The simple dashboard runtime check can be reproduced with
  `verify-dashboard.ps1`: it waits for live worker telemetry, requires
  `动态上限 ... · 电源/电池`, rejects a bottom `详情` button, checks the
  write-state/status bounds, and fails if any non-background pixel appears
  immediately left of `目标功耗`.
- No security controls, driver services, or hardware limits were changed.

No required dashboard capture remains. The release checklist still requires the
supervised AC/battery policy transition and a second physical AMD device.

## Native Rust Redesign Evidence (2026-11-11)

The second clean-room native Rust iteration was captured at 125% Windows
scaling with the real hardware worker connected. This iteration removes the
previous stack of independent white cards:

| State | Asset | Physical size | Evidence |
| --- | --- | ---: | --- |
| Native simple redesign | `assets/native-gui-redesign-simple-2026-11-11.png` | `802x530` | One continuous dark command deck contains identity, modes, live STAPM, target input, apply, and three presets; the flat telemetry ledger and status band sit below without detached card stacking |
| Native advanced redesign | `assets/native-gui-redesign-advanced-2026-11-11.png` | `977x890` | Shared command deck, editable presets, battery/external policy, device capability, worker health, and a live STAPM/Fast/Slow read-back ledger render without visible text clipping or structural overlap |
| Native read-only states | `assets/native-gui-redesign-readonly-simple-2026-11-11.png`, `assets/native-gui-redesign-readonly-advanced-2026-11-11.png` | `802x530`, `977x890` | Write controls retain their geometry while disabled; the simple status explains `只读`, and diagnostics remains available in both modes |
| Worker offline | `assets/native-ui-worker-offline-simple-2026-11-11.png`, `assets/native-ui-worker-offline-advanced-2026-11-11.png` | `802x530`, `977x890` | `连接异常`, a restart/check-worker action, disabled target/preset controls, and enabled diagnostics export |
| Firmware clamp | `assets/native-ui-firmware-clamp-simple-2026-11-11.png`, `assets/native-ui-firmware-clamp-advanced-2026-11-11.png` | `802x530`, `977x890` | Requested 12 W with STAPM clamped to 10 W while Fast/Slow read back 12 W; the amber status remains distinct from transport failure |
| Battery-only policy fixture | `assets/native-battery-only-simple-2026-11-11.png`, `assets/native-battery-only-advanced-2026-11-11.png` | `802x530`, `977x890` | Advanced mode shows the selected `仅电池` toggle and `外接不控制` copy; the fixture confirms the control is visible/enabled without starting a hardware worker |
| Focused target input | `assets/native-focus-simple-2026-11-11.png`, `assets/native-focus-advanced-2026-11-11.png` | `802x530`, `977x890` | `-FocusControlId 316` confirms the target input is the actual focused child and the blue focus ring renders in both modes |
| High contrast | `assets/native-high-contrast-simple-2026-11-11.png`, `assets/native-high-contrast-advanced-2026-11-11.png` | `802x530`, `977x890` | Test-only fixture renders the complete shell with black surfaces, white text, yellow structure, and black text on yellow primary actions; diagnostics report `ui.highContrast=true` without changing Windows accessibility settings |
| Unsupported platform | `assets/native-ui-unsupported-platform-simple-2026-11-11.png`, `assets/native-ui-unsupported-platform-advanced-2026-11-11.png` | `802x530`, `977x890` | Read-only monitoring remains visible while target, presets, and policy controls are disabled with a visible platform reason |
| Long error | `assets/native-ui-long-error-simple-2026-11-11.png`, `assets/native-ui-long-error-advanced-2026-11-11.png` | `802x530`, `977x890` | First line states the action (`关闭其他 RyzenAdj 后重启 Windows`) and later details remain in the accessibility text without breaking the layout |

The native window now uses the embedded application icon in both the title bar
and tray, a dark native title bar where Windows supports it, and
`WS_CLIPCHILDREN` to keep child inputs/buttons stable during one-second custom
canvas repaints. Dark command-deck buttons paint their parent backdrop before
rounded content, eliminating light default-control corner artifacts.

The capture gate now attaches input to the GUI thread, brings the target window
to the foreground, verifies `GetForegroundWindow`, and only then captures the
DWM extended frame. This replaces the earlier unsafe read-only path that could
record unrelated desktop content when foreground activation failed.

Runtime verification:

- Native Rust tests: 30/30 passed.
- `native\verify-rust-gui.ps1 -NoBuild -VerifyWorker -VerifyWriteControls`:
  PASS for simple/advanced switching, topmost, preset editing, diagnostics,
  minimize/restore, tray restore, close-to-tray, and single-instance wake.
- `native\verify-rust-gui.ps1 -NoBuild -VerifyWriteControls -UiFixture
  firmware-clamp`: PASS for the battery-only policy toggle via diagnostics.
- `native\verify-rust-gui.ps1 -NoBuild -VerifyWriteControls -UiFixture
  high-contrast`: PASS for the high-contrast palette and diagnostics flag.
- No power write was requested during screenshot capture.

Machine-readable evidence:
`docs/evidence/ui/native-redesign-2026-11-11.json`.
Failure-state evidence:
`docs/evidence/ui/native-ui-failure-states-2026-11-11.json`.
Battery-only fixture evidence:
`docs/evidence/ui/native-battery-only-policy-2026-11-11.json` and
`docs/evidence/ui/native-battery-only-capture-2026-11-11.json`.
Focused-input evidence:
`docs/evidence/ui/native-focus-2026-11-11.json`.
High-contrast evidence:
`docs/evidence/ui/native-high-contrast-2026-11-11.json`.
Packaged tray/taskbar and mode synchronization evidence:
`docs/evidence/ui/native-packaged-rc17-ui-2026-11-11.json`.

Remaining gates: 100%/150% DPI sessions and broader AMD generation evidence.
