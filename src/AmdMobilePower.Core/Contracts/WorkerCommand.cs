namespace AmdMobilePower.Core.Contracts;

public enum WorkerCommand
{
    GetHealth,
    GetSnapshot,
    ApplyTarget,
    RefreshTelemetry,
    SetPresets,
    ExportDiagnostics,
    RestartWorker,
    Shutdown
}

