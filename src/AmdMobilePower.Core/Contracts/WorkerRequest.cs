using System.Text.Json;

namespace AmdMobilePower.Core.Contracts;

public sealed record WorkerRequest
{
    public int ProtocolVersion { get; init; } = WorkerProtocol.CurrentVersion;
    public required string RequestId { get; init; }
    public WorkerCommand Command { get; init; }
    public JsonElement? Payload { get; init; }
}

