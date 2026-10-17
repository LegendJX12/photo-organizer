# UNDO - moves every file back to where it was before apply.
$ToolDir = $PSScriptRoot
$log = @(Import-Csv -LiteralPath (Join-Path $ToolDir 'undo.csv') -Encoding UTF8)
$ans = Read-Host ('Move {0} files back to their original places? Type YES' -f $log.Count)
if ($ans -ne 'YES') { return }
[array]::Reverse($log)
foreach ($r in $log) {
    try { [void][IO.Directory]::CreateDirectory((Split-Path -Parent $r.From)); [IO.File]::Move($r.To, $r.From) } catch { Write-Host ("Failed: {0}" -f $r.To) -ForegroundColor Red }
}
Write-Host 'Undo finished.' -ForegroundColor Green
