<# :
@echo off
rem ============================================================
rem  sagatavot-datoru.bat  - universala datora sagatavosana PIUAC
rem  sistemai filiale (ka Dobele). Dubultklikskis, pats prasa
rem  administratora tiesibas. Var palaist atkartoti.
rem
rem  Dara:
rem   1. WinRM ieslegsana
rem   2. Administrator konts ieslegts, pec izveles flotes parole
rem   3. Energija: dators neaizmieg (stravaa), monitors 30 min,
rem      hibernacija un Fast Startup izslegti
rem   4. Wake-on-LAN tikla karte (ari bez energijas taupisanas karte)
rem   5. Pieslegsana hub (labupdate) un setup-client.ps1 no hub:
rem      labupdate konts, LabAppUpdate un Update-Notice-Check
rem      uzdevumi, Delivery Optimization LAN
rem   6. Kopsavilkums: vards, IP, MAC, administratori
rem  Zurnals: C:\PIUAC-sagatavosana-DATORS.log
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

$Hub      = "AUCEUPDATE-PC"
$NasRoot  = "\\$Hub\Updates"
$MonitorMinutes = 30
$Log      = "C:\PIUAC-sagatavosana-$env:COMPUTERNAME.log"

function L {
    param([string]$Msg, [string]$Color = "Gray")
    $line = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')  $Msg"
    Write-Host $line -ForegroundColor $Color
    try { Add-Content -Path $Log -Value $line } catch { }
}
function Step { param([string]$T) Write-Host ""; L "=== $T ===" "Cyan" }

$Host.UI.RawUI.WindowTitle = "PIUAC sagatavosana - $env:COMPUTERNAME"
L "=== PIUAC sistemas sagatavosana: $env:COMPUTERNAME ===" "Cyan"
$warn = @()

# ---------- 1. WinRM ----------
Step "1. WinRM"
try {
    Enable-PSRemoting -Force -SkipNetworkProfileCheck -ErrorAction Stop | Out-Null
    Set-Service WinRM -StartupType Automatic
    L "WinRM: $((Get-Service WinRM).Status), Automatic" "Green"
} catch { L "BRIDINAJUMS: WinRM neizdevas ($($_.Exception.Message))" "Yellow"; $warn += "WinRM" }

# ---------- 2. Administrator ----------
Step "2. Administrator konts"
$adm = Get-LocalUser | Where-Object { $_.SID -like 'S-1-5-21-*-500' }
if ($adm) {
    if (-not $adm.Enabled) { Enable-LocalUser -SID $adm.SID; L "Konts '$($adm.Name)' ieslegts." "Green" }
    else { L "Konts '$($adm.Name)' jau ieslegts." }
    $ans = Read-Host "Mainit '$($adm.Name)' paroli uz flotes paroli? (j/n)"
    if ($ans -match '^[jJyY]') {
        & net.exe user $adm.Name *
        if ($LASTEXITCODE -eq 0) { L "Parole nomainita." "Green" } else { L "Parole NETIKA nomainita." "Yellow"; $warn += "Administrator parole" }
    } else { L "Parole netika mainita." }
} else { L "BRIDINAJUMS: iebuveto Administrator kontu neatradu." "Yellow"; $warn += "Administrator" }

# ---------- 3. Energija ----------
Step "3. Energijas iestatijumi"
& powercfg.exe /change standby-timeout-ac 0
& powercfg.exe /change hibernate-timeout-ac 0
& powercfg.exe /change monitor-timeout-ac $MonitorMinutes
& powercfg.exe /hibernate off
New-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power' -Name HiberbootEnabled -Value 0 -PropertyType DWord -Force | Out-Null
L "Stravaa: neaizmieg, monitors $MonitorMinutes min; hibernacija un Fast Startup izslegti." "Green"

