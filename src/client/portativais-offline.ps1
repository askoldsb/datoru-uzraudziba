<#
============================================================
 portativais-offline.ps1
 Portativajiem, kas reti ir Dobeles tikla (piem. DELL-MONTA).

 Problema: LabAppUpdate palaiz client-install.ps1 TIESI NO NAS,
 tapec arpus biroja tikla programmas netiek atjauninatas.

 Risinajums (papildina, nevis aizstaj LabAppUpdate):
   LabOfflineUpdate  (SYSTEM)    - ja dators NAV biroja tikla un ir internets:
                                   reizi ~20 h klusi atjaunina programmas ar winget
                                   (tikai tas, kas jau uzstaditas; saraksts zemak),
                                   zurnals lokali C:\ProgramData\LabUpdates\Offline\Logs
   LabOfflineReport  (labupdate) - ik 30 min: ja dators IR biroja tikla, nosuta
                                   uzkratos zurnalus uz NAS Logs\Clients\<PC>-offline-*.log
 Biroja tikla programmas ka parasti atjaunina LabAppUpdate (client-install.ps1).
 Windows Update un Microsoft 365 atjauninas pasi jebkura tikla (Windows iebuveta funkcija).

 Uzstadisana - uz portativa, admin PowerShell:
   powershell -ExecutionPolicy Bypass -File .\portativais-offline.ps1 -Uzstadit
   (prasa labupdate paroli - ta pati, kas NAS / setup-client.ps1)
 Nonemsana:
   powershell -ExecutionPolicy Bypass -File "C:\Program Files\LabUpdates\portativais-offline.ps1" -Nonemt
============================================================
#>
param(
    [switch]$Uzstadit,
    [switch]$Nonemt,
    [switch]$Atjaunot,      # iekseji - LabOfflineUpdate uzdevums
    [switch]$Atskaite,      # iekseji - LabOfflineReport uzdevums
    [string]$NasIp   = '192.168.3.31',
    [string]$NasRoot = '\\192.168.3.31\Updates'
)

# --- Programmas (winget ID). Atjaunina TIKAI, ja jau uzstaditas. TeamViewer apzinati nav. ---
$Programmas = @(
    'Mozilla.Firefox'
    'Google.Chrome'
    'Zoom.Zoom'
    'VideoLAN.VLC'
    'eParaksts.eParakstitajs'
    'eParaksts.eParakstsTokenSigning'
    'RARLab.WinRAR'
    'Adobe.Acrobat.Reader.64-bit'
    'Notepad++.Notepad++'
    '7zip.7zip'
    'Microsoft.VCRedist.2015+.x64'
    'Microsoft.VCRedist.2015+.x86'
)

$InstallDir  = Join-Path $env:ProgramFiles 'LabUpdates'
$InstallPath = Join-Path $InstallDir 'portativais-offline.ps1'
$BaseDir     = 'C:\ProgramData\LabUpdates\Offline'
$LogDir      = Join-Path $BaseDir 'Logs'
$SentDir     = Join-Path $LogDir 'Sent'
$StateFile   = Join-Path $BaseDir 'last-success.txt'
$UpdTask     = 'LabOfflineUpdate'
$RepTask     = 'LabOfflineReport'
$MinHours    = 20

function Test-Birojs {
    # Biroja tikls = NAS SMB ports atbild 1,5 s laika
    $c = New-Object System.Net.Sockets.TcpClient
    try {
        $ar = $c.BeginConnect($NasIp, 445, $null, $null)
        if ($ar.AsyncWaitHandle.WaitOne(1500)) { $c.EndConnect($ar); return $true }
        return $false
    } catch { return $false } finally { $c.Close() }
}

function Test-Internets {
    try {
        $r = [Net.WebRequest]::Create('http://www.msftconnecttest.com/connecttest.txt')
        $r.Timeout = 5000
        $resp = $r.GetResponse(); $resp.Close(); return $true
    } catch { return $false }
}

function Test-Merits {
    # True, ja savienojums ir ar maksu (mobilais internets / "metered") - tad neko nelejupieladejam
    try {
        $null = [Windows.Networking.Connectivity.NetworkInformation, Windows.Networking.Connectivity, ContentType = WindowsRuntime]
        $p = [Windows.Networking.Connectivity.NetworkInformation]::GetInternetConnectionProfile()
        if (-not $p) { return $false }
        $cost = $p.GetConnectionCost()
        return ($cost.NetworkCostType -ne 'Unrestricted' -and $cost.NetworkCostType -ne 'Unknown') -or $cost.Roaming
    } catch { return $false }
}

