using AmdMobilePower.Core.Models;
using AmdMobilePower.Core.Profiles;

namespace AmdMobilePower.Core.Contracts;

public sealed record WorkerDiagnostics(
    DateTimeOffset GeneratedAt,
    string WorkerVersion,
    int ProcessId,
    string ProcessArchitecture,
    string OperatingSystem,
    string WorkerDirectory,
    int ProfileCount,
    PlatformCapability? Platform,
    PlatformProfile? MatchedProfile,
    TelemetrySnapshot? Telemetry,
    IReadOnlyList<RuntimeFileDiagnostic> RuntimeFiles,
    IReadOnlyList<string> Notes);

public sealed record RuntimeFileDiagnostic(
    string Name,
    bool Present,
    long? SizeBytes,
    string? Sha256,
    string? Error);
