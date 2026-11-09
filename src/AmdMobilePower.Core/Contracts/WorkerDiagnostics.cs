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
    string DiagnosticLogDirectory,
    IReadOnlyList<string> RecentWorkerLogLines,
    IReadOnlyList<string> RecentGuiLogLines,
    IReadOnlyList<string> Notes)
{
    public int SchemaVersion { get; init; } = 1;
    public int ProtocolVersion { get; init; } = WorkerProtocol.CurrentVersion;
    public string PipeName { get; init; } = string.Empty;
    public bool HardwareAdapterConfigured { get; init; }
    public bool WriteControlsEnabled { get; init; }
    public string? WorkerExecutableSha256 { get; init; }
    public IReadOnlyList<PlatformProfileDiagnostic> Profiles { get; init; } = [];
}

public sealed record PlatformProfileDiagnostic(
    string Id,
    string DisplayName,
    string[] CpuFamilyPatterns,
    string[] ProcessorNamePatterns,
    string[] PmTablePatterns,
    int MinimumWatts,
    int MaximumWatts,
    int DefaultWatts,
    bool SupportsStapm,
    bool SupportsFast,
    bool SupportsSlow);

public sealed record RuntimeFileDiagnostic(
    string Name,
    bool Present,
    long? SizeBytes,
    string? Sha256,
    string? Error);
