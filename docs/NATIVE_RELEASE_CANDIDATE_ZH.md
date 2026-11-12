# Native Release Candidate Review

状态：`DRAFT_FOR_HUMAN_REVIEW`

这不是公开 Release，也不是 B 站上传授权。本文只汇总原生 Rust GUI + C++
worker 候选 `1.0.23-native` 的可复核资产、已验证边界和仍需人工完成的门禁。

## 目标与定位

AMD Mobile Power 是面向 AMD 轻薄本的 Windows 原生功耗面板。它把 RyzenAdj
封装为前端 GUI + 特权 worker 的两进程结构，默认只读，写入必须显式解锁并
回读校验。当前只在一块 Ryzen 7 8845HS 开发机上完成硬件门禁，不代表所有
AMD 笔记本都受支持。

## 包与来源

- Repository: `https://github.com/syttys123/amd-mobile-power`
- Branch: `main`
- Candidate: `1.0.23-native`
- Package:
  `artifacts/native-packages/amd-mobile-power-v1.0.23-native-win-x64-native-preview.zip`
- Size: `760,850` bytes
- SHA256:
  `42f6cf9172f3db6d0a2ac81bfffbab4b38b1f5a1423ff64b7b020855fce29f79`
- Package source commit: `2033052dfb0e3fd0a427ea08adab12302b4addfc`
- Working tree at build time: clean
- 19 项包内校验和。

本版在 `1.0.22-native` 滚动基础之上完成边界收口：

1. **输入与焦点**：目标功耗与预设编辑在每秒遥测刷新、模式切换之间保留草稿；
   按钮只对真实点击执行动作，获得焦点不再误触发模式切换。
2. **滚动与窄屏**：滚动条显隐做成稳定循环，默认高级窗口不再残留假滚动条；
   简洁模式在短工作区也可纵向滚动；页头焦点按按钮实际矩形横向带入；DPI 切换
   使用系统建议矩形，不会把自定义窗口尺寸重置成默认值。
3. **最大化与翻页**：矮窗口滚动后最大化/贴边时重新收敛滚动偏移，页头不再被
   推出客户区；翻页步进与滚动条页大小一致；非整数 DPI 下页头不再 1px 错位。

`1.0.18-native` 的 worker 卡死自愈、退出重启、探针管道忙重试、同提交逐字节
可复现、安全驱动卸载、多代 profile 目录、托盘/任务栏与单实例行为全部保留。
worker 二进制与 `1.0.18-native` 完全相同（`67af1d41`）。

## UI 规格

- 简洁模式默认客户区 `600x360`，可缩到 `560x360`；窗口最小客户尺寸含边框换算。
- 高级模式默认 `780x680`，窗口最小客户尺寸 `560x420`；内容布局宽度保持 760，
  工作区不足时整页横向/纵向滚动。
- 逻辑 DPI 夹具：简洁 `600x360 / 750x450 / 900x540`，高级
  `780x680 / 975x850 / 1170x1020`（100/125/150%）。
- 本地预设 `10 / 25 / 45 W`（可编辑），上限 `45 W`；10 W 是夜间手动档，
  不是全局硬编码。

## 本机验证

- Rust GUI 测试：`46/46`（24 library + 22 main，新增翻页与最大化收敛测试）。
- Rust formatting / Clippy `-D warnings`：PASS。
- Rust probe 测试：`7/7`。
- C++ power-limit / power-policy 测试：PASS。
- 19 项包内 SHA256 校验：PASS。
- 提取后 GUI/worker 只读验证、诊断导出、兼容性 JSON/Markdown、无头探针：PASS。
- 可复现构建：GUI `e18c4213`、worker `67af1d41`、探针 `9750418f`、ZIP
  `42f6cf91`，两次构建逐字节一致。
- 打包版交互：模式切换、置顶、预设编辑、目标草稿保留、焦点通知过滤、最小
  窗口边界、高级模式滚动（滚轮/滚动条/焦点带入）、诊断导出、三轮最小化恢复、
  关闭到托盘、托盘恢复、单实例唤醒：PASS。
- worker 卡死替换（2026-11-13 补跑）：`NtSuspendProcess` 挂起隔离 worker 后
  `35.3 s` 完成替换，`21/21` 次窗口响应采样通过、失败 0 次，策略与遥测恢复
  `10/10/10 W`。
- 隔离安装、覆盖安装、卸载：PASS。
- 真实当前用户 Start menu / Startup / uninstall entry 建删循环：PASS。
- 驱动安装/卸载脚本：均进入 ZIP 和 `C:\RyzenAdj`，部署后 19 个载荷文件与
  暂存包逐字节匹配。
