using System.Globalization;
using AmdMobilePower.Core.Models;

namespace AmdMobilePower.Core.Parsing;

public static class KeyValueTelemetryParser
{
    public static TelemetrySnapshot Parse(string content)
    {
        ArgumentNullException.ThrowIfNull(content);

        Dictionary<string, string> values = new(StringComparer.OrdinalIgnoreCase);
        foreach (string rawLine in content.Split(['\r', '\n'], StringSplitOptions.RemoveEmptyEntries))
        {
            string line = rawLine.Trim();
            int separator = line.IndexOf('=');
            if (separator <= 0)
            {
                continue;
            }

            values[line[..separator].Trim()] = line[(separator + 1)..].Trim();
        }

        return new TelemetrySnapshot
        {
            TargetWatts = ParseInt(Get(values, "TargetWatts")),
            StapmValueWatts = ParseDouble(Get(values, "StapmValueW")),
            FastValueWatts = ParseDouble(Get(values, "FastValueW")),
            SlowValueWatts = ParseDouble(Get(values, "SlowValueW")),
            StapmLimitWatts = ParseDouble(Get(values, "StapmLimitW")),
            FastLimitWatts = ParseDouble(Get(values, "FastLimitW")),
            SlowLimitWatts = ParseDouble(Get(values, "SlowLimitW")),
            TctlValueCelsius = ParseDouble(Get(values, "TctlValueC")),
            TctlLimitCelsius = ParseDouble(Get(values, "TctlLimitC")),
            PowerLine = ParsePowerLine(Get(values, "PowerLine")),
            UpdatedAt = ParseTimestamp(Get(values, "UpdatedAt"))
        };
    }

    private static string? Get(Dictionary<string, string> values, string key)
    {
        return values.TryGetValue(key, out string? value) ? value : null;
    }

    private static int? ParseInt(string? value)
    {
        return int.TryParse(value, NumberStyles.Integer, CultureInfo.InvariantCulture, out int parsed)
            ? parsed
            : null;
    }

    private static double? ParseDouble(string? value)
    {
        return double.TryParse(value, NumberStyles.Float, CultureInfo.InvariantCulture, out double parsed)
            ? parsed
            : null;
    }

    private static PowerLineState ParsePowerLine(string? value)
    {
        return value?.Trim().ToUpperInvariant() switch
        {
            "AC" => PowerLineState.Ac,
            "BATTERY" => PowerLineState.Battery,
            _ => PowerLineState.Unknown
        };
    }

    private static DateTimeOffset? ParseTimestamp(string? value)
    {
        return DateTimeOffset.TryParse(
            value,
            CultureInfo.InvariantCulture,
            DateTimeStyles.AssumeLocal,
            out DateTimeOffset parsed)
            ? parsed
            : null;
    }
}

