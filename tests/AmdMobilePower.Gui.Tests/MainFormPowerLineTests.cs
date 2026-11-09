using AmdMobilePower.Core.Models;

namespace AmdMobilePower.Gui.Tests;

public sealed class MainFormPowerLineTests
{
    [Theory]
    [InlineData(PowerLineState.Ac, "电源")]
    [InlineData(PowerLineState.Battery, "电池")]
    [InlineData(PowerLineState.Unknown, "电源未知")]
    public void DescribePowerLine_UsesProductLanguage(
        PowerLineState state,
        string expected)
    {
        Assert.Equal(expected, MainForm.DescribePowerLine(state));
    }
}
