# Native Release Candidate Review

状态：`DRAFT_FOR_HUMAN_REVIEW`

这不是公开 Release，也不是 B 站上传授权。本文只汇总原生 Rust GUI + C++
worker 候选 `1.0.18-native` 的可复核资产、已验证边界和仍需人工完成的门禁。

## 目标与定位

AMD Mobile Power 是面向 AMD 轻薄本的 Windows 原生功耗面板。它把 RyzenAdj
封装为前端 GUI + 特权 worker 的两进程结构，默认只读，写入必须显式解锁并
回读校验。当前只在一块 Ryzen 7 8845HS 开发机上完成硬件门禁，不代表所有
AMD 笔记本都受支持。

## 包与来源

- Repository: `https://github.com/syttys123/amd-mobile-power`
- Branch: `main`
- Candidate: `1.0.18-native`
- Package:
  `artifacts/native-packages/amd-mobile-power-v1.0.18-native-win-x64-native-preview.zip`
- Size: `751,600` bytes
- SHA256:
  `fd7bf191ac557fb9bc1038cb725907ba67e5f819b8eeee6136f5cbe2721d6ef1`
- Package source commit: `12934dfb2850fab6a9a91216343b45a18f849d07`
- Working tree at build time: clean
- Review bundle: `artifacts/native-release-review/v1.0.18-native`

本版是第一个把 `-VerifyWorkerHang` 纳入发布门禁的包：门禁会在展开包上
挂起 worker，等待 30 秒心跳 watchdog 替换，检查窗口全程可响应，并要求
10/10/10 W 策略恢复。1.0.17 的卡死自愈、退出重启、探针管道忙重试、同提交
逐字节可复现、目标框同步、安全驱动卸载、多代 profile 目录、DPI 门禁和
电池/插电统一策略全部保留。

## 本机验证

- Rust GUI 测试：`40/40`（19 + 21 两个测试目标）。
- Rust formatting / Clippy `-D warnings`：PASS。
- C++ power-limit / power-policy 测试：PASS。
- 19 项包内 SHA256 校验：PASS。
- 提取后 GUI/worker 只读验证、诊断导出、兼容性 JSON/Markdown：PASS。
- 无头探针：6/6 单元测试、`--self-test`、包内真实 `--diagnose`
  （`collectionStatus=PASS`，AC `10/10/10 W`）：PASS。
- 可复现构建：GUI `ff2dcd48`、worker `67af1d41`、探针 `6a050588`、
  ZIP `eac6fc73`，两次构建逐字节一致。（1.0.13 记录）
- 1.0.18 可复现构建：GUI `63193c17`、worker `67af1d41`、探针 `9750418f`、
  ZIP `fd7bf191`，两次构建逐字节一致。
- worker 自我修复：杀掉部署中的 worker 后新进程 `1.3 s` 内就绪，策略重新
  下发为 `enabled=true`、电池/插电 `10/10/10`，实时回读 `10/10/10 W`；探针在
  GUI 轮询下连续 `30/30` 次调用成功。
- worker 卡死替换：`NtSuspendProcess` 挂起隔离 worker `34.5 s`，GUI 全程
  `Responding=true`，新 worker 接替后策略恢复为 `enabled=true`、电池/插电
  `10/10/10`、`lastAttemptSucceeded=true`。
- `1.0.18` 的 `-VerifyWorkerHang` 打包门禁：替换 `34.9 s`、`28/28` 次窗口
  响应采样通过、失败 0 次，策略恢复 `10/10/10 W`。
- 隔离安装、覆盖安装、卸载：PASS。
- 真实当前用户 Start menu / Startup / uninstall entry 建删循环：PASS。
- `1.0.9-native -> 1.0.10-native` 晋升：包校验、隔离安装/卸载、桌面快捷方式
  参数契约、真实参数启动：PASS。
- 驱动安装/卸载脚本：均进入 ZIP 和 `C:\RyzenAdj`，部署后 19 个载荷文件
  与暂存包逐字节匹配。
- 驱动更新顺序：运行中服务先停止并等待 `Stopped`，再替换 `.sys`；UI 控件
  就绪等待后的策略控件门禁连续 3 次 PASS。
- DPI 布局夹具：包内 GUI 在 100/125/150% 下简单/高级客户端尺寸分别为
  `640x392`/`780x680`、`800x490`/`975x850`、`960x588`/`1170x1020`，PASS。
- 多代 profile 目录：10 条 profile、family `0-15` 全覆盖且各一次、一个
  verified profile；真机只读采集和导入 PASS，故意删除 family `8` 的报告被拒绝。
- 嵌入图标门禁：构建、暂存、部署三处的 exe 均含 `RT_GROUP_ICON` 1 与 9 个
  `RT_ICON`，取出的 32x32 与源 ICO 逐像素 0 差异。
- 打包版托盘/任务栏与模式同步证据：`CloseToTray`、`TrayRestore`、
  `SingleInstanceWake`、`taskbarIconAvailable=true`、`trayIconId=1`、
  `simple -> advanced` 同步：PASS。

Evidence:

