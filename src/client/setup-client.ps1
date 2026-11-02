<#
============================================================
 setup-client.ps1
 VIENREIZEJS uzstadisanas skripts katram klienta (klases/
 biroja/portativajam) datoram. Palaizams VIENU REIZI uz katra
 jauna klienta datora, ar administratora tiesibam.

 Ko sis skripts dara:
   1. Izveido (vai atjaunina) lokalu 'labupdate' kontu, kas
      TURPAT ir ta pasha konta/paroles ka Synology NAS puse -
      tas lauj SMB piekluvei strradat bez paroles prasisanas
      (workgroup "matching credentials" mehanisms).
   2. Padara so kontu neredzamu logon ekrana un liedz
      interaktivu ielogosanos (tikai fona uzdevumiem).
   3. Registre Scheduled Task "LabAppUpdate", kas palaiz
      client-install.ps1 TIESI NO NAS (nevis lokalas kopijas),
      ik 15 min, visu diennakti, ar labupdate kontu, fona.
   4. Iekopee update-notice.ps1 lokali (jo tas strada ar
      PARASTA lietotaja kontu, kuram nav NAS piekluves) un
      registre Scheduled Task "Update-Notice-Check", kas to
      palaiz darba laika (Pr-Pk, 07:00-18:00) redzami jebkuram
      tobrid ielogotam lietotajam.

 PRIEKSNOSACIJUMS: client-install.ps1 un update-notice.ps1 jau
 jaaugsupielade uz NAS \Scripts\ mapi PIRMS sa skripta
 palaisanas.

 SVARIGI: $AccountPassword JASAKRIT ar paroli, kas jau
 iestatita 'labupdate' lietotajam Synology NAS puse!

 PIEZIME: parole ieprogrammeta ka noklusejuma vertiba (lokalam
 tiklam, lai nebutu janievada katru reizi). Ja NAS puse parole
 mainas, SIS FAILS jalabo ari, lai tas sakristu.
============================================================
#>

param(
    [string]$AccountPassword = "L@bupdate-2026",

    [string]$AccountName = "labupdate",
    [string]$NasRoot = "\\192.168.3.31\Updates",
    [string]$InstallTaskName = "LabAppUpdate",
    [string]$NoticeTaskName = "Update-Notice-Check",
    [int]$InstallIntervalMinutes = 15,
    [int]$NoticeIntervalMinutes = 5,
    [string]$NoticeStartTime = "07:00",
    [string]$NoticeEndTime = "18:00",
    [string]$LocalScriptDir = "C:\Scripts",

    # Energijas iestatijumi (tikai kad dators pieslegts strava): dators
    # NEaizmieg, monitors izslegsies pec $MonitorTimeoutMinutes minutem.
    # Ja sim datoram energijas iestatijumi jaatstaj neskarti, palaidiet
    # ar -SkipPowerSettings.
    [int]$MonitorTimeoutMinutes = 30,
    [switch]$SkipPowerSettings
)

function Write-Step {
    param([string]$Message)
    Write-Host ""
    Write-Host "=== $Message ===" -ForegroundColor Cyan
}

function Get-QuotedArgLocal {
    param([string]$Value)
    if ($Value -match '\s') {
        return '"' + $Value + '"'
    }
    return $Value
}

function Get-AcTimeoutMinutes {
    # Nolasa pasreizeja energijas plana taimeri (strava) minutes.
    # Atgriez $null, ja nolasit neizdodas (piem. cita sistemas valoda).
    param([string]$SubGroup, [string]$Setting)

    $line = & powercfg.exe /query SCHEME_CURRENT $SubGroup $Setting | Select-String "Current AC Power Setting Index"
    if (-not $line) { return $null }
    $hex = (($line.ToString() -split "0x")[1]).Trim()
    return [Convert]::ToInt32($hex, 16) / 60
}

# ---------- PARBAUDES ----------

$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Host "KLUDA: sis skripts japalaiz ka Administrators." -ForegroundColor Red
    exit 1
}

Write-Step "0. Pieslegsanas NAS ar labupdate akreditacijas datiem"

