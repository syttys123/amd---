using AmdMobilePower.Core.Contracts;
using AmdMobilePower.Core.Hardware;
using AmdMobilePower.Core.Ipc;
using AmdMobilePower.Core.Models;
using AmdMobilePower.Core.Profiles;

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
                Command = WorkerCommand.ApplyTarget
            },
            TimeSpan.FromSeconds(5));

        Assert.False(response.Success);
        Assert.Equal("request-1", response.RequestId);
        Assert.Equal(WorkerErrorCodes.UnsupportedCommand, response.Error?.Code);

        shutdown.Cancel();
        await serverTask;
    }

    [Fact]
    public async Task GetCapabilities_ReturnsPlatformAndMatchedProfile()
    {
        string pipeName = CreatePipeName();
        FakeRyzenPowerAdapter adapter = new();
        PlatformProfile profile = ProfileRepository.Parse(
            """
            {
              "id": "hawk-point-8845hs",
              "displayName": "8845HS",
              "processorNamePatterns": ["*8845HS*"],
              "pmTablePatterns": ["4c0009"],
              "minimumWatts": 5,
              "maximumWatts": 60,
              "defaultWatts": 25
            }
            """);
        using CancellationTokenSource shutdown = new(TimeSpan.FromSeconds(10));
        using WorkerServer server = new(
            pipeName,
            startedAt: null,
            adapter: adapter,
            profiles: [profile]);
        Task serverTask = server.RunAsync(shutdown.Token);

        NamedPipeWorkerClient client = new(pipeName);
        WorkerCapabilitySnapshot capabilities = await client.GetCapabilitiesAsync(
            TimeSpan.FromSeconds(5));
        WorkerHealth health = await client.GetHealthAsync(TimeSpan.FromSeconds(5));

        Assert.True(capabilities.Platform.IsSupported);
        Assert.Equal("AMD Ryzen 7 8845HS", capabilities.Platform.Cpu.ProcessorName);
        Assert.Equal("hawk-point-8845hs", capabilities.MatchedProfile?.Id);
        Assert.True(health.HardwareInitialized);

        shutdown.Cancel();
        await serverTask;
    }

    [Fact]
    public async Task GetCapabilities_WithoutAdapter_ReturnsWorkerUnavailable()
    {
        string pipeName = CreatePipeName();
        using CancellationTokenSource shutdown = new(TimeSpan.FromSeconds(10));
        using WorkerServer server = new(pipeName);
        Task serverTask = server.RunAsync(shutdown.Token);

        NamedPipeWorkerClient client = new(pipeName);
        WorkerResponse response = await client.SendAsync(
            new WorkerRequest
            {
                RequestId = "request-2",
                Command = WorkerCommand.GetCapabilities
            },
            TimeSpan.FromSeconds(5));

        Assert.False(response.Success);
        Assert.Equal(WorkerErrorCodes.WorkerUnavailable, response.Error?.Code);

        shutdown.Cancel();
        await serverTask;
    }

    [Fact]
    public async Task GetSnapshot_ReturnsReadOnlyTelemetryAndMatchedProfile()
    {
        string pipeName = CreatePipeName();
        FakeRyzenPowerAdapter adapter = new();
        PlatformProfile profile = ProfileRepository.Parse(
            """
            {
              "id": "hawk-point-8845hs",
              "displayName": "8845HS",
              "processorNamePatterns": ["*8845HS*"],
              "pmTablePatterns": ["4c0009"],
              "minimumWatts": 5,
              "maximumWatts": 60,
              "defaultWatts": 25
            }
            """);
        using CancellationTokenSource shutdown = new(TimeSpan.FromSeconds(10));
        using WorkerServer server = new(
            pipeName,
            startedAt: null,
            adapter: adapter,
            profiles: [profile]);
        Task serverTask = server.RunAsync(shutdown.Token);

        NamedPipeWorkerClient client = new(pipeName);
        WorkerSnapshot snapshot = await client.GetSnapshotAsync(TimeSpan.FromSeconds(5));

        Assert.True(snapshot.Platform.IsSupported);
        Assert.Equal("hawk-point-8845hs", snapshot.MatchedProfile?.Id);
        Assert.Equal(18.5, snapshot.Telemetry.StapmLimitWatts);
        Assert.Equal(PowerLineState.Battery, snapshot.Telemetry.PowerLine);

        shutdown.Cancel();
        await serverTask;
    }

    [Fact]
    public async Task GetSnapshot_ForUnsupportedPlatform_DoesNotRefreshTelemetry()
    {
        string pipeName = CreatePipeName();
        FakeRyzenPowerAdapter adapter = new() { IsSupported = false };
        using CancellationTokenSource shutdown = new(TimeSpan.FromSeconds(10));
        using WorkerServer server = new(
            pipeName,
            startedAt: null,
            adapter: adapter);
        Task serverTask = server.RunAsync(shutdown.Token);

        NamedPipeWorkerClient client = new(pipeName);
        WorkerSnapshot snapshot = await client.GetSnapshotAsync(TimeSpan.FromSeconds(5));

        Assert.False(snapshot.Platform.IsSupported);
        Assert.Null(snapshot.Telemetry.StapmLimitWatts);
        Assert.Equal(0, adapter.RefreshCount);

        shutdown.Cancel();
        await serverTask;
    }

    private static string CreatePipeName()
    {
        return "AmdMobilePower.Tests." + Guid.NewGuid().ToString("N");
    }

    private sealed class FakeRyzenPowerAdapter : IRyzenPowerAdapter
    {
        public bool IsSupported { get; init; } = true;
        public int RefreshCount { get; private set; }

        public ValueTask DisposeAsync()
        {
            return ValueTask.CompletedTask;
        }

        public Task<PlatformCapability> ProbeAsync(CancellationToken cancellationToken = default)
        {
            return Task.FromResult(
                new PlatformCapability(
                    new CpuPlatformInfo
                    {
                        ProcessorName = "AMD Ryzen 7 8845HS",
                        Family = 25,
                        Model = 117,
                        PmTableVersion = "4c0009"
                    },
                    new PowerLimitCapability(
                        SupportsStapm: true,
                        SupportsFast: true,
                        SupportsSlow: true),
                    IsSupported,
                    IsSupported ? null : "Unsupported test platform"));
        }

        public Task<TelemetrySnapshot> RefreshTelemetryAsync(
            CancellationToken cancellationToken = default)
        {
            RefreshCount++;
            return Task.FromResult(
                new TelemetrySnapshot
                {
                    StapmLimitWatts = 18.5,
                    PowerLine = PowerLineState.Battery,
                    UpdatedAt = DateTimeOffset.UtcNow
                });
        }

        public Task<PowerLimitApplicationResult> ApplyTargetAsync(
            PowerLimitTarget target,
            CancellationToken cancellationToken = default)
        {
            return Task.FromResult(new PowerLimitApplicationResult(
                target,
                Array.Empty<PowerLimitReadback>()));
        }
    }
}

