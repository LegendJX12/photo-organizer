# STEP 1 - MAKE PLAN (read-only: nothing is moved or deleted)
# Scans the photos folder, works out a date + destination for every photo/video,
# finds exact duplicates (same content), and writes plan.csv + summary.txt.
$ErrorActionPreference = 'Stop'
$ToolDir = $PSScriptRoot
$Root    = Split-Path -Parent $ToolDir

# ---------------- SETTINGS (edit if needed) ----------------
$OutRoot    = '_Organized'
$DupRoot    = '_Duplicates (review then delete)'
$ReviewRoot = '_Needs review'
$ZipRoot    = '_Zips (extracted - can delete)'
$Exclude    = @('_organize_tool', $OutRoot, $DupRoot, $ReviewRoot, $ZipRoot)
# Folders that are just "dumps" -> their files get sorted by date (and joined to events)
$DumpTop      = @('Camera','New folder','DCIM')   # e.g. phone/camera dump folders
$DumpPatterns = @('^drive-download-','^OneDrive_')
$AlbumParentTop = ''      # optional: a top folder whose sub-folders are each an album
# Albums to merge: 'album name' = 'merge into this album name'
$MergeAlbums = @{ }     # e.g. @{ 'Beach trip' = '20240808 Beach' }
# Final folder name for undated albums: 'album name' = 'folder name'
# When the same photo is in two albums, keep it in these albums first
$PreferAlbums = @()     # e.g. @('Graduation')
$AlbumFolderName = @{ }  # e.g. @{ 'Birthday' = '2022 Birthdays' }
# Name groups of loose photos: @{ Start='2023-09-22'; End='2023-10-03'; Name='Taiwan Trip' }
$CustomEvents = @(
)
$MediaExt = @('.jpg','.jpeg','.png','.heic','.heif','.webp','.gif','.bmp','.tif','.tiff',
              '.cr2','.cr3','.nef','.arw','.dng','.mp4','.mov','.avi','.mkv','.3gp','.m4v','.wmv','.mts')
# -----------------------------------------------------------

function Clean-Name([string]$n) {
    $n = $n -replace '-\d{8}T\d{6}Z(-\d+)?-\d{3}$', ''     # Google Drive download suffix
    $n = $n -replace '(?<=[^\d\-\s_])\d{1,2}$', ''         # split parts: name1, name2 ...
    return $n.Trim()
}
function Is-DumpName([string]$n) {
    if ($DumpTop -contains $n) { return $true }
    foreach ($p in $DumpPatterns) { if ($n -match $p) { return $true } }
    return $false
}
function Safe-Folder([string]$n) { return (($n -replace '[\\/:*?"<>|]', '_').Trim()) }

$Now = Get-Date
function Valid-Date($d) { return ($d -ne $null -and $d -ge [datetime]'2005-01-01' -and $d -le $Now.AddDays(1)) }

$reEpoch = [regex]'(?:mmexport|FB_IMG_|wx_camera_)(1[3-9]\d{11})'
$reDT    = [regex]'(?<!\d)(20[0-3]\d)[-_.]?(0[1-9]|1[0-2])[-_.]?(0[1-9]|[12]\d|3[01])(?:[-_ T]?([01]\d|2[0-3])[-_.:]?([0-5]\d)[-_.:]?([0-5]\d))?(?!\d)'
function Get-NameDate([string]$name) {
    $m = $reEpoch.Match($name)
    if ($m.Success) { return [DateTimeOffset]::FromUnixTimeMilliseconds([int64]$m.Groups[1].Value).LocalDateTime }
    $m = $reDT.Match($name)
    if ($m.Success) {
        try {
            $y=[int]$m.Groups[1].Value; $mo=[int]$m.Groups[2].Value; $d=[int]$m.Groups[3].Value
            if ($m.Groups[4].Success) { return New-Object DateTime $y,$mo,$d,([int]$m.Groups[4].Value),([int]$m.Groups[5].Value),([int]$m.Groups[6].Value) }
            return New-Object DateTime $y,$mo,$d,12,0,0
        } catch { return $null }
    }
    return $null
}
$shell = New-Object -ComObject Shell.Application
$nsCache = @{}
function Get-MetaDate([string]$full) {
    try {
        $dir = Split-Path -Parent $full
        if (-not $nsCache.ContainsKey($dir)) { $nsCache[$dir] = $shell.Namespace($dir) }
        $it = $nsCache[$dir].ParseName((Split-Path -Leaf $full))
        if (-not $it) { return $null }
        foreach ($p in 'System.Photo.DateTaken','System.Media.DateEncoded') {
            $v = $it.ExtendedProperty($p)
            if ($v -ne $null -and "$v" -ne '') { return [DateTime]::SpecifyKind([datetime]$v,'Utc').ToLocalTime() }
        }
    } catch {}
    return $null
}

