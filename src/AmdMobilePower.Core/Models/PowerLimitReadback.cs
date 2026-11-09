namespace AmdMobilePower.Core.Models;

public sealed record PowerLimitReadback(
    PowerLimitKind Kind,
    int RequestedWatts,
    double? EffectiveWatts,
    int DriverResultCode);

public sealed record PowerLimitApplicationResult(
    PowerLimitTarget Target,
    IReadOnlyList<PowerLimitReadback> Readbacks,
    PowerLimitTarget? PreviousTarget = null,
    bool RestoreAttempted = false,
    bool RestoredPreviousLimits = false,
    IReadOnlyList<PowerLimitReadback>? RestoreReadbacks = null,
    string? Error = null)
{
    public bool IsSuccessful => Error is null;

    public bool HasFirmwareClamp =>
        Readbacks.Any(readback =>
            readback.EffectiveWatts is { } effective &&
            Math.Abs(effective - readback.RequestedWatts) > 0.5);

    public bool HasStapmWarning =>
        Readbacks.Any(readback =>
            readback.Kind == PowerLimitKind.Stapm &&
            (readback.DriverResultCode != 0 ||
             readback.EffectiveWatts is not { } effective ||
             Math.Abs(effective - readback.RequestedWatts) > 0.5));
}

