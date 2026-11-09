using System.Diagnostics;
using AmdMobilePower.Core.Contracts;
using AmdMobilePower.Core.Hardware;
using AmdMobilePower.Core.Ipc;
using AmdMobilePower.Core.Models;

namespace AmdMobilePower.Gui;

internal sealed class WorkerProcessController : IAsyncDisposable
{
    private static readonly TimeSpan RequestTimeout = TimeSpan.FromSeconds(3);
    private static readonly TimeSpan ApplyTimeout = TimeSpan.FromSeconds(8);
    private static readonly TimeSpan StartupTimeout = TimeSpan.FromSeconds(12);

    private readonly NamedPipeWorkerClient _client = new();
    private readonly bool _allowHardwareWrites;
    private Process? _workerProcess;
    private string? _hardwareFault;

    public WorkerProcessController(bool allowHardwareWrites)
    {
        _allowHardwareWrites = allowHardwareWrites;
    }

    public async Task<WorkerSnapshot> GetSnapshotAsync(CancellationToken cancellationToken)
    {
        ThrowIfHardwareFaulted();
        try
        {
            return await _client
                .GetSnapshotAsync(RequestTimeout, cancellationToken)
                .ConfigureAwait(false);
        }
        catch (Exception error) when (ShouldTryStartingWorker(error, cancellationToken))
        {
            if (_workerProcess is { HasExited: false } && error is TimeoutException)
            {
                throw await EnterHardwareFaultAsync(
                    "worker 读取硬件超时，已停止自动重启。请重启 Windows 后再打开程序。",
                    error).ConfigureAwait(false);
            }

            if (_workerProcess is { HasExited: false })
            {
                await Task.Delay(120, cancellationToken).ConfigureAwait(false);
                try
                {
                    return await _client
                        .GetSnapshotAsync(RequestTimeout, cancellationToken)
                        .ConfigureAwait(false);
                }
                catch (Exception retryError) when (ShouldTryStartingWorker(retryError, cancellationToken))
                {
                }
            }

            await EnsureWorkerStartedAsync(cancellationToken).ConfigureAwait(false);
            try
            {
                return await _client
                    .GetSnapshotAsync(RequestTimeout, cancellationToken)
                    .ConfigureAwait(false);
            }
            catch (TimeoutException timeoutError)
            {
                throw await EnterHardwareFaultAsync(
                    "worker 读取硬件超时，已停止自动重启。请重启 Windows 后再打开程序。",
                    timeoutError).ConfigureAwait(false);
            }
            catch (IOException pipeError) when (
                _workerProcess is { HasExited: true } && !cancellationToken.IsCancellationRequested)
            {
                throw await EnterHardwareFaultAsync(
                    "worker 在读取硬件时异常退出，已停止自动重启。请重启 Windows 后再打开程序。",
                    pipeError).ConfigureAwait(false);
            }
        }
    }

    public async Task<PowerLimitApplicationResult> ApplyTargetAsync(
        PowerLimitTarget target,
        CancellationToken cancellationToken)
    {
        ThrowIfHardwareFaulted();
        try
        {
            return await _client
                .ApplyTargetAsync(target, ApplyTimeout, cancellationToken)
                .ConfigureAwait(false);
        }
        catch (Exception error) when (ShouldTryStartingWorker(error, cancellationToken))
        {
            await EnsureWorkerStartedAsync(cancellationToken).ConfigureAwait(false);
            return await _client
                .ApplyTargetAsync(target, ApplyTimeout, cancellationToken)
                .ConfigureAwait(false);
        }
    }

    public async Task<WorkerDiagnostics> ExportDiagnosticsAsync(
        CancellationToken cancellationToken)
    {
        ThrowIfHardwareFaulted();
        try
        {
            return await _client
                .ExportDiagnosticsAsync(RequestTimeout, cancellationToken)
                .ConfigureAwait(false);
        }
        catch (Exception error) when (ShouldTryStartingWorker(error, cancellationToken))
        {
            await EnsureWorkerStartedAsync(cancellationToken).ConfigureAwait(false);
            return await _client
                .ExportDiagnosticsAsync(RequestTimeout, cancellationToken)
                .ConfigureAwait(false);
        }
    }

    public Task<PowerPolicyState> GetPowerPolicyAsync(CancellationToken cancellationToken)
    {
        ThrowIfHardwareFaulted();
        return _client.GetPowerPolicyAsync(RequestTimeout, cancellationToken);
    }

    public Task<PowerPolicyState> SetPowerPolicyAsync(
        PowerPolicySettings settings,
        CancellationToken cancellationToken)
    {
        ThrowIfHardwareFaulted();
        return _client.SetPowerPolicyAsync(settings, RequestTimeout, cancellationToken);
    }

    public async ValueTask DisposeAsync()
    {
        await StopWorkerProcessAsync().ConfigureAwait(false);
    }

