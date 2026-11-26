<#
 OpenLab-Display: vienreizeja datora sagatavosana.

 1. kartas palaisana - pieteicies ka OpenLab, admin PowerShell:
      powershell -ExecutionPolicy Bypass -File C:\Scripts\openlab-uzstadisana.ps1
    Dara:
      a) iesledz iebuveto Administrator kontu (paroli prasa sakuma)
      b) Latvijas regionalie iestatijumi (laiks, datums, klaviatura), saskarne angliski
      c) uzstada un aktive ESET Endpoint Antivirus (atslega - parametrs $EsetAtslega zemak;
         ja tukss, prasa sakuma) un parejas programmas ar winget (saraksts zemak)
    PEC UZSTADISANAS IZDZESIET SKRIPTUS UN ZURNALUS NO C:\Scripts (skripta ir ESET atslega).
      d) palaiz openlab-konti.ps1 no tas pasas mapes (kontu ierobezojumi)

 Beigu soli - kad Office uzstadits un viss parbaudits:
      powershell -ExecutionPolicy Bypass -File C:\Scripts\openlab-uzstadisana.ps1 -Pabeigt
    Dara: OpenLab iznem no administratoriem, nonem paroli, aizliedz paroles mainu,
          iestata automatisko pieteiksanos OpenLab konta.

 Zurnals: openlab-uzstadisana-<datums>.log blakus skriptam.
#>
#Requires -RunAsAdministrator
param(
    [switch]$Pabeigt,
    [string]$Lietotajs = 'OpenLab',
    # ESET licences atslega. PEC UZSTADISANAS SKRIPTU IZDZEST!
    [string]$EsetAtslega = ''   # repozitorija NEGLABAT - ja tuks, skripts prasa
)

# --- Programmas (winget ID). Lieko izkomentejiet ar #, vajadzigo pievienojiet. ---
$Programmas = @(
    'Google.Chrome'
    'Mozilla.Firefox'
    'Zoom.Zoom'
    'VideoLAN.VLC'
    'eParaksts.eParakstitajs'            # eParakstitajs 3.0
    'eParaksts.eParakstsTokenSigning'    # eParaksts parluku spraudnis
    'RARLab.WinRAR'
    'BlenderFoundation.Blender'
    'Inkscape.Inkscape'
    # 'Adobe.Acrobat.Reader.64-bit'
    # '7zip.7zip'
)

$ErrorActionPreference = 'Stop'
$log = Join-Path $PSScriptRoot ('openlab-uzstadisana-{0:yyyyMMdd-HHmm}.log' -f (Get-Date))
Start-Transcript -Path $log | Out-Null

function Solis([string]$t) { Write-Host ''; Write-Host "=== $t ===" -ForegroundColor Cyan }

$adminSid = 'S-1-5-32-544'
$winlogon = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon'

