namespace AmdMobilePower.Core.Models;

public readonly record struct PowerLimitTarget(
    int StapmWatts,
    int FastWatts,
    int SlowWatts)
{
    public int MaximumWatts => Math.Max(StapmWatts, Math.Max(FastWatts, SlowWatts));

    public static PowerLimitTarget Uniform(int watts) => new(watts, watts, watts);
}

