using System.Runtime.InteropServices;
using AmdMobilePower.Core.Hardware;
using AmdMobilePower.Core.Models;
using AmdMobilePower.Core.Validation;
using Microsoft.Win32;

namespace AmdMobilePower.Worker.Hardware;

public sealed class RyzenAdjPowerAdapter : IRyzenPowerAdapter
{
    private readonly object _sync = new();
    private readonly RyzenAdjNativeApi _native;
    private IntPtr _ryzenAccess;
    private bool _disposed;

    public RyzenAdjPowerAdapter(string runtimeDirectory)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(runtimeDirectory);
        string libraryPath = Path.Combine(runtimeDirectory, "libryzenadj.dll");
        if (!File.Exists(libraryPath))
        {
            throw new FileNotFoundException("libryzenadj.dll was not found.", libraryPath);
        }
        SetDllDirectory(runtimeDirectory);
        _native = new RyzenAdjNativeApi(runtimeDirectory);
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
                    int result = _native.RefreshTable(_ryzenAccess);
                    if (result != 0)
                    {
                        throw new InvalidOperationException($"RyzenAdj refresh_table failed with code {result}.");
                    }

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
                        PowerLine = GetPowerLineState(),
                        UpdatedAt = DateTimeOffset.Now
                    };
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

                    int stapmResult = _native.SetStapmLimit(
                        _ryzenAccess,
                        checked((uint)(target.StapmWatts * 1000)));
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

                    return new PowerLimitApplicationResult(target, readbacks);
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
        CpuPlatformInfo cpu = ReadCpuInfo();
        try
        {
            EnsureInitialized();
            int family = _native.GetCpuFamily(_ryzenAccess);
            bool supported = family >= 0;
            return new PlatformCapability(
                cpu with
                {
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

    private static PowerLimitReadback CreateReadback(
        PowerLimitKind kind,
        int requestedWatts,
        int driverResult,
        float effectiveWatts)
    {
        return new PowerLimitReadback(
            kind,
            requestedWatts,
            driverResult == 0 ? ReadFloat(effectiveWatts) : null,
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
