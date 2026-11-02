<#
 lab-backup-prune.ps1   (palaist no ADMIN datora, PowerShell kaa administrators)

 Katram datoram \\NAS\ProfiluKopijas\<DATORS> atstaj:
   pedejas 7 kopijas + pa vienai kopijai pedejam 4 nedelam + pa vienai pedejiem 6 menesiem,
 parejas dzes (restic forget --prune). Ar -Check papildus parbauda repozitorija integritati (5% datu).
 Ar -DryRun tikai parada, ko dzestu.
#>
param(
    [string]$Root = "\\192.168.3.31\ProfiluKopijas",
    [string]$Restic = "\\192.168.3.31\Updates\Tools\restic.exe",
    [int]$KeepLast = 7,
    [int]$KeepWeekly = 4,
    [int]$KeepMonthly = 6,
    [switch]$DryRun,
    [switch]$Check
)

$pw = Read-Host "restic repozitorija parole" -AsSecureString
$env:RESTIC_PASSWORD = (New-Object System.Net.NetworkCredential("", $pw)).Password
$env:RESTIC_PROGRESS_FPS = "0.0166"

$repos = @(Get-ChildItem $Root -Directory | Where-Object { $_.Name -notin '_status', '#recycle', '@eaDir' -and (Test-Path (Join-Path $_.FullName 'config')) })
Write-Host ("Repozitoriji: " + (($repos | ForEach-Object Name) -join ', '))
$rows = @()
foreach ($r in $repos) {
    Write-Host ""
    Write-Host ("=== " + $r.Name + " ===") -ForegroundColor Cyan
    $env:RESTIC_REPOSITORY = $r.FullName
    $fa = @('forget', '--keep-last', $KeepLast, '--keep-weekly', $KeepWeekly, '--keep-monthly', $KeepMonthly, '--group-by', 'host,tags', '--prune')
    if ($DryRun) { $fa = @('forget', '--keep-last', $KeepLast, '--keep-weekly', $KeepWeekly, '--keep-monthly', $KeepMonthly, '--group-by', 'host,tags', '--dry-run') }
    & $Restic @fa 2>&1 | Select-Object -Last 12 | ForEach-Object { Write-Host ([string]$_) }
    $code = $LASTEXITCODE
    $chk = ""
    if ($Check -and -not $DryRun) {
        & $Restic check --read-data-subset=5% 2>&1 | Select-Object -Last 3 | ForEach-Object { Write-Host ([string]$_) }
        $chk = $(if ($LASTEXITCODE -eq 0) { "check OK" } else { "check KLUDA" })
    }
    $rows += [PSCustomObject]@{ Dators = $r.Name; Forget = $(if ($code -eq 0) { "OK" } else { "KLUDA $code" }); Check = $chk }
}
Remove-Item Env:\RESTIC_PASSWORD -ErrorAction SilentlyContinue
Write-Host ""
$rows | Format-Table -AutoSize
