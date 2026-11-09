using AmdMobilePower.Worker.Hardware;

namespace AmdMobilePower.Worker.Tests;

public sealed class RyzenAdjFamilyNamesTests
{
    [Theory]
    [InlineData(9, "Phoenix")]
    [InlineData(10, "Hawk Point")]
    [InlineData(13, "Strix Point")]
    [InlineData(14, "Strix Halo")]
    public void GetName_MapsKnownFamilies(int family, string expected)
    {
        Assert.Equal(expected, RyzenAdjFamilyNames.GetName(family));
    }

    [Fact]
    public void GetName_MapsEveryKnownMobileFamily()
    {
        Dictionary<int, string> expected = new()
        {
            [0] = "Raven",
            [1] = "Picasso",
            [2] = "Renoir",
            [3] = "Cezanne",
            [4] = "Dali",
            [5] = "Lucienne",
            [6] = "Van Gogh",
            [7] = "Rembrandt",
            [8] = "Mendocino",
            [9] = "Phoenix",
            [10] = "Hawk Point",
            [11] = "Dragon Range",
            [12] = "Krackan Point",
            [13] = "Strix Point",
            [14] = "Strix Halo",
            [15] = "Fire Range"
        };

        foreach ((int family, string name) in expected)
        {
            Assert.Equal(name, RyzenAdjFamilyNames.GetName(family));
        }
    }
}
