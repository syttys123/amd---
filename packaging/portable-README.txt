AMD Mobile Power
================

启动:
  双击 AmdMobilePower.exe

安装:
  右键 install.ps1，选择“使用 PowerShell 运行”。
  默认安装到 %LocalAppData%\Programs\AmdMobilePower，并创建登录计划任务。

当前开发版默认是只读模式，仅显示平台能力、实时功耗、功耗上限和温度。
写入控件需要显式启动参数 --enable-write-controls，并应在受控硬件测试通过后使用。

程序数据:
  %LocalAppData%\AmdMobilePower

运行时:
  worker 位于 worker\AmdMobilePower.Worker.exe。
  本包使用自包含 .NET 运行时，不要求目标电脑单独安装 .NET 8。

安全提示:
  RyzenAdj 使用底层 Windows 驱动接口。部分安全软件可能拦截或卸载驱动。
  本包尚未完成公开发布所需的全部第三方驱动授权复核，请勿直接公开发布。

更多文档:
  THIRD_PARTY_NOTICES.md
  BUILD-INFO.txt
  SHA256SUMS.txt
