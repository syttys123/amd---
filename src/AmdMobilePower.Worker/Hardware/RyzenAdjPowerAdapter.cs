using System.Runtime.InteropServices;
using AmdMobilePower.Core.Hardware;
using AmdMobilePower.Core.Models;
using AmdMobilePower.Core.Validation;
using Microsoft.Win32;

namespace AmdMobilePower.Worker.Hardware;

public sealed class RyzenAdjPowerAdapter : IRyzenPowerAdapter
{
    private const double ReadbackToleranceWatts = 0.75;
    private const int MinimumRestoreWatts = 1;
    private const int MaximumRestoreWatts = 200;

    private readonly object _sync = new();
    private readonly IRyzenAdjNativeApi _native;
    private readonly Func<CpuPlatformInfo> _cpuInfoProvider;
    private readonly Func<PowerLineState> _powerLineProvider;
    private IntPtr _ryzenAccess;
    private bool _disposed;

    public RyzenAdjPowerAdapter(string runtimeDirectory)
        : this(
            CreateNativeApi(runtimeDirectory),
            ReadCpuInfo,
            GetPowerLineState)
    {
    }

    internal RyzenAdjPowerAdapter(
        IRyzenAdjNativeApi native,
        Func<CpuPlatformInfo>? cpuInfoProvider = null,
        Func<PowerLineState>? powerLineProvider = null)
    {
        _native = native;
        _cpuInfoProvider = cpuInfoProvider ?? ReadCpuInfo;
        _powerLineProvider = powerLineProvider ?? GetPowerLineState;
    }

