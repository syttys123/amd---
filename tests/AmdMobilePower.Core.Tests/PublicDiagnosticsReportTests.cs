using System.Text.Json;
using AmdMobilePower.Core.Contracts;
using AmdMobilePower.Core.Diagnostics;
using AmdMobilePower.Core.Models;
using AmdMobilePower.Core.Profiles;

namespace AmdMobilePower.Core.Tests;

public sealed class PublicDiagnosticsReportTests
{
    [Fact]
    public void Serialize_ExcludesPrivateWorkerFieldsAndRedactsPaths()
    {
        string userProfile = Path.Combine(
            Path.GetTempPath(),
            "amd-mobile-power-public-diagnostics-tests",
            "user");
        string workerDirectory = Path.Combine(userProfile, "apps", "worker");
        string logDirectory = Path.Combine(userProfile, "logs");

        WorkerDiagnostics diagnostics = new(
            GeneratedAt: DateTimeOffset.Parse("2026-11-10T00:00:00+08:00"),
            WorkerVersion: "0.1.3-dev",
            ProcessId: 4242,
            ProcessArchitecture: "X64",
            OperatingSystem: "Windows 11",
            WorkerDirectory: workerDirectory,
            ProfileCount: 1,
            Platform: new PlatformCapability(
                new CpuPlatformInfo
                {
                    ProcessorName = "AMD Ryzen 7 8845HS",
                    RyzenAdjFamily = 10,
                    RyzenAdjFamilyName = "Hawk Point",
                    SmuBiosVersion = "15",
                    PmTableVersion = "4c0009"
                },
                new PowerLimitCapability(true, true, true),
                IsSupported: true,
                UnsupportedReason: $"Failed under {workerDirectory}"),
            MatchedProfile: new PlatformProfile
            {
                Id = "hawk-point-8845hs",
                DisplayName = "Hawk Point 8845HS",
                Notes = [$"Loaded from {workerDirectory}"]
            },
            Telemetry: new TelemetrySnapshot
            {
                StapmLimitWatts = 12,
                FastLimitWatts = 12,
                SlowLimitWatts = 12,
                PowerLine = PowerLineState.Ac
            },
            RuntimeFiles:
            [
                new RuntimeFileDiagnostic(
                    "libryzenadj.dll",
                    true,
                    1024,
                    "abc123",
                    $"Read failed under {workerDirectory}")
            ],
            DiagnosticLogDirectory: logDirectory,
            RecentWorkerLogLines: [$"worker log from {logDirectory}"],
            RecentGuiLogLines: ["gui diagnostic marker"],
            Notes:
            [
                $"Worker log directory: {logDirectory}",
                @"Network path \\server\share\tool.exe failed.",
                "Hardware owner conflict PID 4242."
            ])
        {
            PipeName = "AmdMobilePower.Tests.SecretPipe",
            HardwareAdapterConfigured = true,
            WriteControlsEnabled = false,
            WorkerExecutableSha256 = "abc123",
            Profiles =
            [
                new PlatformProfileDiagnostic(
                    "hawk-point-8845hs",
                    "Hawk Point 8845HS",
                    ["ryzenadj:10"],
                    ["*8845HS*"],
                    ["4c0009"],
                    5,
                    60,
                    25,
                    true,
                    true,
                    true)
            ]
        };

        string json = PublicDiagnosticsReport.Serialize(diagnostics);
        Assert.DoesNotContain("RecentWorkerLogLines", json, StringComparison.OrdinalIgnoreCase);
        Assert.DoesNotContain("RecentGuiLogLines", json, StringComparison.OrdinalIgnoreCase);
        Assert.DoesNotContain("DiagnosticLogDirectory", json, StringComparison.OrdinalIgnoreCase);
        Assert.DoesNotContain("WorkerDirectory", json, StringComparison.OrdinalIgnoreCase);
        Assert.DoesNotContain("\"processId\"", json, StringComparison.OrdinalIgnoreCase);
        Assert.DoesNotContain("AmdMobilePower.Tests.SecretPipe", json);

        using JsonDocument document = JsonDocument.Parse(json);
        JsonElement root = document.RootElement;
        string[] stringValues = GetStringValues(root).ToArray();
        Assert.DoesNotContain(
            stringValues,
            value => value.Contains(workerDirectory, StringComparison.OrdinalIgnoreCase));
        Assert.DoesNotContain(
            stringValues,
            value => value.Contains(logDirectory, StringComparison.OrdinalIgnoreCase));
        Assert.DoesNotContain(stringValues, value => value.Contains("4242", StringComparison.Ordinal));
        Assert.DoesNotContain(
            stringValues,
            value => value.Contains(@"\\server\share", StringComparison.OrdinalIgnoreCase));
        Assert.Contains(stringValues, value => value.Contains("<worker-directory>", StringComparison.Ordinal));
        Assert.Contains(
            stringValues,
            value => value.Contains("<diagnostic-log-directory>", StringComparison.Ordinal));
        Assert.Contains(stringValues, value => value.Contains("<network-path>", StringComparison.Ordinal));
        Assert.Contains(stringValues, value => value.Contains("PID <redacted>", StringComparison.Ordinal));
        Assert.Equal("PASS", root.GetProperty("collectionStatus").GetString());
        Assert.Equal("gui", root.GetProperty("exportSource").GetString());
        Assert.False(root.GetProperty("privacy").GetProperty("localPathsIncluded").GetBoolean());
        Assert.False(root.GetProperty("privacy").GetProperty("processIdIncluded").GetBoolean());
        Assert.False(root.GetProperty("worker").GetProperty("writeControlsEnabled").GetBoolean());
        Assert.Equal(
            "hawk-point-8845hs",
            root.GetProperty("matchedProfile").GetProperty("id").GetString());
    }

    private static IEnumerable<string> GetStringValues(JsonElement element)
    {
        switch (element.ValueKind)
        {
            case JsonValueKind.String:
                yield return element.GetString()!;
                break;
            case JsonValueKind.Array:
                foreach (JsonElement child in element.EnumerateArray())
                {
                    foreach (string value in GetStringValues(child))
                    {
                        yield return value;
                    }
                }
                break;
            case JsonValueKind.Object:
                foreach (JsonProperty property in element.EnumerateObject())
                {
                    foreach (string value in GetStringValues(property.Value))
                    {
                        yield return value;
                    }
                }
                break;
        }
    }
}
