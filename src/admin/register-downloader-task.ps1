<#
============================================================
 register-downloader-task.ps1
 Registre downloader.ps1 ka Scheduled Task administratora
 dators. Palaizams VIENU REIZI, lai izveidotu uzdevumu.

 Prasa: palaist PowerShell ka Administrators.
 Downloader.ps1 jaatrodas $ScriptPath noraditaja vieta PIRMS
 sa registracijas skripta palaisanas.
============================================================
#>

param(
    [string]$ScriptPath = "C:\Scripts\downloader.ps1",
    [string]$TaskName   = "NAS-Updates-Downloader",
    [string]$TaskTime   = "03:00"
)

# ---------- PARBAUDES ----------

if (-not (Test-Path $ScriptPath)) {
    Write-Host "KLUDA: skripts nav atrasts $ScriptPath" -ForegroundColor Red
    Write-Host "Nokopejiet downloader.ps1 uz so celu vai norediet -ScriptPath parametru." -ForegroundColor Yellow
    exit 1
}

$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Host "KLUDA: sis skripts japalaiz ka Administrators." -ForegroundColor Red
    exit 1
}

# ---------- LIETOTAJA KONTS UZDEVUMAM ----------
# Downloader raksta uz NAS share, kuram piekluve ir jusu paša
# (administratora) kontam - tapec Scheduled Task jaregistre ar
# so pasu kontu, nevis SYSTEM (SYSTEM konts neredz tikla resursus
# ar jusu kredencialiem).

Write-Host "Uzdevums tiks registrets ar kontu: $env:USERDOMAIN\$env:USERNAME"
Write-Host "Lugums ievadit sa lietotaja paroli, lai uzdevums varetu palaisties fona,"
Write-Host "pat ja jus neesat ielogojies (piem., dators tikai ieslegts, bet nav aktivas sesijas)."
Write-Host ""

$cred = Get-Credential -UserName "$env:USERDOMAIN\$env:USERNAME" -Message "Ievadiet paroli kontam, ar kuru uzdevums tiks palaists"

# ---------- UZDEVUMA DEFINICIJA ----------

$action = New-ScheduledTaskAction -Execute "powershell.exe" `
    -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$ScriptPath`""

$trigger = New-ScheduledTaskTrigger -Daily -At $TaskTime

$settings = New-ScheduledTaskSettingsSet `
    -StartWhenAvailable `
    -DontStopOnIdleEnd `
    -ExecutionTimeLimit (New-TimeSpan -Hours 1) `
    -RestartCount 3 `
    -RestartInterval (New-TimeSpan -Minutes 10) `
    -WakeToRun

# Ja uzdevums jau eksiste no iepriekseja mekinajuma - noremjam un veidojam no jauna
Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false -ErrorAction SilentlyContinue

try {
    Register-ScheduledTask -TaskName $TaskName `
        -Action $action `
        -Trigger $trigger `
        -Settings $settings `
        -User $cred.UserName `
        -Password $cred.GetNetworkCredential().Password `
        -RunLevel Highest `
        -Description "Parbauda un lejupielade jaunakas programmatura versijas (Firefox, Chrome, Zoom u.c.) uz NAS Updates\Cache." `
        -ErrorAction Stop | Out-Null

    Write-Host ""
    Write-Host "Uzdevums '$TaskName' veiksmigi registrets." -ForegroundColor Green
    Write-Host "Palaidisies katru dienu plkst. $TaskTime, izmantojot skriptu: $ScriptPath"
    Write-Host ""
    Write-Host "Lai testetu uzreiz (nevis gaidot lidz $TaskTime), palaidiet:"
    Write-Host "  Start-ScheduledTask -TaskName `"$TaskName`"" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "Lai parbauditu statusu/pedejo palaisanas rezultatu:"
    Write-Host "  Get-ScheduledTaskInfo -TaskName `"$TaskName`"" -ForegroundColor Cyan

} catch {
    Write-Host "KLUDA registrejot uzdevumu: $_" -ForegroundColor Red
    exit 1
}
