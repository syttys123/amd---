using AmdMobilePower.Core.Models;
using AmdMobilePower.Core.Profiles;

namespace AmdMobilePower.Core.Contracts;

public sealed record WorkerCapabilitySnapshot(
    PlatformCapability Platform,
    PlatformProfile? MatchedProfile);
