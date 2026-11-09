using System.Diagnostics;
using System.IO.Pipes;
using System.Reflection;
using System.Text;
using System.Text.Json;
using AmdMobilePower.Core.Contracts;

public sealed class WorkerServer : IDisposable
{
    private readonly string _pipeName;
    private readonly DateTimeOffset _startedAt;
    private readonly string _workerVersion;

    public WorkerServer(
        string pipeName = WorkerProtocol.DefaultPipeName,
        DateTimeOffset? startedAt = null)
    {
        _pipeName = pipeName;
        _startedAt = startedAt ?? DateTimeOffset.UtcNow;
        _workerVersion = Assembly.GetExecutingAssembly().GetName().Version?.ToString() ?? "0.0.0";
    }

    public async Task RunAsync(CancellationToken cancellationToken)
    {
        try
        {
            while (!cancellationToken.IsCancellationRequested)
            {
                using NamedPipeServerStream server = new(
                    _pipeName,
                    PipeDirection.InOut,
                    maxNumberOfServerInstances: 1,
                    PipeTransmissionMode.Byte,
                    PipeOptions.Asynchronous | PipeOptions.CurrentUserOnly);

                await server.WaitForConnectionAsync(cancellationToken).ConfigureAwait(false);
                await HandleClientAsync(server, cancellationToken).ConfigureAwait(false);
            }
        }
        catch (OperationCanceledException) when (cancellationToken.IsCancellationRequested)
        {
        }
    }

    public void Dispose()
    {
    }

    private async Task HandleClientAsync(
        NamedPipeServerStream server,
        CancellationToken cancellationToken)
    {
        using StreamReader reader = new(
            server,
            Encoding.UTF8,
            detectEncodingFromByteOrderMarks: false,
            bufferSize: 1024,
            leaveOpen: true);
        using StreamWriter writer = new(
            server,
            new UTF8Encoding(encoderShouldEmitUTF8Identifier: false),
            bufferSize: 1024,
            leaveOpen: true)
        {
            AutoFlush = true,
            NewLine = "\n"
        };

        string? requestJson = await reader.ReadLineAsync(cancellationToken).ConfigureAwait(false);
        WorkerResponse response;
        try
        {
            WorkerRequest? request = string.IsNullOrWhiteSpace(requestJson)
                ? null
                : JsonSerializer.Deserialize<WorkerRequest>(requestJson, WorkerProtocol.JsonOptions);
            response = HandleRequest(request);
        }
        catch (JsonException error)
        {
            response = WorkerProtocol.CreateError(
                string.Empty,
                WorkerErrorCodes.InvalidRequest,
                $"Invalid JSON request: {error.Message}");
        }
        catch (Exception error)
        {
            response = WorkerProtocol.CreateError(
                string.Empty,
                WorkerErrorCodes.InternalError,
                error.Message);
        }

        string responseJson = JsonSerializer.Serialize(response, WorkerProtocol.JsonOptions);
        await writer.WriteLineAsync(responseJson.AsMemory(), cancellationToken).ConfigureAwait(false);
    }

    private WorkerResponse HandleRequest(WorkerRequest? request)
    {
        if (request is null)
        {
            return WorkerProtocol.CreateError(
                string.Empty,
                WorkerErrorCodes.InvalidRequest,
                "Request body is required.");
        }

        if (request.ProtocolVersion != WorkerProtocol.CurrentVersion)
        {
            return WorkerProtocol.CreateError(
                request.RequestId,
                WorkerErrorCodes.InvalidRequest,
                $"Unsupported protocol version {request.ProtocolVersion}.");
        }

        if (string.IsNullOrWhiteSpace(request.RequestId))
        {
            return WorkerProtocol.CreateError(
                string.Empty,
                WorkerErrorCodes.InvalidRequest,
                "RequestId is required.");
        }

        if (request.Command != WorkerCommand.GetHealth)
        {
            return WorkerProtocol.CreateError(
                request.RequestId,
                WorkerErrorCodes.UnsupportedCommand,
                $"Command {request.Command} is not available yet.");
        }

        using Process process = Process.GetCurrentProcess();
        WorkerHealth health = new(
            Status: "ok",
            ProtocolVersion: WorkerProtocol.CurrentVersion,
            WorkerVersion: _workerVersion,
            ProcessId: process.Id,
            StartedAt: _startedAt,
            UptimeSeconds: Math.Max(0, (DateTimeOffset.UtcNow - _startedAt).TotalSeconds),
            HardwareInitialized: false);
        return WorkerProtocol.CreateSuccess(request.RequestId, health);
    }
}

