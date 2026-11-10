param(
    [string]$Configuration = "Release",
    [switch]$Offline
)

$ErrorActionPreference = "Stop"

$root = Split-Path -Parent $PSCommandPath
$repositoryRoot = Split-Path -Parent $root
$cmakeCandidates = @(
    "cmake.exe",
    "C:\Program Files\Microsoft Visual Studio\18\Community\Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin\cmake.exe",
    "C:\Program Files\Microsoft Visual Studio\2022\Community\Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin\cmake.exe"
)

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

$cppBuild = Join-Path $repositoryRoot "artifacts\native-build\cpp-worker"
$workerRuntime = Join-Path $repositoryRoot "artifacts\native-build\worker-runtime"
$guiRuntime = Join-Path $repositoryRoot "artifacts\native-build\gui-runtime"
$ryzenAdjRuntime = Join-Path $repositoryRoot "artifacts\ryzenadj-runtime"
$rustGuiManifest = Join-Path $root "rust-gui\Cargo.toml"
Push-Location $repositoryRoot
try {
    & $cmake `
        -S (Join-Path $root "cpp-worker") `
        -B $cppBuild `
        -G $generator `
        -A x64
    if ($LASTEXITCODE -ne 0) {
        throw "C++ worker CMake configuration failed."
    }

    & $cmake --build $cppBuild --config $Configuration
    if ($LASTEXITCODE -ne 0) {
        throw "C++ worker build failed."
    }

    $powerLimitTests = Join-Path `
        $cppBuild `
        "$Configuration\amdmobilepower_power_limit_policy_tests.exe"
    if (-not (Test-Path -LiteralPath $powerLimitTests)) {
        throw "C++ power-limit policy tests were not built."
    }
    & $powerLimitTests
    if ($LASTEXITCODE -ne 0) {
        throw "C++ power-limit policy tests failed."
    }

    $powerPolicyTests = Join-Path `
        $cppBuild `
        "$Configuration\amdmobilepower_power_policy_tests.exe"
    if (-not (Test-Path -LiteralPath $powerPolicyTests)) {
        throw "C++ power-policy tests were not built."
    }
    & $powerPolicyTests
    if ($LASTEXITCODE -ne 0) {
        throw "C++ power-policy tests failed."
    }

    & cargo test `
        --manifest-path $rustGuiManifest `
        --locked `
        --offline
    if ($LASTEXITCODE -ne 0) {
        throw "Rust GUI lifecycle tests failed."
    }

    & cargo build `
        --manifest-path $rustGuiManifest `
        --release `
        --locked `
        --offline
    if ($LASTEXITCODE -ne 0) {
        throw "Rust GUI build failed."
    }

    $cargoArguments = @(
        "build",
        "--manifest-path", (Join-Path $root "rust-probe\Cargo.toml"),
        "--release",
        "--locked"
    )
    if ($Offline) {
        $cargoArguments += "--offline"
    }
    & cargo @cargoArguments
    if ($LASTEXITCODE -ne 0) {
        throw "Rust probe build failed."
    }

    if (Test-Path -LiteralPath $ryzenAdjRuntime) {
        New-Item -ItemType Directory -Path $workerRuntime -Force | Out-Null
        Copy-Item `
            -LiteralPath (Join-Path $cppBuild "$Configuration\amdmobilepower_native_worker.exe") `
            -Destination $workerRuntime `
            -Force
        foreach ($runtimeFile in @(
            "libryzenadj.dll",
            "WinRing0x64.dll",
            "WinRing0x64.sys",
            "inpoutx64.dll"
        )) {
            Copy-Item `
                -LiteralPath (Join-Path $ryzenAdjRuntime $runtimeFile) `
                -Destination $workerRuntime `
                -Force
        }

        New-Item -ItemType Directory -Path $guiRuntime -Force | Out-Null
        Copy-Item `
            -LiteralPath (Join-Path $root "rust-gui\target\release\amd-mobile-power-gui.exe") `
            -Destination $guiRuntime `
            -Force
        Copy-Item `
            -Path (Join-Path $workerRuntime "*") `
            -Destination $guiRuntime `
            -Force
    }
}
finally {
    Pop-Location
}

Write-Output "Native migration build completed."
