using AmdMobilePower.Core.Models;
using AmdMobilePower.Worker.Hardware;

namespace AmdMobilePower.Worker.Tests;

public sealed class RyzenAdjPowerAdapterTests
{
    [Fact]
    public async Task ProbeAsync_ReportsRyzenAdjFamily()
    {
        FakeRyzenAdjNative native = new();
        await using RyzenAdjPowerAdapter adapter = CreateAdapter(native);

        PlatformCapability capability = await adapter.ProbeAsync(
            TestContext.Current.CancellationToken);

        Assert.True(capability.IsSupported);
        Assert.Equal(10, capability.Cpu.RyzenAdjFamily);
        Assert.Equal("Hawk Point", capability.Cpu.RyzenAdjFamilyName);
        Assert.Equal("4c0009", capability.Cpu.PmTableVersion);
    }

    [Fact]
    public async Task ApplyTarget_ReadsBackRequestedLimits()
    {
        FakeRyzenAdjNative native = new();
        await using RyzenAdjPowerAdapter adapter = CreateAdapter(native);

        PowerLimitApplicationResult result = await adapter.ApplyTargetAsync(
            new PowerLimitTarget(20, 30, 40),
            TestContext.Current.CancellationToken);

        Assert.True(result.IsSuccessful);
        Assert.False(result.HasFirmwareClamp);
        Assert.Equal(new PowerLimitTarget(12, 25, 45), result.PreviousTarget);
        Assert.Equal([20.0, 30.0, 40.0], GetEffectiveLimits(result.Readbacks));
        Assert.Equal([20.0, 30.0, 40.0], native.GetLimits());
    }

    [Fact]
    public async Task ApplyTarget_FirmwareClampRemainsSuccessful()
    {
        FakeRyzenAdjNative native = new()
        {
            SlowWriteOverrideWatts = 20
        };
        await using RyzenAdjPowerAdapter adapter = CreateAdapter(native);

        PowerLimitApplicationResult result = await adapter.ApplyTargetAsync(
            new PowerLimitTarget(20, 30, 40),
            TestContext.Current.CancellationToken);

        Assert.True(result.IsSuccessful);
        Assert.True(result.HasFirmwareClamp);
        Assert.Equal([20.0, 30.0, 20.0], GetEffectiveLimits(result.Readbacks));
    }

    [Fact]
    public async Task ApplyTarget_DynamicStapmDoesNotUndoFastAndSlowLimits()
    {
        FakeRyzenAdjNative native = new()
        {
            StapmWriteOverrideWatts = 29
        };
        await using RyzenAdjPowerAdapter adapter = CreateAdapter(native);

        PowerLimitApplicationResult result = await adapter.ApplyTargetAsync(
            new PowerLimitTarget(12, 12, 12),
            TestContext.Current.CancellationToken);

        Assert.True(result.IsSuccessful);
        Assert.True(result.HasFirmwareClamp);
        Assert.False(result.RestoreAttempted);
        Assert.Equal([29.0, 12.0, 12.0], GetEffectiveLimits(result.Readbacks));
        Assert.Equal([29.0, 12.0, 12.0], native.GetLimits());
    }

    [Fact]
    public async Task ApplyTarget_StapmWriteFailureDoesNotUndoFastAndSlowLimits()
    {
        FakeRyzenAdjNative native = new()
        {
            StapmWriteFailuresRemaining = 1
        };
        await using RyzenAdjPowerAdapter adapter = CreateAdapter(native);

        PowerLimitApplicationResult result = await adapter.ApplyTargetAsync(
            new PowerLimitTarget(10, 10, 10),
            TestContext.Current.CancellationToken);

        Assert.True(result.IsSuccessful);
        Assert.False(result.RestoreAttempted);
        Assert.True(result.HasStapmWarning);
        Assert.Equal([12.0, 10.0, 10.0], GetEffectiveLimits(result.Readbacks));
        Assert.Equal([12.0, 10.0, 10.0], native.GetLimits());
    }

    [Fact]
    public async Task ApplyTarget_PartialWriteFailureRestoresPreviousLimits()
    {
        FakeRyzenAdjNative native = new()
        {
            SlowWriteFailuresRemaining = 1
        };
        await using RyzenAdjPowerAdapter adapter = CreateAdapter(native);

        PowerLimitApplicationResult result = await adapter.ApplyTargetAsync(
            new PowerLimitTarget(20, 30, 40),
            TestContext.Current.CancellationToken);

        Assert.False(result.IsSuccessful);
        Assert.True(result.RestoreAttempted);
        Assert.True(result.RestoredPreviousLimits);
        Assert.Contains("Slow write returned", result.Error);
        Assert.Equal(new PowerLimitTarget(12, 25, 45), result.PreviousTarget);
        Assert.Equal([12.0, 25.0, 45.0], native.GetLimits());
    }

    [Fact]
    public async Task ApplyTarget_ReadBackFailureRestoresPreviousLimits()
    {
        FakeRyzenAdjNative native = new()
        {
            FailedRefreshCallNumber = 2
        };
        await using RyzenAdjPowerAdapter adapter = CreateAdapter(native);

        PowerLimitApplicationResult result = await adapter.ApplyTargetAsync(
            new PowerLimitTarget(20, 30, 40),
            TestContext.Current.CancellationToken);

        Assert.False(result.IsSuccessful);
        Assert.True(result.RestoreAttempted);
        Assert.True(result.RestoredPreviousLimits);
        Assert.Contains("read-back is unavailable", result.Error);
        Assert.Equal([12.0, 25.0, 45.0], native.GetLimits());
    }

