using System.Diagnostics;
using AmdMobilePower.Core.Contracts;
using AmdMobilePower.Core.Hardware;
using AmdMobilePower.Core.Ipc;
using AmdMobilePower.Core.Models;

namespace AmdMobilePower.Gui.Tests;

public sealed class WorkerProcessControllerTests
{
    [Fact]
    public async Task GetSnapshotAsync_HardwareTimeout_StopsWorkerAndFailsClosed()
    {
        FakeWorkerClient client = new()
        {
            HealthHandler = _ => Task.FromResult(CreateHealth()),
            SnapshotHandler = _ => Task.FromException<WorkerSnapshot>(
                new TimeoutException("snapshot timed out"))
        };
        FakeWorkerProcess process = new();
        int startCount = 0;
        await using WorkerProcessController controller = CreateController(
            client,
            () =>
            {
                startCount++;
                return process;
            },
            startupTimeout: TimeSpan.FromMilliseconds(100));

        InvalidOperationException firstError = await Assert.ThrowsAsync<InvalidOperationException>(
            () => controller.GetSnapshotAsync(CancellationToken.None));

        Assert.Contains("读取硬件超时", firstError.Message);
        Assert.Contains("已停止自动重启", firstError.Message);
        Assert.Equal(1, startCount);
        Assert.Equal(2, client.SnapshotCalls);
        Assert.Equal(1, process.KillCalls);

        InvalidOperationException secondError = await Assert.ThrowsAsync<InvalidOperationException>(
            () => controller.GetSnapshotAsync(CancellationToken.None));

        Assert.Equal(firstError.Message, secondError.Message);
        Assert.Equal(1, startCount);
        Assert.Equal(2, client.SnapshotCalls);
        Assert.Equal(1, process.KillCalls);
    }

    [Fact]
    public async Task GetSnapshotAsync_WorkerStuckInDriver_StillFaultsWithinKillTimeout()
    {
        FakeWorkerClient client = new()
        {
            HealthHandler = _ => Task.FromResult(CreateHealth()),
            SnapshotHandler = _ => Task.FromException<WorkerSnapshot>(
                new TimeoutException("snapshot timed out"))
        };
        StuckWorkerProcess process = new();
        await using WorkerProcessController controller = CreateController(
            client,
            () => process,
            startupTimeout: TimeSpan.FromMilliseconds(100),
            killTimeout: TimeSpan.FromMilliseconds(200));

        Stopwatch stopwatch = Stopwatch.StartNew();
        InvalidOperationException error = await Assert.ThrowsAsync<InvalidOperationException>(
            () => controller.GetSnapshotAsync(CancellationToken.None));
        stopwatch.Stop();

        Assert.Contains("读取硬件超时", error.Message);
        Assert.Contains("已停止自动重启", error.Message);
        Assert.Equal(1, process.KillCalls);
        Assert.True(
            stopwatch.Elapsed < TimeSpan.FromSeconds(10),
            $"Fault path took {stopwatch.Elapsed}.");
    }

    [Fact]
    public async Task GetSnapshotAsync_WorkerStartupTimeout_FailsClosedWithoutRetry()
    {
        FakeWorkerClient client = new()
        {
            HealthHandler = _ => Task.FromException<WorkerHealth>(
                new TimeoutException("health timed out")),
            SnapshotHandler = _ => Task.FromException<WorkerSnapshot>(
                new IOException("worker unavailable"))
        };
        FakeWorkerProcess process = new();
        int startCount = 0;
        await using WorkerProcessController controller = CreateController(
            client,
            () =>
            {
                startCount++;
                return process;
            },
            startupTimeout: TimeSpan.FromMilliseconds(20));

        InvalidOperationException firstError = await Assert.ThrowsAsync<InvalidOperationException>(
            () => controller.GetSnapshotAsync(CancellationToken.None));

        Assert.Contains("未能在规定时间内开始监听硬件", firstError.Message);
        Assert.Equal(1, startCount);
        Assert.Equal(1, process.KillCalls);

        await Assert.ThrowsAsync<InvalidOperationException>(
            () => controller.GetSnapshotAsync(CancellationToken.None));

        Assert.Equal(1, startCount);
        Assert.Equal(1, client.SnapshotCalls);
        Assert.Equal(1, process.KillCalls);
    }