- 嵌入图标门禁：构建、暂存、部署三处的 exe 均含 `RT_GROUP_ICON` 1 与 9 个
  `RT_ICON`。

Evidence:

- `docs/evidence/packaging/v1.0.23-native-clean-2026-11-13.json`
- `docs/evidence/packaging/v1.0.23-native-release-gate-2026-11-13.json`
- `docs/evidence/packaging/v1.0.23-native-shell-integration-2026-11-13.json`
- `docs/evidence/packaging/v1.0.23-native-deployment-2026-11-13.json`
- `docs/evidence/hardware/v1.0.23-native-power-policy-no-change-2026-11-13.json`
- `docs/evidence/hardware/v1.0.23-native-worker-hang-2026-11-13.json`
- `docs/evidence/ui/native-packaged-1.0.23-native-ui-2026-11-13.json`
- `docs/evidence/ui/native-deployed-1.0.23-native-ui-2026-11-13.json`
- `docs/evidence/ui/native-maximize-scroll-2026-11-13.json`
- `docs/evidence/ui/native-maximize-scroll-1.0.22-baseline-2026-11-13.json`
- `docs/evidence/ui/native-workarea-200-1366x768-2026-11-13.json`
- `docs/evidence/ui/native-dpi-100-125-150-2026-11-13.json`
- `docs/evidence/build/reproducibility-2026-11-13.json`
- `docs/evidence/media/native-promo-1.0.23-draft-2026-11-13.json`
- `native/gui-cli-contract.json`

## 硬件门禁

开发机：MECHREVO WUJIE15 PRO / AMD Ryzen 7 8845HS / Hawk Point。

- 只读能力与遥测：SMU `15`、PM table `4c0009`、profile
  `hawk-point-8845hs [5-60 W]`。
- 受控当前值策略门禁（AC）：请求与回读 `10/10/10 W`，策略随后禁用，worker
  正常关闭；本次同值写入没有改变日常功耗。
- 1.0.22 的 GUI 写入路径由打包版交互门禁与上述策略门禁覆盖。
- 读-only 写入守卫：非法目标被拒绝，没有发起硬件写入。
- 当前用户手动选择的状态：AC `10/10/10 W`（10 W 预设），自动策略关闭。

Evidence:

- `docs/evidence/hardware/v1.0.22-native-power-policy-no-change-2026-11-13.json`
- `docs/evidence/hardware/v1.0.22-native-worker-hang-2026-11-13.json`
- `docs/evidence/compatibility/mechrevo-wujie15-pro-20261112-011617.json`
- `docs/COMPATIBILITY_REPORTS.md`

## 本地部署

- 目标目录：`C:\RyzenAdj`
- 版本：`1.0.23-native`
- 旧版备份：`C:\RyzenAdj.before-20261113-024133`
- 桌面快捷方式：`<USER_HOME>\Desktop\功耗设置 5-60W.lnk`
- 快捷方式参数：`--enable-write-controls --simple-mode --max-target-watts 45`

## 发布物料

- 新截图：`assets/native-gui-1.0.22-simple-2026-11-13.png`、
  `assets/native-gui-1.0.22-advanced-2026-11-13.png`。
- 宣传片草稿：109.2 秒、1920x1080、SAPI 中文配音 + 原创合成配乐、
  7 个不重复场景，`verify-media.ps1` PASS。
- B 站封面：`docs/assets/bilibili-cover-1.0.23-2026-11-13.png`。
- 宣传片状态：`DRAFT_FOR_HUMAN_REVIEW`，未上传。

## 仍需人工或外部条件

- [ ] 第二台物理 AMD 笔记本只读证据（当前无设备）。
- [ ] 真实 Windows 100%/150% 缩放会话的显示器切换证据
      （目前只有逻辑 DPI 夹具）。
- [ ] 托管 Windows CI：GitHub Actions 计费/额度问题在任务启动前失败。
- [ ] 项目所有者审片（节奏、配音、文案、封面）并批准公开。
- [ ] GitHub Release 与 B 站上传需要明确授权与账号会话。

## 复现命令

```powershell
.\native\verify-release.ps1 `
  -Version 1.0.23-native `
  -VerifyReproducibility `
  -VerifyShellIntegration `
  -ExecuteNoChangePolicy `
  -VerifyWorkerHang `
  -AllowBatteryWriteGuard
```