# ---------- 4. Wake-on-LAN ----------
Step "4. Wake-on-LAN"
$nics = @(Get-NetAdapter -Physical -ErrorAction SilentlyContinue | Where-Object { $_.MediaType -eq '802.3' -or $_.Name -match 'Ethernet' })
foreach ($n in $nics) {
    try {
        Set-NetAdapterPowerManagement -Name $n.Name -WakeOnMagicPacket Enabled -ErrorAction Stop
        L "WoL ieslegts: $($n.Name) ($($n.MacAddress))" "Green"
    } catch { L "WoL neizdevas: $($n.Name) - $($_.Exception.Message)" "Yellow"; $warn += "WoL $($n.Name)" }
    try { & powercfg.exe /deviceenablewake "$($n.InterfaceDescription)" 2>$null | Out-Null } catch { }
    # Realtek u.c.: energijas taupisana tikla karte trauce WoL pec izslegsanas (parbaudits Auce 2026-11-09)
    try {
        Get-NetAdapterAdvancedProperty -Name $n.Name -ErrorAction Stop |
            Where-Object { $_.DisplayName -in 'Energy-Efficient Ethernet','Green Ethernet','Power Saving Mode' -and $_.DisplayValue -ne 'Disabled' } |
            ForEach-Object { Set-NetAdapterAdvancedProperty -Name $n.Name -DisplayName $_.DisplayName -DisplayValue 'Disabled' -NoRestart -ErrorAction Stop; L "  $($_.DisplayName): Disabled" }
        # Intel (piem. I217-V): "Energy Efficient Ethernet" = Off
        Get-NetAdapterAdvancedProperty -Name $n.Name -ErrorAction Stop |
            Where-Object { $_.DisplayName -eq 'Energy Efficient Ethernet' -and $_.DisplayValue -ne 'Off' } |
            ForEach-Object { Set-NetAdapterAdvancedProperty -Name $n.Name -DisplayName $_.DisplayName -DisplayValue 'Off' -NoRestart -ErrorAction Stop; L "  $($_.DisplayName): Off" }
        Get-NetAdapterAdvancedProperty -Name $n.Name -ErrorAction Stop |
            Where-Object { $_.DisplayName -in 'Shutdown Wake-On-Lan','Wake on Magic Packet' -and $_.DisplayValue -ne 'Enabled' } |
            ForEach-Object { Set-NetAdapterAdvancedProperty -Name $n.Name -DisplayName $_.DisplayName -DisplayValue 'Enabled' -NoRestart -ErrorAction Stop; L "  $($_.DisplayName): Enabled" }
    } catch { L "  Tikla kartes papildu iestatijumi: $($_.Exception.Message)" "Yellow" }
}
if ($nics.Count -eq 0) { L "Vadu tikla karte nav atrasta (WoL izlaists)." "Yellow"; $warn += "nav vadu tikla kartes" }

# ---------- 5. Hub un setup-client ----------
Step "5. Pieslegsana hub ($Hub) un setup-client.ps1"
$t = Test-NetConnection $Hub -Port 445 -WarningAction SilentlyContinue
if (-not $t.TcpTestSucceeded) {
    L "Hub $Hub nav sasniedzams (445). Solus 1-4 izdarits; palaid so failu velreiz, kad hub ir pieejams." "Red"
    $warn += "hub nav pieejams - setup-client NAV palaists"
} else {
    L "Hub sasniedzams: $($t.RemoteAddress)" "Green"
    $sec = Read-Host "Filiales labupdate parole" -AsSecureString
    $b = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($sec)
    try { $pw = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($b) } finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($b) }
    & net.exe use "\\$Hub" /delete /y 2>$null | Out-Null
    & net.exe use $NasRoot "/user:labupdate" $pw 2>&1 | Out-Null
    $sc = Join-Path $NasRoot "Scripts\setup-client.ps1"
    if (-not (Test-Path $sc)) {
        L "KLUDA: $sc nav pieejams (parole? hub publicesana?)." "Red"; $warn += "setup-client NAV palaists"
    } else {
        & $sc -AccountPassword $pw -NasRoot $NasRoot -MonitorTimeoutMinutes $MonitorMinutes
        if (Get-ScheduledTask -TaskName LabAppUpdate -ErrorAction SilentlyContinue) { L "LabAppUpdate uzdevums ir." "Green" }
        else { L "KLUDA: LabAppUpdate uzdevums NAV izveidots." "Red"; $warn += "LabAppUpdate" }
    }
    $pw = $null
}

# ---------- 6. Kopsavilkums ----------
Step "6. Kopsavilkums"
$ip  = (Get-NetIPAddress -AddressFamily IPv4 | Where-Object { $_.IPAddress -notlike '169.254.*' -and $_.IPAddress -ne '127.0.0.1' } | Select-Object -First 1).IPAddress
$mac = ($nics | Select-Object -First 1).MacAddress
L "Dators: $env:COMPUTERNAME   IP: $ip   MAC: $mac" "Cyan"
L ("Lokalie administratori: " + ((Get-LocalGroupMember -SID 'S-1-5-32-544' | ForEach-Object { $_.Name }) -join ', '))
L ("Ieslegtie lietotaji: " + ((Get-LocalUser | Where-Object Enabled | ForEach-Object { $_.Name }) -join ', '))
if ($warn.Count -gt 0) { L ("JAPARBAUDA: " + ($warn -join '; ')) "Yellow" } else { L "Viss izdarits bez bridinajumiem." "Green" }
L "NAKAMAIS: pievienot $env:COMPUTERNAME filiales grafikam (PIUAC-ASKOLDS C:\Scripts\Filiales\Auce\Config\device-schedule.csv) un publicet." "Cyan"
Read-Host "Nospied Enter, lai aizvertu"
