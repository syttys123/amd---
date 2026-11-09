using AmdMobilePower.Core.Contracts;

string pipeName = WorkerProtocol.DefaultPipeName;
for (int index = 0; index < args.Length - 1; index++)
{
    if (args[index] == "--pipe-name")
    {
        pipeName = args[index + 1];
    }
}

using CancellationTokenSource shutdown = new();
Console.CancelKeyPress += delegate (object? sender, ConsoleCancelEventArgs eventArgs)
{
    eventArgs.Cancel = true;
    shutdown.Cancel();
};

using WorkerServer server = new(pipeName);
Console.WriteLine($"AMD Mobile Power worker listening on {pipeName}");
await server.RunAsync(shutdown.Token);
