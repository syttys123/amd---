using AmdMobilePower.Core.Ipc;

namespace AmdMobilePower.Core.Tests;

public sealed class NamedPipeWorkerClientTests
{
    [Fact]
    public async Task GetHealthAsync_TimeoutBecomesTimeoutException()
    {
        if (!OperatingSystem.IsWindows())
        {
            return;
        }

        string pipeName = $"AmdMobilePower.Test.{Guid.NewGuid():N}";
        NamedPipeWorkerClient client = new(pipeName);

        await Assert.ThrowsAsync<TimeoutException>(
            () => client.GetHealthAsync(TimeSpan.FromMilliseconds(100)));
    }
}
