# Native Launch Copy 1.0.29

状态：`DRAFT_FOR_HUMAN_REVIEW`

本文准备 `1.0.29-native` 的 GitHub 与 B 站文案，不代表已批准公开。
最终 Release、视频、封面、账号登录和上传仍需项目所有者确认。

## 事实口径

- 当前候选包：`1.0.29-native`，portable ZIP，770,245 bytes。
- SHA256：
  `c6b54d84f3f1bdba67407fe72a1f4465913e554defa1577e5c02c7373b5db640`。
- 唯一完整实机证据：MECHREVO WUJIE15 PRO / AMD Ryzen 7 8845HS。
- 默认只读；右上角锁或托盘“写入解锁…”进入免责声明、操作须知和勾选确认。
- 解锁状态持久化，再次点锁立即恢复只读。
- 自动策略支持电池/外接分别设置目标，worker 重启后自动重发策略。
- 当前本地状态：预设 `10 / 25 / 45 W`，上限 `45 W`，夜间 8 W。
- 其他 AMD 世代仍是保守实验配置，不声明全型号通用。
- Windows 无法区分 USB-C 充电宝和墙插，两者统一按外接电源处理。
- 宣传片 v9：42.5 秒、1920x1080、30 fps、字幕、无配音。

## GitHub Release 草稿

标题：

```text
1.0.29-native — AMD Mobile Power 原生预览候选
```

正文：

````markdown
## 原生预览候选

AMD Mobile Power 把 RyzenAdj 封装成 Rust 原生 GUI + C++ worker。界面和硬件
访问分开，默认只读，写入前需要阅读免责声明和操作须知并勾选确认。

## 本版重点

- 托盘菜单和右上角锁按钮共用同一套写入解锁/重新锁定流程。
- 解锁状态持久化；正常快捷方式启动也会把写权限正确传给 worker。
- 自动电源策略在 worker 重启后重新下发，不再静默失效。
- 高级模式设备面板文案精简为“可写：STAPM / Fast / Slow”。
- 保留双缓冲绘制、滚动收敛、小屏整页滚动、托盘和单实例恢复。

## 已验证

- 24 项库测试 + 23 项主程序测试、7 项探针测试、C++ 策略测试。
- Clippy `-D warnings`、包内 SHA256、逐字节可复现构建。
- 100/125/150% DPI、1366x768/200% 工作区、最大化滚动。
- 关闭到托盘、托盘恢复、单实例唤醒、显式退出。
- worker 卡死自动替换，窗口保持响应，策略恢复。
- Ryzen 7 8845HS 电池同值策略回读 `8/8/8 W`。

## 安全边界

这是单设备验证的预览候选，不是“全 AMD 通用版”。硬件写入必须显式解锁，
写入后必须回读。不同 AMD 世代、BIOS 和 EC 需要独立证据。不要关闭 Windows
安全防护来运行开发版。

## 下载

- 原生预览 ZIP。
- 同名 `.sha256` 校验文件。
- 其他机型请先运行只读诊断并提交兼容性报告。
````

## B 站草稿

标题：

```text
把 RyzenAdj 做成原生功耗面板：10/25/45W 预设、自动策略与只读诊断
```

简介：

```text
AMD Mobile Power 是一个开源 Windows 工具，把 RyzenAdj 的底层能力整理成
Rust 原生功耗面板：实时查看 STAPM、PPT Fast、PPT Slow、温度和供电状态，
支持可编辑三档预设、电池/外接自动策略、托盘控制和只读兼容性诊断。

界面默认只读。想修改功耗时，点右上角锁或托盘“写入解锁…”，阅读免责声明和
操作须知并勾选确认后才会启用写入；写入完成后会回读检查，再次点锁即可恢复
只读。当前完整实机证据来自 Ryzen 7 8845HS。

其他 AMD 型号请先运行包内只读诊断，不要照搬其他机型参数，也不要为了运行
开发版关闭 Windows 安全防护。

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

