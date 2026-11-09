using System.Text.Json;

namespace AmdMobilePower.Core.Contracts;

public sealed record WorkerResponse
{
    public int ProtocolVersion { get; init; } = WorkerProtocol.CurrentVersion;
    public required string RequestId { get; init; }
    public required bool Success { get; init; }
    public JsonElement? Payload { get; init; }
    public WorkerError? Error { get; init; }
}

