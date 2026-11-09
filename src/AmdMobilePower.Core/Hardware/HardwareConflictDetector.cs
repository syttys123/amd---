using System.Diagnostics;

namespace AmdMobilePower.Core.Hardware;

public static class HardwareConflictDetector
{
    private static readonly string[] KnownOwners =
    [
        "RyzenPower",
        "ryzenadj",
        "AMD Ryzen Master"
    ];

    public static HardwareProcessConflict? FindKnownHardwareOwner()
    {
        int currentProcessId = Environment.ProcessId;
        foreach (string processName in KnownOwners)
        {
            Process[] processes = Process.GetProcessesByName(processName);
            try
            {
                Process? match = processes.FirstOrDefault(
                    process => process.Id != currentProcessId && !process.HasExited);
                if (match is not null)
                {
                    return new HardwareProcessConflict(processName, match.Id);
                }
            }
            finally
            {
                foreach (Process process in processes)
                {
                    process.Dispose();
                }
            }
        }

        return null;
    }
}

public sealed record HardwareProcessConflict(string ProcessName, int ProcessId);
