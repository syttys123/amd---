param(
    [string]$RepositoryRoot
)

$ErrorActionPreference = "Stop"

$root = if ($RepositoryRoot) {
    [System.IO.Path]::GetFullPath($RepositoryRoot)
}
else {
    Split-Path -Parent (Split-Path -Parent $PSCommandPath)
}

$markdownFiles = @(
    Get-ChildItem -LiteralPath $root -Recurse -Filter *.md -File |
        Where-Object {
            $_.FullName -notmatch "\\artifacts\\" -and
            $_.FullName -notmatch "\\Temp\\" -and
            $_.FullName -notmatch "\\third_party\\" -and
            $_.FullName -notmatch "\\node_modules\\"
        }
)

$broken = New-Object System.Collections.Generic.List[string]
$checked = 0

foreach ($file in $markdownFiles) {
    $text = Get-Content -LiteralPath $file.FullName -Raw
    foreach ($match in [regex]::Matches($text, "\]\(([^)#]+?)(#[^)]*)?\)")) {
        $link = $match.Groups[1].Value.Trim()
        if ([string]::IsNullOrWhiteSpace($link) -or
            $link -match "^(https?:|mailto:)") {
            continue
        }
        $checked++
        $relative = $link -replace "/", "\"
        if (-not (Test-Path -LiteralPath (Join-Path $file.DirectoryName $relative))) {
            $display = $file.FullName.Substring($root.Length).TrimStart("\")
            $broken.Add("$display -> $link")
        }
    }
}

if ($broken.Count -gt 0) {
    $broken | ForEach-Object { Write-Output "BROKEN $_" }
    throw "$($broken.Count) broken relative link(s) in Markdown files."
}

[ordered]@{
    Verification = "PASS"
    MarkdownFiles = $markdownFiles.Count
    RelativeLinks = $checked
    RecordedAt = (Get-Date).ToString("o")
} | ConvertTo-Json
