# STEP 12 - apply your similar-shot review: merge stacks, delete chosen extra shots (to Recycle Bin).
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName Microsoft.VisualBasic
$ToolDir = $PSScriptRoot; $Root = Split-Path -Parent $ToolDir
$acts = @(Import-Csv -LiteralPath (Join-Path $ToolDir 'stack_edits.csv') -Encoding UTF8)
$mv = @($acts | Where-Object Action -eq 'move').Count; $rc = @($acts | Where-Object Action -eq 'recycle').Count
Write-Host ("Merge stacks: {0} moves. Delete extra shots: {1} files to Recycle Bin." -f $mv, $rc) -ForegroundColor Yellow
if ((Read-Host 'Type YES and press Enter to continue') -ne 'YES') { Write-Host 'Cancelled.'; return }
$log = New-Object System.Collections.Generic.List[object]; $dirs = @{}
foreach ($a in $acts) {
    $src = Join-Path $Root $a.From
    if (-not [IO.File]::Exists($src)) { $log.Add([pscustomobject]@{Action='SKIP (missing)';From=$a.From;To=$a.To}); continue }
    $dirs[(Split-Path -Parent $src)] = 1
    if ($a.Action -eq 'recycle') {
        [Microsoft.VisualBasic.FileIO.FileSystem]::DeleteFile($src,'OnlyErrorDialogs','SendToRecycleBin')
        $log.Add([pscustomobject]@{Action='Recycled';From=$a.From;To=''})
    } else {
        $dst = Join-Path $Root $a.To; $c=2; $b=$dst
        while ([IO.File]::Exists($dst)) { $dst = Join-Path (Split-Path -Parent $b) ('{0} ({1}){2}' -f [IO.Path]::GetFileNameWithoutExtension($b),$c,[IO.Path]::GetExtension($b)); $c++ }
        [void][IO.Directory]::CreateDirectory((Split-Path -Parent $dst)); [IO.File]::Move($src,$dst)
        $log.Add([pscustomobject]@{Action='Moved';From=$a.From;To=$dst.Substring($Root.Length+1)})
    }
}
foreach ($d in $dirs.Keys) { if ((Test-Path -LiteralPath $d) -and $d -like '* - similar shots' -and -not (Get-ChildItem -LiteralPath $d -Force)) { Remove-Item -LiteralPath $d -Force } }
$log | Export-Csv -LiteralPath (Join-Path $ToolDir 'stack_edits_log.csv') -NoTypeInformation -Encoding UTF8
Write-Host ("DONE. {0} actions. Log: stack_edits_log.csv" -f $log.Count) -ForegroundColor Green
Write-Host 'Go back to Claude and say "stacks updated".'