    private static IRyzenAdjNativeApi CreateNativeApi(string runtimeDirectory)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(runtimeDirectory);
        string libraryPath = Path.Combine(runtimeDirectory, "libryzenadj.dll");
        if (!File.Exists(libraryPath))
        {
            throw new FileNotFoundException("libryzenadj.dll was not found.", libraryPath);
        }
        SetDllDirectory(runtimeDirectory);
        return new RyzenAdjNativeApi(runtimeDirectory);
    }

    public Task<PlatformCapability> ProbeAsync(CancellationToken cancellationToken = default)
    {
        return Task.Run(
            () =>
            {
                cancellationToken.ThrowIfCancellationRequested();
                lock (_sync)
                {
                    ThrowIfDisposed();
                    return ReadCapability();
                }
            },
            cancellationToken);
    }

    public Task<TelemetrySnapshot> RefreshTelemetryAsync(
        CancellationToken cancellationToken = default)
    {
        return Task.Run(
            () =>
            {
                cancellationToken.ThrowIfCancellationRequested();
                lock (_sync)
                {
                    ThrowIfDisposed();
                    EnsureInitialized();
                    return RefreshTelemetryCore();
                }
            },
            cancellationToken);
    }

    public Task<PowerLimitApplicationResult> ApplyTargetAsync(
        PowerLimitTarget target,
        CancellationToken cancellationToken = default)
    {
        return Task.Run(
            () =>
            {
                cancellationToken.ThrowIfCancellationRequested();
                lock (_sync)
                {
                    ThrowIfDisposed();
                    EnsureInitialized();

                    PlatformCapability capability = ReadCapability();
                    if (!capability.IsSupported)
                    {
                        throw new InvalidOperationException(
                            $"Hardware writes are unavailable: {capability.UnsupportedReason}");
                    }

                    PowerLimitTargetValidationResult validation =
                        PowerLimitTargetValidator.Validate(target, capability.Limits);
                    if (!validation.IsValid)
                    {
                        throw new ArgumentException(validation.Error, nameof(target));
                    }

                    TelemetrySnapshot before = RefreshTelemetryCore();
                    if (!TryGetPreviousTarget(before, out PowerLimitTarget previous, out string? previousError))
                    {
                        throw new InvalidOperationException(
                            $"Previous power limits cannot be verified safely: {previousError}");
                    }

                    PowerLimitWriteAttempt applied;
                    try
                    {
                        applied = WriteTarget(target, requireExactReadback: false);
                    }
                    catch (Exception writeError)
                    {
                        applied = new PowerLimitWriteAttempt(
                            Array.Empty<PowerLimitReadback>(),
                            $"Power-limit write failed: {writeError.Message}");
                    }

                    if (applied.IsSuccessful)
                    {
                        return new PowerLimitApplicationResult(
                            target,
                            applied.Readbacks,
                            previous);
                    }

                    PowerLimitWriteAttempt restored;
                    try
                    {
                        restored = WriteTarget(previous, requireExactReadback: true);
                    }
                    catch (Exception restoreError)
                    {
                        restored = new PowerLimitWriteAttempt(
                            Array.Empty<PowerLimitReadback>(),
                            $"Restore threw an exception: {restoreError.Message}");
                    }

                    return new PowerLimitApplicationResult(
                        target,
                        applied.Readbacks,
                        previous,
                        RestoreAttempted: true,
                        RestoredPreviousLimits: restored.IsSuccessful,
                        restored.Readbacks,
                        restored.IsSuccessful
                            ? applied.Error
                            : $"{applied.Error} Restore failed: {restored.Error}");
                }
            },
            cancellationToken);
    }

    public ValueTask DisposeAsync()
    {
        lock (_sync)
        {
            if (_disposed)
            {
                return ValueTask.CompletedTask;
            }

            if (_ryzenAccess != IntPtr.Zero)
            {
                _native.CleanupRyzenAdj(_ryzenAccess);
                _ryzenAccess = IntPtr.Zero;
            }
            _disposed = true;
        }
        return ValueTask.CompletedTask;
    }

    private void EnsureInitialized()
    {
        if (_ryzenAccess != IntPtr.Zero)
        {
            return;
        }

        _ryzenAccess = _native.InitRyzenAdj();
        if (_ryzenAccess == IntPtr.Zero)
        {
            throw new InvalidOperationException("RyzenAdj could not initialize the Windows hardware backend.");
        }

        int result = _native.InitTable(_ryzenAccess);
        if (result != 0)
        {
            _native.CleanupRyzenAdj(_ryzenAccess);
            _ryzenAccess = IntPtr.Zero;
            throw new InvalidOperationException($"RyzenAdj init_table failed with code {result}.");
        }
    }

    private PlatformCapability ReadCapability()
    {
        CpuPlatformInfo cpu = _cpuInfoProvider();
        try
        {
            EnsureInitialized();
            int family = _native.GetCpuFamily(_ryzenAccess);
            bool supported = family >= 0;
            return new PlatformCapability(
                cpu with
                {
                    RyzenAdjFamily = family,
                    RyzenAdjFamilyName = RyzenAdjFamilyNames.GetName(family),
                    SmuBiosVersion = _native.GetBiosIfVersion(_ryzenAccess).ToString(),
                    PmTableVersion = _native.GetTableVersion(_ryzenAccess).ToString("x")
                },
                new PowerLimitCapability(supported, supported, supported),
                supported,
                supported ? null : $"Unsupported CPU family: {RyzenAdjFamilyNames.GetName(family)}");
        }
        catch (Exception error)
        {
            uint winRingStatus = _native.GetWinRingDllStatus();
            return new PlatformCapability(
                cpu,
                new PowerLimitCapability(false, false, false),
                false,
                $"{error.Message} WinRing0 status={winRingStatus} ({DescribeWinRingStatus(winRingStatus)}).");
        }
    }

    private TelemetrySnapshot ReadTelemetry()
    {
        return new TelemetrySnapshot
        {
            StapmValueWatts = ReadFloat(_native.GetStapmValue(_ryzenAccess)),
            FastValueWatts = ReadFloat(_native.GetFastValue(_ryzenAccess)),
            SlowValueWatts = ReadFloat(_native.GetSlowValue(_ryzenAccess)),
            StapmLimitWatts = ReadFloat(_native.GetStapmLimit(_ryzenAccess)),
            FastLimitWatts = ReadFloat(_native.GetFastLimit(_ryzenAccess)),
            SlowLimitWatts = ReadFloat(_native.GetSlowLimit(_ryzenAccess)),
            TctlValueCelsius = ReadFloat(_native.GetTctlTempValue(_ryzenAccess)),
            TctlLimitCelsius = ReadFloat(_native.GetTctlTemp(_ryzenAccess)),
            PowerLine = _powerLineProvider(),
            UpdatedAt = DateTimeOffset.Now
        };
    }

    private TelemetrySnapshot RefreshTelemetryCore()
    {
        int result = _native.RefreshTable(_ryzenAccess);
        if (result != 0)
        {
            throw new InvalidOperationException($"RyzenAdj refresh_table failed with code {result}.");
        }

        return ReadTelemetry();
    }

    private PowerLimitWriteAttempt WriteTarget(
        PowerLimitTarget target,
        bool requireExactReadback)
    {
        int stapmResult = 0;
        try
        {
            stapmResult = _native.SetStapmLimit(
                _ryzenAccess,
                checked((uint)(target.StapmWatts * 1000)));
        }
        catch
        {
            // Fast/Slow are the effective required caps on firmware-dynamic STAPM
            // platforms. A rejected STAPM write must not roll those caps back.
            stapmResult = -1;
        }

        int fastResult = _native.SetFastLimit(
            _ryzenAccess,
            checked((uint)(target.FastWatts * 1000)));
        int slowResult = _native.SetSlowLimit(
            _ryzenAccess,
            checked((uint)(target.SlowWatts * 1000)));
        int refreshResult = _native.RefreshTable(_ryzenAccess);

        List<PowerLimitReadback> readbacks = new(3)
        {
            CreateReadback(
                PowerLimitKind.Stapm,
                target.StapmWatts,
                stapmResult,
                refreshResult == 0 ? _native.GetStapmLimit(_ryzenAccess) : float.NaN),
            CreateReadback(
                PowerLimitKind.Fast,
                target.FastWatts,
                fastResult,
                refreshResult == 0 ? _native.GetFastLimit(_ryzenAccess) : float.NaN),
            CreateReadback(
                PowerLimitKind.Slow,
                target.SlowWatts,
                slowResult,
                refreshResult == 0 ? _native.GetSlowLimit(_ryzenAccess) : float.NaN)
        };

        List<string> errors = new(4);
        foreach (PowerLimitReadback readback in readbacks)
        {
            if (readback.Kind == PowerLimitKind.Stapm)
            {
                // STAPM can be firmware-managed or rejected independently of the
                // PPT Fast/Slow limits that enforce the requested power ceiling.
                continue;
            }

            if (readback.DriverResultCode != 0)
            {
                errors.Add(
                    $"{readback.Kind} write returned {readback.DriverResultCode}.");
                continue;
            }
            if (readback.EffectiveWatts is not { } effective)
            {
                errors.Add($"{readback.Kind} read-back is unavailable.");
                continue;
            }
            if (effective <= 0)
            {
                errors.Add($"{readback.Kind} read back an invalid value of {effective:0.00}W.");
                continue;
            }

            double difference = effective - readback.RequestedWatts;
            bool increased = difference > ReadbackToleranceWatts;
            bool invalid = requireExactReadback
                ? Math.Abs(difference) > ReadbackToleranceWatts
                : increased;
            if (invalid)
            {
                errors.Add(
                    $"{readback.Kind} requested {readback.RequestedWatts}W but read back {effective:0.00}W.");
            }
        }

        if (refreshResult != 0)
        {
            errors.Add($"RyzenAdj refresh_table failed with code {refreshResult}.");
        }

        return new PowerLimitWriteAttempt(
            readbacks,
            errors.Count == 0 ? null : string.Join(" ", errors));
    }

    private static bool TryGetPreviousTarget(
        TelemetrySnapshot telemetry,
        out PowerLimitTarget target,
        out string? error)
    {
        target = default;
        error = null;
        if (telemetry.StapmLimitWatts is not { } stapm ||
            telemetry.FastLimitWatts is not { } fast ||
            telemetry.SlowLimitWatts is not { } slow)
        {
            error = "STAPM, Fast, or Slow limits are missing.";
            return false;
        }

        int stapmWatts = RoundReadback(stapm);
        int fastWatts = RoundReadback(fast);
        int slowWatts = RoundReadback(slow);
        if (!IsRestorable(stapmWatts) || !IsRestorable(fastWatts) || !IsRestorable(slowWatts))
        {
            error =
                $"Read-back values must be between {MinimumRestoreWatts}W and {MaximumRestoreWatts}W; " +
                $"received {stapm:0.00}/{fast:0.00}/{slow:0.00}W.";
            return false;
        }

        target = new PowerLimitTarget(stapmWatts, fastWatts, slowWatts);
        return true;
    }

    private static int RoundReadback(double watts)
    {
        return checked((int)Math.Round(watts, MidpointRounding.AwayFromZero));
    }

    private static bool IsRestorable(int watts)
    {
        return watts is >= MinimumRestoreWatts and <= MaximumRestoreWatts;
    }

    private static PowerLimitReadback CreateReadback(
        PowerLimitKind kind,
        int requestedWatts,
        int driverResult,
        float effectiveWatts)
    {
        return new PowerLimitReadback(
            kind,
            requestedWatts,
            ReadFloat(effectiveWatts),
            driverResult);
    }

    private static double? ReadFloat(float value)
    {
        return float.IsFinite(value) ? value : null;
    }

    private static CpuPlatformInfo ReadCpuInfo()
    {
        string? processorName = null;
        using RegistryKey? processor = Registry.LocalMachine.OpenSubKey(
            @"HARDWARE\DESCRIPTION\System\CentralProcessor\0");
        processorName = processor?.GetValue("ProcessorNameString") as string;
        return new CpuPlatformInfo
        {
            ProcessorName = string.IsNullOrWhiteSpace(processorName)
                ? "Unknown AMD processor"
                : processorName.Trim()
        };
    }

    private static PowerLineState GetPowerLineState()
    {
        if (!GetSystemPowerStatus(out SystemPowerStatus status))
        {
            return PowerLineState.Unknown;
        }

        return status.ACLineStatus switch
        {
            0 => PowerLineState.Battery,
            1 => PowerLineState.Ac,
            _ => PowerLineState.Unknown
        };
    }

    private static string DescribeWinRingStatus(uint status)
    {
        return status switch
        {
            0 => "ready",
            1 => "unsupported platform",
            2 => "driver not loaded",
            3 => "driver not found",
            4 => "driver unloaded",
            5 => "driver not loaded on network",
            9 => "unknown error",
            _ => "unrecognized status"
        };
    }

    private void ThrowIfDisposed()
    {
        ObjectDisposedException.ThrowIf(_disposed, this);
    }

    private sealed record PowerLimitWriteAttempt(
        IReadOnlyList<PowerLimitReadback> Readbacks,
        string? Error)
    {
        public bool IsSuccessful => Error is null;
    }

    [DllImport("kernel32.dll")]
    private static extern bool GetSystemPowerStatus(out SystemPowerStatus systemPowerStatus);

    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern bool SetDllDirectory(string pathName);

    [StructLayout(LayoutKind.Sequential)]
    private struct SystemPowerStatus
    {
        public byte ACLineStatus;
        public byte BatteryFlag;
        public byte BatteryLifePercent;
        public byte SystemStatusFlag;
        public uint BatteryLifeTime;
        public uint BatteryFullLifeTime;
    }
}
