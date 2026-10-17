# STEP 8 - READ-ONLY scan of your organized photos: date taken, GPS location, and a
# picture fingerprint (for finding similar/burst shots). Writes folder_scan.csv. Moves nothing.
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing
$ToolDir = $PSScriptRoot
$Root    = Split-Path -Parent $ToolDir
$media = '.jpg','.jpeg','.png','.heic','.heif','.webp','.gif','.bmp','.tif','.tiff','.cr2','.cr3','.nef','.arw','.dng','.mp4','.mov','.avi','.mkv','.3gp','.m4v','.wmv','.mts'
$imgExt = '.jpg','.jpeg','.png','.bmp','.webp','.tif','.tiff'
$files = @(Get-ChildItem -LiteralPath $Root -Recurse -File -Force | Where-Object {
    $_.FullName.Substring($Root.Length+1).Split('\')[0] -ne '_organize_tool' -and $media -contains $_.Extension.ToLower() })
Write-Host ("Scanning {0} files (about 30-60 min)..." -f $files.Count) -ForegroundColor Cyan
$shell = New-Object -ComObject Shell.Application
$ns = @{}
function Prop($it, $name) { try { return $it.ExtendedProperty($name) } catch { return $null } }
function ToDeg($v, $ref) {
    if ($v -eq $null) { return $null }
    if ($v -is [array]) { $d = [double]$v[0] + [double]$v[1]/60 + [double]$v[2]/3600 } else { $d = [double]$v }
    if ($ref -eq 'S' -or $ref -eq 'W') { $d = -$d }
    return [math]::Round($d, 6)
}
$out = New-Object System.Collections.Generic.List[object]
$i = 0
foreach ($f in $files) {
    $i++; if ($i % 100 -eq 0) { Write-Progress -Activity 'Scanning photos' -Status "$i / $($files.Count)" -PercentComplete ($i*100/$files.Count) }
    $rel = $f.FullName.Substring($Root.Length+1)
    $taken = ''; $lat = ''; $lon = ''; $hash = ''; $w = ''; $h = ''
    try {
        $dir = $f.DirectoryName
        if (-not $ns.ContainsKey($dir)) { $ns[$dir] = $shell.Namespace($dir) }
        $it = $ns[$dir].ParseName($f.Name)
        if ($it) {
            foreach ($p in 'System.Photo.DateTaken','System.Media.DateEncoded') { $v = Prop $it $p; if ($v) { $taken = ([DateTime]::SpecifyKind([datetime]$v,'Utc').ToLocalTime()).ToString('yyyy-MM-dd HH:mm:ss'); break } }
            $la = Prop $it 'System.GPS.LatitudeDecimal'; $lo = Prop $it 'System.GPS.LongitudeDecimal'
            if ($la -eq $null) { $la = ToDeg (Prop $it 'System.GPS.Latitude') (Prop $it 'System.GPS.LatitudeRef'); $lo = ToDeg (Prop $it 'System.GPS.Longitude') (Prop $it 'System.GPS.LongitudeRef') }
            if ($la -ne $null -and $lo -ne $null -and -not ([double]$la -eq 0 -and [double]$lo -eq 0)) { $lat = [math]::Round([double]$la,6); $lon = [math]::Round([double]$lo,6) }
        }
    } catch {}
    if ($imgExt -contains $f.Extension.ToLower() -and $f.Length -gt 0) {
        try {
            $fs = [IO.File]::OpenRead($f.FullName)
            try {
                $img = [Drawing.Image]::FromStream($fs, $false, $false); $w = $img.Width; $h = $img.Height
                $bmp = New-Object Drawing.Bitmap 9, 8
                $gr = [Drawing.Graphics]::FromImage($bmp); $gr.InterpolationMode = 'HighQualityBilinear'; $gr.DrawImage($img, 0, 0, 9, 8); $gr.Dispose(); $img.Dispose()
                $sb = New-Object Text.StringBuilder
                for ($y=0; $y -lt 8; $y++) { for ($x=0; $x -lt 8; $x++) { $a=$bmp.GetPixel($x,$y); $b=$bmp.GetPixel($x+1,$y)
                    [void]$sb.Append($(if (($a.R*299+$a.G*587+$a.B*114) -gt ($b.R*299+$b.G*587+$b.B*114)) {'1'} else {'0'})) } }
                $bmp.Dispose(); $hash = $sb.ToString()
            } finally { $fs.Dispose() }
        } catch {}
    }
    $out.Add([pscustomobject]@{ Path=$rel; Size=$f.Length; Modified=$f.LastWriteTime.ToString('yyyy-MM-dd HH:mm:ss'); Taken=$taken; Lat=$lat; Lon=$lon; W=$w; H=$h; Hash=$hash })
}
Write-Progress -Activity 'Scanning photos' -Completed
$out | Export-Csv -LiteralPath (Join-Path $ToolDir 'folder_scan.csv') -NoTypeInformation -Encoding UTF8
$gps = @($out | Where-Object { $_.Lat -ne '' }).Count
Write-Host ("DONE. {0} files scanned, {1} have GPS location. Nothing was moved." -f $out.Count, $gps) -ForegroundColor Green
Write-Host 'Go back to Claude and say "scan done".'