    private async Task StopWorkerProcessAsync()
    {
        Process? process = Interlocked.Exchange(ref _workerProcess, null);
        if (process is null)
        {
            return;
        }

        try
        {
            if (!process.HasExited)
            {
                process.Kill(entireProcessTree: true);
                await process.WaitForExitAsync().ConfigureAwait(false);
            }
        }
        finally
        {
            process.Dispose();
        }
    }

    private async Task<InvalidOperationException> EnterHardwareFaultAsync(
        string message,
        Exception innerException)
    {
        _hardwareFault = message;
        await StopWorkerProcessAsync().ConfigureAwait(false);
        return new InvalidOperationException(message, innerException);
    }

    private void ThrowIfHardwareFaulted()
    {
        if (_hardwareFault is { } fault)
        {
            throw new InvalidOperationException(fault);
        }
    }

    private async Task EnsureWorkerStartedAsync(CancellationToken cancellationToken)
    {
        if (_workerProcess is { HasExited: false })
        {
            await WaitForWorkerAsync(cancellationToken).ConfigureAwait(false);
            return;
        }

        HardwareProcessConflict? conflict = HardwareConflictDetector.FindKnownHardwareOwner();
        if (conflict is not null)
        {
            throw new InvalidOperationException(
                $"检测到 {FormatHardwareOwner(conflict)} 正在占用 RyzenAdj，请先退出旧版工具或停止对应计划任务。");
        }

        string executablePath = LocateWorkerExecutable();
        ProcessStartInfo startInfo = new()
        {
            FileName = executablePath,
            WorkingDirectory = Path.GetDirectoryName(executablePath)!,
            UseShellExecute = false,
            CreateNoWindow = true,
            WindowStyle = ProcessWindowStyle.Hidden,
            Arguments = _allowHardwareWrites
                ? "--enable-hardware --enable-write-controls"
                : "--enable-hardware"
        };

        _workerProcess = Process.Start(startInfo)
            ?? throw new InvalidOperationException("无法启动 AMD Mobile Power worker。");
        await WaitForWorkerAsync(cancellationToken).ConfigureAwait(false);
    }

    private async Task WaitForWorkerAsync(CancellationToken cancellationToken)
    {
        DateTimeOffset deadline = DateTimeOffset.UtcNow + StartupTimeout;
        Exception? lastError = null;
        while (DateTimeOffset.UtcNow < deadline)
        {
            cancellationToken.ThrowIfCancellationRequested();
            try
            {
                await _client
                    .GetHealthAsync(TimeSpan.FromMilliseconds(700), cancellationToken)
                    .ConfigureAwait(false);
                return;
            }
            catch (Exception error) when (!cancellationToken.IsCancellationRequested)
            {
                lastError = error;
                await Task.Delay(180, cancellationToken).ConfigureAwait(false);
            }
        }

        throw new InvalidOperationException(
            "worker 未能在规定时间内启动。",
            lastError);
    }

    private static bool ShouldTryStartingWorker(
        Exception error,
        CancellationToken cancellationToken)
    {
        return !cancellationToken.IsCancellationRequested &&
            error is IOException or TimeoutException or OperationCanceledException;
    }

    private static string LocateWorkerExecutable()
    {
        string baseDirectory = AppContext.BaseDirectory;
        string devRelease = Path.GetFullPath(
            Path.Combine(
                baseDirectory,
                "..",
                "..",
                "..",
                "..",
                "AmdMobilePower.Worker",
                "bin",
                "Release",
                "net8.0-windows",
                "AmdMobilePower.Worker.exe"));
        string devDebug = Path.GetFullPath(
            Path.Combine(
                baseDirectory,
                "..",
                "..",
                "..",
                "..",
                "AmdMobilePower.Worker",
                "bin",
                "Debug",
                "net8.0-windows",
                "AmdMobilePower.Worker.exe"));
        string[] candidates =
        [
            Path.Combine(baseDirectory, "AmdMobilePower.Worker.exe"),
            Path.Combine(baseDirectory, "worker", "AmdMobilePower.Worker.exe"),
            devRelease,
            devDebug
        ];

        string? executable = candidates.FirstOrDefault(File.Exists);
        return executable
            ?? throw new FileNotFoundException(
                "未找到 AmdMobilePower.Worker.exe。请先构建解决方案或安装完整的发布包。",
                candidates[0]);
    }

    private static string FormatHardwareOwner(HardwareProcessConflict conflict)
    {
        if (conflict.ScheduledTaskPath is { } taskPath)
        {
            return $"{conflict.ProcessName} 计划任务 {taskPath}";
        }

        return conflict.ProcessId is { } processId
            ? $"{conflict.ProcessName} (PID {processId})"
            : conflict.ProcessName;
    }
}