function Find-WingetSystem {
    $d = Get-ChildItem "$env:ProgramFiles\WindowsApps" -Directory -Filter 'Microsoft.DesktopAppInstaller_*_x64__8wekyb3d8bbwe' -ErrorAction SilentlyContinue |
         Sort-Object { try { [version](($_.Name -split '_')[1]) } catch { [version]'0.0' } } -Descending |
         Select-Object -First 1
    if ($d) {
        $exe = Join-Path $d.FullName 'winget.exe'
        if (Test-Path $exe) { return $exe }
    }
    $c = Get-Command winget.exe -ErrorAction SilentlyContinue
    if ($c) { return $c.Source }
    return $null
}

# =====================================================================
if ($Atjaunot) {
    New-Item -ItemType Directory -Path $LogDir -Force | Out-Null
    if (Test-Birojs) { exit 0 }                       # biroja - to dara LabAppUpdate
    if (Test-Path $StateFile) {
        try {
            $last = [datetime]::ParseExact((Get-Content $StateFile -Raw).Trim(), 'yyyy-MM-dd HH:mm:ss', $null)
            if (((Get-Date) - $last).TotalHours -lt $MinHours) { exit 0 }
        } catch { }
    }
    if (-not (Test-Internets)) { exit 0 }
    if (Test-Merits) { exit 0 }

    $log = Join-Path $LogDir ('{0}-offline-{1:yyyyMMdd-HHmmss}.log' -f $env:COMPUTERNAME, (Get-Date))
    function L([string]$t) { Add-Content -Path $log -Value ('{0:yyyy-MM-dd HH:mm:ss}  {1}' -f (Get-Date), $t) -Encoding UTF8 }

    L "=== Atjauninasana arpus biroja tikla: $env:COMPUTERNAME ==="
    $wg = Find-WingetSystem
    if (-not $wg) { L 'KLUDA: winget nav atrasts'; exit 1 }
    L "winget: $wg"
    & $wg source update --name winget --disable-interactivity 2>&1 | Out-Null

    $kludas = 0
    foreach ($id in $Programmas) {
        $out = & $wg upgrade --id $id --exact --source winget --silent --accept-package-agreements `
                  --accept-source-agreements --disable-interactivity 2>&1 | Out-String
        $code = $LASTEXITCODE
        switch ($code) {
            0            { L "$id : atjauninats" }
            -1978335189  { L "$id : jau aktuals" }                 # 0x8A15002B nav pieejama atjauninajuma
            -1978335212  { }                                        # 0x8A150014 nav uzstadits - klusejam
            -1978334967  { L "$id : atjauninats (vajag restartu)" } # 0x8A150109
            default      {
                $kludas++
                $txt = ($out -split "`r?`n" | Where-Object { $_.Trim() } | Select-Object -Last 2) -join ' / '
                L "$id : KLUDA (kods $code) $txt"
            }
        }
    }
    L "=== Pabeigts, kludas: $kludas ==="
    Set-Content -Path $StateFile -Value (Get-Date -Format 'yyyy-MM-dd HH:mm:ss') -Encoding ASCII
    exit 0
}

# =====================================================================
if ($Atskaite) {
    if (-not (Test-Path $LogDir)) { exit 0 }
    $faili = @(Get-ChildItem $LogDir -Filter '*.log' -File -ErrorAction SilentlyContinue)
    if ($faili.Count -eq 0) { exit 0 }
    if (-not (Test-Birojs)) { exit 0 }
    $dest = Join-Path $NasRoot 'Logs\Clients'
    if (-not (Test-Path $dest)) { exit 0 }
    New-Item -ItemType Directory -Path $SentDir -Force | Out-Null
    foreach ($f in $faili) {
        try {
            Copy-Item $f.FullName (Join-Path $dest $f.Name) -Force -ErrorAction Stop
            Move-Item $f.FullName (Join-Path $SentDir $f.Name) -Force
        } catch { }
    }
    Get-ChildItem $SentDir -File -ErrorAction SilentlyContinue |
        Where-Object LastWriteTime -lt (Get-Date).AddDays(-60) | Remove-Item -Force -ErrorAction SilentlyContinue
    exit 0
}

# =====================================================================
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) { Write-Host 'KLUDA: palaidiet ka administrators.' -ForegroundColor Red; exit 1 }

if ($Nonemt) {
    Unregister-ScheduledTask -TaskName $UpdTask -Confirm:$false -ErrorAction SilentlyContinue
    Unregister-ScheduledTask -TaskName $RepTask -Confirm:$false -ErrorAction SilentlyContinue
    Remove-Item $InstallPath -Force -ErrorAction SilentlyContinue
    Write-Host 'Uzdevumi nonemti, skripts izdzests. Zurnali palikusi: ' $BaseDir
    exit 0
}

if (-not $Uzstadit) {
    Write-Host 'Lietosana: -Uzstadit | -Nonemt (skat. apraksts faila sakuma)'; exit 0
}

Write-Host "=== Uzstadu portativa offline atjauninasanu: $env:COMPUTERNAME ===" -ForegroundColor Cyan

if (-not (Get-LocalUser -Name labupdate -ErrorAction SilentlyContinue)) {
    Write-Host 'KLUDA: labupdate konta nav - vispirms pievienojiet datoru sistemai (remote-setup-client.ps1).' -ForegroundColor Red
    exit 1
}

# 1. Skripts uz Program Files (parastam lietotajam tikai lasit)
New-Item -ItemType Directory -Path $InstallDir -Force | Out-Null
if ($PSCommandPath -ne $InstallPath) { Copy-Item $PSCommandPath $InstallPath -Force }
New-Item -ItemType Directory -Path $LogDir -Force | Out-Null
Write-Host "1. Skripts: $InstallPath"

# 2. winget pieejams SYSTEM kontam?
$wg = Find-WingetSystem
if ($wg) { Write-Host "2. winget: $wg" }
else { Write-Host '2. BRIDINAJUMS: winget nav atrasts - atjauniniet App Installer (Microsoft Store)' -ForegroundColor Yellow }

$arg = '-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File "' + $InstallPath + '"'

# 3. LabOfflineUpdate - SYSTEM, ik 2 h + pec starta (skripts pats ierobezo uz reizi ~20 h)
$a1 = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument ($arg + ' -Atjaunot')
$rep2h = (New-ScheduledTaskTrigger -Once -At '00:00' -RepetitionInterval (New-TimeSpan -Hours 2) -RepetitionDuration (New-TimeSpan -Hours 23 -Minutes 59)).Repetition
$t1a = New-ScheduledTaskTrigger -Daily -At '00:00'; $t1a.Repetition = $rep2h
$t1b = New-ScheduledTaskTrigger -AtStartup; $t1b.Delay = 'PT15M'
$s1 = New-ScheduledTaskSettingsSet -StartWhenAvailable -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries `
        -RunOnlyIfNetworkAvailable -ExecutionTimeLimit (New-TimeSpan -Hours 2) -MultipleInstances IgnoreNew
$p1 = New-ScheduledTaskPrincipal -UserId 'SYSTEM' -LogonType ServiceAccount -RunLevel Highest
Unregister-ScheduledTask -TaskName $UpdTask -Confirm:$false -ErrorAction SilentlyContinue
Register-ScheduledTask -TaskName $UpdTask -Action $a1 -Trigger $t1a, $t1b -Settings $s1 -Principal $p1 `
    -Description 'Portativais arpus biroja tikla: klusa programmu atjauninasana ar winget (portativais-offline.ps1).' | Out-Null
Write-Host "3. Uzdevums $UpdTask (SYSTEM) registrets"

# 4. LabOfflineReport - labupdate, ik 30 min
$pw = Read-Host 'labupdate parole (ta pati, kas NAS)' -AsSecureString
$pwTxt = [Runtime.InteropServices.Marshal]::PtrToStringBSTR([Runtime.InteropServices.Marshal]::SecureStringToBSTR($pw))
$a2 = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument ($arg + ' -Atskaite')
$rep30 = (New-ScheduledTaskTrigger -Once -At '00:00' -RepetitionInterval (New-TimeSpan -Minutes 30) -RepetitionDuration (New-TimeSpan -Hours 23 -Minutes 59)).Repetition
$t2 = New-ScheduledTaskTrigger -Daily -At '00:00'; $t2.Repetition = $rep30
$s2 = New-ScheduledTaskSettingsSet -StartWhenAvailable -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries `
        -RunOnlyIfNetworkAvailable -ExecutionTimeLimit (New-TimeSpan -Minutes 10) -MultipleInstances IgnoreNew
Unregister-ScheduledTask -TaskName $RepTask -Confirm:$false -ErrorAction SilentlyContinue
try {
    Register-ScheduledTask -TaskName $RepTask -Action $a2 -Trigger $t2 -Settings $s2 -User 'labupdate' -Password $pwTxt `
        -RunLevel Highest -Description 'Portativais: nosuta offline atjauninasanas zurnalus uz NAS, kad dators ir biroja tikla.' -ErrorAction Stop | Out-Null
    Write-Host "4. Uzdevums $RepTask (labupdate) registrets"
} catch {
    Write-Host "4. KLUDA: $RepTask neizdevas registret (nepareiza parole?): $($_.Exception.Message)" -ForegroundColor Red
}
$pwTxt = $null

Write-Host ''
Write-Host 'GATAVS.' -ForegroundColor Green
Write-Host "Parbaude arpus biroja (piem. telefona tiklaja): Start-ScheduledTask $UpdTask; zurnals $LogDir"
