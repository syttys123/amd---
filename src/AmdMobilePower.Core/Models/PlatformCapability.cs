namespace AmdMobilePower.Core.Models;

public sealed record PlatformCapability(
    CpuPlatformInfo Cpu,
    PowerLimitCapability Limits,
    bool IsSupported,
    string? UnsupportedReason);

