param(
    [string]$RepositoryRoot,
    [string]$PackagePath,
    [string]$EvidencePath
)

$ErrorActionPreference = "Stop"

$root = if ($RepositoryRoot) {
    [System.IO.Path]::GetFullPath($RepositoryRoot)
}
else {
    Split-Path -Parent (Split-Path -Parent $PSCommandPath)
}

$internalAgentMarker = 'co' + 'dex'
$patterns = [ordered]@{
    personal_windows_home = '(?i)C:[\\/]+Users[\\/]+(?!Public(?:[\\/]|$))[A-Za-z0-9._-]+'
    internal_agent_marker = ('(?i)\b' + $internalAgentMarker + '\b')
    openai_key = '(?i)sk-[A-Za-z0-9]{20,}'
    github_personal_token = '(?i)ghp_[A-Za-z0-9]{20,}'
    github_fine_grained_token = '(?i)github_pat_[A-Za-z0-9_]{20,}'
    aws_access_key = 'AKIA[0-9A-Z]{16}'
    private_key_header = '-----BEGIN (RSA|OPENSSH|EC|DSA) PRIVATE KEY-----'
}
$regexes = @(
    foreach ($entry in $patterns.GetEnumerator()) {
        [pscustomobject]@{
            Name = $entry.Key
            Regex = [regex]::new($entry.Value)
        }
    }
)
$binaryExtensions = @(
    ".exe", ".dll", ".sys", ".png", ".ico", ".jpg", ".jpeg", ".gif",
    ".webp", ".zip", ".mp4", ".wav", ".mp3", ".pdf", ".woff", ".woff2",
    ".ttf", ".otf"
)
$selfRelative = "native/verify-public-sanitization.ps1"
$hits = New-Object System.Collections.Generic.List[object]
$trackedFilesScanned = 0
$packageEntriesScanned = 0

function Find-SanitizationHits {
    param(
        [Parameter(Mandatory = $true)][string]$Label,
        [Parameter(Mandatory = $true)][string]$Text
    )

    $lineNumber = 0
    foreach ($line in ($Text -split "`r?`n")) {
        $lineNumber++
        foreach ($regex in $regexes) {
            if ($regex.Regex.IsMatch($line)) {
                $hits.Add([pscustomobject]@{
                    Location = "${Label}:$lineNumber"
                    Pattern = $regex.Name
                })
            }
        }
    }
}

$tracked = @(& git -C $root ls-files)
if ($LASTEXITCODE -ne 0) {
    throw "git ls-files failed for $root"
}

foreach ($relative in $tracked) {
    $relative = $relative.Replace("\", "/")
    if ($relative -eq $selfRelative) {
        continue
    }
    if ([System.IO.Path]::GetExtension($relative).ToLowerInvariant() -in $binaryExtensions) {
        continue
    }
    $fullPath = Join-Path $root ($relative -replace "/", "\")
    if (-not (Test-Path -LiteralPath $fullPath -PathType Leaf)) {
        continue
    }
    $item = Get-Item -LiteralPath $fullPath
    if ($item.Length -gt 10MB) {
        continue
    }
    $bytes = [System.IO.File]::ReadAllBytes($fullPath)
    if ([Array]::IndexOf($bytes, [byte]0) -ge 0) {
        continue
    }
    $trackedFilesScanned++
    Find-SanitizationHits `
        -Label $relative `
        -Text ([System.Text.Encoding]::UTF8.GetString($bytes))
}

if ($PackagePath) {
    $resolvedPackage = (Resolve-Path -LiteralPath $PackagePath).Path
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $archive = [System.IO.Compression.ZipFile]::OpenRead($resolvedPackage)
    try {
        foreach ($entry in $archive.Entries) {
            if ([string]::IsNullOrEmpty($entry.Name) -or
                $entry.Length -gt 10MB -or
                [System.IO.Path]::GetExtension($entry.Name).ToLowerInvariant() -in $binaryExtensions) {
                continue
            }
            $reader = [System.IO.StreamReader]::new($entry.Open())
            try {
                $text = $reader.ReadToEnd()
            }
            finally {
                $reader.Dispose()
            }
            $packageEntriesScanned++
            Find-SanitizationHits `
                -Label ("package:" + $entry.FullName) `
                -Text $text
        }
    }
    finally {
        $archive.Dispose()
    }
}

if ($hits.Count -gt 0) {
    $hits |
        Select-Object Location, Pattern |
        Format-Table -AutoSize
    throw "$($hits.Count) public-sanitization hit(s) found."
}

$result = [ordered]@{
    SchemaVersion = 1
    Verification = "PASS"
    TrackedFilesScanned = $trackedFilesScanned
    PackageEntriesScanned = $packageEntriesScanned
    Patterns = @($patterns.Keys)
    PackagePath = if ($PackagePath) {
        [System.IO.Path]::GetFullPath($PackagePath)
    } else {
        $null
    }
    RecordedAt = (Get-Date).ToString("o")
}

if ($EvidencePath) {
    $evidenceDirectory = Split-Path -Parent $EvidencePath
    if ($evidenceDirectory) {
        New-Item -ItemType Directory -Path $evidenceDirectory -Force | Out-Null
    }
    $result | ConvertTo-Json -Depth 5 |
        Set-Content -LiteralPath $EvidencePath -Encoding UTF8
}

$result | ConvertTo-Json -Depth 5
