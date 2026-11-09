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
        HardwareProcessConflict? legacyWorker = FindLegacyWorkerOwner();
        if (legacyWorker is not null)
        {
            return legacyWorker;
        }

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

        return FindRunningScheduledTaskOwner();
    }

    private static HardwareProcessConflict? FindLegacyWorkerOwner()
    {
        if (!OperatingSystem.IsWindows())
        {
            return null;
        }

        try
        {
            using Mutex mutex = Mutex.OpenExisting(LegacyWorkerMutexName);
            return FindRunningScheduledTaskOwner()
                ?? new HardwareProcessConflict("RyzenAdjPowerWorker", null);
        }
        catch (WaitHandleCannotBeOpenedException)
        {
            return null;
        }
        catch (UnauthorizedAccessException)
        {
            return new HardwareProcessConflict("RyzenAdjPowerWorker", null);
        }
    }

    private static HardwareProcessConflict? FindRunningScheduledTaskOwner()
    {
        if (!OperatingSystem.IsWindows())
        {
            return null;
        }

        Type? serviceType = Type.GetTypeFromProgID("Schedule.Service");
        if (serviceType is null)
        {
            return null;
        }

        object? service = null;
        try
        {
            service = Activator.CreateInstance(serviceType);
            if (service is null)
            {
                return null;
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
                        return new HardwareProcessConflict(
                            owner.Name,
                            null,
                            $"{owner.Folder}\\{owner.Name}");
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

        return null;
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

public sealed record HardwareProcessConflict(
    string ProcessName,
    int? ProcessId,
    string? ScheduledTaskPath = null);