try {
    $builtinAdmin = Get-LocalUser | Where-Object { $_.SID.Value -like 'S-1-5-21-*-500' }

    # =====================================================================
    if ($Pabeigt) {
        Solis 'Beigu soli'
        if (-not $builtinAdmin.Enabled) {
            throw "Konts $($builtinAdmin.Name) nav ieslegts - beigu soli netiek darits (citadi dators paliktu bez administratora)."
        }
        Write-Host "Administrators: $($builtinAdmin.Name) (ieslegts)"

        $ir = Get-LocalGroupMember -SID $adminSid | Where-Object { $_.Name -like "*\$Lietotajs" }
        if ($ir) {
            Remove-LocalGroupMember -SID $adminSid -Member $Lietotajs
            Write-Host "$Lietotajs iznemts no Administrators"
        }

        Set-LocalUser -Name $Lietotajs -Password (New-Object System.Security.SecureString) `
            -UserMayChangePassword $false -PasswordNeverExpires $true
        Write-Host "$Lietotajs - parole nonemta, mainit nevar"

        Set-ItemProperty $winlogon 'AutoAdminLogon'    '1'
        Set-ItemProperty $winlogon 'DefaultUserName'   $Lietotajs
        Set-ItemProperty $winlogon 'DefaultDomainName' $env:COMPUTERNAME
        Set-ItemProperty $winlogon 'DefaultPassword'   ''
        Write-Host "Automatiska pieteiksanas: $Lietotajs"

        Write-Host ''
        Write-Host 'GATAVS. Restartejiet datoru.' -ForegroundColor Green
        return
    }

    # =====================================================================
    Solis "1. Konts $($builtinAdmin.Name)"
    if ($builtinAdmin.Enabled) {
        Write-Host 'jau ieslegts - parole netiek mainita'
    } else {
        do {
            $p1 = Read-Host "Jauna $($builtinAdmin.Name) parole" -AsSecureString
            $p2 = Read-Host 'Atkartojiet paroli' -AsSecureString
            $s1 = [Runtime.InteropServices.Marshal]::PtrToStringBSTR([Runtime.InteropServices.Marshal]::SecureStringToBSTR($p1))
            $s2 = [Runtime.InteropServices.Marshal]::PtrToStringBSTR([Runtime.InteropServices.Marshal]::SecureStringToBSTR($p2))
            $sakrit = ($s1 -ceq $s2) -and $s1.Length -gt 0
            if (-not $sakrit) { Write-Warning 'Paroles nesakrit vai ir tuksas - meginiet velreiz' }
        } until ($sakrit)
        $s1 = $s2 = $null
        Set-LocalUser -InputObject $builtinAdmin -Password $p1 -PasswordNeverExpires $true
        Enable-LocalUser -InputObject $builtinAdmin
        Write-Host 'ieslegts. Saglabajiet paroli parolu parvaldnieka!' -ForegroundColor Yellow
    }

    # ESET licences atslega - prasam tagad, lai talak skripts strada bez cilveka
    $esetId  = 'ESET.EndpointAntivirus'
    $esetKey = $null
    $esetIr  = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*' -ErrorAction SilentlyContinue |
               Where-Object { $_.DisplayName -like 'ESET Endpoint*' }
    if (-not $esetIr -and $EsetAtslega) {
        $esetKey = $EsetAtslega.Trim().ToUpper()
        Write-Host 'ESET licences atslega nemta no skripta'
    } elseif (-not $esetIr) {
        do {
            $k = Read-Host 'ESET Endpoint Antivirus licences atslega (XXXX-XXXX-XXXX-XXXX-XXXX), tuks = aktivet velak' -AsSecureString
            $esetKey = ([Runtime.InteropServices.Marshal]::PtrToStringBSTR([Runtime.InteropServices.Marshal]::SecureStringToBSTR($k))).Trim().ToUpper()
            $derigs = (-not $esetKey) -or ($esetKey -match '^[A-Z0-9]{4}(-[A-Z0-9]{4}){4}$')
            if (-not $derigs) { Write-Warning 'Atslegas formats nav pareizs - meginiet velreiz' }
        } until ($derigs)
    }

    # =====================================================================
    Solis '2. Latvijas regionalie iestatijumi (saskarne - anglu)'
    Set-TimeZone -Id 'FLE Standard Time'
    Set-WinHomeLocation -GeoId 140
    Set-Culture lv-LV
    $list = New-WinUserLanguageList en-US
    $list[0].InputMethodTips.Clear()
    $list[0].InputMethodTips.Add('0409:00010426')   # Latvian (QWERTY)
    Set-WinUserLanguageList $list -Force
    Set-WinUILanguageOverride -Language en-US
    Set-WinSystemLocale lv-LV
    Copy-UserInternationalSettingsToSystem -WelcomeScreen $true -NewUser $true
    Write-Host 'laika josla Riga, formats lv-LV, klaviatura Latvian (QWERTY), sistemas lokale lv-LV'

    # =====================================================================
    Solis '3. Programmas (winget)'
    function Find-Winget {
        $c = Get-Command winget.exe -ErrorAction SilentlyContinue
        if ($c) { return $c.Source }
        $p = Join-Path $env:LOCALAPPDATA 'Microsoft\WindowsApps\winget.exe'
        if (Test-Path $p) { return $p }
        return $null
    }
    $wg = Find-Winget
    if (-not $wg) {
        Write-Host 'winget nav atrasts - meginu registret App Installer...'
        try {
            Add-AppxPackage -RegisterByFamilyName -MainPackage Microsoft.DesktopAppInstaller_8wekyb3d8bbwe
            Start-Sleep -Seconds 5
        } catch { Write-Host "   neizdevas: $($_.Exception.Message.Split([Environment]::NewLine)[0])" }
        $wg = Find-Winget
    }
    if (-not $wg) {
        Write-Host 'winget joprojam nav - lejupieladeju App Installer no Microsoft (aka.ms/getwinget)...'
        try {
            [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
            $ProgressPreference = 'SilentlyContinue'
            $bundle = Join-Path $env:TEMP 'Microsoft.DesktopAppInstaller.msixbundle'
            Invoke-WebRequest 'https://aka.ms/getwinget' -OutFile $bundle -UseBasicParsing
            Add-AppxPackage -Path $bundle
            Start-Sleep -Seconds 5
        } catch { Write-Host "   neizdevas: $($_.Exception.Message.Split([Environment]::NewLine)[0])" }
        $wg = Find-Winget
    }
    if ($wg) { Write-Host "winget: $wg"; & $wg --version | Out-Host }
    $ok = @(); $jau = @(); $kludas = @()
    if (-not $wg) {
        Write-Warning 'winget nav pieejams - Microsoft Store > Library > Get updates (App Installer), tad palaidiet skriptu velreiz'
        $kludas += 'winget nav pieejams - programmas netika uzstaditas'
    } else {
        & $wg source update --name winget | Out-Host
        $kopejie = @('--exact', '--source', 'winget', '--silent', '--accept-package-agreements',
                     '--accept-source-agreements', '--disable-interactivity')

        # ESET - pirmais, ar aktivaciju (MSI parametrs ACTIVATION_DATA)
        if ($esetIr) {
            Write-Host "$esetId - jau uzstadits"; $jau += $esetId
        } else {
            Write-Host "$esetId - uzstada..." -ForegroundColor Yellow
            $esetArgs = @('install', '--id', $esetId) + $kopejie
            if ($esetKey) { $esetArgs += @('--custom', "ACTIVATION_DATA=key:$esetKey ACTIVATION_DLG_SUPPRESS=1") }
            & $wg @esetArgs | Out-Null      # Out-Null - lai atslega neparadas zurnala
            if ($LASTEXITCODE -eq 0 -or $LASTEXITCODE -eq -1978334967) {
                $ok += $esetId
                if (-not $esetKey) { Write-Warning 'ESET uzstadits bez aktivacijas - aktivejiet ESET loga' }
            } else { $kludas += "$esetId (kods $LASTEXITCODE)" }
            $esetKey = $null
        }

        foreach ($id in $Programmas) {
            & $wg list --id $id --exact --source winget --accept-source-agreements | Out-Null
            if ($LASTEXITCODE -eq 0) { Write-Host "$id - jau uzstadits"; $jau += $id; continue }

            Write-Host "$id - uzstada..." -ForegroundColor Yellow
            & $wg install --id $id --scope machine @kopejie | Out-Host
            if ($LASTEXITCODE -ne 0) {
                Write-Host "   ar --scope machine neizdevas ($LASTEXITCODE), meginu bez ta"
                & $wg install --id $id @kopejie | Out-Host
            }
            # 0x8A150109 = uzstadits, vajag restartu
            if ($LASTEXITCODE -eq 0 -or $LASTEXITCODE -eq -1978334967) { $ok += $id }
            else { $kludas += "$id (kods $LASTEXITCODE)" }
        }
    }

    # =====================================================================
    Solis '4. Kontu ierobezojumi (openlab-konti.ps1)'
    $konti = Join-Path $PSScriptRoot 'openlab-konti.ps1'
    if (Test-Path $konti) {
        & $konti
    } else {
        Write-Warning "Nav atrasts $konti - ielieciet to taja pasa mape un palaidiet atseviski"
        $kludas += 'openlab-konti.ps1 nav palaists'
    }

    # =====================================================================
    Solis 'Kopsavilkums'
    if ($ok)     { Write-Host ('Uzstaditas: ' + ($ok -join ', ')) -ForegroundColor Green }
    if ($jau)    { Write-Host ('Jau bija:   ' + ($jau -join ', ')) }
    if ($kludas) { Write-Host ('KLUDAS:     ' + ($kludas -join '; ')) -ForegroundColor Red }
    Write-Host ''
    Write-Host 'Talak: restartejiet datoru, parbaudiet pieteiksanos ka Administrator,' -ForegroundColor Green
    Write-Host 'tad ka OpenLab uzstadiet Office un piesakieties ar datora @piuac.lv kontu.' -ForegroundColor Green
    Write-Host 'Beigas: ... openlab-uzstadisana.ps1 -Pabeigt' -ForegroundColor Green
}
finally {
    Stop-Transcript | Out-Null
}
