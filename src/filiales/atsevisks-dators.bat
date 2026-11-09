<# :
@echo off
rem ============================================================
rem  atsevisks-dators.bat  - viena datora variants BEZ hub/NAS.
rem  Datoram, kuru nevar pieslegt filiales iekseja tikla.
rem  Dubultklikskis (prasa administratora tiesibas). Var atkartot.
rem
rem  Uzstada C:\ProgramData\PIUAC\auto-update.ps1 un planoto
rem  uzdevumu PIUAC-AutoUpdate (SYSTEM, ik 2 h un startejot).
rem  Skripts reizi diena, kad ir internets, klusi:
rem   - Windows atjauninajumi (bez piespiedu restarta)
rem   - Office Click-to-Run atjauninasana
rem   - winget: Firefox, Chrome, Zoom, VLC, eParaksts, TeamViewer
rem     (uzstada, ja nav), PowerShell 7 (tikai atjaunina)
rem   - CCleaner nonemsana
rem  Zurnali: C:\ProgramData\PIUAC\Logs
rem  Uzreiz pec uzstadisanas palaiz pirmo ciklu.
rem ============================================================
net session >nul 2>&1
if errorlevel 1 (
    echo Prasu administratora tiesibas...
    powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
    exit /b
)
powershell -NoProfile -ExecutionPolicy Bypass -Command "$f='%~f0'; Invoke-Expression ([System.IO.File]::ReadAllText($f))"
exit /b
#>

# ======================= PowerShell dala (uzstaditajs) =======================

$Root     = 'C:\ProgramData\PIUAC'
$Script   = Join-Path $Root 'auto-update.ps1'
$TaskName = 'PIUAC-AutoUpdate'

