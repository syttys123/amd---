# Release Runbook

状态：离线准备好的执行手册。所有步骤都需要项目所有者先明确批准公开发布，
并具备可用的 GitHub / B 站登录会话。

候选版本：`1.0.29-native`。发布物料清单见
`docs/release-assets-1.0.29.json`。

## 0. 前置检查

```powershell
git -C D:\amd-mobile-power status --short --branch
git -C D:\amd-mobile-power log --oneline -5
Get-Command gh -ErrorAction SilentlyContinue
```

- 工作树干净，分支领先远端的提交已全部推送。
- `docs/evidence/release/native-publication-readiness-2026-11-14.json` 的
  `LocalReadiness` 为 `PASS`，`BlockersFromLocalChecks` 为空。
- 项目所有者已审片并批准文案；`ExplicitPublicReleaseApproval` 不再是
  `PENDING`。

## 1. 推送代码与标签

```powershell
git -C D:\amd-mobile-power push origin main
git -C D:\amd-mobile-power tag -a v1.0.29 -m "AMD Mobile Power 1.0.29"
git -C D:\amd-mobile-power push origin v1.0.29
```

- 若 GitHub TLS 握手失败，先修复代理节点再重试；不要用 `--force` 覆盖远端。

## 2. 创建 GitHub Release

本机目前没有安装 `gh`；优先用网页端创建草稿，避免为了发布临时装工具。

网页端步骤：

1. 打开 `https://github.com/syttys123/amd-mobile-power/releases/new`。
2. 选择刚推送的 tag `v1.0.29`，标题填
   `1.0.29 - AMD Mobile Power 原生预览候选`。
3. 正文粘贴 `docs/release-notes-1.0.29-zh.md` 的全部内容。
4. 上传 ZIP 与 `.zip.sha256` 两个附件。
5. 勾选 “Save as draft”，预览通过后再 Publish。

如果以后安装了 `gh`，等价命令：

```powershell
gh release create v1.0.29 `
  "D:\amd-mobile-power\artifacts\native-packages\amd-mobile-power-v1.0.29-win-x64-native-preview.zip" `
  "D:\amd-mobile-power\artifacts\native-packages\amd-mobile-power-v1.0.29-win-x64-native-preview.zip.sha256" `
  --title "1.0.29 - AMD Mobile Power 原生预览候选" `
  --notes-file D:\amd-mobile-power\docs\release-notes-1.0.29-zh.md `
  --draft
```

- 先建草稿，网页端复核渲染与附件后再手动发布。
- 正文使用 `docs/release-notes-1.0.29-zh.md`；`docs/NATIVE_LAUNCH_COPY_1.0.29_ZH.md`
  是内部口径，不要把整份说明贴进 Release。
- 附件只放 ZIP 与 `.sha256`；视频和封面属于 B 站物料。

## 3. B 站上传

- 视频：`artifacts/media/promo-html-v1/amd-mobile-power-promo-2026-11-14-v9.mp4`
  （42.5 秒，1080p30，字幕 + 授权音乐，无配音）。
- 封面：`docs/assets/bilibili-cover-1.0.28-2026-11-14.png`（1146x717）。
- 标题、简介、标签、置顶评论取自 `docs/NATIVE_LAUNCH_COPY_1.0.29_ZH.md`。
- 简介必须保留音乐署名：Deliberate Thought — Kevin MacLeod, CC BY 4.0。
- 分区建议：科技 → 数码；简介中给出 GitHub 地址与“默认只读 / 写入需解锁”
  的安全说明。
- 上传后核对：封面未裁切、字幕可开关、简介链接可点、稿件非“仅自己可见”。

## 4. 发布后核验

```powershell
Get-FileHash $env:USERPROFILE\Downloads\amd-mobile-power-v1.0.29-win-x64-native-preview.zip -Algorithm SHA256
Expand-Archive $env:USERPROFILE\Downloads\amd-mobile-power-v1.0.29-win-x64-native-preview.zip -DestinationPath $env:TEMP\amp-verify
& $env:TEMP\amp-verify\amd-mobile-power-v1.0.29-win-x64-native-preview\amd-mobile-power-probe.exe --self-test
```

- 下载到的 ZIP SHA256 必须等于
  `c6b54d84f3f1bdba67407fe72a1f4465913e554defa1577e5c02c7373b5db640`。
- 探针 `--self-test` 必须返回 `selfTest=PASS`，且不触发任何硬件写入。
- B 站稿件公开可访问后，把链接补进 GitHub Release 正文和 README。

## 5. 回滚

- GitHub：把 Release 改回 Draft 或删除 tag（`git push origin :v1.0.29`
  仅在你确认需要撤回时执行）。
- B 站：稿件设为“仅自己可见”，不要直接删除，保留观众评论与数据。
- 本机应用：`C:\RyzenAdj.before-20261114-054523` 是 1.0.28 的完整回滚目录。

## 6. 已知未闭环项

- 第二台物理 AMD 笔记本证据（当前无设备）。
- 真实 Windows 100%/150% 缩放会话切换证据（目前是逻辑 DPI 夹具）。
- 干净 Windows 环境下的 WinRing0/驱动基线证据。
- 宣传片仍需项目所有者审片。
