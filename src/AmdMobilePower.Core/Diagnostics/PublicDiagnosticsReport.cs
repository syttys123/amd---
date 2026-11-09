using System.Diagnostics.CodeAnalysis;
using System.Text.Encodings.Web;
using System.Text.Json;
using System.Text.Json.Nodes;
using System.Text.RegularExpressions;
using AmdMobilePower.Core.Contracts;

namespace AmdMobilePower.Core.Diagnostics;

public static class PublicDiagnosticsReport
{
    private static readonly Regex WindowsPathPattern = new(
        @"(?i)(?<![A-Za-z0-9])[A-Z]:[\\/](?:[^\\/\r\n""'<>|]+[\\/])*[^\\/\r\n""'<>|]*",
        RegexOptions.Compiled | RegexOptions.CultureInvariant);

    private static readonly Regex NetworkPathPattern = new(
        @"(?i)(?<![A-Za-z0-9])\\\\[^\\/\r\n""'<>|]+[\\/][^\\/\r\n""'<>|]+(?:[\\/][^\\/\r\n""'<>|]*)*",
        RegexOptions.Compiled | RegexOptions.CultureInvariant);

    private static readonly Regex ProcessIdPattern = new(
        @"(?i)\bPID\s+\d+\b",
        RegexOptions.Compiled | RegexOptions.CultureInvariant);

    public static string Serialize(WorkerDiagnostics diagnostics, bool writeIndented = true)
    {
        JsonObject report = Create(diagnostics);
        JsonSerializerOptions options = new(WorkerProtocol.JsonOptions)
        {
            Encoder = JavaScriptEncoder.UnsafeRelaxedJsonEscaping,
            WriteIndented = writeIndented
        };
        return report.ToJsonString(options);
    }

    public static JsonObject Create(WorkerDiagnostics diagnostics)
    {
        ArgumentNullException.ThrowIfNull(diagnostics);

        IReadOnlyList<PathReplacement> replacements = GetPathReplacements(diagnostics);
        JsonObject worker = new()
        {
            ["version"] = diagnostics.WorkerVersion,
            ["architecture"] = diagnostics.ProcessArchitecture,
            ["operatingSystem"] = diagnostics.OperatingSystem,
            ["schemaVersion"] = diagnostics.SchemaVersion,
            ["protocolVersion"] = diagnostics.ProtocolVersion,
            ["hardwareAdapterConfigured"] = diagnostics.HardwareAdapterConfigured,
            ["writeControlsEnabled"] = diagnostics.WriteControlsEnabled,
            ["workerExecutableSha256"] = diagnostics.WorkerExecutableSha256
        };

        JsonArray runtimeFiles = new();
        foreach (RuntimeFileDiagnostic file in diagnostics.RuntimeFiles)
        {
            runtimeFiles.Add(JsonSerializer.SerializeToNode(file, WorkerProtocol.JsonOptions));
        }

        JsonArray profiles = new();
        foreach (PlatformProfileDiagnostic profile in diagnostics.Profiles)
        {
            profiles.Add(JsonSerializer.SerializeToNode(profile, WorkerProtocol.JsonOptions));
        }

        JsonArray notes = new();
        foreach (string note in diagnostics.Notes)
        {
            notes.Add(note);
        }

        JsonObject report = new()
        {
            ["schemaVersion"] = 1,
            ["evidenceType"] = "amd-mobile-power-compatibility-diagnostics",
            ["generatedAt"] = DateTimeOffset.Now,
            ["collectionStatus"] = "PASS",
            ["error"] = null,
            ["exportSource"] = "gui",
            ["privacy"] = new JsonObject
            {
                ["localPathsIncluded"] = false,
                ["processIdIncluded"] = false,
                ["accountNamesIncluded"] = false,
                ["serialNumbersIncluded"] = false,
                ["recentLogsIncluded"] = false,
                ["networkUploadPerformed"] = false
            },
            ["worker"] = worker,
            ["platform"] = JsonSerializer.SerializeToNode(
                diagnostics.Platform,
                WorkerProtocol.JsonOptions),
            ["matchedProfile"] = JsonSerializer.SerializeToNode(
                diagnostics.MatchedProfile,
                WorkerProtocol.JsonOptions),
            ["telemetry"] = JsonSerializer.SerializeToNode(
                diagnostics.Telemetry,
                WorkerProtocol.JsonOptions),
            ["runtimeFiles"] = runtimeFiles,
            ["profiles"] = profiles,
            ["notes"] = notes,
            ["submission"] = new JsonObject
            {
                ["instructions"] =
                    "Review the JSON, then attach it to a compatibility issue. " +
                    "This export never uploads data.",
                ["template"] =
                    "https://github.com/syttys123/amd-mobile-power/blob/main/docs/COMPATIBILITY_REPORT_TEMPLATE.md",
                ["issueUrl"] = "https://github.com/syttys123/amd-mobile-power/issues"
            }
        };

        SanitizeNode(report, replacements);
        return report;
    }

