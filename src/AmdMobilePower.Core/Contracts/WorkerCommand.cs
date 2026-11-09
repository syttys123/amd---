namespace AmdMobilePower.Core.Contracts;

public enum WorkerCommand
{
    GetHealth,
    GetCapabilities,
    GetSnapshot,
    ApplyTarget,
    RefreshTelemetry,
    SetPresets,
    ExportDiagnostics,
    RestartWorker,
    Shutdown
}

