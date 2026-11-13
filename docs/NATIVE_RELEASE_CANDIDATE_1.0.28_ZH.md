# Native Release Candidate 1.0.28

状态：`DRAFT_FOR_HUMAN_REVIEW`

这不是公开 Release，也不是 B 站上传授权。本文汇总原生 Rust GUI + C++
worker 候选 `1.0.28-native` 的可复核资产、验证边界和仍需人工完成的门禁。

## 包与来源

- Repository: `https://github.com/syttys123/amd-mobile-power`
- Branch: `main`
- Candidate: `1.0.28-native`
- Package:
  `artifacts/native-packages/amd-mobile-power-v1.0.28-win-x64-native-preview.zip`
- Size: `769,919` bytes
- SHA256:
  `3a60bd0373120889d6a7bedd11e42f87df7a398288eea95354b20cab4998f593`
- Package source commit: `f64812e6fb873ef72df81e8b324f2172d51aa506`
- Working tree at build time: clean
- Deployed GUI SHA256:
  `d46f885e44aa53355739005a875d107bff58b83a23da4639991be6fd7f538245`
- Deployed worker SHA256:
  `67af1d41c9a054d9522e4f81521c4d9db1803bd8156199fe119e38470fd0efb1`
- Deployed probe SHA256:
  `9750418f15ebce2d70e750e845cfa5408751a96b178d60bbaa168155322a615e`

## 本版重点

1. **托盘写入解锁**：托盘菜单和右上角锁按钮进入同一套免责声明、操作须知和
   勾选确认流程；解锁状态持久化，再次点击锁立即恢复只读。
2. **可写字段文案**：高级模式由“STAPM 是 · Fast 是 · Slow 是”改为
   “可写：STAPM / Fast / Slow”，并覆盖部分支持和全不支持两种情况。
3. **自动策略修复保留**：正常快捷方式启动时，持久化解锁会传给 worker；
   worker 重启后会重新下发已保存的电池/外接策略。
4. **界面稳定性保留**：双缓冲绘制、无白闪重绘、滚动条状态收敛、最大化
   滚动偏移校正、短工作区整页滚动和托盘/任务栏单实例行为。

## 验证结果

- Rust GUI：24 library + 23 main，共 `47/47` 测试通过。
- Rust probe：`7/7` 测试通过。
- C++ power-limit / power-policy 测试：PASS。
- Clippy `-D warnings`：PASS。
- 包内 SHA256 校验：PASS。
- 可复现构建：GUI、worker、probe、portable ZIP 两次构建逐字节一致。
- 100/125/150% DPI、1366x768/200% 工作区、最大化滚动：PASS。
- 关闭到托盘、托盘恢复、单实例唤醒、显式退出：PASS。
- worker 卡死替换：`34.0 s`，17 次响应采样 0 失败，策略恢复。
- 打包版只读启动、诊断导出、模式切换、预设编辑、最小窗口边界：PASS。
- 部署版托盘菜单运行时检查：`简洁模式`、`写入已解锁` 勾选正确，
  预设 `10 / 25 / 45 W` 存在，关闭菜单后进程仍响应。
- 打包版 GUI 独立验证：从发布 ZIP 解包后运行，GUI/worker 哈希与部署记录
  一致；关闭到托盘、托盘恢复、单实例唤醒、模式切换、写入控件、预设编辑、
  最小窗口边界、最大化滚动全部 PASS；验证结束后自动恢复原本运行的托盘应用。
- 发布就绪门禁：`LocalReadiness=PASS`、
  `PublicReleaseReadiness=READY_FOR_HUMAN_REVIEW`，本地阻塞项为空。
- 托管 Windows CI：run `43509158502`（commit `4f91e4e`）全部步骤 success，
  覆盖 PowerShell 语法、文档链接、Rust fmt/clippy、RyzenAdj 构建、原生
  测试、可复现包、探针自检与产物上传。

## 硬件边界

- 唯一完整实机证据：MECHREVO WUJIE15 PRO / AMD Ryzen 7 8845HS /
  Hawk Point / PM table `4c0009`。
- 门禁在电池供电下执行同值策略写回/回读，请求与回读
  `8/8/8 W`；策略随后在隔离 worker 中关闭。
- 部署版当前电池回读：STAPM `8 W`、PPT Fast `8 W`、PPT Slow `8 W`，
  无固件钳制，自动策略已启用，电池和外接目标均为 8 W。
