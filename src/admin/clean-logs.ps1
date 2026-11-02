<#
 clean-logs.ps1  - NAS zurnalu sakopsana. Pec noklusejuma TIKAI PARADA, ko dzestu (sausa palaisana).
 Dzesanai pievieno -Apply.
 Noteikumi:
   Logs\Clients\*.log un Logs\downloader-*.log:
     - "neinteresanti" (nav ERROR/WARN, nav nekas uzstadits/atjauninats) un vecaki par -BoringDays dienam -> dzest
     - jebkurs vecaks par -MaxDays dienam -> dzest
   "interesants" = satur [ERROR], [WARN], "veiksmiga", "instalesu", "instaleju", "jauna versija pieejama", "restart".
 Netiek aiztikti: Logs\MsiLogs, Logs\Inventory, Logs\Status.
#>
param(
    [string]$LogRoot    = "\\PIUAC_CLOUD\Updates\Logs",
    [int]$BoringDays    = 3,
    [int]$MaxDays       = 60,
    [switch]$Apply
)

$interesting = '\[ERROR\]|\[WARN\]|veiksmiga|instalesu|instaleju|jauna versija pieejama|restart'
$targets = @()
$targets += Get-ChildItem (Join-Path $LogRoot "Clients") -Filter *.log -File -ErrorAction SilentlyContinue
$targets += Get-ChildItem $LogRoot -Filter "downloader-*.log" -File -ErrorAction SilentlyContinue

$del = @(); $keep = 0
foreach ($f in $targets) {
    $ageDays = ((Get-Date) - $f.LastWriteTime).TotalDays
    $remove = $false
    if ($ageDays -gt $MaxDays) { $remove = $true }
    elseif ($ageDays -gt $BoringDays) {
        $hit = Select-String -Path $f.FullName -Pattern $interesting -Quiet -ErrorAction SilentlyContinue
        if (-not $hit) { $remove = $true }
    }
    if ($remove) { $del += $f } else { $keep++ }
}

$mb = [math]::Round((($del | Measure-Object Length -Sum).Sum) / 1MB, 1)
Write-Host ("Kopa failu: {0}; paliek: {1}; dzesami: {2} ({3} MB)" -f $targets.Count, $keep, $del.Count, $mb)
if ($Apply) {
    $del | Remove-Item -Force -ErrorAction SilentlyContinue
    Write-Host "Izdzesti." -ForegroundColor Green
} else {
    Write-Host "Sausa palaisana - nekas nav dzests. Dzesanai: .\clean-logs.ps1 -Apply" -ForegroundColor Yellow
}
