# Native Release Candidate Review

状态：`DRAFT_FOR_HUMAN_REVIEW`

这不是公开 Release，也不是 B 站上传授权。本文只汇总原生 Rust GUI + C++
worker 候选 `1.0.20-native` 的可复核资产、已验证边界和仍需人工完成的门禁。

## 目标与定位

AMD Mobile Power 是面向 AMD 轻薄本的 Windows 原生功耗面板。它把 RyzenAdj
封装为前端 GUI + 特权 worker 的两进程结构，默认只读，写入必须显式解锁并
回读校验。当前只在一块 Ryzen 7 8845HS 开发机上完成硬件门禁，不代表所有
AMD 笔记本都受支持。

## 包与来源

- Repository: `https://github.com/syttys123/amd-mobile-power`
- Branch: `main`
- Candidate: `1.0.20-native`
- Package:
  `artifacts/native-packages/amd-mobile-power-v1.0.20-native-win-x64-native-preview.zip`
- Size: `758,548` bytes
- SHA256:
  `4285011dee71e3fbdc9c36869079e54430bccaee168d8d5f0f99b9524d88adf0`
- Package source commit: `d9129b01f4039ebd4db547070612589a1d834936`
- Working tree at build time: clean
- 19 项包内校验和。

本版在 `1.0.19-native` 紧凑 UI 重构之上完成两类修复：

1. **输入与焦点**：目标功耗与预设编辑在每秒遥测刷新、模式切换之间保留草稿；
   按钮只对真实点击执行动作，获得焦点不再误触发模式切换。
2. **矮屏适配**：高级窗口按当前显示器工作区打开，内容可滚动（滚轮、滚动条、
   键盘焦点自动带入视野），修复 1080p/150% 下底栏落到任务栏之后的问题；
   同时修复最小宽度被滚动条填充钳大 1px 的问题。

`1.0.18-native` 的 worker 卡死自愈、退出重启、探针管道忙重试、同提交逐字节
可复现、安全驱动卸载、多代 profile 目录、托盘/任务栏与单实例行为全部保留。
worker 二进制与 `1.0.18-native` 完全相同（`67af1d41`）。

## UI 规格

- 简洁模式默认客户区 `600x360`，可缩到 `560x360`；窗口最小客户尺寸含边框换算。
- 高级模式默认 `780x680`，窗口最小客户尺寸 `780x420`，内容最小布局宽度 760；
  工作区不足时整页滚动，滚动条不挤占内容最小宽度。
- 逻辑 DPI 夹具：简洁 `600x360 / 750x450 / 900x540`，高级
  `780x680 / 975x850 / 1170x1020`（100/125/150%）。
- 本地预设 `10 / 25 / 45 W`（可编辑），上限 `45 W`；10 W 是夜间手动档，
  不是全局硬编码。

## 本机验证

- Rust GUI 测试：`43/43`（21 library + 22 main，滚动修复新增 1 项布局测试）。
- Rust formatting / Clippy `-D warnings`：PASS。
- Rust probe 测试：`7/7`。
- C++ power-limit / power-policy 测试：PASS。
- 19 项包内 SHA256 校验：PASS。
- 提取后 GUI/worker 只读验证、诊断导出、兼容性 JSON/Markdown、无头探针：PASS。
- 可复现构建：GUI `72b22832`、worker `67af1d41`、探针 `9750418f`、ZIP
  `4285011d`，两次构建逐字节一致。
- 打包版交互：模式切换、置顶、预设编辑、目标草稿保留、焦点通知过滤、最小
  窗口边界、高级模式滚动（滚轮/滚动条/焦点带入）、诊断导出、三轮最小化恢复、
  关闭到托盘、托盘恢复、单实例唤醒：PASS。
- worker 卡死替换（2026-11-13 补跑）：`NtSuspendProcess` 挂起隔离 worker 后
  `33.5 s` 完成替换，`20/20` 次窗口响应采样通过、失败 0 次，策略与遥测恢复
  `10/10/10 W`。
