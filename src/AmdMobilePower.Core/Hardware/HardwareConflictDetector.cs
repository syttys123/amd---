using System.Diagnostics;
using System.Globalization;
using System.Runtime.InteropServices;

namespace AmdMobilePower.Core.Hardware;

public static class HardwareConflictDetector
{
    public const string LegacyWorkerMutexName = @"Local\RyzenAdjPowerWorker";

    private const int ScheduledTaskStateRunning = 4;
    private static readonly string[] KnownOwners =
    [
        "RyzenPower",
        "ryzenadj",
        "AMD Ryzen Master"
    ];
    private static readonly ScheduledTaskOwner[] KnownScheduledTaskOwners =
    [
        new(@"\AMD", "RyzenAdjWatch"),
        new(@"\AMD", "RyzenAdj"),
        new(@"\AMD", "RyzenAdjApply"),
        new(@"\AMD", "RyzenAdjToggle")
    ];

    public static HardwareProcessConflict? FindKnownHardwareOwner()
    {
        return Evaluate(
            IsLegacyWorkerMutexPresent(),
            FindKnownProcessOwners(),
            FindRunningScheduledTaskOwners());
    }

    internal static HardwareProcessConflict? Evaluate(
        bool legacyWorkerMutexPresent,
        IReadOnlyList<HardwareProcessCandidate> processes,
        IReadOnlyList<string> runningScheduledTaskPaths)
    {
        HardwareProcessConflict? scheduledTask = FindScheduledTaskConflict(
            runningScheduledTaskPaths);
        if (legacyWorkerMutexPresent)
        {
            return scheduledTask
                ?? new HardwareProcessConflict("RyzenAdjPowerWorker", null);
        }

        foreach (string processName in KnownOwners)
        {
            foreach (HardwareProcessCandidate candidate in processes)
            {
                if (string.Equals(
                    candidate.Name,
                    processName,
                    StringComparison.OrdinalIgnoreCase))
                {
                    return new HardwareProcessConflict(
                        candidate.Name,
                        candidate.ProcessId);
                }
            }
        }

        return scheduledTask;
    }

    private static IReadOnlyList<HardwareProcessCandidate> FindKnownProcessOwners()
    {
        List<HardwareProcessCandidate> owners = [];
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
                    owners.Add(new HardwareProcessCandidate(processName, match.Id));
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

        return owners;
    }

    private static bool IsLegacyWorkerMutexPresent()
    {
        if (!OperatingSystem.IsWindows())
        {
            return false;
        }

        try
        {
            using Mutex mutex = Mutex.OpenExisting(LegacyWorkerMutexName);
            return true;
        }
        catch (WaitHandleCannotBeOpenedException)
        {
            return false;
        }
        catch (UnauthorizedAccessException)
        {
            return true;
        }
    }

    private static HardwareProcessConflict? FindScheduledTaskConflict(
        IReadOnlyList<string> runningScheduledTaskPaths)
    {
        HashSet<string> running = new(
            runningScheduledTaskPaths,
            StringComparer.OrdinalIgnoreCase);
        foreach (ScheduledTaskOwner owner in KnownScheduledTaskOwners)
        {
            string path = $"{owner.Folder}\\{owner.Name}";
            if (running.Contains(path))
            {
                return new HardwareProcessConflict(
                    owner.Name,
                    null,
                    path);
            }
        }

        return null;
    }

    private static IReadOnlyList<string> FindRunningScheduledTaskOwners()
    {
        if (!OperatingSystem.IsWindows())
        {
            return [];
        }

        Type? serviceType = Type.GetTypeFromProgID("Schedule.Service");
        if (serviceType is null)
        {
            return [];
        }

        List<string> running = [];
        object? service = null;
        try
        {
            service = Activator.CreateInstance(serviceType);
            if (service is null)
            {
                return [];
            }

            dynamic scheduler = service;
            scheduler.Connect();
            foreach (ScheduledTaskOwner owner in KnownScheduledTaskOwners)
            {
                object? folder = null;
                object? task = null;
                try
                {
                    folder = scheduler.GetFolder(owner.Folder);
                    dynamic taskFolder = folder;
                    task = taskFolder.GetTask(owner.Name);
                    dynamic scheduledTask = task;
                    int state = Convert.ToInt32(
                        scheduledTask.State,
                        CultureInfo.InvariantCulture);
                    if (state == ScheduledTaskStateRunning)
                    {
                        running.Add($"{owner.Folder}\\{owner.Name}");
                    }
                }
                catch (Exception)
                {
                }
                finally
                {
                    ReleaseComObject(task);
                    ReleaseComObject(folder);
                }
            }
        }
        catch (Exception)
        {
        }
        finally
        {
            ReleaseComObject(service);
        }

        return running;
    }

    private static void ReleaseComObject(object? value)
    {
        if (!OperatingSystem.IsWindows())
        {
            return;
        }

        if (value is not null && Marshal.IsComObject(value))
        {
            Marshal.FinalReleaseComObject(value);
        }
    }

    private sealed record ScheduledTaskOwner(string Folder, string Name);
}

internal readonly record struct HardwareProcessCandidate(
    string Name,
    int ProcessId);

public sealed record HardwareProcessConflict(
    string ProcessName,
    int? ProcessId,
    string? ScheduledTaskPath = null);