# Administrators, kurs palaiz so skriptu, var buit ielogojies ar
# savu kontu, kuram nav atbilstosu NAS akreditacijas datu. Tapec
# seit EKSPLICITI izveidojam SMB savienojumu ar labupdate kontu,
# pirms jebkadas NAS piekluves - tas paraksta, ka setup-client.ps1
# strada neatkarigi no ta, ar kuru kontu administrators tobrid ir
# ielogojies klienta dators.

$nasServer = ($NasRoot -split "\\")[2]
net use "\\$nasServer" /delete /y 2>$null | Out-Null
net use $NasRoot "/user:$AccountName" $AccountPassword 2>&1 | Out-Null

if (-not (Test-Path $NasRoot)) {
    Write-Host "KLUDA: NAS ($NasRoot) nav sasniedzams pat pec pieslegsanas meginajuma." -ForegroundColor Red
    Write-Host "Parbaudiet: vai IP adrese pareiza, vai NAS lietotajs 'labupdate' eksiste un parole sakrit." -ForegroundColor Red
    exit 1
}
Write-Host "NAS sasniedzams un autentificets."

$remoteInstallScript = Join-Path $NasRoot "Scripts\client-install.ps1"
$remoteNoticeScript  = Join-Path $NasRoot "Scripts\update-notice.ps1"

if (-not (Test-Path $remoteInstallScript)) {
    Write-Host "KLUDA: $remoteInstallScript nav atrasts. Vispirms augsupieladejiet client-install.ps1 uz NAS Scripts mapi." -ForegroundColor Red
    exit 1
}
if (-not (Test-Path $remoteNoticeScript)) {
    Write-Host "KLUDA: $remoteNoticeScript nav atrasts. Vispirms augsupieladejiet update-notice.ps1 uz NAS Scripts mapi." -ForegroundColor Red
    exit 1
}

$computerName = $env:COMPUTERNAME
Write-Host "Uzstadu klientu datoram: $computerName" -ForegroundColor Green

# ---------- 1. LABUPDATE KONTA IZVEIDE ----------

Write-Step "1. Labupdate konts"

$secPass = ConvertTo-SecureString $AccountPassword -AsPlainText -Force
$existing = Get-LocalUser -Name $AccountName -ErrorAction SilentlyContinue

try {
    if (-not $existing) {
        $newUserParams = @{
            Name                 = $AccountName
            Password             = $secPass
            FullName             = "Lab Update Service Account"
            Description          = "Fona atjauninasanai, bez interaktivas pieejas"
            PasswordNeverExpires = $true
            UserMayNotChangePassword = $true
        }
        New-LocalUser @newUserParams -ErrorAction Stop | Out-Null
        Write-Host "Konts '$AccountName' izveidots."
    } else {
        Set-LocalUser -Name $AccountName -Password $secPass -ErrorAction Stop
        Write-Host "Konts '$AccountName' jau eksisteja, parole atjaunota."
    }
} catch {
    Write-Host "KLUDA: neizdevas izveidot/atjaunot kontu '$AccountName': $_" -ForegroundColor Red
    exit 1
}

# Parbaudam, ka konts TIESAM eksiste pirms turpinam - citadi
# turpmakie soli (SID uzzinasana, Scheduled Task) maldigi "izdotos"
if (-not (Get-LocalUser -Name $AccountName -ErrorAction SilentlyContinue)) {
    Write-Host "KLUDA: konts '$AccountName' joprojam nav atrodams pec izveides meginajuma." -ForegroundColor Red
    exit 1
}

$adminGroup = (Get-LocalGroup | Where-Object { $_.SID -like "*-544" }).Name
try {
    Add-LocalGroupMember -Group $adminGroup -Member $AccountName -ErrorAction Stop
    Write-Host "Pievienots administratoru grupai '$adminGroup'."
} catch {
    Write-Host "Konts jau bija grupa, vai neliela kluda (nav kritiski)."
}

# ---------- 2. INTERAKTIVAS IELOGOSANAS LIEGUMS + APSLEPSANA ----------

Write-Step "2. Konta apslepsana un ielogosanas liegums"

$tempCfg = Join-Path $env:TEMP "secpol_labupdate.cfg"
secedit /export /cfg $tempCfg /quiet

