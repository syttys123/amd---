using System.Text.Json;
using System.Text.Json.Serialization;

namespace AmdMobilePower.Core.Contracts;

public static class WorkerProtocol
{
    public const int CurrentVersion = 1;
    public const string DefaultPipeName = "AmdMobilePower.Worker.v1";

    public static JsonSerializerOptions JsonOptions { get; } = CreateJsonOptions();

    public static WorkerResponse CreateSuccess(
        string requestId,
        object? payload = null)
    {
        JsonElement? payloadElement = null;
        if (payload is not null)
        {
            payloadElement = JsonSerializer.SerializeToElement(payload, payload.GetType(), JsonOptions);
        }

        return new WorkerResponse
        {
            RequestId = requestId,
            Success = true,
            Payload = payloadElement
        };
    }

    public static WorkerResponse CreateError(
        string requestId,
        string code,
        string message,
        object? payload = null)
    {
        JsonElement? payloadElement = null;
        if (payload is not null)
        {
            payloadElement = JsonSerializer.SerializeToElement(payload, payload.GetType(), JsonOptions);
        }

        return new WorkerResponse
        {
            RequestId = requestId,
            Success = false,
            Payload = payloadElement,
            Error = new WorkerError(code, message)
        };
    }

    private static JsonSerializerOptions CreateJsonOptions()
    {
        JsonSerializerOptions options = new(JsonSerializerDefaults.Web)
        {
            WriteIndented = false
        };
        options.Converters.Add(new JsonStringEnumConverter(JsonNamingPolicy.CamelCase));
        return options;
    }
}

