# Finds pictures/videos in Google Drive (Google Drive for desktop drive) and checks if photos\_Organized already has them.
# Report only - nothing is moved or deleted.
$ErrorActionPreference = 'Continue'
$tool = $PSScriptRoot
$photos = Split-Path $tool -Parent
$org = Join-Path $photos '_Organized'
# Find the Google Drive for desktop drive (a drive letter that has "My Drive")
$roots = @()
foreach ($d in (Get-PSDrive -PSProvider FileSystem)) {
  foreach ($n in @('My Drive', [string][char]0x6211 + [char]0x7684 + [char]0x4E91 + [char]0x7AEF + [char]0x786C + [char]0x76D8, 'Other computers')) {
    $p = Join-Path $d.Root $n
    if (Test-Path -LiteralPath $p) { $roots += $p }
  }
}
if ($roots.Count -eq 0) { Write-Host 'Could not find the Google Drive drive (no "My Drive" folder on any drive letter). Is Google Drive for desktop running?'; exit }
Write-Host ("Google Drive found: " + ($roots -join ' ; '))
$ext = @('.jpg','.jpeg','.png','.heic','.heif','.gif','.bmp','.webp','.tif','.tiff','.dng','.cr2','.nef','.arw','.raw',
         '.mp4','.mov','.avi','.mkv','.m4v','.3gp','.wmv','.mts','.m2ts','.webm','.mpg','.mpeg')
$sha = [System.Security.Cryptography.SHA256]::Create()
function HashFile($p) { $fs = [System.IO.File]::OpenRead($p); try { [BitConverter]::ToString($sha.ComputeHash($fs)) } finally { $fs.Close() } }
function IsCloud($f) { return ((([int]$f.Attributes) -band 0x401000) -ne 0) }

Write-Host 'Step 1/3: listing photos\_Organized...'
$bySize = @{}; $byName = @{}
Get-ChildItem -LiteralPath $org -Recurse -File -Force | ForEach-Object {
  $k = [string]$_.Length
  if (-not $bySize.ContainsKey($k)) { $bySize[$k] = New-Object System.Collections.ArrayList }
  [void]$bySize[$k].Add($_.FullName)
  $byName[($_.Name.ToLower() + '|' + $k)] = $_.FullName
}
$oh = @{}

Write-Host 'Step 2/3: looking for pictures and videos in Google Drive...'
$files = @()
foreach ($r in $roots) {
  $files += Get-ChildItem -LiteralPath $r -Recurse -File -Force -ErrorAction SilentlyContinue |
    Where-Object { $ext -contains $_.Extension.ToLower() -and -not $_.FullName.StartsWith($photos + '\', [StringComparison]::OrdinalIgnoreCase) }
}
Write-Host "  found $($files.Count) media files"

Write-Host 'Step 3/3: comparing...'
$rows = New-Object System.Collections.ArrayList
$i = 0
foreach ($f in $files) {
  $i++; if ($i % 100 -eq 0) { Write-Host "  $i / $($files.Count)" }
  $k = [string]$f.Length; $res = 'NOT in photos'; $match = ''
  $cloud = $true
  try {
    if ($bySize.ContainsKey($k)) {
      if ($cloud) {
        $nk = $f.Name.ToLower() + '|' + $k
        if ($byName.ContainsKey($nk)) { $res = 'In photos (same name + same size)'; $match = $byName[$nk].Substring($org.Length + 1) }
        else { $res = 'Maybe (same size, different name)' }
      } else {
        $h = HashFile $f.FullName
        foreach ($c in $bySize[$k]) {
          if (-not $oh.ContainsKey($c)) { try { $oh[$c] = HashFile $c } catch { $oh[$c] = 'ERR' } }
          if ($oh[$c] -eq $h) { $res = 'In photos (exact copy)'; $match = $c.Substring($org.Length + 1); break }
        }
      }
    }
  } catch { $res = 'Could not read'; $match = $_.Exception.Message }
  [void]$rows.Add([pscustomobject]@{ Result = $res; Path = $f.FullName; Folder = $f.DirectoryName; Size = $f.Length; Date = $f.LastWriteTime.ToString('yyyy-MM-dd'); CloudOnly = $cloud; MatchInOrganized = $match })
}
$rows | Export-Csv (Join-Path $tool 'gdrive_compare.csv') -NoTypeInformation -Encoding UTF8
$rep = @("Google Drive compare  $(Get-Date)", "Searched: $($roots -join ' ; ')  ", "Media files found: $($rows.Count)")
$rep += ($rows | Group-Object Result | ForEach-Object { "  $($_.Name): $($_.Count)" })
$rep += ''; $rep += 'NOT in photos, by folder:'
$rep += ($rows | Where-Object { $_.Result -ne 'In photos (exact copy)' -and $_.Result -notlike 'In photos*' } | Group-Object Folder | Sort-Object Count -Descending |
  ForEach-Object { "  [$($_.Count)] $($_.Name)  ($([math]::Round((($_.Group | Measure-Object Size -Sum).Sum)/1MB,1)) MB)" })
$rep | Set-Content (Join-Path $tool 'gdrive_compare_report.txt') -Encoding UTF8
$rep | Select-Object -First 12 | ForEach-Object { Write-Host $_ }
Write-Host 'Done - nothing was changed. You can close this window.'
