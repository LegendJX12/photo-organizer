# Merges several year folders in _Organized into one flat folder (no subfolders).
# Which years go where is read from merge_years.csv (columns: Target, Years  e.g. "2009-2010 Childhood","2009;2010").
# Same name + same content -> extra copy to Recycle Bin; same name but different photo -> renamed "name (2)". Undo list: merge_old_years_undo.csv
$ErrorActionPreference = 'Stop'
$tool = $PSScriptRoot
$root = Split-Path $tool -Parent
$org  = Join-Path $root '_Organized'
Add-Type -AssemblyName Microsoft.VisualBasic
$sha = [System.Security.Cryptography.SHA256]::Create()
function HashFile($p) { $fs = [System.IO.File]::OpenRead($p); try { [BitConverter]::ToString($sha.ComputeHash($fs)) } finally { $fs.Close() } }

$cfg = Join-Path $tool 'merge_years.csv'
if (-not (Test-Path -LiteralPath $cfg)) { Write-Host 'merge_years.csv not found next to this script. See examples\merge_years.csv.'; exit }
$jobs = @(Import-Csv -LiteralPath $cfg -Encoding UTF8 | ForEach-Object { @{ Target = $_.Target; Years = @($_.Years -split ';' | ForEach-Object { $_.Trim() } | Where-Object { $_ }) } })
$undo = New-Object System.Collections.ArrayList
$log  = New-Object System.Collections.ArrayList
foreach ($j in $jobs) {
  $dst = Join-Path $org $j.Target
  if (-not (Test-Path -LiteralPath $dst)) { New-Item -ItemType Directory -Path $dst | Out-Null }
  foreach ($y in $j.Years) {
    $src = Join-Path $org $y
    if (-not (Test-Path -LiteralPath $src)) { [void]$log.Add("Missing folder: $y"); continue }
    foreach ($f in (Get-ChildItem -LiteralPath $src -Recurse -File -Force | Sort-Object FullName)) {
      $to = Join-Path $dst $f.Name
      if (Test-Path -LiteralPath $to) {
        if ((Get-Item -LiteralPath $to).Length -eq $f.Length -and (HashFile $to) -eq (HashFile $f.FullName)) {
          [Microsoft.VisualBasic.FileIO.FileSystem]::DeleteFile($f.FullName, 'OnlyErrorDialogs', 'SendToRecycleBin')
          [void]$log.Add("Exact duplicate recycled: $($f.FullName.Substring($org.Length+1))")
          continue
        }
        $n = 2
        do { $to = Join-Path $dst ("{0} ({1}){2}" -f $f.BaseName, $n, $f.Extension); $n++ } while (Test-Path -LiteralPath $to)
        [void]$log.Add("Same name, different photo - renamed: $($f.Name) -> $(Split-Path $to -Leaf)")
      }
      Move-Item -LiteralPath $f.FullName -Destination $to
      [void]$undo.Add([pscustomobject]@{ From = $f.FullName; To = $to })
    }
    # remove the now-empty year folder
    Get-ChildItem -LiteralPath $src -Recurse -Directory -Force | Sort-Object { $_.FullName.Length } -Descending | ForEach-Object {
      if (-not (Get-ChildItem -LiteralPath $_.FullName -Force)) { Remove-Item -LiteralPath $_.FullName -Force }
    }
    if (-not (Get-ChildItem -LiteralPath $src -Force)) { Remove-Item -LiteralPath $src -Force; [void]$log.Add("Removed empty folder: $y") }
    else { [void]$log.Add("WARNING: $y not empty, left in place") }
  }
  $cnt = @(Get-ChildItem -LiteralPath $dst -File).Count
  [void]$log.Add("$($j.Target): $cnt files")
}
$undo | Export-Csv (Join-Path $tool 'merge_old_years_undo.csv') -NoTypeInformation -Encoding UTF8
$log | Set-Content (Join-Path $tool 'merge_old_years_log.txt') -Encoding UTF8
$log | ForEach-Object { Write-Host $_ }
Write-Host "Moved $($undo.Count) files. Done - you can close this window."
