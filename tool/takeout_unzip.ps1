# STEP 14 - check and unzip Google Takeout zips from Downloads into Downloads\GooglePhotosTakeout.
# The zips themselves are NOT deleted. Writes takeout_unzip_report.txt in _organize_tool.
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.IO.Compression.FileSystem
$ToolDir = $PSScriptRoot
$Dl   = Join-Path $env:USERPROFILE 'Downloads'
$Dest = Join-Path $Dl 'GooglePhotosTakeout'
$zips = @(Get-ChildItem -LiteralPath $Dl -Filter 'takeout-*.zip' | Sort-Object Name)
$rep = New-Object System.Collections.Generic.List[string]
$rep.Add("TAKEOUT UNZIP REPORT $(Get-Date -Format 'yyyy-MM-dd HH:mm')")
if (-not $zips.Count) { Write-Host 'No takeout-*.zip found in Downloads.' -ForegroundColor Red; return }
# 1) can every zip be opened? (a cut-off download cannot)
$info = @(); $total = 0; $bad = 0
foreach ($z in $zips) {
    try {
        $a = [IO.Compression.ZipFile]::OpenRead($z.FullName)
        $n = $a.Entries.Count; $u = ($a.Entries | Measure-Object Length -Sum).Sum; $a.Dispose()
        $info += [pscustomobject]@{ Z=$z; N=$n; U=$u }; $total += $u
        $rep.Add(("OK to open: {0}  ({1:N1} GB, {2} files inside, {3:N1} GB unzipped)" -f $z.Name, ($z.Length/1GB), $n, ($u/1GB)))
    } catch { $bad++; $rep.Add("CORRUPTED / INCOMPLETE (cannot open): $($z.Name) -> $($_.Exception.Message)") }
}
# 2) enough disk space?
$drive = (Get-Item $Dl).PSDrive; $free = (Get-PSDrive $drive.Name).Free
$rep.Add(("Needed: {0:N1} GB   Free on {1}: {2:N1} GB" -f ($total/1GB), $drive.Name, ($free/1GB)))
foreach ($l in $rep) { Write-Host $l }
if ($bad) { Write-Host 'One or more zips are damaged - re-download them from the Google email before continuing.' -ForegroundColor Red }
if ($total + 2GB -gt $free) { Write-Host 'NOT ENOUGH DISK SPACE to unzip everything. Nothing was unzipped. Tell Claude.' -ForegroundColor Red; [IO.File]::WriteAllLines((Join-Path $ToolDir 'takeout_unzip_report.txt'), $rep); return }
if ((Read-Host 'Type YES to unzip the good zips now (takes 30-90 min)') -ne 'YES') { return }
[void][IO.Directory]::CreateDirectory($Dest)
# 3) unzip with Windows tar (checks every file's checksum while extracting)
foreach ($i in $info) {
    Write-Host ("Unzipping {0} ..." -f $i.Z.Name) -ForegroundColor Cyan
    $errFile = Join-Path $ToolDir ("unzip_errors_{0}.txt" -f $i.Z.BaseName)
    $p = Start-Process -FilePath "$env:SystemRoot\System32\tar.exe" -ArgumentList @('-xf', "`"$($i.Z.FullName)`"", '-C', "`"$Dest`"") -NoNewWindow -Wait -PassThru -RedirectStandardError $errFile
    $errs = @(Get-Content -LiteralPath $errFile -ErrorAction SilentlyContinue | Where-Object { $_ -match '\S' })
    $rep.Add(("Unzip {0}: exit code {1}, {2} error lines (see {3})" -f $i.Z.Name, $p.ExitCode, $errs.Count, (Split-Path -Leaf $errFile)))
    foreach ($e in ($errs | Select-Object -First 30)) { $rep.Add("   $e") }
}
# 4) compare: every file inside the zips present with the right size?
$missing = 0; $wrong = 0; $empty = 0
foreach ($i in $info) {
    $a = [IO.Compression.ZipFile]::OpenRead($i.Z.FullName)
    foreach ($e in $a.Entries) {
        if ($e.FullName.EndsWith('/')) { continue }
        $f = Join-Path $Dest ($e.FullName -replace '/', '\')
        if (-not [IO.File]::Exists($f)) { $missing++; if ($missing -le 30) { $rep.Add("MISSING after unzip: $($e.FullName)") }; continue }
        $len = (Get-Item -LiteralPath $f).Length
        if ($len -ne $e.Length) { $wrong++; if ($wrong -le 30) { $rep.Add("WRONG SIZE: $($e.FullName)") } }
        elseif ($len -eq 0 -and $e.FullName -notmatch '\.json$') { $empty++ }
    }
    $a.Dispose()
}
$media = @(Get-ChildItem -LiteralPath $Dest -Recurse -File | Where-Object { $_.Extension -notmatch '^\.(json|html)$' }).Count
$rep.Add(("RESULT: photos/videos unzipped: {0}; missing: {1}; wrong size: {2}; empty files: {3}" -f $media, $missing, $wrong, $empty))
[IO.File]::WriteAllLines((Join-Path $ToolDir 'takeout_unzip_report.txt'), $rep, (New-Object Text.UTF8Encoding $true))
if ($missing + $wrong -eq 0) { Write-Host 'ALL GOOD - every file unzipped intact.' -ForegroundColor Green } else { Write-Host 'Some problems found - see report.' -ForegroundColor Yellow }
Write-Host 'Go back to Claude and say "unzip done".'