    private static WorkerProcessController CreateController(
        FakeWorkerClient client,
        Func<IWorkerProcess> startProcess,
        TimeSpan startupTimeout,
        TimeSpan? killTimeout = null)
    {
        return new WorkerProcessController(
            allowHardwareWrites: false,
            client,
            requestTimeout: TimeSpan.FromMilliseconds(100),
            applyTimeout: TimeSpan.FromMilliseconds(100),
            startupTimeout,
            findHardwareConflict: static () => null,
            locateWorkerExecutable: static () => "AmdMobilePower.Worker.exe",
            startWorkerProcess: _ => startProcess(),
            killTimeout);
    }

    private static WorkerHealth CreateHealth()
    {
        return new WorkerHealth(
            "ok",
            WorkerProtocol.CurrentVersion,
            "test",
            Environment.ProcessId,
            DateTimeOffset.UtcNow,
            1,
            HardwareInitialized: true);
    }

    private sealed class FakeWorkerProcess : IWorkerProcess
    {
        public bool HasExited { get; private set; }

        public int KillCalls { get; private set; }

        public void Kill(bool entireProcessTree)
        {
            KillCalls++;
            HasExited = true;
        }

        public Task WaitForExitAsync(CancellationToken cancellationToken = default)
        {
            HasExited = true;
            return Task.CompletedTask;
        }

        public void Dispose()
        {
        }
    }

    private sealed class StuckWorkerProcess : IWorkerProcess
    {
        public bool HasExited => false;

        public int KillCalls { get; private set; }

        public void Kill(bool entireProcessTree)
        {
            KillCalls++;
        }

        public Task WaitForExitAsync(CancellationToken cancellationToken = default)
        {
            return Task.Delay(Timeout.Infinite, cancellationToken);
        }

        public void Dispose()
        {
        }
    }

    private sealed class FakeWorkerClient : IWorkerClient
    {
        public Func<TimeSpan, Task<WorkerHealth>> HealthHandler { get; init; } =
            _ => Task.FromException<WorkerHealth>(
                new InvalidOperationException("Health handler not configured."));

        public Func<TimeSpan, Task<WorkerSnapshot>> SnapshotHandler { get; init; } =
            _ => Task.FromException<WorkerSnapshot>(
                new InvalidOperationException("Snapshot handler not configured."));

        public int SnapshotCalls { get; private set; }

        public Task<WorkerHealth> GetHealthAsync(
            TimeSpan timeout,
            CancellationToken cancellationToken = default)
        {
            return HealthHandler(timeout);
        }

        public Task<WorkerSnapshot> GetSnapshotAsync(
            TimeSpan timeout,
            CancellationToken cancellationToken = default)
        {
            SnapshotCalls++;
            return SnapshotHandler(timeout);
        }

        public Task<PowerLimitApplicationResult> ApplyTargetAsync(
            PowerLimitTarget target,
            TimeSpan timeout,
            CancellationToken cancellationToken = default)
        {
            throw new NotSupportedException();
        }

        public Task<WorkerDiagnostics> ExportDiagnosticsAsync(
            TimeSpan timeout,
            CancellationToken cancellationToken = default)
        {
            throw new NotSupportedException();
        }

        public Task<PowerPolicyState> GetPowerPolicyAsync(
            TimeSpan timeout,
            CancellationToken cancellationToken = default)
        {
            throw new NotSupportedException();
        }

        public Task<PowerPolicyState> SetPowerPolicyAsync(
            PowerPolicySettings settings,
            TimeSpan timeout,
            CancellationToken cancellationToken = default)
        {
            throw new NotSupportedException();
        }

        public Task ShutdownAsync(
            TimeSpan timeout,
            CancellationToken cancellationToken = default)
        {
            throw new NotSupportedException();
        }
    }
}
