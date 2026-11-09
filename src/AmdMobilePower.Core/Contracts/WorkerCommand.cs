namespace AmdMobilePower.Core.Contracts;

public enum WorkerCommand
{
    GetHealth,
    GetCapabilities,
    GetSnapshot,
    ApplyTarget,
    GetPowerPolicy,
    SetPowerPolicy,
    RefreshTelemetry,
    SetPresets,
    ExportDiagnostics,
    RestartWorker,
    Shutdown
}

