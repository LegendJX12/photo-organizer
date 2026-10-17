# STEP 5 - (A) delete verified duplicates to Recycle Bin, (B) rescan whole folder for duplicates.
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName Microsoft.VisualBasic
Add-Type -AssemblyName System.Drawing
$ToolDir = $PSScriptRoot
$Root    = Split-Path -Parent $ToolDir
$DupRoot = Join-Path $Root '_Duplicates (review then delete)'

# ---------- A. delete verified duplicates ----------
$deleted = 0; $kept = New-Object System.Collections.Generic.List[string]
if (Test-Path -LiteralPath $DupRoot) {
    $pairs = @(Import-Csv -LiteralPath (Join-Path $ToolDir 'dup_pairs.csv') -Encoding UTF8)
    Write-Host ("Checking {0} duplicates one last time before deleting..." -f $pairs.Count) -ForegroundColor Cyan
    $i = 0
    foreach ($p in $pairs) {
        $i++; if ($i % 20 -eq 0) { Write-Progress -Activity 'Deleting verified duplicates' -Status "$i / $($pairs.Count)" -PercentComplete ($i*100/$pairs.Count) }
        $a = Join-Path $Root $p.Duplicate; $b = Join-Path $Root $p.Kept
        if (-not [IO.File]::Exists($a)) { continue }
        $okToDelete = $false
        $fa = Get-Item -LiteralPath $a
        if ($fa.Length -eq 0) { $okToDelete = $true }
        elseif ([IO.File]::Exists($b)) {
            $fb = Get-Item -LiteralPath $b
            if ($fa.Length -eq $fb.Length -and (Get-FileHash -LiteralPath $a -Algorithm SHA256).Hash -eq (Get-FileHash -LiteralPath $b -Algorithm SHA256).Hash) { $okToDelete = $true }
        }
        if ($okToDelete) { [Microsoft.VisualBasic.FileIO.FileSystem]::DeleteFile($a, 'OnlyErrorDialogs', 'SendToRecycleBin'); $deleted++ }
        else { $kept.Add($p.Duplicate) }
    }
    Write-Progress -Activity 'Deleting verified duplicates' -Completed
    # anything left that was not in the list stays; remove empty folders
    Get-ChildItem -LiteralPath $DupRoot -Directory -Recurse -Force | Sort-Object { $_.FullName.Length } -Descending | ForEach-Object { if (-not (Get-ChildItem -LiteralPath $_.FullName -Force)) { Remove-Item -LiteralPath $_.FullName -Force } }
    if (-not (Get-ChildItem -LiteralPath $DupRoot -Force)) { Remove-Item -LiteralPath $DupRoot -Force }
    Write-Host ("Deleted (to Recycle Bin): {0}.  Not deleted (could not verify): {1}" -f $deleted, $kept.Count) -ForegroundColor Green
}

