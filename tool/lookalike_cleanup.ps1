# STEP 6 - remove lower-quality copies of the same picture (listed in lookalike_actions.csv),
# Optional MoveKeepTo column moves the kept copy to a better folder. Then tidies empty review folders.
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName Microsoft.VisualBasic
$ToolDir = $PSScriptRoot
$Root    = Split-Path -Parent $ToolDir
$acts = @(Import-Csv -LiteralPath (Join-Path $ToolDir 'lookalike_actions.csv') -Encoding UTF8)
Write-Host ("This will send {0} lower-quality copies to the Recycle Bin." -f $acts.Count) -ForegroundColor Yellow
if ((Read-Host 'Type YES and press Enter to continue') -ne 'YES') { Write-Host 'Cancelled.'; return }
$log = New-Object System.Collections.Generic.List[string]
function Recycle($p) { [Microsoft.VisualBasic.FileIO.FileSystem]::DeleteFile($p, 'OnlyErrorDialogs', 'SendToRecycleBin') }
foreach ($a in $acts) {
    $k = Join-Path $Root $a.Keep; $r = Join-Path $Root $a.Remove
    if (-not [IO.File]::Exists($k)) { $log.Add("SKIPPED (keep file missing): $($a.Keep)"); continue }
    if ([IO.File]::Exists($r)) { Recycle $r; $log.Add("Removed: $($a.Remove)") }
    if ($a.MoveKeepTo) {
        $d = Join-Path $Root $a.MoveKeepTo
        if (-not [IO.File]::Exists($d)) { [void][IO.Directory]::CreateDirectory((Split-Path -Parent $d)); [IO.File]::Move($k, $d); $log.Add("Moved: $($a.Keep) -> $($a.MoveKeepTo)") }
    }
}
# tidy empty folders
foreach ($top in '_Duplicates (review then delete)','_Needs review') {
    $t = Join-Path $Root $top
    if (Test-Path -LiteralPath $t) {
        Get-ChildItem -LiteralPath $t -Directory -Recurse -Force | Sort-Object { $_.FullName.Length } -Descending | ForEach-Object { if (-not (Get-ChildItem -LiteralPath $_.FullName -Force)) { Remove-Item -LiteralPath $_.FullName -Force } }
        if (-not (Get-ChildItem -LiteralPath $t -Force)) { Remove-Item -LiteralPath $t -Force }
    }
}
[IO.File]::WriteAllLines((Join-Path $ToolDir 'lookalike_cleanup_log.txt'), $log, (New-Object Text.UTF8Encoding $true))
Write-Host ("DONE. {0} actions. See lookalike_cleanup_log.txt" -f $log.Count) -ForegroundColor Green
Write-Host 'Go back to Claude and say "cleanup done".'