- 隔离安装、覆盖安装、卸载：PASS。
- 真实当前用户 Start menu / Startup / uninstall entry 建删循环：PASS。
- 驱动安装/卸载脚本：均进入 ZIP 和 `C:\RyzenAdj`，部署后 19 个载荷文件与
  暂存包逐字节匹配。
- 嵌入图标门禁：构建、暂存、部署三处的 exe 均含 `RT_GROUP_ICON` 1 与 9 个
  `RT_ICON`。

Evidence:

- `docs/evidence/packaging/v1.0.20-native-clean-2026-11-12.json`
- `docs/evidence/packaging/v1.0.20-native-release-gate-2026-11-12.json`
- `docs/evidence/packaging/v1.0.20-native-shell-integration-2026-11-12.json`
- `docs/evidence/packaging/v1.0.20-native-deployment-2026-11-12.json`
- `docs/evidence/hardware/v1.0.20-native-power-policy-no-change-2026-11-12.json`
- `docs/evidence/hardware/v1.0.20-native-worker-hang-2026-11-13.json`
- `docs/evidence/ui/native-packaged-1.0.20-native-ui-2026-11-12.json`
- `docs/evidence/ui/native-deployed-1.0.20-native-ui-2026-11-12.json`
- `docs/evidence/ui/native-dpi-100-125-150-2026-11-12.json`
- `docs/evidence/build/reproducibility-2026-11-12.json`
- `docs/evidence/media/native-promo-1.0.20-draft-2026-11-12.json`
- `native/gui-cli-contract.json`

## 硬件门禁

开发机：MECHREVO WUJIE15 PRO / AMD Ryzen 7 8845HS / Hawk Point。

- 只读能力与遥测：SMU `15`、PM table `4c0009`、profile
  `hawk-point-8845hs [5-60 W]`。
- 受控当前值策略门禁（电池）：请求与回读 `25/25/20 W`（固件在电池下把 Slow
  动态压到 20 W），策略随后禁用，worker 正常关闭。
- 1.0.19 门禁曾在 AC 上做过 `25/25/25 W` 同值写回/回读；1.0.20 的 GUI 写入
  路径由打包版交互门禁与上述策略门禁覆盖。
- 读-only 写入守卫：非法目标被拒绝，没有发起硬件写入。
- 当前用户手动选择的状态：AC `10/10/10 W`（10 W 预设），自动策略关闭。

Evidence:

- `docs/evidence/hardware/v1.0.20-native-power-policy-no-change-2026-11-12.json`
- `docs/evidence/hardware/v1.0.20-native-worker-hang-2026-11-13.json`
- `docs/evidence/compatibility/mechrevo-wujie15-pro-20261112-011617.json`
- `docs/COMPATIBILITY_REPORTS.md`

## 本地部署

- 目标目录：`C:\RyzenAdj`
- 版本：`1.0.20-native`
- 旧版备份：`C:\RyzenAdj.before-v1.0.20-native-20261112-ui`
  （仓库副本
  `artifacts/deployment-backups/C-RyzenAdj-before-1.0.20-native-d9129b0-20261112-ui`）
- 桌面快捷方式：`<USER_HOME>\Desktop\功耗设置 5-60W.lnk`
- 快捷方式参数：`--enable-write-controls --simple-mode --max-target-watts 45`

## 发布物料

- 新截图：`assets/native-gui-1.0.20-simple-2026-11-12.png`、
  `assets/native-gui-1.0.20-advanced-2026-11-12.png`。
- 宣传片草稿：99.5 秒、1920x1080、SAPI 中文配音 + 原创合成配乐、
  7 个不重复场景，`verify-media.ps1` PASS。
- B 站封面：`docs/assets/bilibili-cover-1.0.20-2026-11-12.png`。
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
  -Version 1.0.20-native `
  -VerifyReproducibility `
  -VerifyShellIntegration `
  -ExecuteNoChangePolicy
```
