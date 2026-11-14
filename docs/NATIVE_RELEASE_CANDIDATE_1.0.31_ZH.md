# Native Release Candidate 1.0.31

状态：`CANDIDATE_PENDING_HARDWARE_GATE`

这不是公开 Release，也不是 B 站上传授权。本文汇总原生 Rust GUI + C++
worker 候选 `1.0.31-native` 的可复核资产、可靠性修复、已通过的软件门禁，
以及仍需在 19:00 后执行的实机门禁。

## 包与来源

- Repository: `https://github.com/syttys123/amd-mobile-power`
- Branch: `codex/atomic-state-persistence`
- Candidate: `1.0.31-native`
- Package:
  `artifacts/native-packages/amd-mobile-power-v1.0.31-win-x64-native-preview.zip`
- Size: `775,091` bytes
- SHA256:
  `ccb0ed9a91cc27ab068f117d8174c605c84fb4ab8f6202faecfdce2058326de5`
- Package source commit: `92c18216e610607a3139af5e4f4335e78a9f9129`
- Working tree at build time: clean
- GUI SHA256:
  `18f82690f768f10d0e27379859a01b8f1f837642e9982d380cf8eb022f70e03b`
- Worker SHA256:
  `67af1d41c9a054d9522e4f81521c4d9db1803bd8156199fe119e38470fd0efb1`
- Probe SHA256:
  `9750418f15ebce2d70e750e845cfa5408751a96b178d60bbaa168155322a615e`

## 本版重点

1. **原子状态持久化**：所有 `save_*` 操作先写同目录临时文件，调用
   `sync_all`，再用 `MoveFileExW` 的
   `MOVEFILE_REPLACE_EXISTING | MOVEFILE_WRITE_THROUGH` 替换目标文件。
   保存过程中异常退出不会再留下半截 `rust-ui-state.json`。
2. **损坏状态保留**：状态文件解析失败时，原文件会保留为
   `rust-ui-state.json.corrupt.bak`，随后由下一次成功保存原子替换。
   UTF-8 BOM 兼容继续保留。
3. **安装器进程范围修复**：`install-preview.ps1` 和
   `uninstall-preview.ps1` 不再按进程名杀死所有 GUI/worker，而是只停止
   可执行文件位于目标安装目录内的进程。隔离安装/卸载不会误杀稳定部署。
4. **回归守卫**：新增 `native/test-install-process-scope.ps1`，在稳定
   GUI/worker 运行时执行隔离安装/卸载，并要求稳定进程集合保持不变。
5. **其余能力保持**：双缓冲界面、托盘解锁、持久化写入权限、电池/外接
   自动策略、worker 重启后重发策略、可编辑预设、只读诊断和单实例恢复
   均未回退。

## 已通过的软件门禁

- Rust GUI：28 library + 23 main = `51/51`。
- Rust probe：`7/7`。
- C++ power-limit / power-policy tests：PASS。
- Rust formatting、Clippy `-D warnings`：PASS。
- Release build、嵌入图标检查：PASS。
- 便携包：19 条 SHA256 校验，isolated install/overwrite/uninstall
  `InstallFlow=PASS`。
- 可复现构建：GUI、probe、worker、portable ZIP 两次构建逐字节一致。
- 安装器进程范围回归：PASS；稳定 GUI/worker PID 集合保持不变，
  隔离目标目录已清理。
- 原生代码 CI：run `43534100849`（commit `92c1821`）全部步骤 success。
- 文档与证据 CI：run `43534569167`（commit `113e9b1`）全部步骤 success。

## 尚未执行的硬件门禁

以下项目故意留到临时 8 W 窗口结束后执行，避免在用户策略有效期间中断
worker 或改变功耗：

- [ ] `verify-release.ps1 -Version 1.0.31` 完整硬件门禁。
- [ ] 当前值同值策略写入/回读。
- [ ] worker 卡死替换与策略恢复。
- [ ] 100/125/150% DPI、1366x768/200% 工作区、最大化滚动。
- [ ] shell integration 与部署版 GUI 交互回归。
- [ ] 晋升到 `C:\RyzenAdj`，并保留新的时间戳回滚目录。

## 硬件边界

- 唯一完整实机证据：MECHREVO WUJIE15 PRO / AMD Ryzen 7 8845HS /
  Hawk Point / PM table `4c0009`。
- 其他 AMD 世代仍是保守 profile 和实验性支持，不声明“全 AMD 通用”。
- Windows 不能区分 USB-C 充电宝和墙插，两者都按外接电源处理。
- 当前稳定部署仍为 `1.0.30`；本候选尚未替换 `C:\RyzenAdj`。

## 证据索引

- `docs/evidence/packaging/v1.0.31-clean-2026-11-14.json`
- `docs/evidence/packaging/v1.0.31-install-process-scope-2026-11-14.json`
- `docs/evidence/build/reproducibility-1.0.31-2026-11-14.json`
- `docs/evidence/packaging/v1.0.30-release-gate-2026-11-14.json`
- `docs/evidence/packaging/v1.0.30-native-deployment-2026-11-14.json`
- `docs/evidence/release/native-publication-readiness-2026-11-14.json`

## 仍需人工或外部条件

- [ ] 第二台物理 AMD 笔记本只读证据（当前无第二台设备）。
- [ ] 真实显示器切换的 100%/150% 会话证据。
- [ ] 干净 Windows 环境下的 WinRing0/驱动基线证据。
- [ ] 项目所有者审片：节奏、字幕、音乐、封面和文案。
- [ ] GitHub Release 发布需要明确授权。
- [ ] B 站上传需要账号会话和明确授权。

## 复现命令

软件包与安装器守卫：

```powershell
.\native\build-package.ps1 `
  -Version 1.0.31 `
  -NoBuild `
  -SkipRuntimeVerification `
  -EvidencePath .\docs\evidence\packaging\v1.0.31-clean-2026-11-14.json

.\native\test-install-process-scope.ps1 `
  -EvidencePath .\docs\evidence\packaging\v1.0.31-install-process-scope-2026-11-14.json
```

19:00 后的完整硬件门禁：

```powershell
.\native\verify-release.ps1 `
  -Version 1.0.31 `
  -VerifyReproducibility `
  -VerifyShellIntegration `
  -ExecuteNoChangePolicy `
  -VerifyWorkerHang `
  -AllowBatteryWriteGuard
```
