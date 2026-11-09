namespace AmdMobilePower.Core.Models;

public sealed record CpuPlatformInfo
{
    public required string ProcessorName { get; init; }
    public string Vendor { get; init; } = "AuthenticAMD";
    public int? Family { get; init; }
    public int? Model { get; init; }
    public int? RyzenAdjFamily { get; init; }
    public string? RyzenAdjFamilyName { get; init; }
    public string? SmuBiosVersion { get; init; }
    public string? PmTableVersion { get; init; }
}

