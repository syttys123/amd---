using System.Diagnostics;
using System.IO.Pipes;
using System.Reflection;
using System.Runtime.InteropServices;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using AmdMobilePower.Core.Contracts;
using AmdMobilePower.Core.Diagnostics;
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
    private readonly bool _allowHardwareWrites;
    private readonly TimeSpan _policyPollInterval;
    private readonly DiagnosticFileLog? _workerLog;
    private readonly DiagnosticFileLog? _guiLog;
    private readonly object _policySync = new();
    private PowerPolicySettings? _powerPolicy;
    private PowerPolicyState _powerPolicyState = new(
        null,
        null,
        null,
        null,
        null,
        null);
    private PowerLineState? _lastAppliedPowerLine;
    private PowerLimitTarget? _lastAppliedPolicyTarget;
    private PowerLineState? _lastAttemptPowerLine;
    private PowerLimitTarget? _lastAttemptPolicyTarget;
    private DateTimeOffset? _lastPolicyFailureAt;
    private bool _hardwareInitialized;

    public WorkerServer(
        string pipeName = WorkerProtocol.DefaultPipeName,
        DateTimeOffset? startedAt = null,
        IRyzenPowerAdapter? adapter = null,
        IReadOnlyList<PlatformProfile>? profiles = null,
        bool allowHardwareWrites = false,
        TimeSpan? policyPollInterval = null,
        DiagnosticFileLog? workerLog = null,
        DiagnosticFileLog? guiLog = null)
    {
        _pipeName = pipeName;
        _startedAt = startedAt ?? DateTimeOffset.UtcNow;
        _workerVersion = Assembly
            .GetExecutingAssembly()
            .GetCustomAttribute<AssemblyInformationalVersionAttribute>()
            ?.InformationalVersion
            .Split('+', 2)[0] ??
            Assembly.GetExecutingAssembly().GetName().Version?.ToString() ??
            "0.0.0";
        _adapter = adapter;
        _profiles = profiles ?? Array.Empty<PlatformProfile>();
        _allowHardwareWrites = allowHardwareWrites;
        _policyPollInterval = policyPollInterval ?? TimeSpan.FromSeconds(1);
        _workerLog = workerLog;
        _guiLog = guiLog;
    }

    public async Task RunAsync(CancellationToken cancellationToken)
    {
        using CancellationTokenSource monitorShutdown =
            CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
        Task? monitorTask = _allowHardwareWrites
            ? MonitorPowerPolicyAsync(monitorShutdown.Token)
            : null;
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
                try
                {
                    await HandleClientAsync(server, cancellationToken).ConfigureAwait(false);
                }
                catch (IOException) when (!cancellationToken.IsCancellationRequested)
                {
                    // A probe or UI can disconnect before completing a frame.
                    // Keep the next pipe instance available for the next client.
                }
            }
        }
        catch (OperationCanceledException) when (cancellationToken.IsCancellationRequested)
        {
        }
        finally
        {
            monitorShutdown.Cancel();
            if (monitorTask is not null)
            {
                try
                {
                    await monitorTask.ConfigureAwait(false);
                }
                catch (OperationCanceledException) when (monitorShutdown.IsCancellationRequested)
                {
                }
            }
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
            _workerLog?.Error(
                $"Request {request?.RequestId ?? "<unknown>"} failed.",
                error);
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

        if (request.Command == WorkerCommand.GetPowerPolicy)
        {
            return WorkerProtocol.CreateSuccess(request.RequestId, GetPowerPolicyState());
        }

        if (request.Command == WorkerCommand.SetPowerPolicy)
        {
            return await CreateSetPowerPolicyResponseAsync(request, cancellationToken)
                .ConfigureAwait(false);
        }

        if (request.Command == WorkerCommand.ExportDiagnostics)
        {
            return await CreateDiagnosticsResponseAsync(request.RequestId, cancellationToken)
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
        if (!_allowHardwareWrites)
        {
            return WorkerProtocol.CreateError(
                request.RequestId,
                WorkerErrorCodes.HardwareWritesDisabled,
                "Hardware power-limit writes are disabled for this worker.");
        }

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
            _workerLog?.Info(
                $"Applied target {payload.Target.StapmWatts}/" +
                $"{payload.Target.FastWatts}/{payload.Target.SlowWatts} W.");
            return WorkerProtocol.CreateSuccess(request.RequestId, result);
        }

        _workerLog?.Error(
            $"Power-limit apply failed: {result.Error ?? "unknown error"}");
        string errorCode = result.RestoreAttempted && !result.RestoredPreviousLimits
            ? WorkerErrorCodes.HardwareRestoreFailed
            : WorkerErrorCodes.HardwareWriteFailed;
        return WorkerProtocol.CreateError(
            request.RequestId,
            errorCode,
            result.Error ?? "The power-limit write did not complete successfully.",
            result);
    }

    private async Task<WorkerResponse> CreateSetPowerPolicyResponseAsync(
        WorkerRequest request,
        CancellationToken cancellationToken)
    {
        if (!_allowHardwareWrites)
        {
            return WorkerProtocol.CreateError(
                request.RequestId,
                WorkerErrorCodes.HardwareWritesDisabled,
                "Hardware power-limit writes are disabled for this worker.");
        }

        if (_adapter is null)
        {
            return WorkerProtocol.CreateError(
                request.RequestId,
                WorkerErrorCodes.WorkerUnavailable,
                "No hardware adapter is configured.");
        }

        SetPowerPolicyRequest? payload;
        try
        {
            payload = request.Payload?.Deserialize<SetPowerPolicyRequest>(
                WorkerProtocol.JsonOptions);
        }
        catch (JsonException error)
        {
            return WorkerProtocol.CreateError(
                request.RequestId,
                WorkerErrorCodes.InvalidRequest,
                $"Invalid setPowerPolicy payload: {error.Message}");
        }

        if (payload is null)
        {
            return WorkerProtocol.CreateError(
                request.RequestId,
                WorkerErrorCodes.InvalidRequest,
                "setPowerPolicy requires a settings payload.");
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

        PlatformProfile? profile = ProfileRepository.FindBestMatch(_profiles, platform.Cpu);
        string? validationError = ValidatePowerPolicyTarget(
            payload.Settings.BatteryTarget,
            platform,
            profile);
        validationError ??= ValidatePowerPolicyTarget(
            payload.Settings.AcTarget,
            platform,
            profile);
        if (validationError is not null)
        {
            return WorkerProtocol.CreateError(
                request.RequestId,
                WorkerErrorCodes.InvalidTarget,
                validationError);
        }

        lock (_policySync)
        {
            _powerPolicy = payload.Settings;
            _lastAppliedPowerLine = null;
            _lastAppliedPolicyTarget = null;
            _lastAttemptPowerLine = null;
            _lastAttemptPolicyTarget = null;
            _lastPolicyFailureAt = null;
            _powerPolicyState = new PowerPolicyState(
                payload.Settings,
                null,
                null,
                null,
                null,
                null);
        }

        return WorkerProtocol.CreateSuccess(request.RequestId, GetPowerPolicyState());
    }

    private static string? ValidatePowerPolicyTarget(
        PowerLimitTarget target,
        PlatformCapability platform,
        PlatformProfile? profile)
    {
        PowerLimitTargetValidationResult capabilityValidation =
            PowerLimitTargetValidator.Validate(target, platform.Limits);
        return capabilityValidation.IsValid
            ? ValidateAgainstProfile(target, profile)
            : capabilityValidation.Error;
    }

    private PowerPolicyState GetPowerPolicyState()
    {
        lock (_policySync)
        {
            return _powerPolicyState;
        }
    }

    private async Task MonitorPowerPolicyAsync(CancellationToken cancellationToken)
    {
        while (!cancellationToken.IsCancellationRequested)
        {
            PowerPolicySettings? settings;
            lock (_policySync)
            {
                settings = _powerPolicy;
            }

            if (settings is null || !settings.Enabled || _adapter is null)
            {
                await Task.Delay(_policyPollInterval, cancellationToken).ConfigureAwait(false);
                continue;
            }

            try
            {
                PlatformCapability platform = await _adapter
                    .ProbeAsync(cancellationToken)
                    .ConfigureAwait(false);
                _hardwareInitialized = platform.IsSupported;
                if (!platform.IsSupported)
                {
                    RecordPolicyFailure(
                        null,
                        null,
                        platform.UnsupportedReason ?? "Unsupported platform.");
                    await Task.Delay(_policyPollInterval, cancellationToken).ConfigureAwait(false);
                    continue;
                }

                TelemetrySnapshot telemetry = await _adapter
                    .RefreshTelemetryAsync(cancellationToken)
                    .ConfigureAwait(false);
                PowerLineState powerLine = telemetry.PowerLine;
                if (powerLine == PowerLineState.Unknown)
                {
                    RecordPolicyFailure(null, null, "Power-line state is unknown.");
                    await Task.Delay(_policyPollInterval, cancellationToken).ConfigureAwait(false);
                    continue;
                }

                PowerLimitTarget target = powerLine == PowerLineState.Ac
                    ? settings.AcTarget
                    : settings.BatteryTarget;
                if (!ShouldAttemptPolicyApply(powerLine, target))
                {
                    await Task.Delay(_policyPollInterval, cancellationToken).ConfigureAwait(false);
                    continue;
                }

                PowerLimitApplicationResult result = await _adapter
                    .ApplyTargetAsync(target, cancellationToken)
                    .ConfigureAwait(false);
                RecordPolicyAttempt(
                    powerLine,
                    target,
                    result.IsSuccessful,
                    result.Error);
            }
            catch (OperationCanceledException) when (cancellationToken.IsCancellationRequested)
            {
                break;
            }
            catch (Exception error)
            {
                RecordPolicyFailure(
                    _lastAttemptPowerLine,
                    _lastAttemptPolicyTarget,
                    error.Message);
            }

            await Task.Delay(_policyPollInterval, cancellationToken).ConfigureAwait(false);
        }
    }

    private bool ShouldAttemptPolicyApply(
        PowerLineState powerLine,
        PowerLimitTarget target)
    {
        lock (_policySync)
        {
            if (_lastAppliedPowerLine == powerLine &&
                _lastAppliedPolicyTarget == target)
            {
                _powerPolicyState = _powerPolicyState with
                {
                    LastObservedPowerLine = powerLine
                };
                return false;
            }

            DateTimeOffset now = DateTimeOffset.Now;
            bool retryingSameFailure =
                _lastAttemptPowerLine == powerLine &&
                _lastAttemptPolicyTarget == target &&
                _lastPolicyFailureAt is { } lastFailure &&
                now - lastFailure < TimeSpan.FromSeconds(5);
            if (retryingSameFailure)
            {
                _powerPolicyState = _powerPolicyState with
                {
                    LastObservedPowerLine = powerLine
                };
                return false;
            }

            _lastAttemptPowerLine = powerLine;
            _lastAttemptPolicyTarget = target;
            _powerPolicyState = _powerPolicyState with
            {
                LastObservedPowerLine = powerLine
            };
            return true;
        }
    }

    private void RecordPolicyAttempt(
        PowerLineState powerLine,
        PowerLimitTarget target,
        bool succeeded,
        string? error)
    {
        lock (_policySync)
        {
            if (succeeded)
            {
                _lastAppliedPowerLine = powerLine;
                _lastAppliedPolicyTarget = target;
                _lastPolicyFailureAt = null;
            }
            else
            {
                _lastPolicyFailureAt = DateTimeOffset.Now;
            }

            _powerPolicyState = new PowerPolicyState(
                _powerPolicy,
                powerLine,
                succeeded ? target : _lastAppliedPolicyTarget,
                DateTimeOffset.Now,
                succeeded,
                error);
        }
    }

    private void RecordPolicyFailure(
        PowerLineState? powerLine,
        PowerLimitTarget? target,
        string error)
    {
        lock (_policySync)
        {
            _lastPolicyFailureAt = DateTimeOffset.Now;
            _powerPolicyState = new PowerPolicyState(
                _powerPolicy,
                powerLine,
                _lastAppliedPolicyTarget,
                DateTimeOffset.Now,
                false,
                error);
        }
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

    private async Task<WorkerResponse> CreateDiagnosticsResponseAsync(
        string requestId,
        CancellationToken cancellationToken)
    {
        using Process process = Process.GetCurrentProcess();
        PlatformCapability? platform = null;
        TelemetrySnapshot? telemetry = null;
        PlatformProfile? profile = null;
        List<string> notes = new(4);

        if (_adapter is null)
        {
            notes.Add("No hardware adapter is configured.");
        }
        else
        {
            try
            {
                platform = await _adapter.ProbeAsync(cancellationToken).ConfigureAwait(false);
                _hardwareInitialized = platform.IsSupported;
                profile = ProfileRepository.FindBestMatch(_profiles, platform.Cpu);
                if (platform.IsSupported)
                {
                    telemetry = await _adapter
                        .RefreshTelemetryAsync(cancellationToken)
                        .ConfigureAwait(false);
                }
                else if (!string.IsNullOrWhiteSpace(platform.UnsupportedReason))
                {
                    notes.Add(platform.UnsupportedReason);
                }
            }
            catch (Exception error)
            {
                notes.Add($"Hardware diagnostics failed: {error.Message}");
            }
        }

        string[] runtimeFiles =
        [
            "AmdMobilePower.Worker.exe",
            "libryzenadj.dll",
            "WinRing0x64.dll",
            "WinRing0x64.sys",
            "inpoutx64.dll"
        ];
        IReadOnlyList<RuntimeFileDiagnostic> fileDiagnostics =
            runtimeFiles.Select(InspectRuntimeFile).ToArray();

        WorkerDiagnostics diagnostics = new(
            GeneratedAt: DateTimeOffset.Now,
            WorkerVersion: _workerVersion,
            ProcessId: process.Id,
            ProcessArchitecture: RuntimeInformation.ProcessArchitecture.ToString(),
            OperatingSystem: RuntimeInformation.OSDescription,
            WorkerDirectory: AppContext.BaseDirectory,
            ProfileCount: _profiles.Count,
            Platform: platform,
            MatchedProfile: profile,
            Telemetry: telemetry,
            RuntimeFiles: fileDiagnostics,
            DiagnosticLogDirectory: _workerLog?.DirectoryPath ?? string.Empty,
            RecentWorkerLogLines: _workerLog?.ReadTail(200) ?? Array.Empty<string>(),
            RecentGuiLogLines: _guiLog?.ReadTail(100) ?? Array.Empty<string>(),
            Notes: notes)
        {
            PipeName = _pipeName,
            HardwareAdapterConfigured = _adapter is not null,
            WriteControlsEnabled = _allowHardwareWrites,
            WorkerExecutableSha256 = fileDiagnostics
                .FirstOrDefault(file => file.Name == "AmdMobilePower.Worker.exe")
                ?.Sha256,
            Profiles = _profiles
                .Select(profile => new PlatformProfileDiagnostic(
                    profile.Id,
                    profile.DisplayName,
                    profile.CpuFamilyPatterns,
                    profile.ProcessorNamePatterns,
                    profile.PmTablePatterns,
                    profile.MinimumWatts,
                    profile.MaximumWatts,
                    profile.DefaultWatts,
                    profile.SupportsStapm,
                    profile.SupportsFast,
                    profile.SupportsSlow))
                .ToArray()
        };
        _workerLog?.Info("Diagnostics export generated.");
        return WorkerProtocol.CreateSuccess(requestId, diagnostics);
    }

    private static RuntimeFileDiagnostic InspectRuntimeFile(string fileName)
    {
        string path = Path.Combine(AppContext.BaseDirectory, fileName);
        try
        {
            if (!File.Exists(path))
            {
                return new RuntimeFileDiagnostic(fileName, false, null, null, null);
            }

            using FileStream stream = File.OpenRead(path);
            string sha256 = Convert.ToHexString(SHA256.HashData(stream)).ToLowerInvariant();
            return new RuntimeFileDiagnostic(
                fileName,
                true,
                stream.Length,
                sha256,
                null);
        }
        catch (Exception error)
        {
            return new RuntimeFileDiagnostic(
                fileName,
                false,
                null,
                null,
                error.Message);
        }
    }
}

