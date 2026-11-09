using System.Text;
using System.Text.RegularExpressions;
using AmdMobilePower.Core.Models;
using AmdMobilePower.Core.Validation;

namespace AmdMobilePower.Core.Profiles;

public sealed record PlatformProfile
{
    public int SchemaVersion { get; init; } = 1;
    public required string Id { get; init; }
    public required string DisplayName { get; init; }
    public string[] CpuFamilyPatterns { get; init; } = [];
    public string[] ProcessorNamePatterns { get; init; } = [];
    public string[] PmTablePatterns { get; init; } = [];
    public int MinimumWatts { get; init; } = PowerLimitValidator.MinimumWatts;
    public int MaximumWatts { get; init; } = PowerLimitValidator.MaximumWatts;
    public int DefaultWatts { get; init; } = 15;
    public bool SupportsStapm { get; init; } = true;
    public bool SupportsFast { get; init; } = true;
    public bool SupportsSlow { get; init; } = true;
    public string[] Notes { get; init; } = [];

    public bool Matches(CpuPlatformInfo cpu)
    {
        return MatchesAny(ProcessorNamePatterns, cpu.ProcessorName) &&
            MatchesFamily(CpuFamilyPatterns, cpu) &&
            MatchesAny(PmTablePatterns, cpu.PmTableVersion);
    }

    public void Validate()
    {
        if (SchemaVersion != 1)
        {
            throw new InvalidDataException($"Unsupported profile schema version {SchemaVersion}.");
        }
        if (string.IsNullOrWhiteSpace(Id) || string.IsNullOrWhiteSpace(DisplayName))
        {
            throw new InvalidDataException("Profile id and displayName are required.");
        }
        if (MinimumWatts < PowerLimitValidator.MinimumWatts ||
            MaximumWatts > PowerLimitValidator.MaximumWatts ||
            MinimumWatts > MaximumWatts)
        {
            throw new InvalidDataException("Profile watt range is invalid.");
        }
        if (DefaultWatts < MinimumWatts || DefaultWatts > MaximumWatts)
        {
            throw new InvalidDataException("Profile default watts is outside its range.");
        }
    }

    private static bool MatchesAny(string[] patterns, string? value)
    {
        if (patterns.Length == 0)
        {
            return true;
        }
        return patterns.Any(pattern => WildcardMatches(pattern, value));
    }

    private static bool WildcardMatches(string pattern, string? value)
    {
        if (value is null)
        {
            return false;
        }

        StringBuilder regex = new("^");
        foreach (char character in pattern)
        {
            regex.Append(character switch
            {
                '*' => ".*",
                '?' => ".",
                _ => Regex.Escape(character.ToString())
            });
        }
        regex.Append('$');
        return Regex.IsMatch(value, regex.ToString(), RegexOptions.IgnoreCase | RegexOptions.CultureInvariant);
    }

    private static bool MatchesFamily(string[] patterns, CpuPlatformInfo cpu)
    {
        if (patterns.Length == 0)
        {
            return true;
        }

        string[] identities = new[]
        {
            cpu.RyzenAdjFamily is { } ryzenAdjFamily
                ? $"ryzenadj:{ryzenAdjFamily}"
                : null,
            cpu.Family is { } family && cpu.Model is { } model
                ? $"{family}:{model}"
                : null,
            cpu.Family?.ToString(),
            cpu.Model?.ToString()
        }
            .Where(value => value is not null)
            .Select(value => value!)
            .ToArray();
        return identities.Any(identity =>
            patterns.Any(pattern => WildcardMatches(pattern, identity)));
    }
}

