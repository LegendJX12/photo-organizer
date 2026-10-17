# STEP 16 - COPY the Google-only photos into your organized folders (google_import.csv).
# Takeout files are not changed. Log: google_import_log.csv. Undo: 17_UNDO_GOOGLE_IMPORT.bat
$ErrorActionPreference = 'Stop'
$ToolDir = $PSScriptRoot; $Root = Split-Path -Parent $ToolDir
$Src = Join-Path $env:USERPROFILE 'Downloads\GooglePhotosTakeout\Takeout\Google Photos'
$rows = @(Import-Csv -LiteralPath (Join-Path $ToolDir 'google_import.csv') -Encoding UTF8)
Write-Host ("This will COPY {0} Google-only photos/videos into your photos folder." -f $rows.Count) -ForegroundColor Yellow
if ((Read-Host 'Type YES and press Enter to continue') -ne 'YES') { Write-Host 'Cancelled.'; return }
$log = New-Object System.Collections.Generic.List[object]; $err = 0; $i = 0
foreach ($r in $rows) {
    $i++; if ($i % 50 -eq 0) { Write-Progress -Activity 'Copying from Google Takeout' -Status "$i / $($rows.Count)" -PercentComplete ($i*100/$rows.Count) }
    $s = Join-Path $Src $r.Source; $d = Join-Path $Root $r.Destination
    try {
        if (-not [IO.File]::Exists($s)) { throw 'source missing' }
        $c=2; $b=$d; while ([IO.File]::Exists($d)) { $d = Join-Path (Split-Path -Parent $b) ('{0} ({1}){2}' -f [IO.Path]::GetFileNameWithoutExtension($b),$c,[IO.Path]::GetExtension($b)); $c++ }
        [void][IO.Directory]::CreateDirectory((Split-Path -Parent $d))
        [IO.File]::Copy($s, $d)
        if ((Get-Item -LiteralPath $d).Length -ne (Get-Item -LiteralPath $s).Length) { throw 'copy size mismatch' }
        $log.Add([pscustomobject]@{ Source=$r.Source; Copied=$d.Substring($Root.Length+1); Status='OK' })
    } catch { $err++; $log.Add([pscustomobject]@{ Source=$r.Source; Copied=''; Status=$_.Exception.Message }) }
}
Write-Progress -Activity 'Copying from Google Takeout' -Completed
$log | Export-Csv -LiteralPath (Join-Path $ToolDir 'google_import_log.csv') -NoTypeInformation -Encoding UTF8
Write-Host ("DONE. Copied {0}, problems {1}." -f ($rows.Count-$err), $err) -ForegroundColor Green
Write-Host 'Go back to Claude and say "import done".'
