using System.Diagnostics;
using System.IO.Pipes;
using System.Reflection;
using System.Text;
using System.Text.Json;
using AmdMobilePower.Core.Contracts;
using AmdMobilePower.Core.Hardware;
using AmdMobilePower.Core.Models;
using AmdMobilePower.Core.Profiles;
using AmdMobilePower.Core.Validation;

public sealed class WorkerServer : IDisposable, IAsyncDisposable
{
    private readonly string _pipeName;
    private readonly DateTimeOffset _startedAt;
    private readonly string _workerVersion;
    private readonly IRyzenPowerAdapter? _adapter;
    private readonly IReadOnlyList<PlatformProfile> _profiles;
    private bool _hardwareInitialized;

    public WorkerServer(
        string pipeName = WorkerProtocol.DefaultPipeName,
        DateTimeOffset? startedAt = null,
        IRyzenPowerAdapter? adapter = null,
        IReadOnlyList<PlatformProfile>? profiles = null)
    {
        _pipeName = pipeName;
        _startedAt = startedAt ?? DateTimeOffset.UtcNow;
        _workerVersion = Assembly.GetExecutingAssembly().GetName().Version?.ToString() ?? "0.0.0";
        _adapter = adapter;
        _profiles = profiles ?? Array.Empty<PlatformProfile>();
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
        DisposeAsync().AsTask().GetAwaiter().GetResult();
    }

    public async ValueTask DisposeAsync()
    {
        if (_adapter is not null)
        {
            await _adapter.DisposeAsync().ConfigureAwait(false);
        }
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
        WorkerRequest? request = null;
        try
        {
            request = string.IsNullOrWhiteSpace(requestJson)
                ? null
                : JsonSerializer.Deserialize<WorkerRequest>(requestJson, WorkerProtocol.JsonOptions);
            response = await HandleRequestAsync(request, cancellationToken).ConfigureAwait(false);
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
                request?.RequestId ?? string.Empty,
                WorkerErrorCodes.InternalError,
                error.Message);
        }