Write-Host "Scanning $Root ..." -ForegroundColor Cyan
$all = @(Get-ChildItem -LiteralPath $Root -Recurse -File -Force | Where-Object {
    $rel = $_.FullName.Substring($Root.Length + 1)
    -not ($Exclude -contains ($rel.Split('\')[0]))
})
Write-Host ("Found {0} files. Reading dates (this can take 10-30 min)..." -f $all.Count)

$items = New-Object System.Collections.Generic.List[object]
$i = 0
foreach ($f in $all) {
    $i++
    if ($i % 100 -eq 0) { Write-Progress -Activity 'Reading dates' -Status "$i / $($all.Count)" -PercentComplete ($i*100/$all.Count) }
    $rel   = $f.FullName.Substring($Root.Length + 1)
    $parts = $rel.Split('\')
    $o = [ordered]@{ Source=$rel; Size=$f.Length; Action=''; Destination=''; Date=''; DateSource=''; Album=''; FromFolder=''; Note=''; DupOf='' }
    $o.FromFolder = if ($parts.Count -gt 1) { $parts[0] } else { '(loose files)' }
    if ($MediaExt -notcontains $f.Extension.ToLower()) {
        $o.Action = 'Skip'; $o.Note = 'not a photo/video - left in place'
        $items.Add([pscustomobject]$o); continue
    }
    # which album (if any)?
    $album = $null; $subStart = 0
    if ($parts.Count -gt 1) {
        $top = $parts[0]
        if ($top -eq $AlbumParentTop) {
            if ($parts.Count -ge 3 -and -not (Is-DumpName $parts[1])) { $album = Clean-Name $parts[1]; $subStart = 2 }
            $o.FromFolder = $AlbumParentTop
        } elseif (-not (Is-DumpName $top)) {
            $album = Clean-Name $top; $subStart = 1
        }
    }
    $sub = ''
    if ($album) {
        $dirs = @(); if ($parts.Count - 1 -gt $subStart) { $dirs = @($parts[$subStart..($parts.Count-2)]) }
        while ($dirs.Count -gt 0 -and (Clean-Name $dirs[0]) -eq $album) { $dirs = @($dirs | Select-Object -Skip 1) }
        if ($dirs.Count) { $sub = $dirs -join '\' }
    }
    $o['_sub'] = $sub
    if ($album -and $MergeAlbums.ContainsKey($album)) { $album = $MergeAlbums[$album] }
    if ($album) { $o.Album = $album }
    # date
    $d = Get-NameDate $f.Name; $src = 'filename'
    if (-not (Valid-Date $d)) { $d = Get-MetaDate $f.FullName; $src = 'photo info' }
    if (Valid-Date $d) { $o.Date = $d.ToString('yyyy-MM-dd HH:mm'); $o.DateSource = $src } else { $o.DateSource = 'none' }
    $o['_d'] = if (Valid-Date $d) { $d } else { $null }
    $items.Add([pscustomobject]$o)
}
Write-Progress -Activity 'Reading dates' -Completed

# ---------- albums ----------
$reEvt = [regex]'^(20\d{2})(\d{2})(\d{2})(?:[-\s]+(\d{4}|\d{2})(?!\d))?(?:\s+(.*))?$'
$albumInfo = @{}
$events = New-Object System.Collections.Generic.List[object]
foreach ($g in ($items | Where-Object { $_.Album } | Group-Object Album)) {
    $key = $g.Name
    $info = @{ Folder=$null; Year=$null; Span='' }
    $dates = @($g.Group | Where-Object { $_._d } | ForEach-Object { $_._d } | Sort-Object)
    if ($dates.Count) { $info.Span = '{0:yyyy-MM-dd} to {1:yyyy-MM-dd}' -f $dates[0], $dates[-1]; $info.SpanDays = ($dates[-1]-$dates[0]).TotalDays }
    $m = $reEvt.Match($key)
    $ok = $false
    if ($m.Success) {
        try {
            $start = New-Object DateTime ([int]$m.Groups[1].Value),([int]$m.Groups[2].Value),([int]$m.Groups[3].Value)
            $end = $start
            if ($m.Groups[4].Success) {
                $t = $m.Groups[4].Value
                if ($t.Length -eq 4) { $end = New-Object DateTime $start.Year,([int]$t.Substring(0,2)),([int]$t.Substring(2,2)) }
                else { $end = New-Object DateTime $start.Year,$start.Month,([int]$t) }
                if ($end -lt $start) { $end = $end.AddYears(1) }
            }
            $title = $m.Groups[5].Value.Trim()
            $info.Folder = Safe-Folder (('{0:yyyy-MM-dd} {1}' -f $start, $title).Trim())
            $info.Year = $start.Year
            $events.Add([pscustomobject]@{ Album=$key; Start=$start; End=$end.AddDays(1).AddHours(5) })
            $ok = $true
        } catch {}
    }
    if (-not $ok) {
        if ($dates.Count) {
            $med = $dates[[int][math]::Floor($dates.Count/2)]
            $info.Folder = Safe-Folder ('{0:yyyy-MM} {1}' -f $med, $key)
            $info.Year = $med.Year
        } else {
            $info.Folder = Safe-Folder $key
        }
        if ($AlbumFolderName.ContainsKey($key)) { $info.Folder = Safe-Folder $AlbumFolderName[$key] }
        # short undated albums (<= 10 days, 30+ photos) also attract loose photos taken in that period
        if ($dates.Count -ge 30 -and $info.SpanDays -le 10) {
            $events.Add([pscustomobject]@{ Album=$key; Start=$dates[0].Date; End=$dates[-1].Date.AddDays(1).AddHours(5) })
        }
    }
    $albumInfo[$key] = $info
}

foreach ($ce in $CustomEvents) {
    $s = [datetime]$ce.Start; $e = [datetime]$ce.End; $k = '#custom ' + $ce.Name
    $albumInfo[$k] = @{ Folder = Safe-Folder ('{0:yyyy-MM-dd} {1}' -f $s, $ce.Name); Year = $s.Year }
    $events.Add([pscustomobject]@{ Album=$k; Start=$s; End=$e.AddDays(1).AddHours(5) })
}

# ---------- destinations ----------
foreach ($it in $items) {
    if ($it.Action -eq 'Skip') { continue }
    $name = Split-Path -Leaf $it.Source
    $it.Action = 'Move'
    if ($it.Album) {
        $ai = $albumInfo[$it.Album]
        if ($ai.Year) { $base = Join-Path (Join-Path $OutRoot $ai.Year) $ai.Folder }
        else { $base = Join-Path (Join-Path $ReviewRoot 'Albums with no date') $ai.Folder }
        if ($it._sub) { $base = Join-Path $base $it._sub }
        $it.Destination = Join-Path $base $name
        continue
    }
    if (-not $it._d) {
        $it.Destination = Join-Path (Join-Path (Join-Path $ReviewRoot 'No date found') (Safe-Folder $it.FromFolder)) $name
        $it.Note = 'no date in name or photo info'
        continue
    }
    $hits = @($events | Where-Object { $it._d -ge $_.Start -and $it._d -lt $_.End })
    if ($hits.Count -eq 1) {
        $ai = $albumInfo[$hits[0].Album]
        $it.Destination = Join-Path (Join-Path (Join-Path $OutRoot $ai.Year) $ai.Folder) $name
        $it.Note = 'joined event by date'
    } else {
        $it.Destination = Join-Path (Join-Path (Join-Path $OutRoot $it._d.Year) ($it._d.ToString('yyyy-MM'))) $name
        if ($hits.Count -gt 1) { $it.Note = 'date matches ' + $hits.Count + ' events - put in month folder' }
    }
}

# ---------- duplicates (exact same content) ----------
Write-Host 'Checking for duplicates...' -ForegroundColor Cyan
$reCopy = [regex]'(\(\d+\)|[ _-]\d|[ _-]copy|- Copy)\.\w+$'
$media = @($items | Where-Object { $_.Action -eq 'Move' })
$sameSize = @($media | Group-Object Size | Where-Object { $_.Count -gt 1 })
$n = 0
foreach ($sg in $sameSize) {
    $n++
    if ($n % 50 -eq 0) { Write-Progress -Activity 'Comparing files' -Status "$n / $($sameSize.Count)" -PercentComplete ($n*100/$sameSize.Count) }
    $hashed = foreach ($x in $sg.Group) {
        try { $h = (Get-FileHash -LiteralPath (Join-Path $Root $x.Source) -Algorithm MD5).Hash; [pscustomobject]@{ H=$h; X=$x } } catch {}
    }
    foreach ($hg in ($hashed | Group-Object H | Where-Object { $_.Count -gt 1 })) {
        $ranked = $hg.Group | Sort-Object @{e={ if ($PreferAlbums -contains $_.X.Album) {0} else {1} }}, @{e={ if ($_.X.Album) {0} else {1} }}, @{e={ if ($reCopy.IsMatch($_.X.Source)) {1} else {0} }}, @{e={ $_.X.Source.Length }}, @{e={ $_.X.Source }}
        $keep = $ranked[0].X
        foreach ($r in ($ranked | Select-Object -Skip 1)) {
            $r.X.Action = 'Duplicate'; $r.X.DupOf = $keep.Source
            $r.X.Destination = Join-Path $DupRoot $r.X.Source
            $r.X.Note = 'exact copy of kept file'
        }
    }
}
Write-Progress -Activity 'Comparing files' -Completed

# ---------- avoid name clashes ----------
$used = @{}
foreach ($it in ($items | Where-Object { $_.Action -ne 'Skip' } | Sort-Object Source)) {
    $dst = $it.Destination; $k = $dst.ToLower(); $c = 2
    while ($used.ContainsKey($k)) {
        $dst = Join-Path (Split-Path -Parent $it.Destination) ('{0} ({1}){2}' -f [IO.Path]::GetFileNameWithoutExtension($it.Destination), $c, [IO.Path]::GetExtension($it.Destination))
        $k = $dst.ToLower(); $c++
    }
    $used[$k] = 1; $it.Destination = $dst
}

# ---------- write outputs ----------
$cols = 'Action','Source','Destination','Date','DateSource','Album','FromFolder','Note','DupOf','Size'
$items | Select-Object $cols | Export-Csv -LiteralPath (Join-Path $ToolDir 'plan.csv') -NoTypeInformation -Encoding UTF8

$sb = New-Object System.Text.StringBuilder
function L($s) { [void]$sb.AppendLine($s) }
$mv  = @($items | Where-Object { $_.Action -eq 'Move' })
$dup = @($items | Where-Object { $_.Action -eq 'Duplicate' })
$skp = @($items | Where-Object { $_.Action -eq 'Skip' })
L ('PLAN SUMMARY  ({0:yyyy-MM-dd HH:mm})' -f (Get-Date))
L ('Files scanned: {0}' -f $items.Count)
L ('Will be organized: {0}' -f $mv.Count)
L ('Duplicates found: {0}  ({1:N2} GB)' -f $dup.Count, (($dup | Measure-Object Size -Sum).Sum/1GB))
L ('Not photo/video (left in place): {0}' -f $skp.Count)
L ''
L '== Destination folders (files | joined from loose photos | date span of album) =='
foreach ($g in ($mv | Group-Object { Split-Path -Parent $_.Destination } | Sort-Object Name)) {
    $j = @($g.Group | Where-Object { $_.Note -eq 'joined event by date' }).Count
    L ('{0}  | {1} | +{2}' -f $g.Name, $g.Count, $j)
}
L ''
L '== Albums whose photos span > 45 days (maybe mixed content) =='
foreach ($k in $albumInfo.Keys) { if ($albumInfo[$k].SpanDays -gt 45) { L ('{0}  ->  {1}' -f $k, $albumInfo[$k].Span) } }
L ''
L '== No date found, by original folder =='
foreach ($g in ($mv | Where-Object { $_.DateSource -eq 'none' -and -not $_.Album } | Group-Object FromFolder)) { L ('{0}: {1}' -f $g.Name, $g.Count) }
L ''
L '== Duplicates by original folder =='
foreach ($g in ($dup | Group-Object FromFolder | Sort-Object Count -Descending)) { L ('{0}: {1}' -f $g.Name, $g.Count) }
L ''
L '== Not photo/video (left in place) =='
foreach ($s in $skp) { L ('{0}  ({1:N1} MB)' -f $s.Source, ($s.Size/1MB)) }
[IO.File]::WriteAllText((Join-Path $ToolDir 'summary.txt'), $sb.ToString(), (New-Object Text.UTF8Encoding $true))

Write-Host ''
Write-Host 'DONE. Nothing was moved.' -ForegroundColor Green
Write-Host 'Created: plan.csv and summary.txt in the _organize_tool folder.'
Write-Host 'Go back to Claude and say "plan done".'