$sid = (Get-LocalUser -Name $AccountName).SID.Value
$content = Get-Content $tempCfg
$lineFound = $false
$newContent = $content | ForEach-Object {
    if ($_ -match "^SeDenyInteractiveLogonRight") {
        $lineFound = $true
        if ($_ -notmatch [regex]::Escape($sid)) {
            "$_,*$sid"
        } else {
            $_
        }
    } else {
        $_
    }
}
if (-not $lineFound) {
    $newContent += "SeDenyInteractiveLogonRight = *$sid"
}
$newContent | Set-Content $tempCfg

secedit /configure /db secedit.sdb /cfg $tempCfg /quiet
Remove-Item $tempCfg -Force
Write-Host "Interaktiva ielogosanas liegta."

$regPath = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon\SpecialAccounts\UserList"
if (-not (Test-Path $regPath)) {
    New-Item -Path $regPath -Force | Out-Null
}
New-ItemProperty -Path $regPath -Name $AccountName -Value 0 -PropertyType DWord -Force | Out-Null
Write-Host "Konts apslepts no logon ekrana."

# ---------- 3. CLIENT-INSTALL SCHEDULED TASK (NO NAS, LABUPDATE) ----------

Write-Step "3. Instalesanas uzdevums (client-install.ps1 no NAS)"

if (-not (Test-Path $LocalScriptDir)) {
    New-Item -ItemType Directory -Path $LocalScriptDir -Force | Out-Null
}

$quotedRemoteInstall = Get-QuotedArgLocal -Value $remoteInstallScript
$quotedNasRootForArg = Get-QuotedArgLocal -Value $NasRoot
$installArgString = "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File " + $quotedRemoteInstall + " -NasRoot " + $quotedNasRootForArg

$installActionParams = @{
    Execute  = "powershell.exe"
    Argument = $installArgString
}
$installAction = New-ScheduledTaskAction @installActionParams

$installHelperParams = @{
    Once               = $true
    At                 = "00:00"
    RepetitionInterval = New-TimeSpan -Minutes $InstallIntervalMinutes
    RepetitionDuration = New-TimeSpan -Hours 23 -Minutes 59
}
$installHelperTrigger = New-ScheduledTaskTrigger @installHelperParams

$installTrigger = New-ScheduledTaskTrigger -Daily -At "00:00"
$installTrigger.Repetition = $installHelperTrigger.Repetition

$installSettingsParams = @{
    StartWhenAvailable         = $true
    DontStopOnIdleEnd          = $true
    AllowStartIfOnBatteries    = $true
    DontStopIfGoingOnBatteries = $true
    # 4 stundas (nevis 1): PIRMAJA reize uz nekad neatjauninata datora Windows atjauninajumu
    # ir daudz un cikls var ilgt ilgak par stundu. Ja uzdevumu nokauj uz puscela, cikls
    # netiek pabeigts, izslegsana netiek ieplanota un nakamais meginajums ir tikai nakamaja diena.
    ExecutionTimeLimit         = (New-TimeSpan -Hours 4)
    RestartCount               = 3
    RestartInterval            = (New-TimeSpan -Minutes 10)
}
$installSettings = New-ScheduledTaskSettingsSet @installSettingsParams

Unregister-ScheduledTask -TaskName $InstallTaskName -Confirm:$false -ErrorAction SilentlyContinue

$installRegParams = @{
    TaskName    = $InstallTaskName
    Action      = $installAction
    Trigger     = $installTrigger
    Settings    = $installSettings
    User        = $AccountName
    Password    = $AccountPassword
    RunLevel    = "Highest"
    Description = "Parbauda un instale programmatiiras atjauninasanas no NAS Cache (client-install.ps1)."
}
try {
    Register-ScheduledTask @installRegParams -ErrorAction Stop | Out-Null
    Write-Host "Uzdevums '$InstallTaskName' registrets (ik $InstallIntervalMinutes min, visu diennakti, fona)."
} catch {
    Write-Host "KLUDA: neizdevas registret uzdevumu '$InstallTaskName': $_" -ForegroundColor Red
    exit 1
}

