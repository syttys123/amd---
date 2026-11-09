namespace AmdMobilePower.Core.Contracts;

public sealed record WorkerHealth(
    string Status,
    int ProtocolVersion,
    string WorkerVersion,
    int ProcessId,
    DateTimeOffset StartedAt,
    double UptimeSeconds,
    bool HardwareInitialized);

