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
        try
        {
            if (!File.Exists(StatePath))
            {
                return [.. DefaultPresets];
            }

            GuiState? state = JsonSerializer.Deserialize<GuiState>(
                File.ReadAllText(StatePath),
                JsonOptions);
            if (state?.Presets is { Length: 3 } presets &&
                presets.All(value => value is >= 5 and <= 60))
            {
                return [.. presets];
            }
        }
        catch
        {
        }

        return [.. DefaultPresets];
    }

    public static void SavePresets(IReadOnlyList<int> presets)
    {
        if (presets.Count != 3 || presets.Any(value => value is < 5 or > 60))
        {
            throw new ArgumentException("Three presets between 5W and 60W are required.", nameof(presets));
        }

        string directory = Path.GetDirectoryName(StatePath)!;
        Directory.CreateDirectory(directory);
        string temporaryPath = StatePath + ".tmp";
        string json = JsonSerializer.Serialize(
            new GuiState { Presets = [presets[0], presets[1], presets[2]] },
            JsonOptions);
        File.WriteAllText(temporaryPath, json);
        File.Move(temporaryPath, StatePath, overwrite: true);
    }

    private sealed record GuiState
    {
        public int[] Presets { get; init; } = [.. DefaultPresets];
    }
}
