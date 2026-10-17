# STEP 0 - EXTRACT ZIPS: unzips every .zip in the photos folder (next to the zip),
# then moves the zip itself into "_Zips (extracted - can delete)". Nothing is deleted.
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.IO.Compression.FileSystem
$ToolDir = $PSScriptRoot
$Root    = Split-Path -Parent $ToolDir
$ZipRoot = '_Zips (extracted - can delete)'
$skip = @('_organize_tool','_Organized','_Duplicates (review then delete)','_Needs review',$ZipRoot)
$zips = @(Get-ChildItem -LiteralPath $Root -Recurse -File -Filter *.zip | Where-Object { $skip -notcontains $_.FullName.Substring($Root.Length+1).Split('\')[0] })
Write-Host ("Found {0} zip files." -f $zips.Count) -ForegroundColor Cyan
foreach ($z in $zips) {
    $dest = Join-Path $z.DirectoryName ([IO.Path]::GetFileNameWithoutExtension($z.Name))
    if (Test-Path -LiteralPath $dest) { $dest = $dest + ' (extracted)' }
    Write-Host ("Extracting {0} ({1:N0} MB) ..." -f $z.Name, ($z.Length/1MB))
    try {
        [IO.Compression.ZipFile]::ExtractToDirectory($z.FullName, $dest)
        $rel = $z.FullName.Substring($Root.Length+1)
        $to = Join-Path (Join-Path $Root $ZipRoot) $rel
        [void][IO.Directory]::CreateDirectory((Split-Path -Parent $to))
        [IO.File]::Move($z.FullName, $to)
        Write-Host '   OK' -ForegroundColor Green
    } catch { Write-Host ('   FAILED: ' + $_.Exception.Message) -ForegroundColor Red }
}
Write-Host 'DONE. Now run 1_MAKE_PLAN.bat again.' -ForegroundColor Green
