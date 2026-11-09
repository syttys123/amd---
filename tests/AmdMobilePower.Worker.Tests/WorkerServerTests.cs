using AmdMobilePower.Core.Contracts;
using AmdMobilePower.Core.Ipc;

namespace AmdMobilePower.Worker.Tests;

public sealed class WorkerServerTests
{
    [Fact]
    public async Task GetHealth_ReturnsProtocolVersionAndProcessId()
    {
        string pipeName = CreatePipeName();
        DateTimeOffset startedAt = DateTimeOffset.UtcNow.AddSeconds(-5);
        using CancellationTokenSource shutdown = new(TimeSpan.FromSeconds(10));
        using WorkerServer server = new(pipeName, startedAt);
        Task serverTask = server.RunAsync(shutdown.Token);

        NamedPipeWorkerClient client = new(pipeName);
        WorkerHealth health = await client.GetHealthAsync(TimeSpan.FromSeconds(5));

        Assert.Equal("ok", health.Status);
        Assert.Equal(WorkerProtocol.CurrentVersion, health.ProtocolVersion);
        Assert.Equal(Environment.ProcessId, health.ProcessId);
        Assert.Equal(startedAt, health.StartedAt);
        Assert.True(health.UptimeSeconds >= 5);
        Assert.False(health.HardwareInitialized);

        shutdown.Cancel();
        await serverTask;
    }

    [Fact]
    public async Task UnsupportedCommand_ReturnsStructuredError()
    {
        string pipeName = CreatePipeName();
        using CancellationTokenSource shutdown = new(TimeSpan.FromSeconds(10));
        using WorkerServer server = new(pipeName);
        Task serverTask = server.RunAsync(shutdown.Token);

        NamedPipeWorkerClient client = new(pipeName);
        WorkerResponse response = await client.SendAsync(
            new WorkerRequest
            {
                RequestId = "request-1",
                Command = WorkerCommand.GetSnapshot
            },
            TimeSpan.FromSeconds(5));

        Assert.False(response.Success);
        Assert.Equal("request-1", response.RequestId);
        Assert.Equal(WorkerErrorCodes.UnsupportedCommand, response.Error?.Code);

        shutdown.Cancel();
        await serverTask;
    }

    private static string CreatePipeName()
    {
        return "AmdMobilePower.Tests." + Guid.NewGuid().ToString("N");
    }
}

