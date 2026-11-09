<# :
@echo off
rem ============================================================
rem  win11-upgrade.bat  - universals Win10 uz Win11 jauninatajs
rem  neatbalstitiem datoriem (no ISO, saglabajot programmas un failus).
rem
rem  Lietosana: iekopet datora (piem. D:\Downloads), dubultklikskis
rem  (pats prasa administratora tiesibas). ISO: D:\Downloads\*Win*11*.iso
rem
rem  Dara: WinRM ieslegsana , parbaudes , MoSetup apiesana  , 
rem  ISO pievienosana , setup.exe /auto upgrade (dators pats
rem  restartesies, ~45-90 min). Zurnals: C:\Win11-upgrade-DATORS.log
rem
rem  Fails ir "bat + PowerShell" kombinacija: zemak esosa dala ir
rem  PowerShell kods, ko sis bat palaiz.
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

# ======================= PowerShell dala =======================

$IsoFolder   = "D:\Downloads"
$MinFreeGB   = 30
$Log         = "C:\Win11-upgrade-$env:COMPUTERNAME.log"

function L {
    param([string]$Msg, [string]$Color = "Gray")
    $line = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')  $Msg"
    Write-Host $line -ForegroundColor $Color
    try { Add-Content -Path $Log -Value $line } catch { }
}
function Stop-Here {
    param([string]$Msg)
    L "KLUDA: $Msg" "Red"
    L "Jauninasana NETIKA sakta." "Red"
    Read-Host "Nospied Enter, lai aizvertu"
    exit 1
}

$Host.UI.RawUI.WindowTitle = "Win11 jauninasana - $env:COMPUTERNAME"
L "=== Win10 -> Win11 jauninasana: $env:COMPUTERNAME ===" "Cyan"

# ---------- 1. Operetajsistema ----------
$os = Get-CimInstance Win32_OperatingSystem
$cv = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion'
L "OS: $($os.Caption) $($cv.DisplayVersion) ($($os.Version))"
if ($os.Caption -notmatch 'Windows 10') { Stop-Here "sis nav Windows 10 (varbut jau Windows 11)." }

# ---------- 2. WinRM ----------
L "WinRM ieslegsana..." "Cyan"
try {
    Enable-PSRemoting -Force -SkipNetworkProfileCheck -ErrorAction Stop | Out-Null
    Set-Service WinRM -StartupType Automatic
    L "WinRM: $((Get-Service WinRM).Status), Automatic" "Green"
} catch {
    L "BRIDINAJUMS: WinRM neizdevas ieslegt ($($_.Exception.Message)) - turpinu ar jauninasanu." "Yellow"
}

