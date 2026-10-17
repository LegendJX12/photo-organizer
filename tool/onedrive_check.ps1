param([switch]$Apply)
# Checks files that OneDrive brought back to the old places (outside _Organized / _organize_tool).
# Without -Apply: only writes a report. With -Apply: sends safe ones to the Recycle Bin.
$ErrorActionPreference = 'Stop'
$tool = $PSScriptRoot
$root = Split-Path $tool -Parent
$org  = Join-Path $root '_Organized'
Add-Type -AssemblyName Microsoft.VisualBasic
Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem

function Rel($p) { return $p.Substring($root.Length + 1) }
$sha = [System.Security.Cryptography.SHA256]::Create()
function HashFile($p) {
  $fs = [System.IO.File]::OpenRead($p)
  try { return [BitConverter]::ToString($sha.ComputeHash($fs)) } finally { $fs.Close() }
}
function HashStream($s) { return [BitConverter]::ToString($sha.ComputeHash($s)) }

Write-Host 'Step 1/4: reading the old plan...'
$planned = @{}
Import-Csv (Join-Path $tool 'plan.csv') -Encoding UTF8 | ForEach-Object { $planned[$_.Source.ToLower()] = $_.Action }

Write-Host 'Step 2/4: listing _Organized...'
$bySize = @{}
$orgCount = 0
Get-ChildItem -LiteralPath $org -Recurse -File -Force | ForEach-Object {
  $orgCount++
  $k = [string]$_.Length
  if (-not $bySize.ContainsKey($k)) { $bySize[$k] = New-Object System.Collections.ArrayList }
  [void]$bySize[$k].Add($_.FullName)
}
$orgHash = @{}
function FindCopy([long]$len, [scriptblock]$getHash) {
  $k = [string]$len
  if (-not $bySize.ContainsKey($k)) { return $null }
  $h = & $getHash
  foreach ($c in $bySize[$k]) {
    if (-not $orgHash.ContainsKey($c)) { try { $orgHash[$c] = HashFile $c } catch { $orgHash[$c] = 'ERR' } }
    if ($orgHash[$c] -eq $h) { return $c }
  }
  return $null
}

Write-Host 'Step 3/4: checking the files that came back...'
$back = Get-ChildItem -LiteralPath $root -Force | Where-Object { $_.Name -ne '_Organized' -and $_.Name -ne '_organize_tool' }
$files = @()
foreach ($b in $back) {
  if ($b.PSIsContainer) { $files += Get-ChildItem -LiteralPath $b.FullName -Recurse -File -Force } else { $files += $b }
}
$rows = New-Object System.Collections.ArrayList
$i = 0
foreach ($f in $files) {
  $i++
  if ($i % 200 -eq 0) { Write-Host "  $i / $($files.Count)" }
  $rel = Rel $f.FullName
  $cloud = (([int]$f.Attributes) -band 0x401000) -ne 0
  $cat = ''; $match = ''
  try {
    if ($f.Extension -ieq '.zip') {
      $z = [System.IO.Compression.ZipFile]::OpenRead($f.FullName)
      $total = 0; $found = 0; $missing = @()
      try {
        foreach ($e in $z.Entries) {
          if ($e.Length -eq 0 -or $e.FullName.EndsWith('/')) { continue }
          $total++
          $entry = $e
          $c = FindCopy $e.Length { $s = $entry.Open(); try { HashStream $s } finally { $s.Close() } }
          if ($c) { $found++ } else { $missing += $e.FullName }
        }
      } finally { $z.Dispose() }
      if ($total -gt 0 -and $found -eq $total) { $cat = 'A_SAFE'; $match = "zip: all $total files already in _Organized" }
      else { $cat = 'C_KEEP_REVIEW'; $match = "zip: $found of $total in _Organized; missing e.g. " + (($missing | Select-Object -First 3) -join ' | ') }
    } else {
      $path = $f.FullName
      $c = FindCopy $f.Length { HashFile $path }
      if ($c) { $cat = 'A_SAFE'; $match = Rel $c }
      elseif ($planned.ContainsKey($rel.ToLower())) { $cat = 'B_DELETED_BEFORE'; $match = 'was in the first plan (' + $planned[$rel.ToLower()] + '); its copy was removed later on purpose (duplicate / look-alike / removed stack)' }
      else { $cat = 'C_KEEP_REVIEW'; $match = 'not seen before and no copy in _Organized' }
    }
  } catch { $cat = 'C_KEEP_REVIEW'; $match = 'could not read: ' + $_.Exception.Message }
  [void]$rows.Add([pscustomobject]@{ Category = $cat; Path = $rel; Size = $f.Length; CloudOnly = $cloud; Match = $match })
}

$rows | Export-Csv (Join-Path $tool 'onedrive_check.csv') -NoTypeInformation -Encoding UTF8
$a = @($rows | Where-Object Category -eq 'A_SAFE').Count
$bb = @($rows | Where-Object Category -eq 'B_DELETED_BEFORE').Count
$cc = @($rows | Where-Object Category -eq 'C_KEEP_REVIEW').Count
$cl = @($rows | Where-Object CloudOnly).Count
$rep = @(
  "OneDrive check  $(Get-Date)",
  "Files in _Organized now: $orgCount",
  "Files that came back outside _Organized: $($rows.Count)  (cloud-only: $cl)",
  "A  exact copy already in _Organized (safe to recycle): $a",
  "B  you deleted these before (duplicates / look-alikes / removed stacks): $bb",
  "C  keep - not matched, please review: $cc",
  '',
  'C list:'
) + ($rows | Where-Object Category -eq 'C_KEEP_REVIEW' | ForEach-Object { "  $($_.Path)  [$($_.Match)]" })

if ($Apply) {
  Write-Host 'Step 4/4: sending A and B to the Recycle Bin...'
  $log = New-Object System.Collections.ArrayList
  foreach ($r in ($rows | Where-Object { $_.Category -ne 'C_KEEP_REVIEW' })) {
    $p = Join-Path $root $r.Path
    try {
      [Microsoft.VisualBasic.FileIO.FileSystem]::DeleteFile($p, 'OnlyErrorDialogs', 'SendToRecycleBin')
      [void]$log.Add("Recycled: $($r.Path)")
    } catch { [void]$log.Add("FAILED: $($r.Path)  $($_.Exception.Message)") }
  }
  # remove old folders that are now empty
  foreach ($b in @($back | Where-Object PSIsContainer)) {
    Get-ChildItem -LiteralPath $b.FullName -Recurse -Directory -Force | Sort-Object { $_.FullName.Length } -Descending | ForEach-Object {
      if (-not (Get-ChildItem -LiteralPath $_.FullName -Force)) { Remove-Item -LiteralPath $_.FullName -Force }
    }
    if (-not (Get-ChildItem -LiteralPath $b.FullName -Force)) { Remove-Item -LiteralPath $b.FullName -Force }
  }
  $log | Set-Content (Join-Path $tool 'onedrive_cleanup_log.txt') -Encoding UTF8
  $rep += ''; $rep += "Cleanup done: $(@($log | Where-Object { $_ -like 'Recycled*' }).Count) recycled, $(@($log | Where-Object { $_ -like 'FAILED*' }).Count) failed."
  $rep | Set-Content (Join-Path $tool 'onedrive_cleanup_report.txt') -Encoding UTF8
} else {
  $rep | Set-Content (Join-Path $tool 'onedrive_check_report.txt') -Encoding UTF8
}
$rep | Select-Object -First 8 | ForEach-Object { Write-Host $_ }
Write-Host 'Done. You can close this window.'
