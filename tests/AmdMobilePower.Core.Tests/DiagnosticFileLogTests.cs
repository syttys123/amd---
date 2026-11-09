using AmdMobilePower.Core.Diagnostics;

namespace AmdMobilePower.Core.Tests;

public sealed class DiagnosticFileLogTests : IDisposable
{
    private readonly string _directory = Path.Combine(
        Path.GetTempPath(),
        "amd-mobile-power-log-tests",
        Guid.NewGuid().ToString("N"));

    [Fact]
    public void Write_AppendsStructuredEntry()
    {
        DiagnosticFileLog log = new(_directory, "worker", retentionDays: 7);

        log.Info("worker started");
        log.Error("write failed", new InvalidOperationException("driver unavailable"));

        IReadOnlyList<string> lines = log.ReadTail();
        Assert.Contains(lines, line => line.Contains("[INFO] [worker] worker started"));
        Assert.Contains(lines, line => line.Contains("[ERROR] [worker] write failed"));
        Assert.Contains(lines, line => line.Contains("InvalidOperationException: driver unavailable"));
    }

    [Fact]
    public void Write_RemovesLogsOutsideRetention()
    {
        Directory.CreateDirectory(_directory);
        string expired = Path.Combine(_directory, "worker-20200101.log");
        File.WriteAllText(expired, "old");
        File.SetLastWriteTime(expired, DateTime.Now.AddDays(-30));
        DiagnosticFileLog log = new(_directory, "worker", retentionDays: 3);

        log.Info("current");

        Assert.False(File.Exists(expired));
        Assert.NotEmpty(log.GetRecentFiles());
    }

    [Fact]
    public void ReadTail_ReturnsOnlyRequestedNumberOfLines()
    {
        DiagnosticFileLog log = new(_directory, "gui");
        for (int index = 0; index < 5; index++)
        {
            log.Info($"entry {index}");
        }

        IReadOnlyList<string> lines = log.ReadTail(maxLines: 2);

        Assert.Equal(2, lines.Count);
        Assert.Contains("entry 3", lines[0]);
        Assert.Contains("entry 4", lines[1]);
    }

    public void Dispose()
    {
        if (Directory.Exists(_directory))
        {
            Directory.Delete(_directory, recursive: true);
        }
    }
}
