<#
============================================================
 filiales-grafiks.ps1
 Admin dators (PIUAC-ASKOLDS), parasts PowerShell.

 Atver TO PASU grafika paneli (C:\Scripts\config-panel.ps1), bet ar
 filiales grafiku C:\Scripts\Filiales\<Branch>\Config\device-schedule.csv.
 Kad panelis aizverts un grafiks mainits (nospiests "Saglabat uz NAS"),
 izmainas automatiski paraksta un publice (publish-filiale.ps1).

 Dobeles panelis NETIEK mainits: katru reizi tiek izveidota kopija
 C:\Scripts\config-panel-filiale.ps1 (taja pasa mape - paneli
 palrikiem), kura paslepas pogas, kas filialei neder ($HideButtons).

 Isceljs uz darbvirsmas: -CreateShortcut
   powershell -ExecutionPolicy Bypass -File C:\Scripts\Filiales\filiales-grafiks.ps1 -Branch Auce -CreateShortcut
============================================================
#>
param(
    [string]$Branch = "Auce",
    [string]$Panel = "C:\Scripts\config-panel.ps1",
    [switch]$CreateShortcut,
    [string[]]$HideButtons = @("Atvert ESET portalu", "Profilu kopijas")
)

$root = "C:\Scripts\Filiales\$Branch"
$csv  = Join-Path $root "Config\device-schedule.csv"
$pub  = "C:\Scripts\Filiales\publish-filiale.ps1"

if ($CreateShortcut) {
    $lnk = Join-Path ([Environment]::GetFolderPath('Desktop')) "$Branch grafiks.lnk"
    $ws = New-Object -ComObject WScript.Shell
    $sc = $ws.CreateShortcut($lnk)
    $sc.TargetPath = "powershell.exe"
    $sc.Arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`" -Branch $Branch"
    $sc.WorkingDirectory = "C:\Scripts\Filiales"
    $sc.IconLocation = "shell32.dll,21"
    $sc.Save()
    Write-Host "Izveidots: $lnk" -ForegroundColor Green
    exit 0
}

foreach ($p in @($Panel, $csv, $pub)) {
    if (-not (Test-Path $p)) { Write-Host "KLUDA: nav $p" -ForegroundColor Red; Read-Host "Enter"; exit 1 }
}

$before = (Get-FileHash $csv -Algorithm SHA256).Hash
Write-Host "Atveru $Branch grafiku ($csv)..." -ForegroundColor Cyan
Write-Host "Pec izmainam: 'Saglabat uz NAS', tad aizver logu - publicesana notiks automatiski."
# Panela kopija ar paslepta pogam (originals netiek mainits)
$panelCopy = Join-Path (Split-Path $Panel -Parent) "config-panel-filiale.ps1"
$txt = [System.IO.File]::ReadAllText($Panel)
foreach ($h in $HideButtons) {
    $pattern = '(?m)^([ \t]*)(\$\w+)\.Text\s*=\s*"' + [regex]::Escape($h) + '"'
    if ([regex]::IsMatch($txt, $pattern)) {
        $txt = [regex]::Replace($txt, $pattern, '$0; $2.Visible = $false')
    } else {
        Write-Host "  (poga '$h' panelii nav atrasta - neko neslepju)" -ForegroundColor Yellow
    }
}
[System.IO.File]::WriteAllText($panelCopy, $txt, (New-Object System.Text.UTF8Encoding($true)))
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $panelCopy -NasRoot $root
$after = (Get-FileHash $csv -Algorithm SHA256).Hash

if ($after -eq $before) {
    Write-Host "`nGrafiks nav mainits - publicet nevajag." -ForegroundColor Yellow
    Start-Sleep -Seconds 3
    exit 0
}

Write-Host "`nGrafiks mainits - parakstu un publiceju..." -ForegroundColor Cyan
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $pub -Branch $Branch
Read-Host "`nNospied Enter, lai aizvertu"
