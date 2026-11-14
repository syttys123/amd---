# Release Runbook

状态：`DRAFT_PENDING_HARDWARE_GATE`

执行前必须由项目所有者明确批准公开发布，并具备可用的 GitHub / B 站
登录会话。本手册覆盖 `1.0.31-native`；未完成硬件门禁和人工审片前不要
创建公开 Release 或上传视频。

候选版本：`1.0.31-native`。发布物料清单见
`docs/release-assets-1.0.31.json`。

## 0. 前置检查

```powershell
git -C D:\amd-mobile-power status --short --branch
git -C D:\amd-mobile-power log --oneline -8
Get-Command gh -ErrorAction SilentlyContinue
```

- 工作树干净，分支 `release/1.0.31` 已推送。
- 确认临时 8 W 窗口已结束，19:00 恢复任务已把策略恢复为 10 W。
- 先执行完整硬件门禁：

```powershell
.\native\verify-release.ps1 `
  -Version 1.0.31 `
  -VerifyReproducibility `
  -VerifyShellIntegration `
  -ExecuteNoChangePolicy `
  -VerifyWorkerHang `
  -AllowBatteryWriteGuard
```

- 只有门禁 PASS 后才能晋升、合并 `main` 和创建 tag。
- 项目所有者已审片并批准文案；视频、封面和音乐署名均已完成人工复核。

## 1. 晋升与发布线

先对晋升计划做 dry run：

```powershell
.\native\promote-stable-deployment.ps1 `
  -PackagePath .\artifacts\native-packages\amd-mobile-power-v1.0.31-win-x64-native-preview.zip `
  -TargetDirectory C:\RyzenAdj `
  -GuiArguments "--simple-mode --max-target-watts 45"
```

确认输出中的目标目录、回滚目录和快捷方式参数后执行：

```powershell
.\native\promote-stable-deployment.ps1 `
  -PackagePath .\artifacts\native-packages\amd-mobile-power-v1.0.31-win-x64-native-preview.zip `
  -TargetDirectory C:\RyzenAdj `
  -GuiArguments "--simple-mode --max-target-watts 45" `
  -Apply -NoLaunch
```

晋升后运行发布就绪检查，并把新的部署证据和审查包刷新到 1.0.31。确认
`LocalReadiness=PASS`、`PublicReleaseReadiness=READY_FOR_HUMAN_REVIEW`、
本地阻塞项为空后，再把分支合并到 `main`：

```powershell
git -C D:\amd-mobile-power switch main
git -C D:\amd-mobile-power merge --ff-only release/1.0.31
git -C D:\amd-mobile-power push origin main
```

## 2. 推送代码与标签

```powershell
git -C D:\amd-mobile-power tag -a v1.0.31 -m "AMD Mobile Power 1.0.31"
git -C D:\amd-mobile-power push origin v1.0.31
```

- 若 GitHub TLS 握手失败，先修复代理节点再重试；不要用 `--force` 覆盖远端。

## 3. 创建 GitHub Release

优先用网页端创建草稿，避免为了发布临时安装工具：

1. 打开 `https://github.com/syttys123/amd-mobile-power/releases/new`。
2. 选择刚推送的 tag `v1.0.31`，标题填
   `1.0.31 - AMD Mobile Power 原生预览候选`。
3. 正文粘贴 `docs/release-notes-1.0.31-zh.md` 的全部内容。
4. 上传 ZIP 与 `.zip.sha256` 两个附件。
5. 勾选 “Save as draft”，预览通过后再 Publish。

如果以后安装了 `gh`，等价命令：

```powershell
gh release create v1.0.31 `
  "D:\amd-mobile-power\artifacts\native-packages\amd-mobile-power-v1.0.31-win-x64-native-preview.zip" `
  "D:\amd-mobile-power\artifacts\native-packages\amd-mobile-power-v1.0.31-win-x64-native-preview.zip.sha256" `
  --title "1.0.31 - AMD Mobile Power 原生预览候选" `
  --notes-file D:\amd-mobile-power\docs\release-notes-1.0.31-zh.md `
  --draft
```

- 先建草稿，网页端复核渲染与附件后再手动发布。
- `docs/NATIVE_LAUNCH_COPY_1.0.31_ZH.md` 是内部口径，不要把整份说明贴进
  Release。
- 附件只放 ZIP 与 `.sha256`；视频和封面属于 B 站物料。

## 4. B 站上传

- 视频：`artifacts/media/promo-html-v1/amd-mobile-power-promo-2026-11-14-v9.mp4`
  （42.5 秒，1080p30，字幕 + 授权音乐，无配音）。
- 封面：`docs/assets/bilibili-cover-1.0.28-2026-11-14.png`（1146x717）。
- 标题、简介、标签和置顶评论取自
  `docs/NATIVE_LAUNCH_COPY_1.0.31_ZH.md`。
- 简介必须保留音乐署名：Deliberate Thought — Kevin MacLeod, CC BY 4.0。
- 分区建议：科技 → 数码；简介中给出 GitHub 地址与“默认只读 / 写入需解锁”
  的安全说明。
- 上传后核对：封面未裁切、字幕可开关、简介链接可点、稿件非“仅自己可见”。

## 5. 发布后核验

```powershell
Get-FileHash $env:USERPROFILE\Downloads\amd-mobile-power-v1.0.31-win-x64-native-preview.zip -Algorithm SHA256
Expand-Archive $env:USERPROFILE\Downloads\amd-mobile-power-v1.0.31-win-x64-native-preview.zip -DestinationPath $env:TEMP\amp-verify
& $env:TEMP\amp-verify\amd-mobile-power-v1.0.31-win-x64-native-preview\amd-mobile-power-probe.exe --self-test
```

- 下载到的 ZIP SHA256 必须等于
  `ccb0ed9a91cc27ab068f117d8174c605c84fb4ab8f6202faecfdce2058326de5`。
- 探针 `--self-test` 必须返回 `selfTest=PASS`，且不触发任何硬件写入。
- B 站稿件公开可访问后，把链接补进 GitHub Release 正文和 README。

## 6. 回滚

- 本机应用：使用晋升输出中的 `C:\RyzenAdj.before-<timestamp>` 完整目录，
  不要手工覆盖部署文件。
- GitHub：把 Release 改回 Draft 或删除 tag（`git push origin :v1.0.31`
  仅在你确认需要撤回时执行）。
- B 站：稿件设为“仅自己可见”，不要直接删除，保留观众评论与数据。

## 7. 已知未闭环项

- 第二台物理 AMD 笔记本证据（当前无设备）。
- 真实 Windows 100%/150% 缩放会话切换证据（目前是逻辑 DPI 夹具）。
- 干净 Windows 环境下的 WinRing0/驱动基线证据。
- 宣传片仍需项目所有者审片。
