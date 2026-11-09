using AmdMobilePower.Core.Models;
using AmdMobilePower.Core.Profiles;

namespace AmdMobilePower.Core.Tests;

public sealed class PlatformProfileTests
{
    [Fact]
    public void FindBestMatch_PrefersSpecificProcessorAndPmTableProfile()
    {
        PlatformProfile fallback = ProfileRepository.Parse(
            """
            {
              "id": "default",
              "displayName": "Default",
              "processorNamePatterns": ["*AMD*"],
              "minimumWatts": 5,
              "maximumWatts": 45,
              "defaultWatts": 15
            }
            """);
        PlatformProfile specific = ProfileRepository.Parse(
            """
            {
              "id": "hawk-point-8845hs",
              "displayName": "8845HS",
              "cpuFamilyPatterns": ["25:117"],
              "processorNamePatterns": ["*8845HS*"],
              "pmTablePatterns": ["4c0009"],
              "minimumWatts": 5,
              "maximumWatts": 60,
              "defaultWatts": 25
            }
            """);

        CpuPlatformInfo cpu = new()
        {
            ProcessorName = "AMD Ryzen 7 8845HS w/ Radeon 780M Graphics",
            Family = 25,
            Model = 117,
            PmTableVersion = "4c0009"
        };

        PlatformProfile? result = ProfileRepository.FindBestMatch([fallback, specific], cpu);

        Assert.NotNull(result);
        Assert.Equal("hawk-point-8845hs", result.Id);
    }

    [Fact]
    public void WildcardPatterns_AreCaseInsensitive()
    {
        PlatformProfile profile = ProfileRepository.Parse(
            """
            {
              "id": "test",
              "displayName": "Test",
              "processorNamePatterns": ["*ryzen?7*"],
              "minimumWatts": 5,
              "maximumWatts": 45,
              "defaultWatts": 15
            }
            """);

        CpuPlatformInfo cpu = new()
        {
            ProcessorName = "AMD RYZEN 7 7840U"
        };

        Assert.True(profile.Matches(cpu));
    }

    [Fact]
    public void FindBestMatch_UsesRyzenAdjFamilyWhenCpuidFamilyIsUnavailable()
    {
        PlatformProfile fallback = ProfileRepository.Parse(
            """
            {
              "id": "default",
              "displayName": "Default",
              "processorNamePatterns": ["*AMD*"],
              "minimumWatts": 5,
              "maximumWatts": 45,
              "defaultWatts": 15
            }
            """);
        PlatformProfile family = ProfileRepository.Parse(
            """
            {
              "id": "ryzenadj-renoir-cezanne",
              "displayName": "Renoir Cezanne",
              "cpuFamilyPatterns": ["ryzenadj:2", "ryzenadj:3", "ryzenadj:5"],
              "processorNamePatterns": ["*AMD*"],
              "minimumWatts": 5,
              "maximumWatts": 45,
              "defaultWatts": 15
            }
            """);
        CpuPlatformInfo cpu = new()
        {
            ProcessorName = "AMD Ryzen 7 5800U with Radeon Graphics",
            RyzenAdjFamily = 3
        };

        PlatformProfile? result = ProfileRepository.FindBestMatch([fallback, family], cpu);

        Assert.NotNull(result);
        Assert.Equal("ryzenadj-renoir-cezanne", result.Id);
    }

    [Fact]
    public void FindBestMatch_PrefersDeviceProfileOverFamilyProfile()
    {
        PlatformProfile family = ProfileRepository.Parse(
            """
            {
              "id": "ryzenadj-hawk-point",
              "displayName": "Hawk Point",
              "cpuFamilyPatterns": ["ryzenadj:10"],
              "processorNamePatterns": ["*AMD*"],
              "minimumWatts": 5,
              "maximumWatts": 45,
              "defaultWatts": 15
            }
            """);
        PlatformProfile device = ProfileRepository.Parse(
            """
            {
              "id": "hawk-point-8845hs",
              "displayName": "8845HS",
              "cpuFamilyPatterns": ["ryzenadj:10"],
              "processorNamePatterns": ["*8845HS*"],
              "pmTablePatterns": ["4c0009"],
              "minimumWatts": 5,
              "maximumWatts": 60,
              "defaultWatts": 25
            }
            """);
        CpuPlatformInfo cpu = new()
        {
            ProcessorName = "AMD Ryzen 7 8845HS w/ Radeon 780M Graphics",
            RyzenAdjFamily = 10,
            PmTableVersion = "4c0009"
        };

        PlatformProfile? result = ProfileRepository.FindBestMatch([family, device], cpu);

        Assert.NotNull(result);
        Assert.Equal("hawk-point-8845hs", result.Id);
    }

    [Fact]
    public void Validate_RejectsDefaultOutsideSupportedRange()
    {
        const string json = """
            {
              "id": "invalid",
              "displayName": "Invalid",
              "minimumWatts": 25,
              "maximumWatts": 30,
              "defaultWatts": 60
            }
            """;

        Assert.Throws<InvalidDataException>(() => ProfileRepository.Parse(json));
    }

    [Fact]
    public void RepositoryProfiles_LoadWithUniqueIdsAndUnknownCpuFallsBack()
    {
        IReadOnlyList<PlatformProfile> profiles = ProfileRepository.LoadDirectory(
            Path.Combine(AppContext.BaseDirectory, "profiles"));

        Assert.True(profiles.Count >= 9);
        Assert.Contains(profiles, profile => profile.Id == "default");

        CpuPlatformInfo unknown = new()
        {
            ProcessorName = "AMD Ryzen AI 9 HX 999",
            RyzenAdjFamily = 999
        };

        Assert.Equal("default", ProfileRepository.FindBestMatch(profiles, unknown)?.Id);
    }

    [Fact]
    public void RepositoryProfiles_CoverEveryKnownRyzenAdjFamilyExactlyOnce()
    {
        IReadOnlyList<PlatformProfile> profiles = ProfileRepository.LoadDirectory(
            Path.Combine(AppContext.BaseDirectory, "profiles"));

        int[] coveredFamilies = profiles
            .SelectMany(profile => profile.CpuFamilyPatterns)
            .Where(pattern => pattern.StartsWith("ryzenadj:", StringComparison.OrdinalIgnoreCase))
            .Select(pattern => int.Parse(
                pattern["ryzenadj:".Length..],
                System.Globalization.CultureInfo.InvariantCulture))
            .OrderBy(family => family)
            .ToArray();

        Assert.Equal(Enumerable.Range(0, 16), coveredFamilies);
    }

    [Fact]
    public void LoadDirectory_RejectsDuplicateProfileIds()
    {
        string directory = Path.Combine(
            Path.GetTempPath(),
            "amd-mobile-power-profile-tests",
            Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(directory);
        try
        {
            const string first = """
                {
                  "id": "duplicate",
                  "displayName": "First",
                  "minimumWatts": 5,
                  "maximumWatts": 45,
                  "defaultWatts": 15
                }
                """;
            const string second = """
                {
                  "id": "DUPLICATE",
                  "displayName": "Second",
                  "minimumWatts": 5,
                  "maximumWatts": 45,
                  "defaultWatts": 15
                }
                """;
            File.WriteAllText(Path.Combine(directory, "first.json"), first);
            File.WriteAllText(Path.Combine(directory, "second.json"), second);

            InvalidDataException error = Assert.Throws<InvalidDataException>(
                () => ProfileRepository.LoadDirectory(directory));

            Assert.Contains("Duplicate profile id", error.Message);
        }
        finally
        {
            Directory.Delete(directory, recursive: true);
        }
    }
}

