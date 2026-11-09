using AmdMobilePower.Core.Hardware;

namespace AmdMobilePower.Core.Tests;

public sealed class HardwareConflictDetectorTests
{
    [Fact]
    public void FindKnownHardwareOwner_DetectsLegacyWorkerMutex()
    {
        if (!OperatingSystem.IsWindows())
        {
            return;
        }

        using Mutex mutex = new(
            initiallyOwned: true,
            HardwareConflictDetector.LegacyWorkerMutexName,
            out _);

        HardwareProcessConflict? conflict =
            HardwareConflictDetector.FindKnownHardwareOwner();

        Assert.NotNull(conflict);
        Assert.Contains(
            conflict.ProcessName,
            new[] { "RyzenAdjPowerWorker", "RyzenAdjWatch" });
    }
}
