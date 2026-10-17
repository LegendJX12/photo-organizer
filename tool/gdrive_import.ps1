# Copies the chosen pictures/videos from Google Drive (G:) into photos\_Organized. Drive is not changed.
$ErrorActionPreference = 'Stop'
$tool = $PSScriptRoot
$photos = Split-Path $tool -Parent
$rows = Import-Csv (Join-Path $tool 'gdrive_import.csv') -Encoding UTF8
$need = ($rows | Measure-Object -Property Size -Sum).Sum
$drive = Get-PSDrive -Name ($photos.Substring(0, 1))
Write-Host ("Files to copy: {0}  ({1:N1} GB). Free space on {2}: {3:N1} GB" -f $rows.Count, ($need / 1GB), $drive.Name, ($drive.Free / 1GB))
if ($drive.Free -lt ($need + 10GB)) { Write-Host 'Not enough free space (need the files + 10 GB spare). Stopping - nothing copied.'; exit }

$log = New-Object System.Collections.ArrayList
$undo = New-Object System.Collections.ArrayList
$i = 0
foreach ($r in $rows) {
  $i++
  $name = Split-Path $r.Source -Leaf
  $dir = Join-Path $photos $r.DestFolder
  Write-Host ("[{0}/{1}] {2}" -f $i, $rows.Count, $name)
  try {
    if (-not (Test-Path -LiteralPath $r.Source)) { [void]$log.Add("MISSING in Drive: $($r.Source)"); continue }
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
    $to = Join-Path $dir $name
    if (Test-Path -LiteralPath $to) {
      if ((Get-Item -LiteralPath $to).Length -eq [long]$r.Size) { [void]$log.Add("Already there: $to"); continue }
      $base = [IO.Path]::GetFileNameWithoutExtension($name); $ext = [IO.Path]::GetExtension($name); $n = 2
      do { $to = Join-Path $dir ("{0} ({1}){2}" -f $base, $n, $ext); $n++ } while (Test-Path -LiteralPath $to)
    }
    $ok = $false
    for ($t = 1; $t -le 2 -and -not $ok; $t++) {
      try {
        Copy-Item -LiteralPath $r.Source -Destination $to -Force
        if ((Get-Item -LiteralPath $to).Length -eq [long]$r.Size) { $ok = $true }
        else { Remove-Item -LiteralPath $to -Force }
      } catch { if (Test-Path -LiteralPath $to) { Remove-Item -LiteralPath $to -Force } }
    }
    if ($ok) { [void]$log.Add("Copied: $($r.Source) -> $to"); [void]$undo.Add([pscustomobject]@{ Copied = $to }) }
    else { [void]$log.Add("FAILED (size check): $($r.Source)") }
  } catch { [void]$log.Add("FAILED: $($r.Source)  $($_.Exception.Message)") }
}
$undo | Export-Csv (Join-Path $tool 'gdrive_import_undo.csv') -NoTypeInformation -Encoding UTF8
$sum = "Copied: $(@($log | Where-Object { $_ -like 'Copied*' }).Count)  Already there: $(@($log | Where-Object { $_ -like 'Already*' }).Count)  Failed/missing: $(@($log | Where-Object { $_ -like 'FAILED*' -or $_ -like 'MISSING*' }).Count)"
[void]$log.Add($sum)
$log | Set-Content (Join-Path $tool 'gdrive_import_log.txt') -Encoding UTF8
Write-Host $sum
Write-Host 'Done - you can close this window.'
