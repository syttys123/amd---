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

    public WorkerProcessController(bool allowHardwareWrites)
    {
        _allowHardwareWrites = allowHardwareWrites;
    }

    public async Task<WorkerSnapshot> GetSnapshotAsync(CancellationToken cancellationToken)
    {
        try
        {
            return await _client
                .GetSnapshotAsync(RequestTimeout, cancellationToken)
                .ConfigureAwait(false);
        }
        catch (Exception error) when (ShouldTryStartingWorker(error, cancellationToken))
        {
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
            return await _client
                .GetSnapshotAsync(RequestTimeout, cancellationToken)
                .ConfigureAwait(false);
        }
    }

    public async Task<PowerLimitApplicationResult> ApplyTargetAsync(
        PowerLimitTarget target,
        CancellationToken cancellationToken)
    {
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
        return _client.GetPowerPolicyAsync(RequestTimeout, cancellationToken);
    }

    public Task<PowerPolicyState> SetPowerPolicyAsync(
        PowerPolicySettings settings,
        CancellationToken cancellationToken)
    {
        return _client.SetPowerPolicyAsync(settings, RequestTimeout, cancellationToken);
    }

    public async ValueTask DisposeAsync()
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
                $"检测到 {conflict.ProcessName} 正在占用 RyzenAdj (PID {conflict.ProcessId})，请先退出旧版工具。");
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
}
