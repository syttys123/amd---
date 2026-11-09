using AmdMobilePower.Core.Models;

namespace AmdMobilePower.Core.Contracts;

public sealed record PowerPolicySettings(
    bool Enabled,
    PowerLimitTarget BatteryTarget,
    PowerLimitTarget AcTarget);

public sealed record SetPowerPolicyRequest(PowerPolicySettings Settings);

public sealed record PowerPolicyState(
    PowerPolicySettings? Settings,
    PowerLineState? LastObservedPowerLine,
    PowerLimitTarget? LastAppliedTarget,
    DateTimeOffset? LastAttemptAt,
    bool? LastAttemptSucceeded,
    string? LastError);
