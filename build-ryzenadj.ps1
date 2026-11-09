param(
    [string]$Configuration = "Release"
)

$ErrorActionPreference = "Stop"

$root = Split-Path -Parent $PSCommandPath
$upstream = Join-Path $root "third_party\RyzenAdj"
$build = Join-Path $root "artifacts\ryzenadj-build"
$runtime = Join-Path $root "artifacts\ryzenadj-runtime"
$cmakeCandidates = @(
    "cmake.exe",
    "C:\Program Files\Microsoft Visual Studio\18\Community\Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin\cmake.exe",
    "C:\Program Files\Microsoft Visual Studio\2022\Community\Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin\cmake.exe"
)

if (-not (Test-Path -LiteralPath (Join-Path $upstream "CMakeLists.txt"))) {
    git -C $root submodule update --init --recursive
}

$vswhere = Join-Path ${env:ProgramFiles(x86)} "Microsoft Visual Studio\Installer\vswhere.exe"
$visualStudioPath = $null
if (Test-Path -LiteralPath $vswhere) {
    $visualStudioResult = & $vswhere `
        -latest `
        -products * `
        -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 `
        -property installationPath
    $visualStudioPath = if ($visualStudioResult) {
        ($visualStudioResult | Select-Object -First 1).Trim()
    }
    else {
        $null
    }
}

$generator = if ($visualStudioPath -match "\\2026\\") {
    "Visual Studio 18 2026"
}
elseif ($visualStudioPath -match "\\2022\\") {
    "Visual Studio 17 2022"
}
elseif ($visualStudioPath -match "\\2019\\") {
    "Visual Studio 16 2019"
}
else {
    "Visual Studio 18 2026"
}

if ($visualStudioPath) {
    $visualStudioCmake = Join-Path $visualStudioPath `
        "Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin\cmake.exe"
    if (Test-Path -LiteralPath $visualStudioCmake) {
        $cmakeCandidates = @($visualStudioCmake) + $cmakeCandidates
    }
}

$cmake = $cmakeCandidates |
    Where-Object {
        if ($_ -eq "cmake.exe") {
            [bool](Get-Command $_ -ErrorAction SilentlyContinue)
        }
        else {
            Test-Path -LiteralPath $_
        }
    } |
    Select-Object -First 1

if (-not $cmake) {
    throw "CMake was not found."
}

& $cmake `
    -S $upstream `
    -B $build `
    -G $generator `
    -A x64 `
    -DBUILD_SHARED_LIBS=ON
if ($LASTEXITCODE -ne 0) {
    throw "RyzenAdj CMake configuration failed."
}

& $cmake --build $build --config $Configuration --target libryzenadj
if ($LASTEXITCODE -ne 0) {
    throw "RyzenAdj build failed."
}

New-Item -ItemType Directory -Path $runtime -Force | Out-Null
Copy-Item -LiteralPath (Join-Path $build "$Configuration\libryzenadj.dll") -Destination $runtime -Force
Copy-Item -LiteralPath (Join-Path $upstream "win32\WinRing0x64.dll") -Destination $runtime -Force
Copy-Item -LiteralPath (Join-Path $upstream "win32\WinRing0x64.sys") -Destination $runtime -Force
Copy-Item -LiteralPath (Join-Path $upstream "win32\inpoutx64.dll") -Destination $runtime -Force

$commit = (& git -C $upstream rev-parse HEAD).Trim()
@(
    "RyzenAdjCommit=$commit"
    "Configuration=$Configuration"
    "BuiltAt=$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss zzz')"
) | Set-Content -LiteralPath (Join-Path $runtime "BUILD-INFO.txt") -Encoding utf8

Write-Output "RyzenAdj runtime staged at $runtime"
