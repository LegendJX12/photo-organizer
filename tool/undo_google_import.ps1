$ToolDir = $PSScriptRoot; $Root = Split-Path -Parent $ToolDir
$log = @(Import-Csv -LiteralPath (Join-Path $ToolDir 'google_import_log.csv') -Encoding UTF8 | Where-Object Status -eq 'OK')
if ((Read-Host ('Remove the {0} copied Google photos again? Type YES' -f $log.Count)) -ne 'YES') { return }
foreach ($r in $log) { $f = Join-Path $Root $r.Copied; if ([IO.File]::Exists($f)) { Remove-Item -LiteralPath $f -Force } }
Write-Host 'Undo finished (the originals are still in your Takeout folder).' -ForegroundColor Green
