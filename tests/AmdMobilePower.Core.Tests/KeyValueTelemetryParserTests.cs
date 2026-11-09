using AmdMobilePower.Core.Models;
using AmdMobilePower.Core.Parsing;

namespace AmdMobilePower.Core.Tests;

public sealed class KeyValueTelemetryParserTests
{
    [Fact]
    public void Parse_ReadsPrototypeTelemetryAndDetectsStapmClamp()
    {
        const string content = """
            TargetWatts=45
            StapmValueW=25.00
            FastValueW=25.01
            SlowValueW=25.02
            StapmLimitW=25.00
            FastLimitW=45.00
            SlowLimitW=45.00
            TctlValueC=66.0
            TctlLimitC=95.0
            PowerLine=AC
            UpdatedAt=2026-11-09 09:52:35
            """;

        TelemetrySnapshot snapshot = KeyValueTelemetryParser.Parse(content);

        Assert.Equal(45, snapshot.TargetWatts);
        Assert.Equal(25.0, snapshot.StapmLimitWatts);
        Assert.Equal(45.0, snapshot.FastLimitWatts);
        Assert.Equal(PowerLineState.Ac, snapshot.PowerLine);
        Assert.True(snapshot.HasFirmwareClamp);
        Assert.Equal([PowerLimitKind.Stapm], snapshot.GetClampedLimits());
        Assert.NotNull(snapshot.UpdatedAt);
    }

    [Fact]
    public void Parse_IgnoresMalformedLinesAndIsCaseInsensitive()
    {
        const string content = """
            targetwatts=25
            invalid line
            stapmlimitw=25.00
            powerline=battery
            """;

        TelemetrySnapshot snapshot = KeyValueTelemetryParser.Parse(content);

        Assert.Equal(25, snapshot.TargetWatts);
        Assert.Equal(25.0, snapshot.StapmLimitWatts);
        Assert.Equal(PowerLineState.Battery, snapshot.PowerLine);
        Assert.False(snapshot.HasFirmwareClamp);
    }
}

