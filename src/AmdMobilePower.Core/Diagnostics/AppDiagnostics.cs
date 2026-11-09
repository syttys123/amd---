namespace AmdMobilePower.Core.Diagnostics;

public static class AppDiagnostics
{
    public static string LogDirectory { get; } = Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
        "AmdMobilePower",
        "logs");

    public static DiagnosticFileLog Gui { get; } =
        new(LogDirectory, "gui");

    public static DiagnosticFileLog Worker { get; } =
        new(LogDirectory, "worker");
}
