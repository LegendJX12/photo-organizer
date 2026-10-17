# STEP 2 - APPLY PLAN: moves files exactly as listed in plan.csv. Nothing is deleted.
$ErrorActionPreference = 'Stop'
$ToolDir = $PSScriptRoot
$Root    = Split-Path -Parent $ToolDir
$plan = @(Import-Csv -LiteralPath (Join-Path $ToolDir 'plan.csv') -Encoding UTF8 | Where-Object { $_.Action -eq 'Move' -or $_.Action -eq 'Duplicate' })
Write-Host ('This will MOVE {0} files (duplicates go to the review folder, nothing is deleted).' -f $plan.Count) -ForegroundColor Yellow
$ans = Read-Host 'Type YES and press Enter to continue'
if ($ans -ne 'YES') { Write-Host 'Cancelled.'; return }
$undo = New-Object System.Collections.Generic.List[object]
$errs = 0; $i = 0
foreach ($p in $plan) {
    $i++
    if ($i % 100 -eq 0) { Write-Progress -Activity 'Moving' -Status "$i / $($plan.Count)" -PercentComplete ($i*100/$plan.Count) }
    $src = Join-Path $Root $p.Source
    $dst = Join-Path $Root $p.Destination
    try {
        if (-not [IO.File]::Exists($src)) { throw 'source missing' }
        $c = 2; $base = $dst
        while ([IO.File]::Exists($dst)) { $dst = Join-Path (Split-Path -Parent $base) ('{0} ({1}){2}' -f [IO.Path]::GetFileNameWithoutExtension($base), $c, [IO.Path]::GetExtension($base)); $c++ }
        [void][IO.Directory]::CreateDirectory((Split-Path -Parent $dst))
        [IO.File]::Move($src, $dst)
        $undo.Add([pscustomobject]@{ From=$src; To=$dst })
    } catch { $errs++; Add-Content -LiteralPath (Join-Path $ToolDir 'errors.txt') -Value ("{0} -> {1}" -f $p.Source, $_.Exception.Message) -Encoding UTF8 }
}
Write-Progress -Activity 'Moving' -Completed
$undo | Export-Csv -LiteralPath (Join-Path $ToolDir 'undo.csv') -NoTypeInformation -Encoding UTF8
# remove folders that are now empty (old structure only)
$keep = @('_organize_tool','_Organized','_Duplicates (review then delete)','_Needs review','_Zips (extracted - can delete)')
Get-ChildItem -LiteralPath $Root -Directory -Recurse -Force | Sort-Object { $_.FullName.Length } -Descending | ForEach-Object {
    $top = $_.FullName.Substring($Root.Length + 1).Split('\')[0]
    if ($keep -notcontains $top -and -not (Get-ChildItem -LiteralPath $_.FullName -Force)) { Remove-Item -LiteralPath $_.FullName -Force }
}
Write-Host ('DONE. Moved {0} files. Problems: {1} (see errors.txt if any).' -f $undo.Count, $errs) -ForegroundColor Green
Write-Host 'To reverse everything, run 3_UNDO.bat'
