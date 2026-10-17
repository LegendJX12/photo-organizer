# VERIFY DUPLICATES - read-only. Re-checks every duplicate against the photo that was kept,
# using a different, stronger fingerprint (SHA256) + exact size. Writes verify_report.txt.
$ToolDir = $PSScriptRoot
$Root    = Split-Path -Parent $ToolDir
$pairs = @(Import-Csv -LiteralPath (Join-Path $ToolDir 'dup_pairs.csv') -Encoding UTF8)
$ok = 0; $bad = New-Object System.Collections.Generic.List[string]; $empty = New-Object System.Collections.Generic.List[string]; $i = 0
foreach ($p in $pairs) {
    $i++; if ($i % 20 -eq 0) { Write-Progress -Activity 'Verifying duplicates' -Status "$i / $($pairs.Count)" -PercentComplete ($i*100/$pairs.Count) }
    $a = Join-Path $Root $p.Duplicate; $b = Join-Path $Root $p.Kept
    try {
        $fa = Get-Item -LiteralPath $a; $fb = Get-Item -LiteralPath $b
        if ($fa.Length -eq 0) { $empty.Add($p.Duplicate); continue }
        $ha = (Get-FileHash -LiteralPath $a -Algorithm SHA256).Hash
        $hb = (Get-FileHash -LiteralPath $b -Algorithm SHA256).Hash
        if ($fa.Length -eq $fb.Length -and $ha -eq $hb) { $ok++ } else { $bad.Add("DIFFERENT: $($p.Duplicate)  vs  $($p.Kept)") }
    } catch { $bad.Add("ERROR: $($p.Duplicate) -> $($_.Exception.Message)") }
}
Write-Progress -Activity 'Verifying duplicates' -Completed
$r = @("VERIFY REPORT $(Get-Date -Format 'yyyy-MM-dd HH:mm')", "Pairs checked: $($pairs.Count)", "Identical (safe to delete): $ok", "Empty 0-byte files (no picture, safe to delete): $($empty.Count)", "PROBLEMS: $($bad.Count)", '') + $bad + @('', 'Empty files:') + $empty
[IO.File]::WriteAllLines((Join-Path $ToolDir 'verify_report.txt'), $r, (New-Object Text.UTF8Encoding $true))
if ($bad.Count -eq 0) { Write-Host "ALL GOOD: $ok duplicates are exact copies. $($empty.Count) empty files." -ForegroundColor Green }
else { Write-Host "$($bad.Count) PROBLEMS found - do NOT delete yet, tell Claude." -ForegroundColor Red }
Write-Host 'Go back to Claude and say "verify done".'
