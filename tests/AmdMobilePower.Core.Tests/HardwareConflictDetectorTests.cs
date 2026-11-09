using AmdMobilePower.Core.Hardware;

namespace AmdMobilePower.Core.Tests;

public sealed class HardwareConflictDetectorTests
{
    [Fact]
    public void Evaluate_DetectsLegacyWorkerMutex()
    {
        HardwareProcessConflict? conflict = HardwareConflictDetector.Evaluate(
            legacyWorkerMutexPresent: true,
            processes: [],
            runningScheduledTaskPaths: []);

        Assert.NotNull(conflict);
        Assert.Equal("RyzenAdjPowerWorker", conflict.ProcessName);
        Assert.Null(conflict.ProcessId);
        Assert.Null(conflict.ScheduledTaskPath);
    }

    [Theory]
    [InlineData("RyzenPower")]
    [InlineData("ryzenadj")]
    [InlineData("AMD Ryzen Master")]
    public void Evaluate_DetectsKnownProcessOwner(string processName)
    {
        HardwareProcessConflict? conflict = HardwareConflictDetector.Evaluate(
            legacyWorkerMutexPresent: false,
            processes: [new HardwareProcessCandidate(processName, 4242)],
            runningScheduledTaskPaths: []);

        Assert.NotNull(conflict);
        Assert.Equal(processName, conflict.ProcessName);
        Assert.Equal(4242, conflict.ProcessId);
        Assert.Null(conflict.ScheduledTaskPath);
    }

    [Theory]
    [InlineData(@"\AMD\RyzenAdjWatch", "RyzenAdjWatch")]
    [InlineData(@"\AMD\RyzenAdj", "RyzenAdj")]
    [InlineData(@"\AMD\RyzenAdjApply", "RyzenAdjApply")]
    [InlineData(@"\AMD\RyzenAdjToggle", "RyzenAdjToggle")]
    public void Evaluate_DetectsRunningScheduledTaskOwner(
        string taskPath,
        string taskName)
    {
        HardwareProcessConflict? conflict = HardwareConflictDetector.Evaluate(
            legacyWorkerMutexPresent: false,
            processes: [],
            runningScheduledTaskPaths: [taskPath]);

        Assert.NotNull(conflict);
        Assert.Equal(taskName, conflict.ProcessName);
        Assert.Null(conflict.ProcessId);
        Assert.Equal(taskPath, conflict.ScheduledTaskPath);
    }

    [Fact]
    public void Evaluate_PrefersMutexScheduledTaskOwner()
    {
        HardwareProcessConflict? conflict = HardwareConflictDetector.Evaluate(
            legacyWorkerMutexPresent: true,
            processes: [],
            runningScheduledTaskPaths: [@"\AMD\RyzenAdjWatch"]);

        Assert.NotNull(conflict);
        Assert.Equal("RyzenAdjWatch", conflict.ProcessName);
        Assert.Equal(@"\AMD\RyzenAdjWatch", conflict.ScheduledTaskPath);
    }

    [Fact]
    public void Evaluate_ReturnsNullWithoutKnownOwner()
    {
        HardwareProcessConflict? conflict = HardwareConflictDetector.Evaluate(
            legacyWorkerMutexPresent: false,
            processes: [new HardwareProcessCandidate("OtherPowerTool", 1)],
            runningScheduledTaskPaths: [@"\Other\PowerTask"]);

        Assert.Null(conflict);
    }

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
