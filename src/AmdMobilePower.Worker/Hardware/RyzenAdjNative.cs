using System.Runtime.InteropServices;

namespace AmdMobilePower.Worker.Hardware;

internal sealed class RyzenAdjNativeApi
{
    private readonly IntPtr _winRingHandle;
    private readonly IntPtr _inpOutHandle;
    private readonly IntPtr _libraryHandle;
    private readonly GetDllStatusFn _getDllStatus;
    private readonly InitRyzenAdjFn _initRyzenAdj;
    private readonly CleanupRyzenAdjFn _cleanupRyzenAdj;
    private readonly GetCpuFamilyFn _getCpuFamily;
    private readonly GetBiosIfVersionFn _getBiosIfVersion;
    private readonly InitTableFn _initTable;
    private readonly RefreshTableFn _refreshTable;
    private readonly GetTableVersionFn _getTableVersion;
    private readonly SetLimitFn _setStapmLimit;
    private readonly SetLimitFn _setFastLimit;
    private readonly SetLimitFn _setSlowLimit;
    private readonly GetValueFn _getStapmLimit;
    private readonly GetValueFn _getStapmValue;
    private readonly GetValueFn _getFastLimit;
    private readonly GetValueFn _getFastValue;
    private readonly GetValueFn _getSlowLimit;
    private readonly GetValueFn _getSlowValue;
    private readonly GetValueFn _getTctlTemp;
    private readonly GetValueFn _getTctlTempValue;

    public RyzenAdjNativeApi(string runtimeDirectory)
    {
        _winRingHandle = NativeLibrary.Load(Path.Combine(runtimeDirectory, "WinRing0x64.dll"));
        _getDllStatus = GetDelegate<GetDllStatusFn>(_winRingHandle, "GetDllStatus");
        _inpOutHandle = NativeLibrary.Load(Path.Combine(runtimeDirectory, "inpoutx64.dll"));
        _libraryHandle = NativeLibrary.Load(Path.Combine(runtimeDirectory, "libryzenadj.dll"));

        _initRyzenAdj = GetDelegate<InitRyzenAdjFn>(_libraryHandle, "init_ryzenadj");
        _cleanupRyzenAdj = GetDelegate<CleanupRyzenAdjFn>(_libraryHandle, "cleanup_ryzenadj");
        _getCpuFamily = GetDelegate<GetCpuFamilyFn>(_libraryHandle, "get_cpu_family");
        _getBiosIfVersion = GetDelegate<GetBiosIfVersionFn>(_libraryHandle, "get_bios_if_ver");
        _initTable = GetDelegate<InitTableFn>(_libraryHandle, "init_table");
        _refreshTable = GetDelegate<RefreshTableFn>(_libraryHandle, "refresh_table");
        _getTableVersion = GetDelegate<GetTableVersionFn>(_libraryHandle, "get_table_ver");
        _setStapmLimit = GetDelegate<SetLimitFn>(_libraryHandle, "set_stapm_limit");
        _setFastLimit = GetDelegate<SetLimitFn>(_libraryHandle, "set_fast_limit");
        _setSlowLimit = GetDelegate<SetLimitFn>(_libraryHandle, "set_slow_limit");
        _getStapmLimit = GetDelegate<GetValueFn>(_libraryHandle, "get_stapm_limit");
        _getStapmValue = GetDelegate<GetValueFn>(_libraryHandle, "get_stapm_value");
        _getFastLimit = GetDelegate<GetValueFn>(_libraryHandle, "get_fast_limit");
        _getFastValue = GetDelegate<GetValueFn>(_libraryHandle, "get_fast_value");
        _getSlowLimit = GetDelegate<GetValueFn>(_libraryHandle, "get_slow_limit");
        _getSlowValue = GetDelegate<GetValueFn>(_libraryHandle, "get_slow_value");
        _getTctlTemp = GetDelegate<GetValueFn>(_libraryHandle, "get_tctl_temp");
        _getTctlTempValue = GetDelegate<GetValueFn>(_libraryHandle, "get_tctl_temp_value");
    }