- 其他 AMD 世代仍是保守 profile 和实验性支持，不声明“全 AMD 通用”。
- Windows 不能区分 USB-C 充电宝和墙插，两者都按外接电源处理。

## 证据索引

- `docs/evidence/packaging/v1.0.28-release-gate-2026-11-14.json`
- `docs/evidence/packaging/v1.0.28-clean-2026-11-14.json`
- `docs/evidence/packaging/v1.0.28-shell-integration-2026-11-14.json`
- `docs/evidence/packaging/v1.0.28-native-deployment-2026-11-14.json`
- `docs/evidence/hardware/v1.0.28-power-policy-no-change-2026-11-14.json`
- `docs/evidence/hardware/v1.0.28-worker-hang-2026-11-14.json`
- `docs/evidence/ui/v1.0.28-tray-menu-2026-11-14.json`
- `docs/evidence/ui/native-maximize-scroll-2026-11-14.json`
- `docs/evidence/ui/native-workarea-200-1366x768-2026-11-14.json`
- `docs/evidence/ui/native-dpi-100-125-150-2026-11-14.json`
- `docs/evidence/ui/native-packaged-1.0.28-ui-2026-11-14.json`
- `docs/evidence/media/native-promo-1.0.28-draft-2026-11-14.json`
- `docs/evidence/build/reproducibility-2026-11-14.json`
- `docs/evidence/build/hosted-ci-2026-11-14.json`
- `docs/evidence/release/native-publication-readiness-2026-11-14.json`

## 发布就绪

- 审查包：`artifacts/native-release-review/v1.0.28`，29 个文件，
  `SHA256SUMS.txt` 全部校验通过。
- 审查包内含安装包、`release-gate.json`、`clean-package.json`、
  `shell-integration.json`、`deployment.json`、`packaged-ui.json`、
  功耗策略证据、DPI 截图、宣传片、封面、联系表和发布文案。
- 未创建 GitHub Release，未上传 B 站，未使用账号登录。

## 本地部署

- 目标目录：`C:\RyzenAdj`
- 版本：`1.0.28`
- 旧版备份：`C:\RyzenAdj.before-20261114-025845`
- 桌面快捷方式：`<USER_HOME>\Desktop\功耗设置 5-60W.lnk`
- 快捷方式参数：`--simple-mode --max-target-watts 45`
- 正常启动默认只读；写入通过右上角锁或托盘“写入解锁…”开启。

## 发布物料

- 实际截图：
  `assets/native-gui-1.0.28-simple-2026-11-14.png`、
  `assets/native-gui-1.0.28-advanced-2026-11-14.png`。
- 宣传片 v9：42.5 秒、1920x1080、30 fps、无配音、字幕和授权音乐，
  界面片段来自 1.0.28 实机/实机截图。
- 宣传片文件：
  `artifacts/media/promo-html-v1/amd-mobile-power-promo-2026-11-14-v9.mp4`
- SHA256:
  `ca887aa5ec3b55157e91206781d15f502e3fdede7c3c7e3907621ac331863023`
- 媒体证据：`docs/evidence/media/native-promo-1.0.28-draft-2026-11-14.json`
- B 站封面：`docs/assets/bilibili-cover-1.0.28-2026-11-14.png`
  （1146x717，文字安全宽度 PASS）
- 联系表：`docs/assets/native-promo-1.0.28-contact-sheet-2026-11-14.png`
  （1920x540，8 帧）
- 音乐：Kevin MacLeod — Deliberate Thought，CC BY 4.0；发布描述必须保留署名。
- 状态：`DRAFT_FOR_HUMAN_REVIEW`，未上传。

## 仍需人工或外部条件

- [ ] 第二台物理 AMD 笔记本只读证据（当前无第二台设备）。
- [ ] 真实显示器切换的 100%/150% 会话证据（当前使用逻辑 DPI 夹具）。
- [ ] 干净 Windows 环境下的 WinRing0/驱动基线证据。
- [ ] 项目所有者审片：节奏、字幕、音乐、封面和文案。
- [ ] GitHub Release 发布需要明确授权。
- [ ] B 站上传需要账号会话和明确授权。

## 复现命令

```powershell
.\native\verify-release.ps1 `
  -Version 1.0.28 `
  -VerifyReproducibility `
  -VerifyShellIntegration `
  -ExecuteNoChangePolicy `
  -VerifyWorkerHang `
  -AllowBatteryWriteGuard
```
