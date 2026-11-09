<# :
@echo off
rem ============================================================
rem  win11-versijas-atjaunosana.bat  - VECAKA Windows 11 versija uz ISO
rem  versiju (piem. 23H2/24H2 uz 26300) neatbalstitiem datoriem, no ISO,
rem  saglabajot programmas un failus. Der ari Windows 10.
rem
rem  Lietosana: iekopet datora (piem. D:\Downloads), dubultklikskis
rem  (pats prasa administratora tiesibas). ISO: D:\Downloads\*Win*11*.iso
rem
rem  Dara: WinRM ieslegsana , parbaudes , ISO pievienosana un versijas
rem  salidzinasana , apiesana , setup.exe /product server /auto upgrade
rem  (dators pats restartesies, ~45-90 min).
rem  Zurnals: C:\Win11-upgrade-DATORS.log
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

$Host.UI.RawUI.WindowTitle = "Win11 versijas atjaunosana - $env:COMPUTERNAME"
L "=== Windows 11 versijas atjaunosana no ISO: $env:COMPUTERNAME ===" "Cyan"

# ---------- 1. Operetajsistema ----------
$os = Get-CimInstance Win32_OperatingSystem
$cv = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion'
$curBuild = [int]$cv.CurrentBuild
L "OS: $($os.Caption) $($cv.DisplayVersion) (build $curBuild.$($cv.UBR))"
if ($os.Caption -notmatch 'Windows 1[01]') { Stop-Here "nav Windows 10/11." }

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
L ("TPM: " + $(if ($tpm) { [string]$tpm.SpecVersion } else { "nav atrasts" }))

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

# ---------- 5b. ISO versija pret pasreizejo ----------
$wim = @("$($letter):\sources\install.wim", "$($letter):\sources\install.esd") | Where-Object { Test-Path $_ } | Select-Object -First 1
$isoBuild = 0
if ($wim) {
    try { $isoBuild = [int](((Get-WindowsImage -ImagePath $wim -Index 1 -ErrorAction Stop).Version -split '\.')[2]) } catch { }
}
if (-not $isoBuild -and $iso.Name -match '_(\d{5})[_.]') { $isoBuild = [int]$Matches[1] }
L "ISO Windows build: $(if ($isoBuild) { $isoBuild } else { 'nav nosakams' })   Pasreizejais: $curBuild"
if ($isoBuild -and $curBuild -ge $isoBuild) { Stop-Here "dators jau ir build $curBuild (ISO: $isoBuild) - atjaunot nav vajadzigs." }

# ---------- 6. Apiesana neatbalstitai aparaturai ----------
# MoSetup atslega (palidz Win10 uz 11) + "/product server" (setup izlaiz
# aparaturas parbaudi; vajadzigs Win11 uz jaunaku Win11 neatbalstita datora).
New-Item 'HKLM:\SYSTEM\Setup\MoSetup' -Force | Out-Null
New-ItemProperty 'HKLM:\SYSTEM\Setup\MoSetup' -Name AllowUpgradesWithUnsupportedTPMOrCPU -Value 1 -PropertyType DWord -Force | Out-Null
L "MoSetup AllowUpgradesWithUnsupportedTPMOrCPU = 1"

# ---------- 7. Atjaunosana ----------
$setupArgs = @('/product', 'server', '/auto', 'upgrade', '/eula', 'accept', '/dynamicupdate', 'disable', '/compat', 'IgnoreWarning', '/telemetry', 'disable')
L "Palaizu: $setup $($setupArgs -join ' ')" "Cyan"
L "Windows instalacija SAKTA. Aizver programmas - dators pats restartesies vairakas reizes (~45-90 min)." "Green"
$p = Start-Process -FilePath $setup -ArgumentList $setupArgs -Wait -PassThru
# Ja viss labi, dators restartejas pirms setup beidzas. Ja setup beidzas pats - kluda.
$code = '0x{0:X8}' -f $p.ExitCode
if ($p.ExitCode -ne 0) {
    L "Setup beidzas ar kodu $code (piem. 0xC1900208 = nesaderiba, 0xC1900107 = jarestarte)." "Red"
    L "Zurnali: C:\`$WINDOWS.~BT\Sources\Panther\ (setuperr.log, setupact.log)." "Red"
    Read-Host "Nospied Enter, lai aizvertu"
    exit 1
}
L "Setup beidzas ar kodu $code - dators drizuma restartesies."
Start-Sleep -Seconds 15
