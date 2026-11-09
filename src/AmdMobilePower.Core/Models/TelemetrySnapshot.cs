namespace AmdMobilePower.Core.Models;

public sealed record TelemetrySnapshot
{
    public int? TargetWatts { get; init; }
    public double? StapmValueWatts { get; init; }
    public double? FastValueWatts { get; init; }
    public double? SlowValueWatts { get; init; }
    public double? StapmLimitWatts { get; init; }
    public double? FastLimitWatts { get; init; }
    public double? SlowLimitWatts { get; init; }
    public double? TctlValueCelsius { get; init; }
    public double? TctlLimitCelsius { get; init; }
    public PowerLineState PowerLine { get; init; } = PowerLineState.Unknown;
    public DateTimeOffset? UpdatedAt { get; init; }

    public bool HasFirmwareClamp => GetClampedLimits().Count > 0;

    public IReadOnlyList<PowerLimitKind> GetClampedLimits(double toleranceWatts = 0.5)
    {
        if (TargetWatts is not { } target)
        {
            return Array.Empty<PowerLimitKind>();
        }

        List<PowerLimitKind> limits = new(3);
        AddIfClamped(limits, PowerLimitKind.Stapm, StapmLimitWatts, target, toleranceWatts);
        AddIfClamped(limits, PowerLimitKind.Fast, FastLimitWatts, target, toleranceWatts);
        AddIfClamped(limits, PowerLimitKind.Slow, SlowLimitWatts, target, toleranceWatts);
        return limits;
    }

    private static void AddIfClamped(
        ICollection<PowerLimitKind> limits,
        PowerLimitKind kind,
        double? effectiveWatts,
        int targetWatts,
        double toleranceWatts)
    {
        if (effectiveWatts is { } effective &&
            effective < targetWatts - toleranceWatts)
        {
            limits.Add(kind);
        }
    }
}