# ---------- 3. Parbaudes ----------
L "Parbaudes..." "Cyan"
$cpu  = (Get-CimInstance Win32_Processor | Select-Object -First 1).Name
$ram  = [math]::Round((Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory / 1GB, 1)
$free = [math]::Round((Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='C:'").FreeSpace / 1GB, 1)
L "CPU: $cpu"
L "RAM: $ram GB   C: brivs: $free GB"
if ($free -lt $MinFreeGB) { Stop-Here "C: diska brivs tikai $free GB (vajag vismaz $MinFreeGB GB)." }

$pending = (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending') -or
           (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired')
if ($pending) { Stop-Here "dators gaida restartu pec atjauninajumiem. Restarte un palaid so failu velreiz." }

$lang = (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Nls\Language').InstallLanguage
L "Windows instalacijas valoda: $lang (0409 = English US)"
if ($lang -ne '0409') { Stop-Here "Windows valoda nav English (US), bet ISO ir en-us - programmas un faili netiktu saglabati. Vajag ISO saja valoda." }

$tpm = Get-CimInstance -Namespace root/cimv2/Security/MicrosoftTpm -ClassName Win32_Tpm -ErrorAction SilentlyContinue
$tpmVer = if ($tpm) { [string]$tpm.SpecVersion } else { "" }
$tpmOk = $tpmVer -match '^\s*(1\.2|2\.0)'
L ("TPM: " + $(if ($tpmVer) { $tpmVer } else { "nav atrasts" }))

try {
    $bl = Get-BitLockerVolume -MountPoint C: -ErrorAction Stop
    if ($bl.ProtectionStatus -eq 'On') {
        Suspend-BitLocker -MountPoint C: -RebootCount 3 | Out-Null
        L "BitLocker C: aizsardziba APTURETA uz 3 restartiem (atjaunosies pati)." "Yellow"
    } else { L "BitLocker C: izslegts." }
} catch { L "BitLocker: nav pieejams (ok)." }

$usb = @(Get-Disk | Where-Object { $_.BusType -eq 'USB' })
if ($usb.Count -gt 0) {
    foreach ($u in $usb) { L "USB disks pievienots: $($u.FriendlyName) ($([math]::Round($u.Size/1GB)) GB)" "Yellow" }
    Read-Host "Ieteicams atvienot arejos USB diskus. Atvieno (vai atstaj) un nospied Enter, lai turpinatu"
}

# ---------- 4. Apiesana neatbalstitai aparaturai ----------
New-Item 'HKLM:\SYSTEM\Setup\MoSetup' -Force | Out-Null
New-ItemProperty 'HKLM:\SYSTEM\Setup\MoSetup' -Name AllowUpgradesWithUnsupportedTPMOrCPU -Value 1 -PropertyType DWord -Force | Out-Null
L "MoSetup AllowUpgradesWithUnsupportedTPMOrCPU = 1"
# MoSetup apiet CPU un TPM 2.0 prasibu, bet NE: TPM vispar nav / RAM < 4 GB.
# Tad izmantojam "/product server" (setup izlaiz aparaturas parbaudi).
$useServerTrick = (-not $tpmOk) -or ($ram -lt 3.8)
if ($useServerTrick) { L "Nav TPM 1.2/2.0 vai RAM < 4 GB - izmantoju '/product server' apiesanu." "Yellow" }

# ---------- 5. ISO ----------
$iso = Get-ChildItem -Path $IsoFolder -Filter *.iso -ErrorAction SilentlyContinue |
       Where-Object { $_.Name -match 'Win.*11' } | Sort-Object LastWriteTime -Descending | Select-Object -First 1
if (-not $iso) { Stop-Here "$IsoFolder nav atrasts Windows 11 ISO (*Win*11*.iso)." }
L "ISO: $($iso.FullName)"

$img = Get-DiskImage -ImagePath $iso.FullName
if (-not $img.Attached) { $img = Mount-DiskImage -ImagePath $iso.FullName -PassThru }
Start-Sleep -Seconds 2
$letter = ($img | Get-Volume).DriveLetter
if (-not $letter) { Stop-Here "ISO pievienots, bet nav diska burta." }
$setup = "$($letter):\setup.exe"
if (-not (Test-Path $setup)) { Stop-Here "$setup nav atrasts." }
L "ISO pievienots ka $($letter):"

# ---------- 6. Jauninasana ----------
$setupArgs = @('/auto', 'upgrade', '/eula', 'accept', '/dynamicupdate', 'disable', '/compat', 'IgnoreWarning', '/telemetry', 'disable')
if ($useServerTrick) { $setupArgs = @('/product', 'server') + $setupArgs }
L "Palaizu: $setup $($setupArgs -join ' ')" "Cyan"
Start-Process -FilePath $setup -ArgumentList $setupArgs
L "Windows 11 instalacija SAKTA. Aizver programmas - dators pats restartesies vairakas reizes (~45-90 min)." "Green"
L "Ja kaut kas neizdodas: zurnali C:\`$WINDOWS.~BT\Sources\Panther\ (setupact.log, setuperr.log)."
Start-Sleep -Seconds 15
