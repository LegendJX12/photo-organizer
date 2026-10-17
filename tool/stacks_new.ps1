# STEP 18 - similar-shot stacks for newly imported photos (stacks_new.csv):
# sharpest stays in place, the others go to a "<best> - similar shots" subfolder.
# Files listed in no_moves.csv are left alone. Logged in stacks_new_undo.csv.
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing
Add-Type -ReferencedAssemblies System.Drawing -TypeDefinition @"
using System; using System.Drawing; using System.Drawing.Imaging; using System.IO;
public static class Sharp {
  public static double Score(string path) {
    using (var fs = File.OpenRead(path)) using (var img = Image.FromStream(fs, false, false)) {
      int w = 512; int h = Math.Max(1, (int)(img.Height * 512.0 / img.Width));
      using (var bmp = new Bitmap(w, h, PixelFormat.Format24bppRgb)) {
        using (var g = Graphics.FromImage(bmp)) { g.DrawImage(img, 0, 0, w, h); }
        var d = bmp.LockBits(new Rectangle(0,0,w,h), ImageLockMode.ReadOnly, PixelFormat.Format24bppRgb);
        int stride = d.Stride; byte[] px = new byte[stride*h]; System.Runtime.InteropServices.Marshal.Copy(d.Scan0, px, 0, px.Length); bmp.UnlockBits(d);
        Func<int,int,double> L = (x,y) => { int i=y*stride+x*3; return px[i+2]*0.299+px[i+1]*0.587+px[i]*0.114; };
        double s=0, s2=0; long n=0;
        for (int y=1;y<h-1;y++) for (int x=1;x<w-1;x++) { double v = 4*L(x,y)-L(x-1,y)-L(x+1,y)-L(x,y-1)-L(x,y+1); s+=v; s2+=v*v; n++; }
        double m=s/n; return s2/n - m*m;
      }
    }
  }
}
"@
$ToolDir = $PSScriptRoot
$Root    = Split-Path -Parent $ToolDir
$movesFile = Join-Path $ToolDir 'no_moves.csv'
$moves  = @(if (Test-Path -LiteralPath $movesFile) { Import-Csv -LiteralPath $movesFile -Encoding UTF8 })  # optional: no file = no trip moves
$stacks = @(Import-Csv -LiteralPath (Join-Path $ToolDir 'stacks_new.csv') -Encoding UTF8)
Write-Host ("This will move {0} photos into trip folders and sort {1} similar-shot stacks." -f $moves.Count, ($stacks | Select-Object -ExpandProperty Stack -Unique).Count) -ForegroundColor Yellow
if ((Read-Host 'Type YES and press Enter to continue') -ne 'YES') { Write-Host 'Cancelled.'; return }
$undo = New-Object System.Collections.Generic.List[object]
$map = @{}
function Unique($dst) { $c=2; $b=$dst; while ([IO.File]::Exists($dst)) { $dst = Join-Path (Split-Path -Parent $b) ('{0} ({1}){2}' -f [IO.Path]::GetFileNameWithoutExtension($b),$c,[IO.Path]::GetExtension($b)); $c++ }; return $dst }
function MoveOne($fromRel, $toFull) {
    $src = Join-Path $Root $fromRel
    if (-not [IO.File]::Exists($src)) { return $null }
    $dst = Unique $toFull
    [void][IO.Directory]::CreateDirectory((Split-Path -Parent $dst)); [IO.File]::Move($src, $dst)
    $undo.Add([pscustomobject]@{ From=$src; To=$dst }); return $dst
}
# A. trips
$i=0
foreach ($m in $moves) {
    $i++; if ($i % 100 -eq 0) { Write-Progress -Activity 'Moving into trip folders' -Status "$i / $($moves.Count)" -PercentComplete ($i*100/$moves.Count) }
    $new = MoveOne $m.Source (Join-Path $Root $m.Destination)
    if ($new) { $map[$m.Source] = $new.Substring($Root.Length+1) }
}
Write-Progress -Activity 'Moving into trip folders' -Completed
# B. stacks
$review = New-Object System.Collections.Generic.List[object]
$groups = $stacks | Group-Object Stack
$i=0
foreach ($g in $groups) {
    $i++; if ($i % 20 -eq 0) { Write-Progress -Activity 'Sorting similar shots (picking sharpest)' -Status "$i / $($groups.Count)" -PercentComplete ($i*100/$groups.Count) }
    $mem = foreach ($p in $g.Group) { $rel = if ($map.ContainsKey($p.Path)) { $map[$p.Path] } else { $p.Path }; $full = Join-Path $Root $rel; if ([IO.File]::Exists($full)) { $full } }
    $mem = @($mem)
    if ($mem.Count -lt 2) { continue }
    if (@($mem | ForEach-Object { Split-Path -Parent $_ } | Sort-Object -Unique).Count -ne 1) { continue }
    $scored = foreach ($f in $mem) { $s = 0; try { $s = [Sharp]::Score($f) } catch {}; [pscustomobject]@{ F=$f; S=$s; L=(Get-Item -LiteralPath $f).Length } }
    $ranked = @($scored | Sort-Object @{e={$_.S};Descending=$true}, @{e={$_.L};Descending=$true})
    $best = $ranked[0]
    $sub = Join-Path (Split-Path -Parent $best.F) ('{0} - similar shots' -f [IO.Path]::GetFileNameWithoutExtension($best.F))
    $others = @()
    foreach ($o in ($ranked | Select-Object -Skip 1)) {
        $new = MoveOne $o.F.Substring($Root.Length+1) (Join-Path $sub (Split-Path -Leaf $o.F))
        if ($new) { $others += [pscustomobject]@{ P=$new.Substring($Root.Length+1); S=[math]::Round($o.S) } }
    }
    $review.Add([pscustomobject]@{ Best=$best.F.Substring($Root.Length+1); BestS=[math]::Round($best.S); Others=$others })
}
Write-Progress -Activity 'Sorting similar shots (picking sharpest)' -Completed
$undo | Export-Csv -LiteralPath (Join-Path $ToolDir 'stacks_new_undo.csv') -NoTypeInformation -Encoding UTF8
# remove now-empty old month folders
Get-ChildItem -LiteralPath (Join-Path $Root '_Organized') -Directory -Recurse -Force | Sort-Object { $_.FullName.Length } -Descending | ForEach-Object { if (-not (Get-ChildItem -LiteralPath $_.FullName -Force)) { Remove-Item -LiteralPath $_.FullName -Force } }
# compare page
function U($p) { return '../' + (($p.Split('\') | ForEach-Object { [Uri]::EscapeDataString($_) }) -join '/') }
$h = New-Object Text.StringBuilder
[void]$h.Append('<!doctype html><html><head><meta charset="utf-8"><title>Similar Shots</title><style>body{font-family:Segoe UI,Arial;background:#f4f4f2;padding:16px;color:#222}.g{background:#fff;border-radius:10px;padding:10px;margin:12px 0}.row{display:flex;gap:10px;flex-wrap:wrap}.c{width:230px;font-size:12px;word-break:break-all}.best{outline:4px solid #2e9e4f;border-radius:6px}img{width:230px;border-radius:6px}.k{color:#17652d;font-weight:600}.x{color:#666}</style></head><body>')
[void]$h.Append("<h1>Similar shots ($($review.Count) stacks)</h1><p>Green = sharpest, kept in the event folder. The others are in the <i>'... - similar shots'</i> subfolder next to it. Sharpness score: higher is sharper. To swap, just drag files between the folder and the subfolder.</p>")
$n=0
foreach ($r in $review) { $n++
  [void]$h.Append("<div class='g'><b>#$n</b> <span class='x'>$([Net.WebUtility]::HtmlEncode((Split-Path -Parent $r.Best)))</span><div class='row'>")
  [void]$h.Append("<div class='c'><div class='k'>BEST (kept) - sharpness $($r.BestS)</div><a href='$(U $r.Best)' target='_blank'><img class='best' loading='lazy' src='$(U $r.Best)'></a><br>$([Net.WebUtility]::HtmlEncode((Split-Path -Leaf $r.Best)))</div>")
  foreach ($o in $r.Others) { [void]$h.Append("<div class='c'><div class='x'>similar - sharpness $($o.S)</div><a href='$(U $o.P)' target='_blank'><img loading='lazy' src='$(U $o.P)'></a><br>$([Net.WebUtility]::HtmlEncode((Split-Path -Leaf $o.P)))</div>") }
  [void]$h.Append('</div></div>') }
[void]$h.Append('</body></html>')
[IO.File]::WriteAllText((Join-Path $ToolDir 'similar_shots_new.html'), $h.ToString(), (New-Object Text.UTF8Encoding $true))
Write-Host ("DONE. Moved {0} files. Stacks sorted: {1}. Open similar_shots_new.html to compare." -f $undo.Count, $review.Count) -ForegroundColor Green
Write-Host 'Go back to Claude and say "new stacks done".'