# ---------- 4. UPDATE-NOTICE LOKALA KOPIJA + SCHEDULED TASK ----------

Write-Step "4. Bridinajuma uzdevums (update-notice.ps1 lokali)"

$localNoticeScript = Join-Path $LocalScriptDir "update-notice.ps1"
Copy-Item -Path $remoteNoticeScript -Destination $localNoticeScript -Force
Write-Host "update-notice.ps1 iekopets lokali: $localNoticeScript"

$noticeStartDt = [datetime]::ParseExact($NoticeStartTime, "HH:mm", $null)
$noticeEndDt   = [datetime]::ParseExact($NoticeEndTime, "HH:mm", $null)
$noticeDuration = $noticeEndDt - $noticeStartDt

$quotedLocalNotice = Get-QuotedArgLocal -Value $localNoticeScript
$noticeArgString = "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File " + $quotedLocalNotice + " -NasRoot " + $quotedNasRootForArg

# "-WindowStyle Hidden" pats par sevi dazkart NEpilniba noversh isslaicigu
# loga uzplaiksnijumu, ipasi biezi palaistam uzdevumam (sis strada ik
# 5 min). Drosakais veids - izmantot VBS "palaisanas apvalku", kas
# izsauc PowerShell ar WScript.Shell.Run stilu 0 (NEKAD nerada logu).
$vbsLauncherPath = Join-Path $LocalScriptDir "notice-launcher.vbs"
$vbsCommandLine = "powershell.exe " + $noticeArgString
$vbsCommandLineEscaped = $vbsCommandLine.Replace('"', '""')
$newline = [string]([char]13) + [string]([char]10)
$vbsContent = 'Set objShell = CreateObject("WScript.Shell")' + $newline +
              'objShell.Run "' + $vbsCommandLineEscaped + '", 0, True' + $newline
Set-Content -Path $vbsLauncherPath -Value $vbsContent -Encoding ASCII
Write-Host "notice-launcher.vbs izveidots (nodrosina logu bez uzplaiksnijuma)."

$quotedVbsPath = Get-QuotedArgLocal -Value $vbsLauncherPath
$noticeActionParams = @{
    Execute  = "wscript.exe"
    Argument = $quotedVbsPath
}
$noticeAction = New-ScheduledTaskAction @noticeActionParams

$noticeHelperParams = @{
    Once               = $true
    At                 = $NoticeStartTime
    RepetitionInterval = New-TimeSpan -Minutes $NoticeIntervalMinutes
    RepetitionDuration = $noticeDuration
}
$noticeHelperTrigger = New-ScheduledTaskTrigger @noticeHelperParams

$weekdays = @(
    [System.DayOfWeek]::Monday,
    [System.DayOfWeek]::Tuesday,
    [System.DayOfWeek]::Wednesday,
    [System.DayOfWeek]::Thursday,
    [System.DayOfWeek]::Friday
)
$noticeTrigger = New-ScheduledTaskTrigger -Weekly -DaysOfWeek $weekdays -At $NoticeStartTime
$noticeTrigger.Repetition = $noticeHelperTrigger.Repetition

$noticeSettingsParams = @{
    StartWhenAvailable         = $true
    DontStopOnIdleEnd          = $true
    AllowStartIfOnBatteries    = $true
    DontStopIfGoingOnBatteries = $true
    ExecutionTimeLimit         = (New-TimeSpan -Minutes 10)
}
$noticeSettings = New-ScheduledTaskSettingsSet @noticeSettingsParams

$noticePrincipal = New-ScheduledTaskPrincipal -GroupId "BUILTIN\Users" -RunLevel Limited

Unregister-ScheduledTask -TaskName $NoticeTaskName -Confirm:$false -ErrorAction SilentlyContinue

$noticeRegParams = @{
    TaskName    = $NoticeTaskName
    Action      = $noticeAction
    Trigger     = $noticeTrigger
    Settings    = $noticeSettings
    Principal   = $noticePrincipal
    Description = "Rada bridinajuma logu pirms planotas atjauninasanas (darba laika, ik $NoticeIntervalMinutes min)."
}
try {
    Register-ScheduledTask @noticeRegParams -ErrorAction Stop | Out-Null
    Write-Host "Uzdevums '$NoticeTaskName' registrets (Pr-Pk, $NoticeStartTime-$NoticeEndTime, ik $NoticeIntervalMinutes min)."
} catch {
    Write-Host "KLUDA: neizdevas registret uzdevumu '$NoticeTaskName': $_" -ForegroundColor Red
    exit 1
}

