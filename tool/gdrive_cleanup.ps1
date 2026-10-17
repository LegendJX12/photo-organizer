# Deletes from Google Drive (G:) ONLY the files that have a same-size copy in photos\_Organized.
# Deleted Drive files go to Google Drive Trash (restorable for 30 days).
$ErrorActionPreference = 'Stop'
$tool = $PSScriptRoot
$photos = Split-Path $tool -Parent
$rows = Import-Csv (Join-Path $tool 'gdrive_delete_list.csv') -Encoding UTF8
$log = New-Object System.Collections.ArrayList
foreach ($r in $rows) {
  try {
    if (-not (Test-Path -LiteralPath $r.Source)) { [void]$log.Add("Already gone from Drive: $($r.Source)"); continue }
    $name = Split-Path $r.Source -Leaf
    $dir = Join-Path $photos $r.DestFolder
    $base = [IO.Path]::GetFileNameWithoutExtension($name); $ext = [IO.Path]::GetExtension($name)
    $copy = $null
    if (Test-Path -LiteralPath $dir) {
      $copy = Get-ChildItem -LiteralPath $dir -File | Where-Object {
        ($_.Name -eq $name -or ($_.BaseName -like "$base (*)" -and $_.Extension -eq $ext)) -and $_.Length -eq [long]$r.Size
      } | Select-Object -First 1
    }
    if ($copy) {
      Remove-Item -LiteralPath $r.Source -Force
      [void]$log.Add("Deleted from Drive: $($r.Source)  (copy: $($copy.FullName.Substring($photos.Length + 1)))")
    } else { [void]$log.Add("KEPT in Drive (no matching copy in photos): $($r.Source)") }
  } catch { [void]$log.Add("FAILED: $($r.Source)  $($_.Exception.Message)") }
}
$sum = "Deleted: $(@($log | Where-Object { $_ -like 'Deleted*' }).Count)  Kept: $(@($log | Where-Object { $_ -like 'KEPT*' }).Count)  Failed: $(@($log | Where-Object { $_ -like 'FAILED*' }).Count)"
[void]$log.Add($sum)
$log | Set-Content (Join-Path $tool 'gdrive_cleanup_log.txt') -Encoding UTF8
Write-Host $sum
Write-Host 'Done - you can close this window.'
