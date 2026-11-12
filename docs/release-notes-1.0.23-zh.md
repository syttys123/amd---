# 1.0.23-native - AMD Mobile Power

AMD Mobile Power 把 RyzenAdj 封装为原生 Rust GUI + C++ worker：界面与硬件
访问分离，默认只读，写入必须显式解锁并回读校验。本版面向 AMD 轻薄本，目标
是让实时功耗、固件上限、目标设置和兼容性诊断在一个窗口里可见。

## 本版重点

- 高级模式在矮窗口滚动后最大化/贴边时重新收敛滚动偏移，页头不再被推出窗口。
- 翻页步进与滚动条页大小一致；非整数 DPI 下页头不再出现 1px 错位。
- 600x360 紧凑简洁模式：实时功耗、可编辑目标、三档预设、四列遥测。
- 高级模式按显示器工作区打开，矮屏/高缩放时整页滚动，底栏不被任务栏遮挡。
- 目标与预设草稿在每秒刷新和模式切换之间保留；按钮只响应真实点击。
- 悬停、手形光标、键盘焦点环、原生 tooltip 与高对比度主题。

## 已验证

- Ryzen 7 8845HS / Hawk Point 只读能力、遥测与 `10/10/10 W` 当前值写回。
- 46/46 Rust 测试、7/7 探针测试、C++ 策略测试、Clippy、19 项包内 SHA256。
- 同提交逐字节可复现：GUI `e18c4213`、worker `67af1d41`、探针 `9750418f`、
  ZIP `42f6cf91`。
- worker 卡死替换：35.3 秒完成替换，21 次窗口响应采样 0 失败，策略恢复。
- 100/125/150% DPI 夹具、1366x768/200% 工作区夹具、托盘、任务栏图标、
  单实例唤醒、隔离安装/升级/卸载。

## 下载与校验

```powershell
Get-FileHash .\amd-mobile-power-v1.0.23-native-win-x64-native-preview.zip -Algorithm SHA256
```

SHA256：

```text
42f6cf9172f3db6d0a2ac81bfffbab4b38b1f5a1423ff64b7b020855fce29f79
```

解压后先运行只读探针确认环境：

```powershell
.\amd-mobile-power-probe.exe --self-test
```

## 安全边界

这是单设备验证的候选版本，不是“全 AMD 通用版”。硬件写入默认关闭，需要
`--enable-write-controls` 解锁；写入后必须回读。不同 AMD 世代、BIOS 和 EC
需要各自的实机证据。不要为了运行 WinRing0 关闭 Windows 安全防护。

## 兼容性反馈

从解压目录运行 `collect-native-diagnostics.ps1`，检查脱敏 JSON 后提交
Issue。收集器只读、不上传、不启用功耗写入。也可直接用
`amd-mobile-power-probe.exe --diagnose --out compatibility.json`。