# ---------- 5. DELIVERY OPTIMIZATION (LAN KOPLIETOSANA) ----------

Write-Step "5. Delivery Optimization (lokala tikla koplietosana)"

try {
    $doRegPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DeliveryOptimization"
    if (-not (Test-Path $doRegPath)) {
        New-Item -Path $doRegPath -Force | Out-Null
    }
    # DODownloadMode = 1 nozime "LAN" - datori sanjema atjauninajumus
    # cits no cita tajaa pasha lokalajaa tikla, nevis katrs atsevisgi
    # no Microsoft serveriem. Samazina interneta slodzi.
    New-ItemProperty -Path $doRegPath -Name "DODownloadMode" -Value 1 -PropertyType DWord -Force | Out-Null
    Write-Host "Delivery Optimization iestatits uz LAN rezimu (datori kopliets atjauninajumus savaa starpaa)."
} catch {
    Write-Host "BRIDINAJUMS: neizdevas iestatit Delivery Optimization: $_" -ForegroundColor Yellow
}

# ---------- 6. MIEGA (AIZMIGSANAS) IZSLEGSANA ----------

Write-Step "6. Energijas iestatijumi (dators neaizmieg, monitors izslegsies pec $MonitorTimeoutMinutes min)"

if ($SkipPowerSettings) {
    Write-Host "Izlaists (-SkipPowerSettings): energijas iestatijumi netiek mainiti."
} else {
    # Aizmidzis dators NEPALAIZ Scheduled Task, tapec UpdateTime logs
    # (+20 min) tiek nokavets. Mainam TIKAI barosanu no tikla (-ac);
    # darbs no akumulatora (portativajiem) netiek aiztikts.
    # Monitora izslegsanas taimeris datoru neaizmidzina.
    try {
        & powercfg.exe /change standby-timeout-ac 0
        & powercfg.exe /change hibernate-timeout-ac 0
        & powercfg.exe /change monitor-timeout-ac $MonitorTimeoutMinutes

        $sleepMinutes = Get-AcTimeoutMinutes -SubGroup "SUB_SLEEP" -Setting "STANDBYIDLE"
        $monitorMinutes = Get-AcTimeoutMinutes -SubGroup "SUB_VIDEO" -Setting "VIDEOIDLE"

        if ($null -ne $sleepMinutes) {
            Write-Host "Miega taimeris (strava): $sleepMinutes min (0 = datora neaizmieg)."
        } else {
            Write-Host "Miega taimeri iestatits, bet nolasit pec tam neizdevas (iespejams, cita sistemas valoda)." -ForegroundColor Yellow
        }
        if ($null -ne $monitorMinutes) {
            Write-Host "Monitora taimeris (strava): $monitorMinutes min."
        } else {
            Write-Host "Monitora taimeri iestatits, bet nolasit pec tam neizdevas (iespejams, cita sistemas valoda)." -ForegroundColor Yellow
        }
    } catch {
        Write-Host "BRIDINAJUMS: neizdevas iestatit energijas parametrus: $_" -ForegroundColor Yellow
    }
}

# ---------- GATAVS ----------

Write-Step "GATAVS"
Write-Host "Dators '$computerName' ir uzstadits un gatavs."
Write-Host ""
Write-Host "SVARIGI NAKAMIE SOLI:" -ForegroundColor Yellow
Write-Host "  1. Pievienojiet '$computerName' ierakstu device-schedule.csv (caur config-panel.ps1),"
Write-Host "     citadi atjauninasana NEKAD nenotiks (drosa noklusejuma uzvediba)."
Write-Host "  2. Testesanai uzreiz:"
Write-Host ("       schtasks /Run /TN " + [char]34 + $InstallTaskName + [char]34)
Write-Host ("       schtasks /Run /TN " + [char]34 + $NoticeTaskName + [char]34)
