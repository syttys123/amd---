using System.Text.Json;

namespace AmdMobilePower.Gui;

internal static class UiStateStore
{
    private static readonly int[] DefaultPresets = [12, 25, 45];
    private static readonly JsonSerializerOptions JsonOptions = new(JsonSerializerDefaults.Web)
    {
        WriteIndented = true
    };

    private static string StatePath { get; } = Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
        "AmdMobilePower",
        "ui-state.json");

    public static int[] LoadPresets()
    {
        GuiState? state = LoadState();
        if (state?.Presets is { Length: 3 } presets &&
            presets.All(value => value is >= 5 and <= 60))
        {
            return [.. presets];
        }

        return [.. DefaultPresets];
    }

    public static UiMode LoadUiMode()
    {
        return string.Equals(
            LoadState()?.UiMode,
            "simple",
            StringComparison.OrdinalIgnoreCase)
            ? UiMode.Simple
            : UiMode.Advanced;
    }

    public static bool LoadTopMost()
    {
        return LoadState()?.TopMost == true;
    }

    public static StoredPowerPolicy? LoadPowerPolicy()
    {
        StoredPowerPolicy? policy = LoadState()?.PowerPolicy;
        if (policy is null ||
            policy.BatteryWatts is < 5 or > 60 ||
            policy.AcWatts is < 5 or > 60)
        {
            return null;
        }

        return policy;
    }

    public static void SaveUiMode(UiMode mode)
    {
        GuiState state = LoadState() ?? new GuiState();
        WriteState(state with
        {
            UiMode = mode == UiMode.Simple ? "simple" : "advanced"
        });
    }

    public static void SaveTopMost(bool topMost)
    {
        GuiState state = LoadState() ?? new GuiState();
        WriteState(state with { TopMost = topMost });
    }

    public static void SavePresets(IReadOnlyList<int> presets)
    {
        if (presets.Count != 3 || presets.Any(value => value is < 5 or > 60))
        {
            throw new ArgumentException("Three presets between 5W and 60W are required.", nameof(presets));
        }

        GuiState state = LoadState() ?? new GuiState();
        WriteState(state with
        {
            Presets = [presets[0], presets[1], presets[2]]
        });
    }

    public static void SavePowerPolicy(StoredPowerPolicy policy)
    {
        if (policy.BatteryWatts is < 5 or > 60 ||
            policy.AcWatts is < 5 or > 60)
        {
            throw new ArgumentOutOfRangeException(
                nameof(policy),
                "Battery and AC targets must be between 5W and 60W.");
        }

        GuiState state = LoadState() ?? new GuiState();
        WriteState(state with { PowerPolicy = policy });
    }

    private static GuiState? LoadState()
    {
        try
        {
            return File.Exists(StatePath)
                ? JsonSerializer.Deserialize<GuiState>(File.ReadAllText(StatePath), JsonOptions)
                : null;
        }
        catch
        {
            return null;
        }
    }

    private static void WriteState(GuiState state)
    {
        string directory = Path.GetDirectoryName(StatePath)!;
        Directory.CreateDirectory(directory);
        string temporaryPath = StatePath + ".tmp";
        string json = JsonSerializer.Serialize(state, JsonOptions);
        File.WriteAllText(temporaryPath, json);
        File.Move(temporaryPath, StatePath, overwrite: true);
    }

    private sealed record GuiState
    {
        public int[] Presets { get; init; } = [.. DefaultPresets];
        public StoredPowerPolicy? PowerPolicy { get; init; }
        public string UiMode { get; init; } = "advanced";
        public bool TopMost { get; init; }
    }
}

internal enum UiMode
{
    Simple,
    Advanced
}

internal sealed record StoredPowerPolicy(
    bool Enabled,
    int BatteryWatts,
    int AcWatts);
