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
}
