using System.Text.Json;
using AmdMobilePower.Core.Contracts;
using AmdMobilePower.Core.Models;

namespace AmdMobilePower.Core.Profiles;

public static class ProfileRepository
{
    public static PlatformProfile Parse(string json)
    {
        PlatformProfile profile = JsonSerializer.Deserialize<PlatformProfile>(
            json,
            WorkerProtocol.JsonOptions)
            ?? throw new InvalidDataException("Profile JSON is empty.");
        profile.Validate();
        return profile;
    }

    public static IReadOnlyList<PlatformProfile> LoadDirectory(string path)
    {
        if (!Directory.Exists(path))
        {
            return Array.Empty<PlatformProfile>();
        }

        return Directory
            .EnumerateFiles(path, "*.json", SearchOption.TopDirectoryOnly)
            .OrderBy(file => file, StringComparer.OrdinalIgnoreCase)
            .Select(file => Parse(File.ReadAllText(file)))
            .ToArray();
    }

    public static PlatformProfile? FindBestMatch(
        IEnumerable<PlatformProfile> profiles,
        CpuPlatformInfo cpu)
    {
        return profiles
            .Where(profile => profile.Matches(cpu))
            .OrderByDescending(GetSpecificity)
            .ThenBy(profile => profile.Id, StringComparer.OrdinalIgnoreCase)
            .FirstOrDefault();
    }

    private static int GetSpecificity(PlatformProfile profile)
    {
        return
            (CountSpecificPatterns(profile.ProcessorNamePatterns) * 100) +
            (CountSpecificPatterns(profile.CpuFamilyPatterns) * 30) +
            (CountSpecificPatterns(profile.PmTablePatterns) * 10);
    }

    private static int CountSpecificPatterns(IEnumerable<string> patterns)
    {
        return patterns.Count(pattern =>
            !string.IsNullOrWhiteSpace(pattern) &&
            pattern != "*");
    }
}

