# STEP 15 - READ-ONLY scan of Downloads\GooglePhotosTakeout: Google's info files (date, GPS, original name)
# plus a picture fingerprint for each photo. Writes takeout_files.csv + takeout_meta.csv. Moves nothing.
$ErrorActionPreference = 'Stop'
Add-Type -ReferencedAssemblies System.Drawing -TypeDefinition @"
using System; using System.Drawing; using System.IO; using System.Text;
public static class DH {
  public static string Hash(string path, out int w, out int h) {
    using (var fs = File.OpenRead(path)) using (var img = Image.FromStream(fs, false, false)) {
      w = img.Width; h = img.Height;
      using (var bmp = new Bitmap(9, 8)) {
        using (var g = Graphics.FromImage(bmp)) { g.InterpolationMode = System.Drawing.Drawing2D.InterpolationMode.HighQualityBilinear; g.DrawImage(img, 0, 0, 9, 8); }
        var sb = new StringBuilder();
        for (int y=0;y<8;y++) for (int x=0;x<8;x++) { var a=bmp.GetPixel(x,y); var b=bmp.GetPixel(x+1,y);
          sb.Append((a.R*299+a.G*587+a.B*114) > (b.R*299+b.G*587+b.B*114) ? '1' : '0'); }
        return sb.ToString();
      }
    }
  }
}
"@
$ToolDir = $PSScriptRoot
$Base = Join-Path $env:USERPROFILE 'Downloads\GooglePhotosTakeout\Takeout\Google Photos'
$all = @(Get-ChildItem -LiteralPath $Base -Recurse -File)
Write-Host ("Scanning {0} files (about 30-60 min)..." -f $all.Count) -ForegroundColor Cyan
$files = New-Object System.Collections.Generic.List[object]
$meta  = New-Object System.Collections.Generic.List[object]
$imgExt = '.jpg','.jpeg','.png','.bmp','.webp','.gif','.tif','.tiff'
$i = 0
foreach ($f in $all) {
    $i++; if ($i % 100 -eq 0) { Write-Progress -Activity 'Scanning Google Photos export' -Status "$i / $($all.Count)" -PercentComplete ($i*100/$all.Count) }
    $rel = $f.FullName.Substring($Base.Length + 1)
    if ($f.Extension -eq '.json') {
        try {
            $j = Get-Content -LiteralPath $f.FullName -Raw -Encoding UTF8 | ConvertFrom-Json
            $lat=''; $lon=''
            foreach ($gk in 'geoData','geoDataExif') { $gd = $j.$gk; if ($gd -and ([double]$gd.latitude -ne 0 -or [double]$gd.longitude -ne 0)) { $lat=$gd.latitude; $lon=$gd.longitude; break } }
            $meta.Add([pscustomobject]@{ Json=$rel; Title=$j.title; Taken=$j.photoTakenTime.timestamp; Lat=$lat; Lon=$lon })
        } catch {}
        continue
    }
    if ($f.Extension -eq '.html') { continue }
    $hash=''; $w=''; $h=''
    if ($imgExt -contains $f.Extension.ToLower() -and $f.Length -gt 0) { try { $ww=0; $hh=0; $hash=[DH]::Hash($f.FullName,[ref]$ww,[ref]$hh); $w=$ww; $h=$hh } catch {} }
    $files.Add([pscustomobject]@{ Path=$rel; Size=$f.Length; Hash=$hash; W=$w; H=$h })
}
Write-Progress -Activity 'Scanning Google Photos export' -Completed
$files | Export-Csv -LiteralPath (Join-Path $ToolDir 'takeout_files.csv') -NoTypeInformation -Encoding UTF8
$meta  | Export-Csv -LiteralPath (Join-Path $ToolDir 'takeout_meta.csv')  -NoTypeInformation -Encoding UTF8
Write-Host ("DONE. {0} photos/videos, {1} info files. Nothing was moved." -f $files.Count, $meta.Count) -ForegroundColor Green
Write-Host 'Go back to Claude and say "google scan done".'
