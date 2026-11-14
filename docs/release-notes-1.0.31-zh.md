## AMD Mobile Power 1.0.31 原生预览候选

AMD Mobile Power 把 RyzenAdj 封装成 Rust 原生 GUI + C++ worker。界面和硬件
访问分开，默认只读，写入前需要阅读免责声明和操作须知并勾选确认。

### 本版重点

- `rust-ui-state.json` 改为原子持久化：先写同目录临时文件并刷盘，再原子
  替换目标文件，异常退出不会留下半截 JSON。
- 状态文件解析失败时保留 `rust-ui-state.json.corrupt.bak`，方便定位问题；
  下一次成功保存会用完整状态替换损坏文件。
- 安装和卸载脚本只停止目标安装目录内的 GUI/worker，不再误杀正在运行的稳定
  部署或其他目录中的实例。
- 保留 UTF-8 BOM 兼容、应用内锁/托盘“写入解锁…”、`10 / 25 / 45 W`
  默认预设、电池/外接自动策略、双缓冲绘制、小屏整页滚动和托盘单实例恢复。

### 已验证的软件门禁

- 28 项库测试 + 23 项主程序测试、7 项探针测试、C++ 策略测试。
- Clippy `-D warnings`，便携包 19 条 SHA256，隔离安装/覆盖/卸载流程通过。
- 安装器进程范围回归通过，稳定 GUI/worker 进程集合保持不变。
- GUI、probe、worker 和 portable ZIP 逐字节可复现。
- 托管 Windows CI 全步骤通过。

### 验证边界

这是原生预览候选，不是“全 AMD 通用版”。完整实机功耗写入、worker 卡死替换
和真实 DPI/工作区门禁会在公开 Release 前单独执行并记录证据。其他 AMD
世代仍需要独立只读与受控写入证据。不要关闭 Windows 安全防护来运行开发版。

### 下载

- `amd-mobile-power-v1.0.31-win-x64-native-preview.zip`
- 同名 `.sha256` 校验文件
- 其他机型请先运行包内只读诊断并提交兼容性报告
