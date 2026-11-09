namespace AmdMobilePower.Core.Models;

public sealed record PowerLimitCapability(
    bool SupportsStapm,
    bool SupportsFast,
    bool SupportsSlow)
{
    public bool SupportsAny => SupportsStapm || SupportsFast || SupportsSlow;

    public IReadOnlyList<PowerLimitKind> GetSupportedLimits()
    {
        List<PowerLimitKind> limits = new(3);
        if (SupportsStapm)
        {
            limits.Add(PowerLimitKind.Stapm);
        }
        if (SupportsFast)
        {
            limits.Add(PowerLimitKind.Fast);
        }
        if (SupportsSlow)
        {
            limits.Add(PowerLimitKind.Slow);
        }
        return limits;
    }
}

