# UI Screenshot Evidence

Last captured: 2026-11-10

Machine-readable evidence:
`docs/evidence/ui/screenshot-baseline-2026-11-10.json`.

## Captured States

| State | Asset | Evidence |
| --- | --- | --- |
| Healthy read-only external power | `assets/main-dashboard-external-power-2026-11-10.png` | GUI online, worker connected, live telemetry, read-only apply disabled, zero visible boundary violations |
| Preset editor | `assets/preset-editor-2026-11-10.png` | 12/25/45 W inputs, save/cancel controls, zero visible boundary violations, cancelled without saving |
| Legacy hardware conflict | `assets/worker-conflict-2026-11-10.png` | `旧版 RyzenAdj 正在占用，退出后再试`, zero worker processes, zero visible boundary violations |
| Diagnostics export | `assets/diagnostics-export-2026-11-10.png` | Generic diagnostics filename, save type, save/cancel bottom crop; address bar and personal path excluded |
| Clean-package dashboard | `assets/main-dashboard-clean-package-2026-11-10.png` | Packaged read-only GUI connected to its bundled worker, `动态上限 12.0 W · 电源`, zero visible boundary violations |
| Real battery dashboard | `assets/main-dashboard-battery-2026-11-10.png` | Packaged read-only GUI and worker on battery, `动态上限 25.0 W · 电池`, zero visible boundary violations |
| Tray context menu | `assets/tray-menu-clean-package-2026-11-10.png` | `verify-tray-menu.ps1` found the real hidden-tray icon, opened the upward anchored menu, read 11 items, captured the visible bounds, invoked Exit, and confirmed no GUI/worker remained |

All screenshots were captured on the development laptop at 125% scaling.
Coordinates were checked with UI Automation using the root window rectangle, not
the DPI-virtualized rectangle from the capture process.

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
  `动态上限 ... · 电源/电池`, and fails if any non-background pixel appears
  immediately left of `目标功耗`.
- No security controls, driver services, or hardware limits were changed.

No required dashboard capture remains. The release checklist still requires the
supervised AC/battery policy transition and a second physical AMD device.
