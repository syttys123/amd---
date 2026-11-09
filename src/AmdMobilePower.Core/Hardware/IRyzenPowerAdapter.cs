using AmdMobilePower.Core.Models;

namespace AmdMobilePower.Core.Hardware;

public interface IRyzenPowerAdapter : IAsyncDisposable
{
    Task<PlatformCapability> ProbeAsync(CancellationToken cancellationToken = default);

    Task<TelemetrySnapshot> RefreshTelemetryAsync(CancellationToken cancellationToken = default);

    Task<PowerLimitApplicationResult> ApplyTargetAsync(
        PowerLimitTarget target,
        CancellationToken cancellationToken = default);
}

