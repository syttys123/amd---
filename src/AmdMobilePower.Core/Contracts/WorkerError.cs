namespace AmdMobilePower.Core.Contracts;

public sealed record WorkerError(string Code, string Message);

public static class WorkerErrorCodes
{
    public const string InvalidRequest = "invalid_request";
    public const string UnsupportedCommand = "unsupported_command";
    public const string InternalError = "internal_error";
    public const string WorkerUnavailable = "worker_unavailable";
}

