param(
    [Parameter(Mandatory = $true)]
    [string]$Path,
    [int]$ExpectedGroupIconId = 1
)

$ErrorActionPreference = "Stop"

if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
    throw "Icon check target is missing: $Path"
}

if (-not ("AmdMobilePowerIconProbe" -as [type])) {
    Add-Type -Namespace AmdMobilePowerIconProbe -Name Native -MemberDefinition @'
[DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
public static extern IntPtr LoadLibraryEx(string fileName, IntPtr file, uint flags);

[DllImport("kernel32.dll", SetLastError = true)]
public static extern IntPtr FindResource(IntPtr module, IntPtr name, IntPtr type);

[DllImport("kernel32.dll", SetLastError = true)]
public static extern uint SizeofResource(IntPtr module, IntPtr resource);

[DllImport("kernel32.dll", SetLastError = true)]
public static extern bool FreeLibrary(IntPtr module);
'@
}

$LOAD_LIBRARY_AS_DATAFILE = 0x00000002
$RESOURCE_TYPE_ICON = [IntPtr]3
$RESOURCE_TYPE_GROUP_ICON = [IntPtr]14

$module = [AmdMobilePowerIconProbe.Native]::LoadLibraryEx(
    (Resolve-Path -LiteralPath $Path).Path,
    [IntPtr]::Zero,
    $LOAD_LIBRARY_AS_DATAFILE)
if ($module -eq [IntPtr]::Zero) {
    throw "Unable to load $Path as a resource image (Win32 error $([System.Runtime.InteropServices.Marshal]::GetLastWin32Error()))."
}

try {
    $groupHandle = [AmdMobilePowerIconProbe.Native]::FindResource(
        $module,
        [IntPtr]$ExpectedGroupIconId,
        $RESOURCE_TYPE_GROUP_ICON)
    if ($groupHandle -eq [IntPtr]::Zero) {
        throw "No RT_GROUP_ICON resource $ExpectedGroupIconId in $Path. Windows would fall back to a generic icon."
    }
    $groupBytes = [AmdMobilePowerIconProbe.Native]::SizeofResource($module, $groupHandle)
    if ($groupBytes -lt 6) {
        throw "RT_GROUP_ICON resource $ExpectedGroupIconId in $Path is empty ($groupBytes bytes)."
    }

    $iconIds = New-Object System.Collections.Generic.List[int]
    for ($id = 1; $id -le 32; $id++) {
        $iconHandle = [AmdMobilePowerIconProbe.Native]::FindResource(
            $module,
            [IntPtr]$id,
            $RESOURCE_TYPE_ICON)
        if ($iconHandle -ne [IntPtr]::Zero -and
            [AmdMobilePowerIconProbe.Native]::SizeofResource($module, $iconHandle) -gt 0) {
            $iconIds.Add($id)
        }
    }
    if ($iconIds.Count -eq 0) {
        throw "RT_GROUP_ICON exists in $Path but no RT_ICON images were found."
    }

    [pscustomobject]@{
        Verification = "PASS"
        Path = (Resolve-Path -LiteralPath $Path).Path
        GroupIconId = $ExpectedGroupIconId
        GroupIconBytes = $groupBytes
        IconResourceIds = @($iconIds)
        IconImageCount = $iconIds.Count
    } | Format-List
}
finally {
    [void][AmdMobilePowerIconProbe.Native]::FreeLibrary($module)
}
