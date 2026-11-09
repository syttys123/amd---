# AMD Mobile Power 项目介绍

AMD Mobile Power 是一个面向 AMD 轻薄本的 Windows 功耗管理工具。目标是把
RyzenAdj 的底层能力整理成更安全、更清晰、可维护的原生桌面应用，而不是让用户
直接操作命令行或时刻面对隐藏窗口。

> 当前状态：早期开发版。默认只读；硬件写入需要双重开发开关。开发机已完成
> 10 W/12 W 受控写入、回读和恢复验证，以及打包版 12 W 无变化写入门禁。项目目前
> 只在一台 Ryzen 7 8845HS 笔记本上取得实测证据，不声明支持“所有 AMD 笔记本”。

## 为什么做这个项目

很多 AMD 轻薄本允许处理器在插电时跑到较高功耗，但宿舍断电、移动办公、使用充电宝
等场景会频繁切换供电状态。用户真正需要的往往不是一组永远固定的数值，而是：

- 随时看见当前实际功耗、固件上限、温度和供电状态。
- 快速切换几个可编辑功耗预设。
- 只在明确需要时改变 STAPM、PPT Fast、PPT Slow。
- 固件没有接受目标值时，能够看到真实回读结果，而不是只看到“调用成功”。

## 当前能力

- 原生 WinForms 界面，带任务栏、托盘和单实例唤醒。
- 隐藏 worker 进程，通过当前用户专属命名管道与 GUI 通信。
- 每秒读取 STAPM、PPT Fast、PPT Slow、温度和插电/电池状态。
- 自动识别 CPU、SMU BIOS 接口、PM Table 和匹配配置。
- 默认 12 W、25 W、45 W 三个快捷预设，并支持编辑。
- 可选电池/插电自动策略；只读模式下保持锁定。
- 写入前检查能力和范围，写入后强制回读，并报告固件限制。
- 写入或回读失败时尝试恢复上一组三项限制。
- 导出 CPU 家族、SMU、PM Table、profile、运行文件哈希等兼容性诊断，不包含账号或
  Provider 密钥。
- 便携包提供无需打开 GUI 的只读诊断收集器，使用字段白名单和路径脱敏生成兼容性
  JSON，不启用功耗写入，也不会联网上传。
- 提供自包含或轻量 .NET 依赖两种 Windows x64 便携包，以及当前用户安装、升级和
  卸载脚本。
- 配置 GitHub Actions 构建、测试、RyzenAdj 编译和 ZIP/SHA256 工件流程；本地发布
  门禁已验证，远程 CI 仍受仓库账户计费状态影响。

## 安全设计

- GUI 默认只读，硬件写入需要 `--enable-write-controls`。
- worker 还必须显式获得 `--enable-write-controls` 才会接受写入命令。
- 检测 `RyzenPower`、`ryzenadj`、AMD Ryzen Master、旧 worker 互斥量和旧计划任务。
- 只允许一个 RyzenAdj 硬件所有者，避免多个进程同时访问底层驱动。
- 硬件读取超时后停止 worker 并锁定本会话，避免崩溃/重启循环。
- WinRing0、InpOut32 和 RyzenAdj 许可文本随包分发。

## 适用边界

- 只处理 STAPM、PPT Fast、PPT Slow，不写温度墙、电流、电压或 CPU 时钟。
- BIOS、EC 或厂商性能模式可能覆盖 RyzenAdj 写入。
- Windows 安全软件可能拦截 WinRing0。
- 不同 AMD 世代、不同机型需要独立证据，不能只凭 CPU 名称推断支持。

## 后续方向

- 完成真实电池供电截图和受控 AC/电池策略验证。
- 增加更多 AMD 移动平台配置，并在第二台实机上验证。
- 完善兼容性反馈、诊断和支持流程。
- 在稳定发布门槛全部通过后，提供正式 GitHub Release、介绍视频和 B 站发布稿。

## 相关文档

- `DEV_STATUS.md`：当前事实、证据和下一步。
- `SUPPORTED_HARDWARE.md`：兼容范围和证据等级。
- `SECURITY.md`：硬件、驱动和进程安全边界。
- `MEDIA_PLAN.md`：宣传视频和发布素材计划。
- `LAUNCH_COPY_ZH.md`：待人工审阅的 GitHub Release 与 B 站发布文案。
- `RELEASE_CHECKLIST.md`：公开发布检查表。