    private static IReadOnlyList<PathReplacement> GetPathReplacements(
        WorkerDiagnostics diagnostics)
    {
        List<PathReplacement> replacements = new();
        AddPath(replacements, diagnostics.WorkerDirectory, "<worker-directory>");
        AddPath(replacements, diagnostics.DiagnosticLogDirectory, "<diagnostic-log-directory>");
        AddPath(replacements, AppContext.BaseDirectory, "<application-directory>");
        AddPath(
            replacements,
            Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
            "<local-app-data>");
        AddPath(
            replacements,
            Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData),
            "<app-data>");
        AddPath(
            replacements,
            Environment.GetEnvironmentVariable("USERPROFILE"),
            "<user-profile>");
        AddPath(replacements, Path.GetTempPath(), "<temp>");
        AddPath(replacements, Environment.CurrentDirectory, "<current-directory>");

        return replacements
            .DistinctBy(item => item.Path, StringComparer.OrdinalIgnoreCase)
            .OrderByDescending(item => item.Path.Length)
            .ToArray();
    }

    private static void AddPath(
        ICollection<PathReplacement> replacements,
        string? path,
        string token)
    {
        if (!string.IsNullOrWhiteSpace(path))
        {
            replacements.Add(new PathReplacement(path, token));
        }
    }

    private static void SanitizeNode(
        JsonNode? node,
        IReadOnlyList<PathReplacement> replacements)
    {
        if (node is JsonObject obj)
        {
            foreach (KeyValuePair<string, JsonNode?> property in obj.ToArray())
            {
                if (TryGetStringValue(property.Value, out string? text))
                {
                    obj[property.Key] = RedactLocalText(text, replacements);
                }
                else
                {
                    SanitizeNode(property.Value, replacements);
                }
            }
            return;
        }

        if (node is JsonArray array)
        {
            for (int index = 0; index < array.Count; index++)
            {
                JsonNode? item = array[index];
                if (TryGetStringValue(item, out string? text))
                {
                    array[index] = RedactLocalText(text, replacements);
                }
                else
                {
                    SanitizeNode(item, replacements);
                }
            }
        }
    }

    private static bool TryGetStringValue(
        JsonNode? node,
        [NotNullWhen(true)] out string? text)
    {
        text = null;
        if (node is not JsonValue value)
        {
            return false;
        }
        if (value.TryGetValue(out string? directText))
        {
            text = directText;
            return directText is not null;
        }
        if (value.TryGetValue(out JsonElement element) &&
            element.ValueKind == JsonValueKind.String)
        {
            text = element.GetString();
            return text is not null;
        }
        return false;
    }

    private static string RedactLocalText(
        string value,
        IReadOnlyList<PathReplacement> replacements)
    {
        foreach (PathReplacement replacement in replacements)
        {
            value = value.Replace(
                replacement.Path,
                replacement.Token,
                StringComparison.OrdinalIgnoreCase);
        }

        value = WindowsPathPattern.Replace(value, "<local-path>");
        value = NetworkPathPattern.Replace(value, "<network-path>");
        return ProcessIdPattern.Replace(value, "PID <redacted>");
    }

    private sealed record PathReplacement(string Path, string Token);
}