$auto = @'
# auto-update.ps1 - PIUAC atsevisks dators (bez hub). Palaiz SYSTEM uzdevums PIUAC-AutoUpdate.
param([switch]$Force)
$Root   = 'C:\ProgramData\PIUAC'
$LogDir = Join-Path $Root 'Logs'
$Marker = Join-Path $Root 'last-run-date.txt'
if (-not (Test-Path $LogDir)) { New-Item -ItemType Directory -Path $LogDir -Force | Out-Null }
$Log = Join-Path $LogDir ("auto-update-" + (Get-Date -Format 'yyyyMMdd-HHmmss') + ".log")
function L { param([string]$m) $line = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')  $m"; Add-Content -Path $Log -Value $line; Write-Host $line }

$today = Get-Date -Format 'yyyy-MM-dd'
if (-not $Force -and (Test-Path $Marker) -and ((Get-Content $Marker -TotalCount 1) -eq $today)) { Remove-Item $Log -ErrorAction SilentlyContinue; exit 0 }

# Internets?
$online = $false
foreach ($i in 1..10) {
    try { $r = Invoke-WebRequest -Uri 'http://www.msftconnecttest.com/connecttest.txt' -UseBasicParsing -TimeoutSec 10; if ($r.Content -match 'Microsoft Connect Test') { $online = $true; break } } catch { }
    Start-Sleep -Seconds 30
}
if (-not $online) { L "Nav interneta - meginasim nakamreiz."; exit 0 }
Set-Content -Path $Marker -Value $today
L "=== PIUAC auto-update sakts uz $env:COMPUTERNAME ==="

# --- Office Click-to-Run ---
$c2r = "$env:CommonProgramFiles\microsoft shared\ClickToRun\OfficeC2RClient.exe"
if (Test-Path $c2r) {
    Start-Process -FilePath $c2r -ArgumentList '/update user displaylevel=false forceappshutdown=false' -WindowStyle Hidden
    L "Office: atjauninasana uzdota fona."
} else { L "Office: Click-to-Run nav atrasts - izlaists." }

# --- winget ---
$pkg = Get-AppxPackage -Name 'Microsoft.DesktopAppInstaller' -AllUsers -ErrorAction SilentlyContinue | Sort-Object Version -Descending | Select-Object -First 1
$winget = if ($pkg) { Join-Path $pkg.InstallLocation 'winget.exe' } else { $null }
if ($winget -and (Test-Path $winget)) {
    L "winget: $winget"
    & $winget source update --name winget 2>&1 | Out-Null
    $common = @('--source','winget','--exact','--silent','--accept-package-agreements','--accept-source-agreements','--disable-interactivity')
    $apps = @(
        @{ Id = 'Mozilla.Firefox';          Mode = 'Install' },
        @{ Id = 'Google.Chrome';            Mode = 'Install' },
        @{ Id = 'Zoom.Zoom';                Mode = 'Install' },
        @{ Id = 'VideoLAN.VLC';             Mode = 'Install' },
        @{ Id = 'eParaksts.eParakstitajs';  Mode = 'Install' },
        @{ Id = 'TeamViewer.TeamViewer';    Mode = 'Install' },
        @{ Id = 'TeamViewer.TeamViewer.Host'; Mode = 'UpdateOnly' },
        @{ Id = 'Microsoft.PowerShell';     Mode = 'UpdateOnly' }
    )
    $hasTvHost = $false
    & $winget list --id 'TeamViewer.TeamViewer.Host' --exact --source winget --accept-source-agreements --disable-interactivity 2>&1 | Out-Null
    if ($LASTEXITCODE -eq 0) { $hasTvHost = $true }
    foreach ($a in $apps) {
        & $winget list --id $a.Id --exact --source winget --accept-source-agreements --disable-interactivity 2>&1 | Out-Null
        $installed = ($LASTEXITCODE -eq 0)
        if ($installed) {
            $out = & $winget upgrade --id $a.Id @common --scope machine 2>&1
            if ($LASTEXITCODE -ne 0) { $out = & $winget upgrade --id $a.Id @common 2>&1 }
            L ("{0}: upgrade kods {1}" -f $a.Id, $LASTEXITCODE)
        } elseif ($a.Mode -eq 'Install') {
            if ($a.Id -eq 'TeamViewer.TeamViewer' -and $hasTvHost) { L "TeamViewer: ir Host - pilno versiju neuzstadu."; continue }
            $out = & $winget install --id $a.Id @common --scope machine 2>&1
            if ($LASTEXITCODE -ne 0) { $out = & $winget install --id $a.Id @common 2>&1 }
            L ("{0}: install kods {1}" -f $a.Id, $LASTEXITCODE)
        }
    }
    # CCleaner nonemsana (ka Dobele)
    & $winget list --id 'Piriform.CCleaner' --exact --accept-source-agreements --disable-interactivity 2>&1 | Out-Null
    if ($LASTEXITCODE -eq 0) {
        & $winget uninstall --id 'Piriform.CCleaner' --exact --silent --disable-interactivity 2>&1 | Out-Null
        L "CCleaner: nonemsana, kods $LASTEXITCODE"
    }
} else { L "winget nav atrasts - programmas izlaistas." }

# --- Windows Update (COM, bez restarta) ---
try {
    $s = New-Object -ComObject Microsoft.Update.Session
    $res = $s.CreateUpdateSearcher().Search("IsInstalled=0 and IsHidden=0 and Type='Software'")
    $col = New-Object -ComObject Microsoft.Update.UpdateColl
    foreach ($u in $res.Updates) { if (-not $u.EulaAccepted) { $u.AcceptEula() }; [void]$col.Add($u) }
    L "Windows Update: atrasti $($col.Count)."
    if ($col.Count -gt 0) {
        $d = $s.CreateUpdateDownloader(); $d.Updates = $col; [void]$d.Download()
        $i = $s.CreateUpdateInstaller(); $i.Updates = $col; $r = $i.Install()
        L "Windows Update: rezultats $($r.ResultCode) (2=OK), vajag restartu: $($r.RebootRequired)"
        foreach ($u in $col) { L "  - $($u.Title)" }
    }
} catch { L "Windows Update kluda: $_" }

# Vecie zurnali (30 dienas)
Get-ChildItem $LogDir -Filter 'auto-update-*.log' | Where-Object { $_.LastWriteTime -lt (Get-Date).AddDays(-30) } | Remove-Item -Force -ErrorAction SilentlyContinue
L "=== Pabeigts ==="
'@

if (-not (Test-Path $Root)) { New-Item -ItemType Directory -Path $Root -Force | Out-Null }
Set-Content -Path $Script -Value $auto -Encoding UTF8
Write-Host "Ierakstits: $Script" -ForegroundColor Green

$action = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument "-NoProfile -NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$Script`""
$t1 = New-ScheduledTaskTrigger -Once -At (Get-Date).AddMinutes(5) -RepetitionInterval (New-TimeSpan -Hours 2)
$t2 = New-ScheduledTaskTrigger -AtStartup
$t2.Delay = 'PT10M'
$principal = New-ScheduledTaskPrincipal -UserId 'SYSTEM' -LogonType ServiceAccount -RunLevel Highest
$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -MultipleInstances IgnoreNew -ExecutionTimeLimit (New-TimeSpan -Hours 4)
Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger @($t1, $t2) -Principal $principal -Settings $settings -Description 'PIUAC: atjauninajumi no interneta (atsevisks dators, bez hub).' -Force | Out-Null
Write-Host "Uzdevums '$TaskName' registrets (SYSTEM, ik 2 h + startejot; reizi diena, kad ir internets)." -ForegroundColor Green

# Ja dators bija sagatavots filiales sistemai, hub uzdevumi te nav vajadzigi
foreach ($n in 'LabAppUpdate', 'LabAppUpdate-Kick') {
    if (Get-ScheduledTask -TaskName $n -ErrorAction SilentlyContinue) { Disable-ScheduledTask -TaskName $n | Out-Null; Write-Host "Atslegts: $n (hub nav pieejams)" -ForegroundColor Yellow }
}

Write-Host "`nPirmais cikls (var ilgt ilgi; logs nav jaaizver - uzdevums strada fona)..." -ForegroundColor Cyan
Start-ScheduledTask -TaskName $TaskName
Start-Sleep -Seconds 5
Write-Host "Sakts. Zurnals: C:\ProgramData\PIUAC\Logs\ (jaunakais auto-update-*.log)."
Read-Host "Nospied Enter, lai aizvertu"
