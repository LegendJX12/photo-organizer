# STEP 9 - look up place names for the GPS areas in geo_cells.csv using OpenStreetMap.
# Only coordinates are sent (about 1 per second). Writes geo_names.csv. Moves nothing.
$ToolDir = $PSScriptRoot
$cells = @(Import-Csv -LiteralPath (Join-Path $ToolDir 'geo_cells.csv'))
$outFile = Join-Path $ToolDir 'geo_names.csv'
$done = @{}
if (Test-Path -LiteralPath $outFile) { foreach ($d in (Import-Csv -LiteralPath $outFile -Encoding UTF8)) { $done[$d.Cell] = $d } }
$res = New-Object System.Collections.Generic.List[object]
foreach ($d in $done.Values) { $res.Add($d) }
$i = 0
foreach ($c in $cells) {
    $i++; Write-Progress -Activity 'Looking up place names' -Status "$i / $($cells.Count)" -PercentComplete ($i*100/$cells.Count)
    if ($done.ContainsKey($c.Cell)) { continue }
    $url = "https://nominatim.openstreetmap.org/reverse?format=jsonv2&zoom=10&accept-language=en&lat=$($c.Lat)&lon=$($c.Lon)"
    try {
        $j = Invoke-RestMethod -Uri $url -Headers @{ 'User-Agent' = 'personal-photo-organizer/1.0' } -TimeoutSec 30
        $a = $j.address
        $city = @($a.city, $a.town, $a.village, $a.municipality, $a.county, $a.state_district, $a.state) | Where-Object { $_ } | Select-Object -First 1
        $res.Add([pscustomobject]@{ Cell=$c.Cell; City=$city; State=$a.state; Country=$a.country; Display=$j.display_name })
    } catch { $res.Add([pscustomobject]@{ Cell=$c.Cell; City=''; State=''; Country=''; Display='ERROR' }) }
    $res | Export-Csv -LiteralPath $outFile -NoTypeInformation -Encoding UTF8
    Start-Sleep -Milliseconds 1100
}
Write-Progress -Activity 'Looking up place names' -Completed
Write-Host ("DONE. {0} places looked up. Go back to Claude and say ""places done""." -f $res.Count) -ForegroundColor Green
