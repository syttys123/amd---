using AmdMobilePower.Core.Models;
using AmdMobilePower.Core.Profiles;

namespace AmdMobilePower.Core.Contracts;

public sealed record WorkerSnapshot(
    PlatformCapability Platform,
    PlatformProfile? MatchedProfile,
    TelemetrySnapshot Telemetry);
