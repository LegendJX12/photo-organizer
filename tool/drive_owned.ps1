param([switch]$Apply)
# For each Drive file OWNED by you (drive_owned_manifest.csv):
#  check if photos\_Organized has it (same size + same name, ignoring "[1]").
#  Without -Apply: report only.  With -Apply: copy missing ones into photos (size-checked),
#  then delete from Drive (G:) ONLY files that are confirmed backed up.
$ErrorActionPreference = 'Stop'
$tool = $PSScriptRoot
$photos = Split-Path $tool -Parent
$org = Join-Path $photos '_Organized'
function Stem($n) { return ([IO.Path]::GetFileNameWithoutExtension($n) -replace '\[1\]$', '').Trim().ToLower() }

Write-Host 'Listing photos\_Organized...'
$bySize = @{}
Get-ChildItem -LiteralPath $org -Recurse -File -Force | ForEach-Object {
  $k = [string]$_.Length
  if (-not $bySize.ContainsKey($k)) { $bySize[$k] = New-Object System.Collections.ArrayList }
  [void]$bySize[$k].Add($_)
}
function FindCopy($name, $size) {
  $k = [string]$size
  if (-not $bySize.ContainsKey($k)) { return $null }
  $s = Stem $name
  foreach ($f in $bySize[$k]) { if ((Stem $f.Name) -eq $s) { return $f } }
  return $null
}

$rows = Import-Csv (Join-Path $tool 'drive_owned_manifest.csv') -Encoding UTF8
$out = New-Object System.Collections.ArrayList
foreach ($r in $rows) {
  $status = ''; $where = ''
  $c = FindCopy $r.Name $r.Size
  if ($c) { $status = 'BACKED UP'; $where = $c.FullName.Substring($photos.Length + 1) }
  elseif ($r.CopyTo) {
    $status = 'NOT IN PHOTOS - will copy'
    if ($Apply) {
      try {
        if (-not (Test-Path -LiteralPath $r.GPath)) { throw 'not found on G:' }
        $dir = Join-Path $photos $r.CopyTo
        New-Item -ItemType Directory -Force -Path $dir | Out-Null
        $to = Join-Path $dir $r.Name
        Write-Host "Copying $($r.Name) ..."
        Copy-Item -LiteralPath $r.GPath -Destination $to -Force
        if ((Get-Item -LiteralPath $to).Length -eq [long]$r.Size) { $status = 'BACKED UP (copied now)'; $where = $to.Substring($photos.Length + 1) }
        else { Remove-Item -LiteralPath $to -Force; $status = 'COPY FAILED - kept in Drive' }
      } catch { $status = "COPY FAILED - kept in Drive ($($_.Exception.Message))" }
    }
  } else { $status = 'NOT IN PHOTOS - kept in Drive' }

  $action = ''
  if ($Apply -and $status -like 'BACKED UP*') {
    try {
      if (-not (Test-Path -LiteralPath $r.GPath)) { $action = 'not on G: (already gone?)' }
      elseif ((Get-Item -LiteralPath $r.GPath).Length -ne [long]$r.Size) { $action = 'size differs on G: - kept' }
      else { Remove-Item -LiteralPath $r.GPath -Force; $action = 'DELETED from Drive' }
    } catch { $action = "delete failed: $($_.Exception.Message)" }
  }
  [void]$out.Add([pscustomobject]@{ Name = $r.Name; SizeMB = [math]::Round([long]$r.Size / 1MB, 1); Status = $status; InPhotos = $where; DriveAction = $action; DrivePath = $r.GPath })
}
$file = if ($Apply) { 'drive_owned_apply.csv' } else { 'drive_owned_check.csv' }
$out | Export-Csv (Join-Path $tool $file) -NoTypeInformation -Encoding UTF8
$out | Group-Object Status | ForEach-Object { Write-Host ("{0}: {1}" -f $_.Name, $_.Count) }
if ($Apply) { $out | Group-Object DriveAction | ForEach-Object { Write-Host ("Drive - {0}: {1}" -f $_.Name, $_.Count) } }
Write-Host 'Done - you can close this window.'
