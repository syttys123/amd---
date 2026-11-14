# Native Launch Copy 1.0.31

状态：`DRAFT_PENDING_HARDWARE_GATE`

本文准备 `1.0.31-native` 的 GitHub 与 B 站文案，不代表已批准公开。
完整实机门禁、最终 Release、视频审核、账号登录和上传仍需项目所有者确认。

## 事实口径

- 当前候选包：`1.0.31-native`，portable ZIP，775,091 bytes。
- SHA256：
  `ccb0ed9a91cc27ab068f117d8174c605c84fb4ab8f6202faecfdce2058326de5`。
- 唯一完整实机证据：MECHREVO WUJIE15 PRO / AMD Ryzen 7 8845HS。
- 默认只读；右上角锁或托盘“写入解锁…”进入免责声明、操作须知和勾选确认。
- 解锁状态持久化，再次点锁立即恢复只读。
- 自动策略支持电池/外接分别设置目标，worker 重启后自动重发策略。
- 1.0.31 重点是状态持久化和安装器进程隔离修复，界面与 1.0.30 相同。
- 当前稳定部署仍是 1.0.30；1.0.31 尚未完成实机门禁和晋升。
- 其他 AMD 世代仍是保守实验配置，不声明全型号通用。
- Windows 无法区分 USB-C 充电宝和墙插，两者统一按外接电源处理。
- 宣传片 v9：42.5 秒、1920x1080、30 fps、字幕、无配音。

## GitHub Release 草稿

标题：

```text
1.0.31-native — AMD Mobile Power 原生预览候选
```

正文：

````markdown
## 原生预览候选

AMD Mobile Power 把 RyzenAdj 封装成 Rust 原生 GUI + C++ worker。界面和硬件
访问分开，默认只读，写入前需要阅读免责声明和操作须知并勾选确认。

## 本版重点

- 状态文件改为原子持久化，异常退出不会留下半截 JSON。
- 损坏状态会保留为 `.corrupt.bak`，预设、策略和解锁状态不再静默丢失。
- 安装/卸载只停止目标目录内的 GUI/worker，避免影响稳定部署。
- 保留托盘解锁、自动电源策略、可编辑预设、只读诊断和双缓冲界面。

## 已验证的软件门禁

- 51 项 Rust 测试、7 项探针测试、C++ 策略测试和 Clippy。
- 便携包校验、隔离安装/覆盖/卸载流程和安装器进程范围回归。
- GUI、probe、worker 和 portable ZIP 逐字节可复现。
- 托管 Windows CI 全步骤通过。

## 验证边界

完整实机功耗写入、worker 恢复和真实 DPI/工作区门禁会在公开 Release 前执行。
这不是“全 AMD 通用版”。硬件写入必须显式解锁，写入后必须回读。不同 AMD
世代、BIOS 和 EC 需要独立证据。不要关闭 Windows 安全防护来运行开发版。

## 下载

- 原生预览 ZIP。
- 同名 `.sha256` 校验文件。
- 其他机型请先运行只读诊断并提交兼容性报告。
````

## B 站草稿

标题：

```text
把 RyzenAdj 做成原生功耗面板：状态安全、自动策略与只读诊断
```

简介：

```text
AMD Mobile Power 是一个开源 Windows 工具，把 RyzenAdj 的底层能力整理成
Rust 原生功耗面板：实时查看 STAPM、PPT Fast、PPT Slow、温度和供电状态，
支持可编辑三档预设、电池/外接自动策略、托盘控制和只读兼容性诊断。

1.0.31 重点修复状态文件保存和安装器进程隔离：异常退出不再留下半截配置，
卸载测试也不会误杀正在运行的稳定实例。界面默认只读，写入前需要阅读免责
声明和操作须知并勾选确认；写入完成后会回读检查。

当前完整实机证据来自 Ryzen 7 8845HS。其他 AMD 型号请先运行包内只读诊断，
不要照搬其他机型参数，也不要为了运行开发版关闭 Windows 安全防护。

项目地址：
https://github.com/syttys123/amd-mobile-power
```

标签建议：

```text
AMD, Ryzen, 轻薄本, 功耗管理, Windows, 开源, RyzenAdj
```

音乐署名（发布时保留）：

```text
Music: Deliberate Thought — Kevin MacLeod (incompetech.com) · CC BY 4.0
```
