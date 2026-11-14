param(
    [Parameter(Mandatory = $true)][string]$PackagePath,
    [string]$EvidencePath
)
$ErrorActionPreference = 'Stop'
$repository = Split-Path -Parent (Split-Path -Parent $PSCommandPath)
$artifacts = [System.IO.Path]::GetFullPath((Join-Path $repository 'artifacts'))
$scratch = [System.IO.Path]::GetFullPath((Join-Path $artifacts "native-build\repack-$([Guid]::NewGuid().ToString('N'))"))
if (-not $scratch.StartsWith($artifacts + [System.IO.Path]::DirectorySeparatorChar,
    [System.StringComparison]::OrdinalIgnoreCase)) { throw 'Scratch directory escapes artifacts.' }
$package = (Resolve-Path -LiteralPath $PackagePath).Path
$originalHash = (Get-FileHash -LiteralPath $package -Algorithm SHA256).Hash.ToLowerInvariant()
Add-Type -AssemblyName System.IO.Compression.FileSystem
try {
    $extracted = Join-Path $scratch 'extracted'
    Expand-Archive -LiteralPath $package -DestinationPath $extracted
    $roots = @(Get-ChildItem -LiteralPath $extracted)
    if ($roots.Count -ne 1 -or -not $roots[0].PSIsContainer) { throw 'Expected exactly one package root directory.' }
    $rebuilt = Join-Path $scratch 'repacked.zip'
    $output = [System.IO.File]::Open($rebuilt, [System.IO.FileMode]::CreateNew)
    try {
        $archive = [System.IO.Compression.ZipArchive]::new($output,
            [System.IO.Compression.ZipArchiveMode]::Create, $true)
        try {
            foreach ($file in Get-ChildItem -LiteralPath $roots[0].FullName -File -Recurse | Sort-Object FullName) {
                $relative = [System.IO.Path]::GetRelativePath($roots[0].FullName, $file.FullName).Replace('\', '/')
                $entry = $archive.CreateEntry("$($roots[0].Name)/$relative", [System.IO.Compression.CompressionLevel]::Optimal)
                $entry.LastWriteTime = [DateTimeOffset]::new(2000, 1, 1, 0, 0, 0, [TimeSpan]::Zero)
                $destination = $entry.Open()
                try {
                    $source = [System.IO.File]::OpenRead($file.FullName)
                    try { $source.CopyTo($destination) } finally { $source.Dispose() }
                } finally { $destination.Dispose() }
            }
        } finally { $archive.Dispose() }
    } finally { $output.Dispose() }
    $repackedHash = (Get-FileHash -LiteralPath $rebuilt -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($repackedHash -ne $originalHash) { throw 'Repacked ZIP differs from the candidate.' }
    if ((Get-FileHash -LiteralPath $package -Algorithm SHA256).Hash.ToLowerInvariant() -ne $originalHash) {
        throw 'Original ZIP changed during verification.'
    }
    $record = [ordered]@{
        Verification = 'PASS'
        Scope = 'Existing package contents and deterministic ZIP serialization; not a source rebuild'
        Package = Split-Path -Leaf $package
        OriginalSHA256 = $originalHash
        RepackedSHA256 = $repackedHash
        OriginalUnchanged = $true
        RecordedAt = (Get-Date).ToString('o')
    }
} finally {
    if (Test-Path -LiteralPath $scratch) { Remove-Item -LiteralPath $scratch -Recurse -Force }
}
if ($EvidencePath) {
    $parent = Split-Path -Parent $EvidencePath
    if ($parent) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
    $record | ConvertTo-Json | Set-Content -LiteralPath $EvidencePath -Encoding utf8
}
$record | ConvertTo-Json
