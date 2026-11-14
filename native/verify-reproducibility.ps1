param(
    [switch]$SkipGui,
    [switch]$SkipWorker,
    [switch]$SkipProbe,
    [string]$PackageVersion,
    [string]$EvidencePath
)

$ErrorActionPreference = "Stop"

$root = Split-Path -Parent $PSCommandPath
$repositoryRoot = Split-Path -Parent $root
$artifacts = Join-Path $repositoryRoot "artifacts"
$cppBuild = Join-Path $artifacts "native-build\cpp-worker"
$fallbackGenerators = [ordered]@{
    "C:\Program Files\Microsoft Visual Studio\18\Community\Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin\cmake.exe" = "Visual Studio 18 2026"
    "C:\Program Files\Microsoft Visual Studio\2022\Community\Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin\cmake.exe" = "Visual Studio 17 2022"
}

function Resolve-Toolchain {
    $result = [ordered]@{
        CMake = $null
        Generator = "Visual Studio 18 2026"
    }
    $vswhere = Join-Path ${env:ProgramFiles(x86)} "Microsoft Visual Studio\Installer\vswhere.exe"
    if (Test-Path -LiteralPath $vswhere) {
        $visualStudioPath = (& $vswhere `
            -latest `
            -products * `
            -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 `
            -property installationPath | Select-Object -First 1)
        if ($visualStudioPath) {
            $visualStudioPath = $visualStudioPath.Trim()
            $result.Generator = if ($visualStudioPath -match "\\18\\") {
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
            $candidate = Join-Path $visualStudioPath `
                "Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin\cmake.exe"
            if (Test-Path -LiteralPath $candidate) {
                $result.CMake = $candidate
                return [pscustomobject]$result
            }
        }
    }
    foreach ($entry in $fallbackGenerators.GetEnumerator()) {
        if (Test-Path -LiteralPath $entry.Key) {
            $result.CMake = $entry.Key
            $result.Generator = $entry.Value
            return [pscustomobject]$result
        }
    }
    $command = Get-Command "cmake.exe" -ErrorAction SilentlyContinue
    if ($command) {
        $result.CMake = $command.Source
        return [pscustomobject]$result
    }
    throw "CMake was not found."
}

function Get-Sha256 {
    param([Parameter(Mandatory = $true)][string]$Path)

    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Rebuild-RustBinary {
    param(
        [Parameter(Mandatory = $true)][string]$Manifest,
        [Parameter(Mandatory = $true)][string]$Executable
    )

    $freshTarget = [System.IO.Path]::GetFullPath(
        (Join-Path $artifacts "native-build\repro-$([Guid]::NewGuid().ToString('N'))"))
    $allowedRoot = [System.IO.Path]::GetFullPath($artifacts) + [System.IO.Path]::DirectorySeparatorChar
    if (-not $freshTarget.StartsWith($allowedRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Fresh Rust target directory must stay under artifacts."
    }
    try {
        & cargo build --manifest-path $Manifest --target-dir $freshTarget --release --locked --offline
        if ($LASTEXITCODE -ne 0) {
            throw "Fresh Rust rebuild failed for $Manifest"
        }
        $rebuilt = Join-Path $freshTarget ("release\" + (Split-Path -Leaf $Executable))
        if (-not (Test-Path -LiteralPath $rebuilt)) {
            throw "Fresh Rust rebuild did not produce $rebuilt"
        }
        Copy-Item -LiteralPath $rebuilt -Destination $Executable -Force
    }
    finally {
        if (Test-Path -LiteralPath $freshTarget) {
            Remove-Item -LiteralPath $freshTarget -Recurse -Force
        }
    }
}

$results = [ordered]@{}
$failures = New-Object System.Collections.Generic.List[string]

if (-not $SkipGui) {
    $manifest = Join-Path $root "rust-gui\Cargo.toml"
    $executable = Join-Path $root "rust-gui\target\release\amd-mobile-power-gui.exe"
    $first = Get-Sha256 $executable
    Rebuild-RustBinary -Manifest $manifest -Executable $executable
    $second = Get-Sha256 $executable
    $results.Gui = [ordered]@{
        First = $first
        Second = $second
        Reproducible = $first -eq $second
        Size = (Get-Item -LiteralPath $executable).Length
    }
    if ($first -ne $second) {
        $failures.Add("GUI rebuild produced a different hash.")
    }
}

if (-not $SkipProbe) {
    $manifest = Join-Path $root "rust-probe\Cargo.toml"
    $executable = Join-Path $root "rust-probe\target\release\amd-mobile-power-probe.exe"
    $first = Get-Sha256 $executable
    Rebuild-RustBinary -Manifest $manifest -Executable $executable
    $second = Get-Sha256 $executable
    $results.Probe = [ordered]@{
        First = $first
        Second = $second
        Reproducible = $first -eq $second
        Size = (Get-Item -LiteralPath $executable).Length
    }
    if ($first -ne $second) {
        $failures.Add("Probe rebuild produced a different hash.")
    }
}

if (-not $SkipWorker) {
    $toolchain = Resolve-Toolchain
    $cmake = $toolchain.CMake
    $executable = Join-Path $cppBuild "Release\amdmobilepower_native_worker.exe"
    $generator = $toolchain.Generator
    & $cmake -S (Join-Path $root "cpp-worker") -B $cppBuild -G $generator -A x64 | Out-Null
    if ($LASTEXITCODE -ne 0) {
        throw "CMake configuration failed."
    }
    & $cmake --build $cppBuild --config Release | Out-Null
    if ($LASTEXITCODE -ne 0) {
        throw "C++ worker build failed."
    }
    $first = Get-Sha256 $executable
    & $cmake --build $cppBuild --config Release --clean-first | Out-Null
    if ($LASTEXITCODE -ne 0) {
        throw "C++ worker clean rebuild failed."
    }
    $second = Get-Sha256 $executable
    $results.Worker = [ordered]@{
        First = $first
        Second = $second
        Reproducible = $first -eq $second
        Size = (Get-Item -LiteralPath $executable).Length
    }
    if ($first -ne $second) {
        $failures.Add("C++ worker clean rebuild produced a different hash.")
    }
}

if ($PackageVersion) {
    $packageScript = Join-Path $root "build-package.ps1"
    $zipPath = Join-Path `
        $artifacts `
        "native-packages\amd-mobile-power-v$PackageVersion-win-x64-native-preview.zip"
    & $packageScript -Version $PackageVersion -NoBuild -NoVerify | Out-Null
    if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $zipPath)) {
        throw "Package build failed for $PackageVersion"
    }
    $first = Get-Sha256 $zipPath
    # A short pause makes a wall-clock timestamp visible if one sneaks back in.
    Start-Sleep -Seconds 2
    & $packageScript -Version $PackageVersion -NoBuild -NoVerify | Out-Null
    if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $zipPath)) {
        throw "Second package build failed for $PackageVersion"
    }
    $second = Get-Sha256 $zipPath
    $results.Package = [ordered]@{
        Version = $PackageVersion
        First = $first
        Second = $second
        Reproducible = $first -eq $second
        Size = (Get-Item -LiteralPath $zipPath).Length
    }
    if ($first -ne $second) {
        $failures.Add("Package rebuild produced a different hash.")
    }
}

$status = if ($failures.Count -eq 0) { "PASS" } else { "FAILED" }
$record = [ordered]@{
    Verification = $status
    RustBuildIsolation = "Fresh unique target directory; removed in finally"
    RecordedAt = (Get-Date).ToString("o")
    Results = $results
    Failures = @($failures)
}

if ($EvidencePath) {
    $evidenceDirectory = Split-Path -Parent $EvidencePath
    if ($evidenceDirectory) {
        New-Item -ItemType Directory -Path $evidenceDirectory -Force | Out-Null
    }
    $record | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $EvidencePath -Encoding utf8
}

$record | ConvertTo-Json -Depth 6
if ($status -ne "PASS") {
    exit 1
}
