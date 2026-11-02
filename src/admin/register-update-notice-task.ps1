<#
============================================================
 register-update-notice-task.ps1
 Registre update-notice.ps1 ka Scheduled Task, kas darbojas
 TIKAI darba laika un darba dienas (noklusejuma Pr-Pk, 07:00-18:00)
 ik pa 5 minutem.

 SVARIGI: sis Task strada citadi neka client-install.ps1 -
 tas registrets, lai palaistos JEBKURAM tobrid ielogotam
 lietotajam redzamaa sesija (BUILTIN\Users grupa, Interactive
 logon tips), NEVIS fona ar labupdate kontu - pretejaa
 gadijumaa parinojums nekad nebutu redzams.

 Palaizams VIENU REIZI katra datora, kur velaties redzamus
 bridinajumus (piem. biroja darbinieku dators).
 Prasa: Administrators PowerShell logs.
============================================================
#>

param(
    [string]$ScriptPath = "C:\Scripts\update-notice.ps1",
    [string]$TaskName   = "Update-Notice-Check",
    [string]$StartTime  = "07:00",
    [string]$EndTime    = "18:00",
    [int]$IntervalMinutes = 5,
    [System.DayOfWeek[]]$DaysOfWeek = @(
        [System.DayOfWeek]::Monday,
        [System.DayOfWeek]::Tuesday,
        [System.DayOfWeek]::Wednesday,
        [System.DayOfWeek]::Thursday,
        [System.DayOfWeek]::Friday
    )
)

function Get-QuotedArgLocal {
    param([string]$Value)
    if ($Value -match '\s') {
        return '"' + $Value + '"'
    }
    return $Value
}

if (-not (Test-Path $ScriptPath)) {
    Write-Host "KLUDA: skripts nav atrasts $ScriptPath" -ForegroundColor Red
    exit 1
}

$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Host "KLUDA: sis skripts japalaiz ka Administrators." -ForegroundColor Red
    exit 1
}

$startDt = [datetime]::ParseExact($StartTime, "HH:mm", $null)
$endDt   = [datetime]::ParseExact($EndTime, "HH:mm", $null)
if ($endDt -le $startDt) {
    Write-Host "KLUDA: EndTime ($EndTime) jabut velakam par StartTime ($StartTime)." -ForegroundColor Red
    exit 1
}
$duration = $endDt - $startDt

$quotedScriptPath = Get-QuotedArgLocal -Value $ScriptPath
$argumentString = "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File " + $quotedScriptPath

# "-WindowStyle Hidden" dazkart neverst isslaicigu loga uzplaiksnijumu
# biezi palaistam uzdevumam. Drosakais veids - VBS "palaisanas apvalks"
# ar WScript.Shell.Run stilu 0 (NEKAD nerada logu).
$scriptDir = Split-Path $ScriptPath -Parent
$vbsLauncherPath = Join-Path $scriptDir "notice-launcher.vbs"
$vbsCommandLine = "powershell.exe " + $argumentString
$vbsCommandLineEscaped = $vbsCommandLine.Replace('"', '""')
$newline = [string]([char]13) + [string]([char]10)
$vbsContent = 'Set objShell = CreateObject("WScript.Shell")' + $newline +
              'objShell.Run "' + $vbsCommandLineEscaped + '", 0, True' + $newline
Set-Content -Path $vbsLauncherPath -Value $vbsContent -Encoding ASCII
Write-Host "notice-launcher.vbs izveidots: $vbsLauncherPath"

$quotedVbsPath = Get-QuotedArgLocal -Value $vbsLauncherPath
$actionParams = @{
    Execute  = "wscript.exe"
    Argument = $quotedVbsPath
}
$action = New-ScheduledTaskAction @actionParams

$onceParams = @{
    Once                = $true
    At                  = $StartTime
    RepetitionInterval   = New-TimeSpan -Minutes $IntervalMinutes
    RepetitionDuration   = $duration
}
$helperTrigger = New-ScheduledTaskTrigger @onceParams

$trigger = New-ScheduledTaskTrigger -Weekly -DaysOfWeek $DaysOfWeek -At $StartTime
$trigger.Repetition = $helperTrigger.Repetition

$settingsParams = @{
    StartWhenAvailable         = $true
    DontStopOnIdleEnd          = $true
    AllowStartIfOnBatteries    = $true
    DontStopIfGoingOnBatteries = $true
    ExecutionTimeLimit         = (New-TimeSpan -Minutes 10)
}
$settings = New-ScheduledTaskSettingsSet @settingsParams

# BUILTIN\Users + Interactive = palaidzas redzami JEBKURAM
# tobrid ielogotam lietotajam, bez paroles glabasanas.
$principal = New-ScheduledTaskPrincipal -GroupId "BUILTIN\Users" -RunLevel Limited

Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false -ErrorAction SilentlyContinue

try {
    $registerParams = @{
        TaskName    = $TaskName
        Action      = $action
        Trigger     = $trigger
        Settings    = $settings
        Principal   = $principal
        Description = "Rada bridinajuma logu lietotajam pirms planotas atjauninasanas (darba laika, ik $IntervalMinutes min)."
        ErrorAction = "Stop"
    }
    Register-ScheduledTask @registerParams | Out-Null

    Write-Host ""
    Write-Host "Uzdevums '$TaskName' veiksmigi registrets." -ForegroundColor Green
    Write-Host "Palaidisies ik $IntervalMinutes min no $StartTime lidz $EndTime, darba dienas (Pr-Pk), jebkuram tobrid ielogotam lietotajam."
    Write-Host ""
    Write-Host "Testesanai uzreiz:"
    Write-Host "  schtasks /Run /TN " -NoNewline -ForegroundColor Cyan
    Write-Host $TaskName -ForegroundColor Cyan

} catch {
    Write-Host "KLUDA registrejot uzdevumu: $_" -ForegroundColor Red
    exit 1
}
