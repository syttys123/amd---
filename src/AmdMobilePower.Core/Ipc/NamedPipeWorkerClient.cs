using System.IO.Pipes;
using System.Text;
using System.Text.Json;
using AmdMobilePower.Core.Contracts;
using AmdMobilePower.Core.Models;

namespace AmdMobilePower.Core.Ipc;

public sealed class NamedPipeWorkerClient
{
    private readonly string _pipeName;

    public NamedPipeWorkerClient(string pipeName = WorkerProtocol.DefaultPipeName)
    {
        _pipeName = pipeName;
    }

    public async Task<WorkerHealth> GetHealthAsync(
        TimeSpan timeout,
        CancellationToken cancellationToken = default)
    {
        WorkerResponse response = await SendAsync(
            new WorkerRequest
            {
                RequestId = Guid.NewGuid().ToString("N"),
                Command = WorkerCommand.GetHealth
            },
            timeout,
            cancellationToken).ConfigureAwait(false);

        if (!response.Success || response.Payload is not { } payload)
        {
            string message = response.Error?.Message ?? "Worker returned no health payload.";
            throw new InvalidOperationException(message);
        }

        return payload.Deserialize<WorkerHealth>(WorkerProtocol.JsonOptions)
            ?? throw new InvalidOperationException("Worker returned an invalid health payload.");
    }

    public async Task<WorkerCapabilitySnapshot> GetCapabilitiesAsync(
        TimeSpan timeout,
        CancellationToken cancellationToken = default)
    {
        WorkerResponse response = await SendAsync(
            new WorkerRequest
            {
                RequestId = Guid.NewGuid().ToString("N"),
                Command = WorkerCommand.GetCapabilities
            },
            timeout,
            cancellationToken).ConfigureAwait(false);

        if (!response.Success || response.Payload is not { } payload)
        {
            string message = response.Error?.Message ?? "Worker returned no capability payload.";
            throw new InvalidOperationException(message);
        }

        return payload.Deserialize<WorkerCapabilitySnapshot>(WorkerProtocol.JsonOptions)
            ?? throw new InvalidOperationException("Worker returned an invalid capability payload.");
    }

    public async Task<WorkerSnapshot> GetSnapshotAsync(
        TimeSpan timeout,
        CancellationToken cancellationToken = default)
    {
        WorkerResponse response = await SendAsync(
            new WorkerRequest
            {
                RequestId = Guid.NewGuid().ToString("N"),
                Command = WorkerCommand.GetSnapshot
            },
            timeout,
            cancellationToken).ConfigureAwait(false);

        if (!response.Success || response.Payload is not { } payload)
        {
            string message = response.Error?.Message ?? "Worker returned no snapshot payload.";
            throw new InvalidOperationException(message);
        }

        return payload.Deserialize<WorkerSnapshot>(WorkerProtocol.JsonOptions)
            ?? throw new InvalidOperationException("Worker returned an invalid snapshot payload.");
    }

    public async Task<PowerLimitApplicationResult> ApplyTargetAsync(
        PowerLimitTarget target,
        TimeSpan timeout,
        CancellationToken cancellationToken = default)
    {
        ApplyTargetRequest requestPayload = new(target);
        WorkerResponse response = await SendAsync(
            new WorkerRequest
            {
                RequestId = Guid.NewGuid().ToString("N"),
                Command = WorkerCommand.ApplyTarget,
                Payload = JsonSerializer.SerializeToElement(
                    requestPayload,
                    WorkerProtocol.JsonOptions)
            },
            timeout,
            cancellationToken).ConfigureAwait(false);

        if (!response.Success || response.Payload is not { } payload)
        {
            string message = response.Error?.Message ?? "Worker returned no application payload.";
            throw new InvalidOperationException(message);
        }

        return payload.Deserialize<PowerLimitApplicationResult>(WorkerProtocol.JsonOptions)
            ?? throw new InvalidOperationException("Worker returned an invalid application payload.");
    }

    public async Task<WorkerResponse> SendAsync(
        WorkerRequest request,
        TimeSpan timeout,
        CancellationToken cancellationToken = default)
    {
        using CancellationTokenSource timeoutSource = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
        timeoutSource.CancelAfter(timeout);

        using NamedPipeClientStream client = new(
            ".",
            _pipeName,
            PipeDirection.InOut,
            PipeOptions.Asynchronous);

        await client.ConnectAsync(timeoutSource.Token).ConfigureAwait(false);

        using StreamWriter writer = new(
            client,
            new UTF8Encoding(encoderShouldEmitUTF8Identifier: false),
            bufferSize: 1024,
            leaveOpen: true)
        {
            AutoFlush = true,
            NewLine = "\n"
        };
        using StreamReader reader = new(
            client,
            Encoding.UTF8,
            detectEncodingFromByteOrderMarks: false,
            bufferSize: 1024,
            leaveOpen: true);

        string requestJson = JsonSerializer.Serialize(request, WorkerProtocol.JsonOptions);
        await writer.WriteLineAsync(requestJson.AsMemory(), timeoutSource.Token).ConfigureAwait(false);

        string? responseJson = await reader.ReadLineAsync(timeoutSource.Token).ConfigureAwait(false);
        if (string.IsNullOrWhiteSpace(responseJson))
        {
            throw new IOException("Worker closed the pipe without a response.");
        }

        return JsonSerializer.Deserialize<WorkerResponse>(responseJson, WorkerProtocol.JsonOptions)
            ?? throw new InvalidOperationException("Worker returned an invalid response.");
    }
}

