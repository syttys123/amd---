using System.Diagnostics;
using AmdMobilePower.Core.Contracts;
using AmdMobilePower.Core.Hardware;
using AmdMobilePower.Core.Ipc;
using AmdMobilePower.Core.Models;

namespace AmdMobilePower.Gui;

internal sealed class WorkerProcessController : IAsyncDisposable
{
    private static readonly TimeSpan DefaultRequestTimeout = TimeSpan.FromSeconds(3);
    private static readonly TimeSpan DefaultApplyTimeout = TimeSpan.FromSeconds(8);
    private static readonly TimeSpan DefaultStartupTimeout = TimeSpan.FromSeconds(12);

    private readonly IWorkerClient _client;
    private readonly bool _allowHardwareWrites;
    private readonly TimeSpan _requestTimeout;
    private readonly TimeSpan _applyTimeout;
    private readonly TimeSpan _startupTimeout;
    private readonly Func<HardwareProcessConflict?> _findHardwareConflict;
    private readonly Func<string> _locateWorkerExecutable;
    private readonly Func<ProcessStartInfo, IWorkerProcess> _startWorkerProcess;
    private IWorkerProcess? _workerProcess;
    private string? _hardwareFault;

    public WorkerProcessController(bool allowHardwareWrites)
        : this(
            allowHardwareWrites,
            new NamedPipeWorkerClient(),
            DefaultRequestTimeout,
            DefaultApplyTimeout,
            DefaultStartupTimeout,
            HardwareConflictDetector.FindKnownHardwareOwner,
            LocateDefaultWorkerExecutable,
            StartSystemWorkerProcess)
    {
    }

    internal WorkerProcessController(
        bool allowHardwareWrites,
        IWorkerClient client,
        TimeSpan requestTimeout,
        TimeSpan applyTimeout,
        TimeSpan startupTimeout,
        Func<HardwareProcessConflict?> findHardwareConflict,
        Func<string> locateWorkerExecutable,
        Func<ProcessStartInfo, IWorkerProcess> startWorkerProcess)
    {
        _client = client;
        _allowHardwareWrites = allowHardwareWrites;
        _requestTimeout = requestTimeout;
        _applyTimeout = applyTimeout;
        _startupTimeout = startupTimeout;
        _findHardwareConflict = findHardwareConflict;
        _locateWorkerExecutable = locateWorkerExecutable;
        _startWorkerProcess = startWorkerProcess;
    }

    public async Task<WorkerSnapshot> GetSnapshotAsync(CancellationToken cancellationToken)
    {
        ThrowIfHardwareFaulted();
        try
        {
            return await _client
                .GetSnapshotAsync(_requestTimeout, cancellationToken)
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
                        .GetSnapshotAsync(_requestTimeout, cancellationToken)
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
                    .GetSnapshotAsync(_requestTimeout, cancellationToken)
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
                .ApplyTargetAsync(target, _applyTimeout, cancellationToken)
                .ConfigureAwait(false);
        }
        catch (Exception error) when (ShouldTryStartingWorker(error, cancellationToken))
        {
            await EnsureWorkerStartedAsync(cancellationToken).ConfigureAwait(false);
            return await _client
                .ApplyTargetAsync(target, _applyTimeout, cancellationToken)
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
                .ExportDiagnosticsAsync(_requestTimeout, cancellationToken)
                .ConfigureAwait(false);
        }
        catch (Exception error) when (ShouldTryStartingWorker(error, cancellationToken))
        {
            await EnsureWorkerStartedAsync(cancellationToken).ConfigureAwait(false);
            return await _client
                .ExportDiagnosticsAsync(_requestTimeout, cancellationToken)
                .ConfigureAwait(false);
        }
    }

    public Task<PowerPolicyState> GetPowerPolicyAsync(CancellationToken cancellationToken)
    {
        ThrowIfHardwareFaulted();
        return _client.GetPowerPolicyAsync(_requestTimeout, cancellationToken);
    }

    public Task<PowerPolicyState> SetPowerPolicyAsync(
        PowerPolicySettings settings,
        CancellationToken cancellationToken)
    {
        ThrowIfHardwareFaulted();
        return _client.SetPowerPolicyAsync(settings, _requestTimeout, cancellationToken);
    }

    public async ValueTask DisposeAsync()
    {
        await StopWorkerProcessAsync().ConfigureAwait(false);
    }

    private async Task StopWorkerProcessAsync()
    {
        IWorkerProcess? process = Interlocked.Exchange(ref _workerProcess, null);
        if (process is null)
        {
            return;
        }

        try
        {
            if (!process.HasExited)
            {
                try
                {
                    await _client
                        .ShutdownAsync(TimeSpan.FromSeconds(2))
                        .ConfigureAwait(false);
                    using CancellationTokenSource gracefulTimeout =
                        new(TimeSpan.FromSeconds(3));
                    await process
                        .WaitForExitAsync(gracefulTimeout.Token)
                        .ConfigureAwait(false);
                }
                catch (Exception)
                {
                    if (!process.HasExited)
                    {
                        process.Kill(entireProcessTree: true);
                        await process.WaitForExitAsync().ConfigureAwait(false);
                    }
                }
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
            await WaitForWorkerOrFaultAsync(cancellationToken).ConfigureAwait(false);
            return;
        }

        HardwareProcessConflict? conflict = _findHardwareConflict();
        if (conflict is not null)
        {
            throw new InvalidOperationException(
                $"检测到 {FormatHardwareOwner(conflict)} 正在占用 RyzenAdj，请先退出旧版工具或停止对应计划任务。");
        }

        string executablePath = _locateWorkerExecutable();
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

        _workerProcess = _startWorkerProcess(startInfo);
        await WaitForWorkerOrFaultAsync(cancellationToken).ConfigureAwait(false);
    }

    private async Task WaitForWorkerOrFaultAsync(CancellationToken cancellationToken)
    {
        try
        {
            await WaitForWorkerAsync(cancellationToken).ConfigureAwait(false);
        }
        catch (Exception error) when (!cancellationToken.IsCancellationRequested)
        {
            throw await EnterHardwareFaultAsync(
                "worker 未能在规定时间内开始监听硬件，已停止自动重启。请重启 Windows 后再打开程序。",
                error).ConfigureAwait(false);
        }
    }

    private async Task WaitForWorkerAsync(CancellationToken cancellationToken)
    {
        DateTimeOffset deadline = DateTimeOffset.UtcNow + _startupTimeout;
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

    private static string LocateDefaultWorkerExecutable()
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

    private static IWorkerProcess StartSystemWorkerProcess(ProcessStartInfo startInfo)
    {
        Process process = Process.Start(startInfo)
            ?? throw new InvalidOperationException("无法启动 AMD Mobile Power worker。");
        return new SystemWorkerProcess(process);
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

internal interface IWorkerProcess : IDisposable
{
    bool HasExited { get; }

    void Kill(bool entireProcessTree);

    Task WaitForExitAsync(CancellationToken cancellationToken = default);
}

internal sealed class SystemWorkerProcess : IWorkerProcess
{
    private readonly Process _process;

    public SystemWorkerProcess(Process process)
    {
        _process = process;
    }

    public bool HasExited => _process.HasExited;

    public void Kill(bool entireProcessTree)
    {
        _process.Kill(entireProcessTree);
    }

    public Task WaitForExitAsync(CancellationToken cancellationToken = default)
    {
        return _process.WaitForExitAsync(cancellationToken);
    }

    public void Dispose()
    {
        _process.Dispose();
    }
}
