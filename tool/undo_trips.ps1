$ToolDir = $PSScriptRoot
$log = @(Import-Csv -LiteralPath (Join-Path $ToolDir 'trips_undo.csv') -Encoding UTF8)
if ((Read-Host ('Move {0} files back to where they were before step 10? Type YES' -f $log.Count)) -ne 'YES') { return }
[array]::Reverse($log)
foreach ($r in $log) { try { [void][IO.Directory]::CreateDirectory((Split-Path -Parent $r.From)); [IO.File]::Move($r.To, $r.From) } catch { Write-Host "Failed: $($r.To)" -ForegroundColor Red } }
Write-Host 'Undo finished.' -ForegroundColor Green
