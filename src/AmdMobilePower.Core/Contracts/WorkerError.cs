namespace AmdMobilePower.Core.Contracts;

public sealed record WorkerError(string Code, string Message);

public static class WorkerErrorCodes
{
    public const string InvalidRequest = "invalid_request";
    public const string UnsupportedCommand = "unsupported_command";
    public const string InternalError = "internal_error";
    public const string WorkerUnavailable = "worker_unavailable";
    public const string UnsupportedPlatform = "unsupported_platform";
    public const string InvalidTarget = "invalid_target";
    public const string HardwareWritesDisabled = "hardware_writes_disabled";
    public const string HardwareWriteFailed = "hardware_write_failed";
    public const string HardwareRestoreFailed = "hardware_restore_failed";
}

