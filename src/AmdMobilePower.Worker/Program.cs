using AmdMobilePower.Core.Contracts;
using AmdMobilePower.Core.Hardware;
using AmdMobilePower.Core.Profiles;
using AmdMobilePower.Worker.Hardware;

string pipeName = WorkerProtocol.DefaultPipeName;
bool enableHardware = false;
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
}

IRyzenPowerAdapter? adapter = null;
if (enableHardware)
{
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

await using WorkerServer server = new(
    pipeName,
    adapter: adapter,
    profiles: profiles);
Console.WriteLine($"AMD Mobile Power worker listening on {pipeName}");
if (enableHardware)
{
    Console.WriteLine("Hardware access is enabled.");
}
await server.RunAsync(shutdown.Token);
