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