    public IntPtr InitRyzenAdj() => _initRyzenAdj();
    public uint GetWinRingDllStatus() => _getDllStatus();
    public void CleanupRyzenAdj(IntPtr ryzenAccess) => _cleanupRyzenAdj(ryzenAccess);
    public int GetCpuFamily(IntPtr ryzenAccess) => _getCpuFamily(ryzenAccess);
    public int GetBiosIfVersion(IntPtr ryzenAccess) => _getBiosIfVersion(ryzenAccess);
    public int InitTable(IntPtr ryzenAccess) => _initTable(ryzenAccess);
    public int RefreshTable(IntPtr ryzenAccess) => _refreshTable(ryzenAccess);
    public uint GetTableVersion(IntPtr ryzenAccess) => _getTableVersion(ryzenAccess);
    public int SetStapmLimit(IntPtr ryzenAccess, uint value) => _setStapmLimit(ryzenAccess, value);
    public int SetFastLimit(IntPtr ryzenAccess, uint value) => _setFastLimit(ryzenAccess, value);
    public int SetSlowLimit(IntPtr ryzenAccess, uint value) => _setSlowLimit(ryzenAccess, value);
    public float GetStapmLimit(IntPtr ryzenAccess) => _getStapmLimit(ryzenAccess);
    public float GetStapmValue(IntPtr ryzenAccess) => _getStapmValue(ryzenAccess);
    public float GetFastLimit(IntPtr ryzenAccess) => _getFastLimit(ryzenAccess);
    public float GetFastValue(IntPtr ryzenAccess) => _getFastValue(ryzenAccess);
    public float GetSlowLimit(IntPtr ryzenAccess) => _getSlowLimit(ryzenAccess);
    public float GetSlowValue(IntPtr ryzenAccess) => _getSlowValue(ryzenAccess);
    public float GetTctlTemp(IntPtr ryzenAccess) => _getTctlTemp(ryzenAccess);
    public float GetTctlTempValue(IntPtr ryzenAccess) => _getTctlTempValue(ryzenAccess);

    private static TDelegate GetDelegate<TDelegate>(IntPtr libraryHandle, string exportName)
        where TDelegate : Delegate
    {
        IntPtr address = NativeLibrary.GetExport(libraryHandle, exportName);
        return Marshal.GetDelegateForFunctionPointer<TDelegate>(address);
    }

    [UnmanagedFunctionPointer(CallingConvention.StdCall)]
    private delegate uint GetDllStatusFn();

    [UnmanagedFunctionPointer(CallingConvention.StdCall)]
    private delegate IntPtr InitRyzenAdjFn();

    [UnmanagedFunctionPointer(CallingConvention.StdCall)]
    private delegate void CleanupRyzenAdjFn(IntPtr ryzenAccess);

    [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
    private delegate int GetCpuFamilyFn(IntPtr ryzenAccess);

    [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
    private delegate int GetBiosIfVersionFn(IntPtr ryzenAccess);

    [UnmanagedFunctionPointer(CallingConvention.StdCall)]
    private delegate int InitTableFn(IntPtr ryzenAccess);

    [UnmanagedFunctionPointer(CallingConvention.StdCall)]
    private delegate int RefreshTableFn(IntPtr ryzenAccess);

    [UnmanagedFunctionPointer(CallingConvention.StdCall)]
    private delegate uint GetTableVersionFn(IntPtr ryzenAccess);

    [UnmanagedFunctionPointer(CallingConvention.StdCall)]
    private delegate int SetLimitFn(IntPtr ryzenAccess, uint value);

    [UnmanagedFunctionPointer(CallingConvention.StdCall)]
    private delegate float GetValueFn(IntPtr ryzenAccess);
}
