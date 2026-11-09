using AmdMobilePower.Core.Contracts;
using AmdMobilePower.Core.Diagnostics;
using AmdMobilePower.Core.Hardware;
using AmdMobilePower.Core.Profiles;
using AmdMobilePower.Worker.Hardware;

string pipeName = WorkerProtocol.DefaultPipeName;
bool enableHardware = false;
bool enableWrites = false;
string? ryzenAdjDirectory = null;
string? profilesDirectory = null;
for (int index = 0; index < args.Length - 1; index++)
{
    if (args[index] == "--pipe-name")
    {
        pipeName = args[index + 1];
    }
    else if (args[index] == "--ryzenadj-dir")
    {
        ryzenAdjDirectory = args[index + 1];
    }
    else if (args[index] == "--profiles-dir")
    {
        profilesDirectory = args[index + 1];
    }
}
for (int index = 0; index < args.Length; index++)
{
    if (args[index] == "--enable-hardware")
    {
        enableHardware = true;
    }
    else if (args[index] == "--enable-write-controls")
    {
        enableWrites = true;
    }
}

AppDiagnostics.Worker.Info(
    $"Worker starting. Pipe={pipeName}; hardware={enableHardware}; writes={enableWrites}.");
AppDomain.CurrentDomain.UnhandledException += delegate (object sender, UnhandledExceptionEventArgs eventArgs)
{
    Exception? error = eventArgs.ExceptionObject as Exception;
    AppDiagnostics.Worker.Error(
        $"Unhandled worker exception. Terminating={eventArgs.IsTerminating}.",
        error);
};
TaskScheduler.UnobservedTaskException += delegate (object? sender, UnobservedTaskExceptionEventArgs eventArgs)
{
    AppDiagnostics.Worker.Error("Unobserved worker task exception.", eventArgs.Exception);
    eventArgs.SetObserved();
};

IRyzenPowerAdapter? adapter = null;
EventWaitHandle? hardwareOwner = null;
if (enableHardware)
{
    HardwareProcessConflict? conflict = HardwareConflictDetector.FindKnownHardwareOwner();
    if (conflict is not null)
    {
        AppDiagnostics.Worker.Warning(
            $"Hardware access already owned by {FormatHardwareOwner(conflict)}.");
        Console.Error.WriteLine(
            $"Hardware access is already owned by {FormatHardwareOwner(conflict)}.");
        Environment.ExitCode = 3;
        return;
    }

    hardwareOwner = new EventWaitHandle(
        initialState: false,
        EventResetMode.ManualReset,
        @"Local\AmdMobilePower.HardwareOwner.v1",
        out bool ownsHardwareEvent);
    if (!ownsHardwareEvent)
    {
        AppDiagnostics.Worker.Warning(
            "Another AMD Mobile Power worker owns hardware access.");
        hardwareOwner.Dispose();
        hardwareOwner = null;
        Console.Error.WriteLine("Another AMD Mobile Power worker owns hardware access.");
        Environment.ExitCode = 4;
        return;
    }

    ryzenAdjDirectory ??= File.Exists(Path.Combine(AppContext.BaseDirectory, "libryzenadj.dll"))
        ? AppContext.BaseDirectory
        : Path.Combine(Environment.CurrentDirectory, "artifacts", "ryzenadj-runtime");
    ryzenAdjDirectory = Path.GetFullPath(ryzenAdjDirectory);
    Environment.SetEnvironmentVariable(
        "PATH",
        ryzenAdjDirectory + Path.PathSeparator + Environment.GetEnvironmentVariable("PATH"));
    adapter = new RyzenAdjPowerAdapter(ryzenAdjDirectory);
}

profilesDirectory ??= Directory.Exists(Path.Combine(AppContext.BaseDirectory, "profiles"))
    ? Path.Combine(AppContext.BaseDirectory, "profiles")
    : Path.Combine(Environment.CurrentDirectory, "profiles");
IReadOnlyList<PlatformProfile> profiles = ProfileRepository.LoadDirectory(profilesDirectory);

using CancellationTokenSource shutdown = new();
Console.CancelKeyPress += delegate (object? sender, ConsoleCancelEventArgs eventArgs)
{
    eventArgs.Cancel = true;
    shutdown.Cancel();
};

try
{
    await using WorkerServer server = new(
        pipeName,
        adapter: adapter,
        profiles: profiles,
        allowHardwareWrites: enableWrites,
        workerLog: AppDiagnostics.Worker,
        guiLog: AppDiagnostics.Gui,
        requestShutdown: shutdown.Cancel);
    Console.WriteLine($"AMD Mobile Power worker listening on {pipeName}");
    if (enableHardware)
    {
        Console.WriteLine("Hardware access is enabled.");
    }
    if (enableWrites)
    {
        Console.WriteLine("Hardware power-limit writes are enabled.");
    }
    await server.RunAsync(shutdown.Token);
}
finally
{
    AppDiagnostics.Worker.Info($"Worker stopping. ExitCode={Environment.ExitCode}.");
    hardwareOwner?.Dispose();
}

static string FormatHardwareOwner(HardwareProcessConflict conflict)
{
    if (conflict.ScheduledTaskPath is { } taskPath)
    {
        return $"{conflict.ProcessName} scheduled task {taskPath}";
    }

    return conflict.ProcessId is { } processId
        ? $"{conflict.ProcessName} (PID {processId})"
        : conflict.ProcessName;
}
