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
            () => client.GetHealthAsync(
                TimeSpan.FromMilliseconds(100),
                TestContext.Current.CancellationToken));
    }

    [Fact]
    public async Task SendAsync_RejectsNullRequest()
    {
        NamedPipeWorkerClient client = new(
            $"AmdMobilePower.Test.{Guid.NewGuid():N}");

        await Assert.ThrowsAsync<ArgumentNullException>(
            () => client.SendAsync(
                null!,
                TimeSpan.FromSeconds(1),
                TestContext.Current.CancellationToken));
    }
}