# ---------- B. rescan everything ----------
$skipTop = @('_organize_tool')
$media = '.jpg','.jpeg','.png','.heic','.heif','.webp','.gif','.bmp','.tif','.tiff','.cr2','.cr3','.nef','.arw','.dng','.mp4','.mov','.avi','.mkv','.3gp','.m4v','.wmv','.mts'
$files = @(Get-ChildItem -LiteralPath $Root -Recurse -File -Force | Where-Object {
    $skipTop -notcontains $_.FullName.Substring($Root.Length+1).Split('\')[0] -and $media -contains $_.Extension.ToLower() })
Write-Host ("Rescanning {0} photos/videos..." -f $files.Count) -ForegroundColor Cyan

# B1 exact copies (same size, then SHA256)
$exact = New-Object System.Collections.Generic.List[object]
$groups = @($files | Where-Object { $_.Length -gt 0 } | Group-Object Length | Where-Object { $_.Count -gt 1 })
$i = 0
foreach ($g in $groups) {
    $i++; if ($i % 20 -eq 0) { Write-Progress -Activity 'Exact-copy check' -Status "$i / $($groups.Count)" -PercentComplete ($i*100/$groups.Count) }
    $h = foreach ($f in $g.Group) { [pscustomobject]@{ H=(Get-FileHash -LiteralPath $f.FullName -Algorithm SHA256).Hash; F=$f } }
    foreach ($hg in ($h | Group-Object H | Where-Object { $_.Count -gt 1 })) { $exact.Add(@($hg.Group | ForEach-Object { $_.F.FullName.Substring($Root.Length+1) })) }
}
Write-Progress -Activity 'Exact-copy check' -Completed
$emptyFiles = @($files | Where-Object { $_.Length -eq 0 } | ForEach-Object { $_.FullName.Substring($Root.Length+1) })

# B2 look-alike photos (same picture, different size/quality) using a 9x8 difference hash
$imgExt = '.jpg','.jpeg','.png','.bmp','.gif','.webp','.tif','.tiff'
$imgs = @($files | Where-Object { $imgExt -contains $_.Extension.ToLower() -and $_.Length -gt 0 })
$dh = @{}; $i = 0
foreach ($f in $imgs) {
    $i++; if ($i % 50 -eq 0) { Write-Progress -Activity 'Look-alike check (slowest part)' -Status "$i / $($imgs.Count)" -PercentComplete ($i*100/$imgs.Count) }
    try {
        $fs = [IO.File]::OpenRead($f.FullName)
        try {
            $img = [Drawing.Image]::FromStream($fs, $false, $false)
            $bmp = New-Object Drawing.Bitmap 9, 8
            $gr = [Drawing.Graphics]::FromImage($bmp); $gr.InterpolationMode = 'HighQualityBilinear'; $gr.DrawImage($img, 0, 0, 9, 8); $gr.Dispose(); $img.Dispose()
            $bits = New-Object Text.StringBuilder
            for ($y=0; $y -lt 8; $y++) { for ($x=0; $x -lt 8; $x++) {
                $p1 = $bmp.GetPixel($x,$y); $p2 = $bmp.GetPixel($x+1,$y)
                $l1 = $p1.R*0.299+$p1.G*0.587+$p1.B*0.114; $l2 = $p2.R*0.299+$p2.G*0.587+$p2.B*0.114
                [void]$bits.Append($(if ($l1 -gt $l2) {'1'} else {'0'})) } }
            $bmp.Dispose()
            $k = $bits.ToString()
            if ($k -ne ('0'*64) -and $k -ne ('1'*64)) { if (-not $dh.ContainsKey($k)) { $dh[$k] = New-Object System.Collections.Generic.List[object] }; $dh[$k].Add($f) }
        } finally { $fs.Dispose() }
    } catch {}
}
Write-Progress -Activity 'Look-alike check (slowest part)' -Completed
$exactSet = @{}; foreach ($g in $exact) { foreach ($p in $g) { $exactSet[$p] = 1 } }
$alike = New-Object System.Collections.Generic.List[object]
foreach ($k in $dh.Keys) {
    $g = $dh[$k]
    if ($g.Count -lt 2) { continue }
    $sizes = @($g | ForEach-Object { $_.Length } | Sort-Object -Unique)
    if ($sizes.Count -lt 2) { continue }   # same size = already covered by exact check
    $alike.Add(@($g | Sort-Object Length -Descending | ForEach-Object { [pscustomobject]@{ P=$_.FullName.Substring($Root.Length+1); S=$_.Length } }))
}

# ---------- report ----------
$r = New-Object System.Collections.Generic.List[string]
$r.Add("RESCAN REPORT $(Get-Date -Format 'yyyy-MM-dd HH:mm')")
$r.Add("Duplicates deleted to Recycle Bin: $deleted   (not verified, left in place: $($kept.Count))")
$r.Add("Photos/videos scanned: $($files.Count)")
$r.Add("EXACT copies still found: $($exact.Count) groups")
$r.Add("Empty 0-byte files: $($emptyFiles.Count)")
$r.Add("LOOK-ALIKE groups (same picture, different file size): $($alike.Count)  -> see lookalikes.html")
$r.Add(''); $r.Add('== Exact copies =='); foreach ($g in $exact) { $r.Add(($g -join '   ==   ')) }
$r.Add(''); $r.Add('== Empty files =='); foreach ($e in $emptyFiles) { $r.Add($e) }
$r.Add(''); $r.Add('== Not deleted =='); foreach ($k2 in $kept) { $r.Add($k2) }
[IO.File]::WriteAllLines((Join-Path $ToolDir 'rescan_report.txt'), $r, (New-Object Text.UTF8Encoding $true))
# csv for Claude
$rows = foreach ($idx in 0..($alike.Count-1)) { if ($alike.Count) { foreach ($m in $alike[$idx]) { [pscustomobject]@{ Group=$idx+1; Path=$m.P; Size=$m.S } } } }
$rows | Export-Csv -LiteralPath (Join-Path $ToolDir 'lookalikes.csv') -NoTypeInformation -Encoding UTF8
$ex = foreach ($idx in 0..($exact.Count-1)) { if ($exact.Count) { foreach ($m in $exact[$idx]) { [pscustomobject]@{ Group=$idx+1; Path=$m } } } }
$ex | Export-Csv -LiteralPath (Join-Path $ToolDir 'exact_left.csv') -NoTypeInformation -Encoding UTF8
# html
function U($p) { return '../' + (($p.Split('\') | ForEach-Object { [Uri]::EscapeDataString($_) }) -join '/') }
$h = New-Object Text.StringBuilder
[void]$h.Append('<!doctype html><html><head><meta charset="utf-8"><title>Look-alike photos</title><style>body{font-family:Segoe UI,Arial;background:#f4f4f2;padding:16px}.g{background:#fff;border-radius:10px;padding:10px;margin:12px 0}.row{display:flex;gap:12px;flex-wrap:wrap}.c{flex:1;min-width:240px;font-size:12px;word-break:break-all}img{max-width:100%;max-height:300px;border-radius:6px}</style></head><body>')
[void]$h.Append("<h1>Look-alike photos ($($alike.Count) groups)</h1><p>Same picture fingerprint but different file size (e.g. a WhatsApp or resized copy). Nothing was deleted. The largest file (usually best quality) is shown first.</p>")
$n = 0
foreach ($g in $alike) { $n++; [void]$h.Append("<div class='g'><b>Group $n</b><div class='row'>"); foreach ($m in $g) { [void]$h.Append("<div class='c'><a href='$(U $m.P)' target='_blank'><img loading='lazy' src='$(U $m.P)'></a><br>$([Net.WebUtility]::HtmlEncode($m.P))<br><b>$([math]::Round($m.S/1MB,2)) MB</b></div>") }; [void]$h.Append('</div></div>') }
[void]$h.Append('</body></html>')
[IO.File]::WriteAllText((Join-Path $ToolDir 'lookalikes.html'), $h.ToString(), (New-Object Text.UTF8Encoding $true))
Write-Host ''
Write-Host ("DONE. Exact copies left: {0} groups. Look-alike groups: {1}." -f $exact.Count, $alike.Count) -ForegroundColor Green
Write-Host 'Go back to Claude and say "rescan done".'
