# Applies onedrive_actions.csv:
#  Recycle -> Recycle Bin (exact copy in _Organized, or deleted before on purpose)
#  Review  -> moved to "_Review after OneDrive" (kept, for you to look at)
#  Zip     -> files missing from _Organized are extracted to the review folder, then the zip is recycled
$ErrorActionPreference = 'Stop'
$tool = $PSScriptRoot
$root = Split-Path $tool -Parent
$org  = Join-Path $root '_Organized'
$rev  = Join-Path $root '_Review after OneDrive'
Add-Type -AssemblyName Microsoft.VisualBasic
Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem
$sha = [System.Security.Cryptography.SHA256]::Create()
function HashFile($p) { $fs = [System.IO.File]::OpenRead($p); try { [BitConverter]::ToString($sha.ComputeHash($fs)) } finally { $fs.Close() } }
function Recycle($p) { [Microsoft.VisualBasic.FileIO.FileSystem]::DeleteFile($p, 'OnlyErrorDialogs', 'SendToRecycleBin') }

$bySize = @{}
Get-ChildItem -LiteralPath $org -Recurse -File -Force | ForEach-Object {
  $k = [string]$_.Length
  if (-not $bySize.ContainsKey($k)) { $bySize[$k] = New-Object System.Collections.ArrayList }
  [void]$bySize[$k].Add($_.FullName)
}
$oh = @{}
function InOrganized([long]$len, [string]$h) {
  $k = [string]$len
  if (-not $bySize.ContainsKey($k)) { return $false }
  foreach ($c in $bySize[$k]) { if (-not $oh.ContainsKey($c)) { $oh[$c] = HashFile $c }; if ($oh[$c] -eq $h) { return $true } }
  return $false
}

$log = New-Object System.Collections.ArrayList
$rows = Import-Csv (Join-Path $tool 'onedrive_actions.csv') -Encoding UTF8
foreach ($r in $rows) {
  $p = Join-Path $root $r.Path
  if (-not (Test-Path -LiteralPath $p)) { [void]$log.Add("Already gone: $($r.Path)"); continue }
  try {
    if ($r.Action -eq 'Recycle') { Recycle $p; [void]$log.Add("Recycled: $($r.Path)") }
    elseif ($r.Action -eq 'Review') {
      $to = Join-Path $rev $r.Path
      New-Item -ItemType Directory -Force -Path (Split-Path $to -Parent) | Out-Null
      Move-Item -LiteralPath $p -Destination $to
      [void]$log.Add("To review: $($r.Path)")
    }
    elseif ($r.Action -eq 'Zip') {
      $zdir = Join-Path $rev ([IO.Path]::GetFileNameWithoutExtension($p) + ' (missing files)')
      $z = [System.IO.Compression.ZipFile]::OpenRead($p)
      $bad = 0
      try {
        foreach ($e in $z.Entries) {
          if ($e.Length -eq 0 -or $e.FullName.EndsWith('/')) { continue }
          $s = $e.Open(); try { $h = [BitConverter]::ToString($sha.ComputeHash($s)) } finally { $s.Close() }
          if (-not (InOrganized $e.Length $h)) {
            $to = Join-Path $zdir ($e.FullName -replace '/', '\')
            New-Item -ItemType Directory -Force -Path (Split-Path $to -Parent) | Out-Null
            [System.IO.Compression.ZipFileExtensions]::ExtractToFile($e, $to, $false)
            if ((Get-Item -LiteralPath $to).Length -ne $e.Length) { $bad++ }
            [void]$log.Add("Extracted from zip: $($e.FullName)")
          }
        }
      } finally { $z.Dispose() }
      if ($bad -eq 0) { Recycle $p; [void]$log.Add("Recycled zip: $($r.Path)") } else { [void]$log.Add("Zip KEPT (extract problem): $($r.Path)") }
    }
  } catch { [void]$log.Add("FAILED: $($r.Path)  $($_.Exception.Message)") }
}

# remove old folders that are now empty
Get-ChildItem -LiteralPath $root -Directory -Force | Where-Object { $_.Name -notin @('_Organized', '_organize_tool', '_Review after OneDrive') } | ForEach-Object {
  $d = $_.FullName
  Get-ChildItem -LiteralPath $d -Recurse -Directory -Force | Sort-Object { $_.FullName.Length } -Descending | ForEach-Object {
    if (-not (Get-ChildItem -LiteralPath $_.FullName -Force)) { Remove-Item -LiteralPath $_.FullName -Force }
  }
  if (-not (Get-ChildItem -LiteralPath $d -Force)) { Remove-Item -LiteralPath $d -Force; [void]$log.Add("Removed empty folder: $($_.Name)") }
  else { [void]$log.Add("Folder NOT empty, left: $($_.Name)") }
}
$log | Set-Content (Join-Path $tool 'onedrive_apply_log.txt') -Encoding UTF8
$sum = "Recycled: $(@($log | Where-Object { $_ -like 'Recycled*' }).Count)  To review: $(@($log | Where-Object { $_ -like 'To review*' }).Count)  Extracted: $(@($log | Where-Object { $_ -like 'Extracted*' }).Count)  Failed: $(@($log | Where-Object { $_ -like 'FAILED*' }).Count)"
Write-Host $sum
Add-Content (Join-Path $tool 'onedrive_apply_log.txt') $sum
Write-Host 'Done - you can close this window.'
