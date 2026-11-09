AMD Mobile Power
================

启动:
  双击 AmdMobilePower.exe

安装:
  右键 install.ps1，选择“使用 PowerShell 运行”。
  默认安装到 %LocalAppData%\Programs\AmdMobilePower，并创建登录计划任务。

当前开发版默认是只读模式，仅显示平台能力、实时功耗、功耗上限和温度。
写入控件需要显式启动参数 --enable-write-controls，并应在受控硬件测试通过后使用。

从旧版 RyzenPower 迁移:
  先运行 migrate-legacy-owner.ps1 查看旧任务状态。
  确认后再以管理员 PowerShell 运行 migrate-legacy-owner.ps1 -Apply。
  该脚本只禁用并停止旧任务，不删除 C:\RyzenAdj，也不会自动重启。
  完成后必须重启 Windows，再启动 AMD Mobile Power。

程序数据:
  %LocalAppData%\AmdMobilePower

运行时:
  worker 位于 worker\AmdMobilePower.Worker.exe。
  自包含包不要求目标电脑单独安装 .NET 8。
  轻量版需要 Microsoft .NET 8 Desktop Runtime x64，详见文末附加说明。

兼容性诊断:
  在解压目录打开 PowerShell，运行:
    powershell -ExecutionPolicy Bypass -File .\collect-diagnostics.ps1
  collector 会隐藏启动打包的 worker，只启用硬件读取，不启用功耗写入，
  在桌面生成 amd-mobile-power-diagnostics-*.json 后通过协议关闭 worker。
  输出不包含账号名、PID、序列号、最近日志或本机绝对路径，也不会联网上传。
  人工检查 JSON 后，可附到 GitHub 的兼容性问题中。

安全提示:
  RyzenAdj 使用底层 Windows 驱动接口。部分安全软件可能拦截或卸载驱动。
  RyzenAdj（LGPL-3.0/GPL-3.0）、InpOut32 和 WinRing0 的许可文本
  已包含在 licenses 目录。
  RyzenAdj 以独立 worker\libryzenadj.dll 动态加载；高级用户可按
  THIRD_PARTY_NOTICES.md 获取对应源码并使用兼容构建替换该 DLL。
  本包仍是开发版本，公开发布前必须完成 RELEASE-CHECKLIST 中的验证。

更多文档:
  MIGRATING-FROM-LEGACY.md
  RELEASE-CHECKLIST.md
  THIRD_PARTY_NOTICES.md
  BUILD-INFO.txt
  SHA256SUMS.txt