        string responseJson = JsonSerializer.Serialize(response, WorkerProtocol.JsonOptions);
        await writer.WriteLineAsync(responseJson.AsMemory(), cancellationToken).ConfigureAwait(false);
    }

    private async Task<WorkerResponse> HandleRequestAsync(
        WorkerRequest? request,
        CancellationToken cancellationToken)
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

        if (request.Command == WorkerCommand.GetHealth)
        {
            return CreateHealthResponse(request.RequestId);
        }

        if (request.Command == WorkerCommand.GetCapabilities)
        {
            return await CreateCapabilityResponseAsync(request.RequestId, cancellationToken)
                .ConfigureAwait(false);
        }

        if (request.Command == WorkerCommand.GetSnapshot)
        {
            return await CreateSnapshotResponseAsync(request.RequestId, cancellationToken)
                .ConfigureAwait(false);
        }

        if (request.Command == WorkerCommand.ApplyTarget)
        {
            return await CreateApplyTargetResponseAsync(request, cancellationToken)
                .ConfigureAwait(false);
        }

        return WorkerProtocol.CreateError(
            request.RequestId,
            WorkerErrorCodes.UnsupportedCommand,
            $"Command {request.Command} is not available yet.");
    }

    private WorkerResponse CreateHealthResponse(string requestId)
    {
        using Process process = Process.GetCurrentProcess();
        WorkerHealth health = new(
            Status: "ok",
            ProtocolVersion: WorkerProtocol.CurrentVersion,
            WorkerVersion: _workerVersion,
            ProcessId: process.Id,
            StartedAt: _startedAt,
            UptimeSeconds: Math.Max(0, (DateTimeOffset.UtcNow - _startedAt).TotalSeconds),
            HardwareInitialized: _hardwareInitialized);
        return WorkerProtocol.CreateSuccess(requestId, health);
    }

    private async Task<WorkerResponse> CreateCapabilityResponseAsync(
        string requestId,
        CancellationToken cancellationToken)
    {
        if (_adapter is null)
        {
            return WorkerProtocol.CreateError(
                requestId,
                WorkerErrorCodes.WorkerUnavailable,
                "No hardware adapter is configured.");
        }

        PlatformCapability platform = await _adapter.ProbeAsync(cancellationToken).ConfigureAwait(false);
        _hardwareInitialized = platform.IsSupported;
        PlatformProfile? profile = ProfileRepository.FindBestMatch(_profiles, platform.Cpu);
        return WorkerProtocol.CreateSuccess(
            requestId,
            new WorkerCapabilitySnapshot(platform, profile));
    }

    private async Task<WorkerResponse> CreateSnapshotResponseAsync(
        string requestId,
        CancellationToken cancellationToken)
    {
        if (_adapter is null)
        {
            return WorkerProtocol.CreateError(
                requestId,
                WorkerErrorCodes.WorkerUnavailable,
                "No hardware adapter is configured.");
        }

        PlatformCapability platform = await _adapter.ProbeAsync(cancellationToken).ConfigureAwait(false);
        _hardwareInitialized = platform.IsSupported;
        PlatformProfile? profile = ProfileRepository.FindBestMatch(_profiles, platform.Cpu);
        TelemetrySnapshot telemetry = platform.IsSupported
            ? await _adapter.RefreshTelemetryAsync(cancellationToken).ConfigureAwait(false)
            : new TelemetrySnapshot();

        return WorkerProtocol.CreateSuccess(
            requestId,
            new WorkerSnapshot(platform, profile, telemetry));
    }

    private async Task<WorkerResponse> CreateApplyTargetResponseAsync(
        WorkerRequest request,
        CancellationToken cancellationToken)
    {
        if (_adapter is null)
        {
            return WorkerProtocol.CreateError(
                request.RequestId,
                WorkerErrorCodes.WorkerUnavailable,
                "No hardware adapter is configured.");
        }

        ApplyTargetRequest? payload;
        try
        {
            payload = request.Payload?.Deserialize<ApplyTargetRequest>(WorkerProtocol.JsonOptions);
        }
        catch (JsonException error)
        {
            return WorkerProtocol.CreateError(
                request.RequestId,
                WorkerErrorCodes.InvalidRequest,
                $"Invalid applyTarget payload: {error.Message}");
        }

        if (payload is null)
        {
            return WorkerProtocol.CreateError(
                request.RequestId,
                WorkerErrorCodes.InvalidRequest,
                "applyTarget requires a target payload.");
        }

        PlatformCapability platform = await _adapter.ProbeAsync(cancellationToken).ConfigureAwait(false);
        _hardwareInitialized = platform.IsSupported;
        if (!platform.IsSupported)
        {
            return WorkerProtocol.CreateError(
                request.RequestId,
                WorkerErrorCodes.UnsupportedPlatform,
                platform.UnsupportedReason ?? "The platform does not support power-limit writes.",
                platform);
        }

        PowerLimitTargetValidationResult validation =
            PowerLimitTargetValidator.Validate(payload.Target, platform.Limits);
        if (!validation.IsValid)
        {
            return WorkerProtocol.CreateError(
                request.RequestId,
                WorkerErrorCodes.InvalidTarget,
                validation.Error ?? "The target power limits are invalid.");
        }

        PlatformProfile? profile = ProfileRepository.FindBestMatch(_profiles, platform.Cpu);
        string? profileError = ValidateAgainstProfile(payload.Target, profile);
        if (profileError is not null)
        {
            return WorkerProtocol.CreateError(
                request.RequestId,
                WorkerErrorCodes.InvalidTarget,
                profileError);
        }

        PowerLimitApplicationResult result = await _adapter
            .ApplyTargetAsync(payload.Target, cancellationToken)
            .ConfigureAwait(false);
        if (result.IsSuccessful)
        {
            return WorkerProtocol.CreateSuccess(request.RequestId, result);
        }

        string errorCode = result.RestoreAttempted && !result.RestoredPreviousLimits
            ? WorkerErrorCodes.HardwareRestoreFailed
            : WorkerErrorCodes.HardwareWriteFailed;
        return WorkerProtocol.CreateError(
            request.RequestId,
            errorCode,
            result.Error ?? "The power-limit write did not complete successfully.",
            result);
    }

    private static string? ValidateAgainstProfile(
        PowerLimitTarget target,
        PlatformProfile? profile)
    {
        if (profile is null)
        {
            return null;
        }

        int minimum = Math.Min(target.StapmWatts, Math.Min(target.FastWatts, target.SlowWatts));
        int maximum = target.MaximumWatts;
        if (minimum < profile.MinimumWatts || maximum > profile.MaximumWatts)
        {
            return
                $"Target values must be between {profile.MinimumWatts}W and " +
                $"{profile.MaximumWatts}W for profile {profile.Id}.";
        }

        return null;
    }
}

