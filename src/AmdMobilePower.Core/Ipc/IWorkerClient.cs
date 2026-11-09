using AmdMobilePower.Core.Contracts;
using AmdMobilePower.Core.Models;

namespace AmdMobilePower.Core.Ipc;

public interface IWorkerClient
{
    Task<WorkerHealth> GetHealthAsync(
        TimeSpan timeout,
        CancellationToken cancellationToken = default);

    Task<WorkerSnapshot> GetSnapshotAsync(
        TimeSpan timeout,
        CancellationToken cancellationToken = default);

    Task<PowerLimitApplicationResult> ApplyTargetAsync(
        PowerLimitTarget target,
        TimeSpan timeout,
        CancellationToken cancellationToken = default);

    Task<WorkerDiagnostics> ExportDiagnosticsAsync(
        TimeSpan timeout,
        CancellationToken cancellationToken = default);

    Task<PowerPolicyState> GetPowerPolicyAsync(
        TimeSpan timeout,
        CancellationToken cancellationToken = default);

    Task<PowerPolicyState> SetPowerPolicyAsync(
        PowerPolicySettings settings,
        TimeSpan timeout,
        CancellationToken cancellationToken = default);
}