    [Fact]
    public async Task ApplyTarget_UnexpectedReadBackIncreaseRestoresPreviousLimits()
    {
        FakeRyzenAdjNative native = new()
        {
            SlowWriteOverrideWatts = 50
        };
        await using RyzenAdjPowerAdapter adapter = CreateAdapter(native);

        PowerLimitApplicationResult result = await adapter.ApplyTargetAsync(
            new PowerLimitTarget(20, 30, 40),
            TestContext.Current.CancellationToken);

        Assert.False(result.IsSuccessful);
        Assert.True(result.RestoredPreviousLimits);
        Assert.Contains("requested 40W but read back 50.00W", result.Error);
        Assert.Equal([12.0, 25.0, 45.0], native.GetLimits());
    }

    [Fact]
    public async Task ApplyTarget_NativeWriteExceptionRestoresPreviousLimits()
    {
        FakeRyzenAdjNative native = new()
        {
            SlowWriteFailuresRemaining = 0,
            ThrowOnSlowWriteCount = 1
        };
        await using RyzenAdjPowerAdapter adapter = CreateAdapter(native);

        PowerLimitApplicationResult result = await adapter.ApplyTargetAsync(
            new PowerLimitTarget(20, 30, 40),
            TestContext.Current.CancellationToken);

        Assert.False(result.IsSuccessful);
        Assert.True(result.RestoredPreviousLimits);
        Assert.Contains("native write exception", result.Error);
        Assert.Equal([12.0, 25.0, 45.0], native.GetLimits());
    }

    private static RyzenAdjPowerAdapter CreateAdapter(FakeRyzenAdjNative native)
    {
        return new RyzenAdjPowerAdapter(
            native,
            () => new CpuPlatformInfo
            {
                ProcessorName = "AMD Ryzen 7 8845HS",
                Family = 25,
                Model = 117
            },
            () => PowerLineState.Ac);
    }

    private static double?[] GetEffectiveLimits(IEnumerable<PowerLimitReadback> readbacks)
    {
        return readbacks.Select(readback => readback.EffectiveWatts).ToArray();
    }

    private sealed class FakeRyzenAdjNative : IRyzenAdjNativeApi
    {
        private double _stapmLimitWatts = 12;
        private double _fastLimitWatts = 25;
        private double _slowLimitWatts = 45;
        private int _slowOverrideApplications;
        private int _stapmOverrideApplications;

        public int SlowWriteFailuresRemaining { get; set; }
        public int StapmWriteFailuresRemaining { get; set; }
        public int ThrowOnSlowWriteCount { get; set; }
        public int FailedRefreshCallNumber { get; init; }
        public double? StapmWriteOverrideWatts { get; init; }
        public double? SlowWriteOverrideWatts { get; init; }
        public int SlowWriteOverrideUses { get; init; } = 1;
        public int RefreshCallCount { get; private set; }

        public IntPtr InitRyzenAdj() => new(1);

        public uint GetWinRingDllStatus() => 0;

        public void CleanupRyzenAdj(IntPtr ryzenAccess)
        {
        }

        public int GetCpuFamily(IntPtr ryzenAccess) => 10;

        public int GetBiosIfVersion(IntPtr ryzenAccess) => 15;

        public int InitTable(IntPtr ryzenAccess) => 0;

        public int RefreshTable(IntPtr ryzenAccess)
        {
            RefreshCallCount++;
            return RefreshCallCount == FailedRefreshCallNumber ? 9 : 0;
        }

        public uint GetTableVersion(IntPtr ryzenAccess) => 0x4c0009;

        public int SetStapmLimit(IntPtr ryzenAccess, uint value)
        {
            if (StapmWriteFailuresRemaining > 0)
            {
                StapmWriteFailuresRemaining--;
                return 12;
            }

            bool useOverride =
                StapmWriteOverrideWatts is { } &&
                _stapmOverrideApplications < 1;
            if (useOverride)
            {
                _stapmOverrideApplications++;
                _stapmLimitWatts = StapmWriteOverrideWatts!.Value;
            }
            else
            {
                _stapmLimitWatts = value / 1000.0;
            }
            return 0;
        }

        public int SetFastLimit(IntPtr ryzenAccess, uint value)
        {
            _fastLimitWatts = value / 1000.0;
            return 0;
        }

        public int SetSlowLimit(IntPtr ryzenAccess, uint value)
        {
            if (ThrowOnSlowWriteCount > 0)
            {
                ThrowOnSlowWriteCount--;
                throw new InvalidOperationException("native write exception");
            }
            if (SlowWriteFailuresRemaining > 0)
            {
                SlowWriteFailuresRemaining--;
                return 13;
            }

            bool useOverride =
                SlowWriteOverrideWatts is { } &&
                _slowOverrideApplications < SlowWriteOverrideUses;
            if (useOverride)
            {
                _slowOverrideApplications++;
                _slowLimitWatts = SlowWriteOverrideWatts!.Value;
            }
            else
            {
                _slowLimitWatts = value / 1000.0;
            }
            return 0;
        }

        public float GetStapmLimit(IntPtr ryzenAccess) => (float)_stapmLimitWatts;

        public float GetStapmValue(IntPtr ryzenAccess) => 15;

        public float GetFastLimit(IntPtr ryzenAccess) => (float)_fastLimitWatts;

        public float GetFastValue(IntPtr ryzenAccess) => 15;

        public float GetSlowLimit(IntPtr ryzenAccess) => (float)_slowLimitWatts;

        public float GetSlowValue(IntPtr ryzenAccess) => 15;

        public float GetTctlTemp(IntPtr ryzenAccess) => 95;

        public float GetTctlTempValue(IntPtr ryzenAccess) => 60;

        public double[] GetLimits()
        {
            return [_stapmLimitWatts, _fastLimitWatts, _slowLimitWatts];
        }
    }
}
