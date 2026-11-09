using System.Globalization;
using System.Text;

namespace AmdMobilePower.Core.Diagnostics;

public sealed class DiagnosticFileLog
{
    private readonly object _sync = new();
    private readonly string _component;
    private readonly int _retentionDays;
    private DateOnly _lastCleanupDate;

    public DiagnosticFileLog(
        string directory,
        string component,
        int retentionDays = 7)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(directory);
        ArgumentException.ThrowIfNullOrWhiteSpace(component);
        if (retentionDays < 1)
        {
            throw new ArgumentOutOfRangeException(
                nameof(retentionDays),
                "Retention must be at least one day.");
        }

        DirectoryPath = Path.GetFullPath(directory);
        _component = SanitizeFileComponent(component);
        _retentionDays = retentionDays;
    }

    public string DirectoryPath { get; }

    public void Info(string message)
    {
        Write("INFO", message);
    }

    public void Warning(string message)
    {
        Write("WARN", message);
    }

    public void Error(string message, Exception? exception = null)
    {
        Write("ERROR", message, exception);
    }

    public void Write(string level, string message, Exception? exception = null)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(level);
        ArgumentException.ThrowIfNullOrWhiteSpace(message);

        try
        {
            lock (_sync)
            {
                Directory.CreateDirectory(DirectoryPath);
                DateTimeOffset now = DateTimeOffset.Now;
                CleanupOldLogs(now);

                StringBuilder entry = new();
                entry.Append('[')
                    .Append(now.ToString(
                        "yyyy-MM-dd HH:mm:ss.fff zzz",
                        CultureInfo.InvariantCulture))
                    .Append("] [")
                    .Append(level.Trim().ToUpperInvariant())
                    .Append("] [")
                    .Append(_component)
                    .Append("] ")
                    .AppendLine(NormalizeLine(message));
                if (exception is not null)
                {
                    entry.Append("  ")
                        .Append(exception.GetType().FullName)
                        .Append(": ")
                        .AppendLine(NormalizeLine(exception.Message));
                    if (!string.IsNullOrWhiteSpace(exception.StackTrace))
                    {
                        entry.AppendLine(exception.StackTrace);
                    }
                }

                File.AppendAllText(
                    GetFilePath(now),
                    entry.ToString(),
                    new UTF8Encoding(encoderShouldEmitUTF8Identifier: false));
            }
        }
        catch
        {
            // Diagnostics must never take down the GUI or hardware worker.
        }
    }

    public IReadOnlyList<string> ReadTail(int maxLines = 200)
    {
        ArgumentOutOfRangeException.ThrowIfNegativeOrZero(maxLines);
        string path = GetFilePath(DateTimeOffset.Now);
        try
        {
            lock (_sync)
            {
                if (!File.Exists(path))
                {
                    return Array.Empty<string>();
                }

                string[] lines = File.ReadAllLines(path, Encoding.UTF8);
                return lines.TakeLast(maxLines).ToArray();
            }
        }
        catch
        {
            return Array.Empty<string>();
        }
    }

    public IReadOnlyList<string> GetRecentFiles(int maxFiles = 10)
    {
        ArgumentOutOfRangeException.ThrowIfNegativeOrZero(maxFiles);
        try
        {
            lock (_sync)
            {
                if (!Directory.Exists(DirectoryPath))
                {
                    return Array.Empty<string>();
                }

                return Directory
                    .EnumerateFiles(DirectoryPath, $"{_component}-*.log")
                    .OrderByDescending(File.GetLastWriteTimeUtc)
                    .Take(maxFiles)
                    .ToArray();
            }
        }
        catch
        {
            return Array.Empty<string>();
        }
    }

    private string GetFilePath(DateTimeOffset timestamp)
    {
        return Path.Combine(
            DirectoryPath,
            $"{_component}-{timestamp:yyyyMMdd}.log");
    }

    private void CleanupOldLogs(DateTimeOffset now)
    {
        DateOnly today = DateOnly.FromDateTime(now.LocalDateTime);
        if (_lastCleanupDate == today)
        {
            return;
        }

        _lastCleanupDate = today;
        DateTime cutoff = now.LocalDateTime.Date.AddDays(-_retentionDays + 1);
        foreach (string path in Directory.EnumerateFiles(
                     DirectoryPath,
                     $"{_component}-*.log"))
        {
            try
            {
                if (File.GetLastWriteTime(path) < cutoff)
                {
                    File.Delete(path);
                }
            }
            catch
            {
            }
        }
    }

    private static string NormalizeLine(string value)
    {
        return value
            .Replace("\r\n", " ", StringComparison.Ordinal)
            .Replace('\r', ' ')
            .Replace('\n', ' ');
    }

    private static string SanitizeFileComponent(string value)
    {
        char[] invalid = Path.GetInvalidFileNameChars();
        string sanitized = new(
            value
                .Trim()
                .ToLowerInvariant()
                .Select(character =>
                    invalid.Contains(character) || char.IsWhiteSpace(character)
                        ? '-'
                        : character)
                .ToArray());
        return string.IsNullOrWhiteSpace(sanitized) ? "app" : sanitized;
    }
}
