# Native Release Candidate Review

状态：`DRAFT_FOR_HUMAN_REVIEW`

这不是公开 Release，也不是 B 站上传授权。本文只汇总原生 Rust GUI + C++
worker 候选 `1.0.0-native` 的可复核资产、已验证边界和仍需人工完成的门禁。

## 目标与定位

AMD Mobile Power 是面向 AMD 轻薄本的 Windows 原生功耗面板。它把 RyzenAdj
封装为前端 GUI + 特权 worker 的两进程结构，默认只读，写入必须显式解锁并
回读校验。当前只在一块 Ryzen 7 8845HS 开发机上完成硬件门禁，不代表所有
AMD 笔记本都受支持。

## 包与来源

- Repository: `https://github.com/syttys123/amd-mobile-power`
- Branch: `main`
- Candidate: `1.0.0-native`
- Package:
  `artifacts/native-packages/amd-mobile-power-v1.0.0-native-win-x64-native-preview.zip`
- Size: `535,197` bytes
- SHA256:
  `f3fd6ea1d1b0292c6ec9ea7445f191adc302066f78a728528a3722923c73a0bf`
- Package source commit: `ddb7d9cba3195f4a16df1299215a9e26cd18544f`
- Working tree at build time: clean
- Review bundle: `artifacts/native-release-review/v1.0.0-native`

## 本机验证

- Rust GUI 测试：`30/30`。
- Rust formatting / Clippy `-D warnings`：PASS。
- C++ power-limit / power-policy 测试：PASS。
- 16 项包内 SHA256 校验：PASS。
- 提取后 GUI/worker 只读验证、诊断导出、兼容性 JSON/Markdown：PASS。
- 隔离安装、覆盖安装、卸载：PASS。
- 真实当前用户 Start menu / Startup / uninstall entry 建删循环：PASS。
- `rc.17 -> 1.0.0-native` 升级：payload 一致、升级后只读运行、卸载清理：PASS。
- 打包版托盘/任务栏与模式同步证据：`CloseToTray`、`TrayRestore`、
  `SingleInstanceWake`、`taskbarIconAvailable=true`、`trayIconId=1`、
  `simple -> advanced` 同步：PASS。

Evidence:

- `docs/evidence/packaging/v1.0.0-native-clean-2026-11-11.json`
- `docs/evidence/packaging/v1.0.0-native-release-gate-2026-11-11.json`
- `docs/evidence/packaging/v1.0.0-native-shell-integration-2026-11-11.json`
- `docs/evidence/packaging/v1.0.0-native-cross-version-upgrade-2026-11-11.json`
- `docs/evidence/ui/native-packaged-1.0.0-ui-2026-11-11.json`

## 硬件门禁

开发机：MECHREVO WUJIE15 PRO / AMD Ryzen 7 8845HS / Hawk Point。

- 只读能力与遥测：SMU `15`、PM table `4c0009`、profile
  `hawk-point-8845hs [5-60 W]`、AC `25/45/25 W`。
- 受控当前值策略门禁：请求与回读均为 `25/45/25 W`，策略随后禁用，
  worker 正常关闭，实际限制不变。
- 读-only 写入守卫：非法目标被拒绝，没有发起硬件写入。

Evidence:

- `docs/evidence/hardware/v1.0.0-native-power-policy-no-change-2026-11-11.json`
- `docs/COMPATIBILITY_REPORTS.md`
- `docs/evidence/compatibility/index.json`

## 本地部署

- 目标目录：`C:\RyzenAdj`
- 版本：`1.0.0-native`
- 旧版备份：`C:\RyzenAdj.before-20261111-223017`
- 仓库备份：
  `artifacts/deployment-backups/C-RyzenAdj-before-1.0.0-native-20261111-223017`
- 桌面快捷方式：`<USER_HOME>\Desktop\功耗设置 5-60W.lnk`
- 快捷方式参数：`--enable-write-controls --simple-mode`
- 部署验证：worker、托盘、单实例、模式、预设、电池策略开关、诊断导出 PASS
- Evidence:
  `docs/evidence/packaging/v1.0.0-native-deployment-2026-11-11.json`

## 界面证据

- `assets/native-gui-redesign-simple-2026-11-11.png`
- `assets/native-gui-redesign-advanced-2026-11-11.png`
- `assets/native-high-contrast-simple-2026-11-11.png`
- `assets/native-high-contrast-advanced-2026-11-11.png`
- `docs/UI_SCREENSHOT_EVIDENCE.md`

设计依据：Apple HIG、Atlassian、Ant Design、Primer、Fluent、Carbon、
Spectrum、Paste、React Aria，以及
`D:\tong\docs\design\DESIGN_UI_PERCEPTION_AND_PATTERNS_2026-11-11.md`。

## 兼容性收集

发布包内的 `collect-native-diagnostics.ps1` 只读采集主机、CPU、家族、SMU、
PM table、匹配 profile、电源线和当前限制，并写出脱敏 JSON/Markdown。
维护者用 `native/import-compatibility-report.ps1` 导入审阅后的报告；导入器
拒绝写入态、隐私字段缺失、路径泄漏和重复报告。

当前已索引：MECHREVO WUJIE15 PRO / Ryzen 7 8845HS。

## 未完成门禁

- 第二台 AMD 笔记本或不同代的只读兼容性证据；当前没有第二台设备。
- 真实 100% 和 150% Windows 缩放会话截图；当前证据为 125%。
- GitHub Actions 托管构建；当前外部阻断是仓库账号计费/额度。
- 干净 Windows 安全基线下 WinRing0 行为复核。
- 项目所有者对最终视频、封面、文案和发布范围的审阅。
- GitHub tag/release、B 站登录上传和公开发布仍需明确人工批准。

## 最终重建命令

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass `
  -File native\verify-release.ps1 `
  -Version 1.0.0-native `
  -ExecuteNoChangePolicy `
  -VerifyShellIntegration
```

仅从干净工作树运行。重建后重新记录 ZIP size、SHA256、source commit、
兼容性报告索引和 review bundle。