- `docs/evidence/packaging/v1.0.18-native-clean-2026-11-12.json`
- `docs/evidence/packaging/v1.0.18-native-release-gate-2026-11-12.json`
- `docs/evidence/packaging/v1.0.18-native-shell-integration-2026-11-12.json`
- `docs/evidence/hardware/v1.0.18-native-worker-hang-2026-11-12.json`
- `docs/evidence/hardware/v1.0.18-native-worker-hang-clean-2026-11-12.json`
- `docs/evidence/ui/native-packaged-1.0.18-native-ui-2026-11-12.json`
- `docs/evidence/packaging/v1.0.17-native-watchdog-hang-2026-11-12.json`
- `docs/evidence/packaging/v1.0.17-native-clean-2026-11-12.json`
- `docs/evidence/packaging/v1.0.17-native-release-gate-2026-11-12.json`
- `docs/evidence/packaging/v1.0.17-native-shell-integration-2026-11-12.json`
- `docs/evidence/ui/native-packaged-1.0.17-native-ui-2026-11-12.json`
- `docs/evidence/build/reproducibility-2026-11-12.json`
- `docs/evidence/diagnostics/headless-probe-8845hs-live-2026-11-12.json`
- `docs/evidence/ui/native-dpi-100-125-150-2026-11-12.json`
- `docs/assets/native-exe-icon-2026-11-11.png`
- `native/gui-cli-contract.json`

## 硬件门禁

开发机：MECHREVO WUJIE15 PRO / AMD Ryzen 7 8845HS / Hawk Point。

- 只读能力与遥测：SMU `15`、PM table `4c0009`、profile
  `hawk-point-8845hs [5-60 W]`、AC `10/10/10 W`。
- 受控当前值策略门禁：请求与回读均为 `10/10/10 W`，策略随后禁用，
  worker 正常关闭，实际限制不变。
- 读-only 写入守卫：非法目标被拒绝，没有发起硬件写入。

Evidence:

- `docs/evidence/hardware/v1.0.18-native-power-policy-no-change-2026-11-12.json`
- `docs/evidence/hardware/v1.0.17-native-power-policy-no-change-2026-11-12.json`
- `docs/evidence/hardware/v1.0.17-native-worker-hang-verifier-2026-11-12.json`
- `docs/evidence/compatibility/mechrevo-wujie15-pro-20261112-011617.json`
- `docs/COMPATIBILITY_REPORTS.md`
- `docs/evidence/compatibility/index.json`

## 本地部署

- 目标目录：`C:\RyzenAdj`
- 版本：`1.0.18-native`
- 旧版备份：`C:\RyzenAdj.before-20261112-074413`
- 仓库备份：
  `artifacts/deployment-backups/promote-amd-mobile-power-v1.0.18-native-win-x64-native-preview-20261112-074413.json`
- 桌面快捷方式：`<USER_HOME>\Desktop\功耗设置 5-60W.lnk`
- 快捷方式参数：`--enable-write-controls --simple-mode --max-target-watts 45`
- 部署验证：worker、托盘、单实例、模式、预设、电池策略开关、诊断导出 PASS；
  快捷方式真实参数启动验证 PASS。本机预设为 `10/25/45 W`，自动策略关闭，
  25 W 与 45 W 预设均完成真机写入/回读，当前停留在 25 W；`10 W` 仅作为
  夜间手动预设
- Evidence:
  `docs/evidence/packaging/v1.0.18-native-deployment-2026-11-12.json`

## 发布就绪检查

- Local readiness：`PASS`
- Public release readiness：`READY_FOR_HUMAN_REVIEW`
- 已核对：包 hash、clean gate、当前值策略回写、打包 UI/托盘、C 盘部署文件、
  部署探针 hash 与 `--self-test`、桌面快捷方式、兼容性索引、媒体草稿、
  review bundle 校验和；13 项检查全部为 true，本地阻塞项为空。
- 桌面快捷方式实际拉起：`WindowReady=true`，拒绝参数为空；带值参数
  `--max-target-watts 10` 与 `--uniform-target-watts 10` 均按契约正确识别。
- 100%/125%/150% 逻辑布局夹具已通过；仍需人工/外部完成：第二台 AMD 设备、
  真实 100%/150% Windows 会话缩放、托管 CI、
  WinRing0 干净安全基线、视频/封面/文案审阅、公开发布批准、B 站上传。
- Evidence:
  `docs/evidence/release/native-publication-readiness-1.0.18-2026-11-12.json`

## 发布媒体

- 视频草稿：
  `artifacts/media/amd-mobile-power-native-promo-10w-2026-11-12/amd-mobile-power-native-intro-10w-2026-11-12.mp4`
- 时长：`78.2 s`，`1920x1080`，H.264 + AAC
- SHA256：
  `af70c9e7bd837c04346dde7110fa7cd0a9c9221edad5f3e5826a28c92ed7d575`
- B 站封面：`docs/assets/bilibili-cover-native-10w-2026-11-12.png`
- 审片帧：`docs/assets/native-promo-10w-contact-sheet-2026-11-12.png`
- 机器证据：`docs/evidence/media/native-promo-draft-2026-11-12.json`

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
  -Version 1.0.18-native `
  -ExecuteNoChangePolicy `
  -VerifyShellIntegration
```

仅从干净工作树运行。重建后重新记录 ZIP size、SHA256、source commit、
兼容性报告索引和 review bundle。
