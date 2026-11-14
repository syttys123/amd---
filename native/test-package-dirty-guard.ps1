param([string]$Version = '1.0.34')
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSCommandPath
$repository = Split-Path -Parent $root
$status = (& git -C $repository status --porcelain --ignore-submodules=dirty |
    Where-Object { $_ -notmatch '^.. docs/evidence/' } | Out-String).Trim()
if (-not $status) { throw 'Run this regression with an existing diagnostic source change; the test never dirties source itself.' }
$zip = Join-Path $repository "artifacts\native-packages\amd-mobile-power-v$Version-win-x64-native-preview.zip"
$before = if (Test-Path -LiteralPath $zip) { (Get-FileHash -LiteralPath $zip).Hash } else { $null }
$blocked = $false
try { & (Join-Path $root 'build-package.ps1') -Version $Version -NoBuild -NoVerify }
catch { $blocked = $_.Exception.Message -like 'Dirty worktree requires*' }
$after = if (Test-Path -LiteralPath $zip) { (Get-FileHash -LiteralPath $zip).Hash } else { $null }
if (-not $blocked -or $before -ne $after) { throw 'Dirty package guard failed or changed the existing artifact.' }
[pscustomobject]@{ Verification = 'PASS'; ExistingArtifactUnchanged = $true }
