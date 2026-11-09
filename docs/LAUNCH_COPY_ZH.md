# GitHub 与 B 站发布文案

状态：`DRAFT_FOR_HUMAN_REVIEW`

本文只准备发布文案，不代表已经批准公开。真实电池证据、第二台 AMD 实机证据、
最终视频审片和项目所有者确认仍是公开 Release 与 B 站上传的门槛。

## 事实口径

- 当前包是只读开发预览，默认不修改功耗。
- 当前已验证设备为 MECHREVO WUJIE15 PRO，AMD Ryzen 7 8845HS。
- 受控验证覆盖 10 W、12 W 写入/回读/恢复，以及 12 W 无变化写入门禁。
- 当前没有第二台 AMD 实机的完整能力、遥测、写入和恢复证据。
- Windows 无法可靠区分 USB-C 充电宝和墙插，因此外接供电统一显示为“电源”。
- 不声称支持“所有 AMD 笔记本”，不为运行开发版而关闭系统安全防护。

## GitHub Release

拟用标题：

```text
v0.1.3-dev — AMD 轻薄本只读功耗面板开发预览
```

拟用正文：

````markdown
## 开发预览

AMD Mobile Power 是一个面向 AMD 轻薄本的 Windows 原生功耗监控工具。
本版本默认只读，适合查看平台识别、实时 STAPM/PPT、温度、供电状态，
以及提交兼容性诊断。

## 当前已验证

- Ryzen 7 8845HS / Hawk Point 开发机能够读取实时功耗和固件上限。
- GUI 与隐藏 worker 通过当前用户专属命名管道通信。
- 12 W、25 W、45 W 预设可编辑，写入门禁与失败回读路径已有自动化测试。
- 便携包包含无需打开 GUI 的只读诊断收集器。
- 本地发布门禁通过：构建 0 警告、62/62 测试、安装/卸载、托盘退出、
  只读诊断和 clean-package 校验。

## 安全边界

开发包默认只读。硬件写入仍处于受控验证阶段，需要显式开发开关；
不要关闭 Windows 安全防护来强行运行 WinRing0。

不同 AMD 世代、BIOS 和 EC 行为需要独立证据。目前只有一台开发机的完整
实机证据，因此本项目不声明支持所有 AMD 笔记本。

## 兼容性反馈

解压 Lite 包后运行：

```powershell
powershell -ExecutionPolicy Bypass -File .\collect-diagnostics.ps1
```

收集器只启用硬件读取，不启用功耗写入，不上传数据，并会移除本机绝对路径、
进程 ID 和最近日志。请检查生成的 JSON 后再附到兼容性 Issue。

## 下载

- Lite 包需要 Microsoft .NET 8 Desktop Runtime x64。
- 完整 SHA256、构建提交和测试证据见 Release Assets 与本仓库文档。
````

## B 站

拟用标题：

```text
给 AMD 轻薄本做一个原生功耗面板：实时功耗、可编辑预设、只读诊断
```

备用标题：

```text
AMD 轻薄本功耗别只靠猜：RyzenAdj 原生 GUI 开发预览
```

拟用简介：

```text
AMD Mobile Power 是一个正在开发中的开源 Windows 工具，目标是把 RyzenAdj
的底层能力整理为更安全、更清晰的原生功耗面板。

当前可以查看实时 STAPM、PPT Fast、PPT Slow、温度、供电和电池状态，
支持可编辑预设、托盘监控、固件上限提示和兼容性诊断。

当前版本默认只读，硬件写入仍在受控验证阶段。视频中的 8845HS 是目前的
主要实机证据，不代表所有 AMD 轻薄本都支持。Windows 也无法区分充电宝和
墙插，所以两者都会显示为“电源”。

项目地址：
https://github.com/syttys123/amd-mobile-power

兼容性反馈请优先使用便携包内的 collect-diagnostics.ps1。不要为了运行
开发版关闭 Windows 安全防护。
```

标签建议：

```text
AMD,Ryzen,RyzenAdj,轻薄本,功耗管理,Windows,开源软件,数码
```

置顶评论：

```text
这是只读开发预览，不是“全 AMD 笔记本通用版”。目前完整实机证据来自
Ryzen 7 8845HS。不同型号请先运行包内 collect-diagnostics.ps1 提交诊断，
不要关闭系统安全防护，也不要直接照搬其他机型的写入参数。
```

封面主文案：

```text
AMD 轻薄本
功耗看得见
```

封面副文案：

```text
原生 GUI · 实时功耗 · 只读诊断
```

机器可验证的 1146x717 封面：

```text
docs/assets/bilibili-cover-2026-11-10.png
```

## 发布前人工确认

- 确认最终视频的配音、字幕、节奏、封面和事实口径。
- 确认 GitHub Release 使用最终 clean commit 生成的 ZIP 与 SHA256。
- 确认最终 Release 没有把开发候选描述为稳定版。
- 确认 B 站上传由人工登录操作，并保留安全提示和兼容范围。
- 确认项目所有者明确批准公开 Release 与视频上传。
