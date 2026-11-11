# Native Launch Copy

状态：`DRAFT_FOR_HUMAN_REVIEW`

本文只准备原生候选 `1.0.0-native` 的 GitHub 与 B 站文案，不代表已经批准公开。
最终 Release、视频、封面、账号登录和上传仍需项目所有者确认。

## 事实口径

- 当前候选包为 `1.0.0-native`，默认只读。
- 唯一完整实机证据：MECHREVO WUJIE15 PRO / AMD Ryzen 7 8845HS。
- 已验证 AC `25/45/25 W` 当前值写回/回读、策略禁用和优雅退出。
- 已验证打包版托盘、任务栏图标、单实例、模式同步、诊断导出。
- 当前没有第二台 AMD 设备；其他世代仍是实验性配置。
- Windows 无法区分 USB-C 充电宝和墙插，两者统一显示为“电源”。
- 不声明支持所有 AMD 笔记本，不建议为运行开发版关闭系统安全防护。

## GitHub Release 草稿

标题：

```text
1.0.0-native — AMD Mobile Power 原生稳定本地候选
```

正文：

````markdown
## 原生候选

AMD Mobile Power 将 RyzenAdj 封装为原生 Rust GUI + C++ worker，默认只读。
本候选面向 AMD 轻薄本，目标是让实时功耗、固件上限、目标设置和兼容性诊断
在一个窗口中可见。

## 已验证

- Ryzen 7 8845HS / Hawk Point 只读能力与遥测。
- AC `25/45/25 W` 当前值写回、回读、策略禁用和 worker 关闭。
- 30/30 Rust 测试、C++ 策略测试、Clippy、包内 SHA256。
- 隔离安装、覆盖安装、卸载、`rc.17 -> 1.0.0-native` 升级。
- 托盘、任务栏图标、单实例唤醒、简洁/高级模式同步。
- 高对比度、本地化、诊断脱敏和兼容性报告导入。

## 安全边界

这是单设备验证的内部候选，不是“全 AMD 通用版”。硬件写入必须显式解锁，
写入后必须回读；不要关闭 Windows 安全防护来运行 WinRing0。不同 AMD
世代、BIOS 和 EC 需要独立证据。

## 兼容性反馈

请从解压后的包运行 `collect-native-diagnostics.ps1`，检查脱敏 JSON 后提交
Issue。收集器只读、不上传、不启用功耗写入。

## 下载

- 原生预览 ZIP。
- 同名 `.sha256` 校验文件。
- 当前只有单台 8845HS 实机证据，其他设备请先提交只读诊断。
````

## B 站草稿

标题：

```text
给 AMD 轻薄本做一个原生功耗面板：实时功耗、预设、回读与兼容诊断
```

简介：

```text
AMD Mobile Power 是一个开源 Windows 工具，目标是把 RyzenAdj 的底层能力
整理成更清晰、可回读的原生功耗面板。

当前可以查看实时 STAPM、PPT Fast、PPT Slow、温度、供电和电池状态，
支持可编辑预设、托盘、简洁/高级模式、高对比度和只读兼容性诊断。

当前候选默认只读，完整实机证据来自 Ryzen 7 8845HS。不同 AMD 型号请先
运行包内 collect-native-diagnostics.ps1 提交诊断，不要照搬其他机型参数，
也不要为了运行开发版关闭 Windows 安全防护。

项目地址：
https://github.com/syttys123/amd-mobile-power
```

标签建议：

```text
AMD,Ryzen,RyzenAdj,轻薄本,功耗管理,Windows,开源软件,数码
```

封面主文案：

```text
AMD 轻薄本
功耗看得见
```

封面副文案：

```text
原生 GUI · 实时功耗 · 安全回读
```

当前原生封面：

```text
docs/assets/bilibili-cover-native-2026-11-11.png
```

当前原生视频草稿：

```text
artifacts/media/amd-mobile-power-native-promo-draft-2026-11-11/
  amd-mobile-power-native-intro-draft-2026-11-11.mp4
```

## 发布前人工确认

- 确认最终视频的配音、字幕、节奏和事实口径。
- 用最终 clean commit 重建 native ZIP 与 SHA256。
- 确认封面使用当前原生界面截图，不沿用旧版 .NET 界面。
- 确认 Release 标注为候选/单设备验证，不冒充广泛稳定版。
- 确认 B 站由人工登录上传，并保留安全与兼容范围提示。
- 确认项目所有者明确批准 GitHub Release 与 B 站上传。
