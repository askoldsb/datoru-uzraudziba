<#
 OpenLab-Display: kopigs prezentaciju dators (skarienjutigais ekrans).

 Ko dara:
  1. Windows: aizliegts pievienot Microsoft (personigo) kontu un pieteikties ar to
  2. Office/Teams pieteiksanas NEpiesaista datoru iestades Entra ID
     (nav "Stay signed in to all your apps" / "Allow my organization to manage my device")
  3. OneDrive: personigie konti bloketi; sinhronize TIKAI @piuac.lv (iestades tenant) kontus
  4. Edge un Chrome: parluka profila pieteiksanas izslegta, paroles netiek saglabatas,
     aizverot parluku vesture, sikdatnes un pieteiksanas vietnes tiek izdzestas;
     mekletajs = Google (nav izveles loga), programmu spraudni (eParaksts) ieslegti pec noklusejuma
     Chrome: Google pakalpojumos (Gmail, YouTube, Drive) var pieteikties tikai ar @piuac.lv
     Google kontu - t.i., personigie Gmail konti Chrome nestrada
  5. Office: atlauts pieteikties TIKAI ar iestades (darba) kontu - visiem esosajiem
     un visiem nakotnes lietotaju profiliem
  6. (ar -Lektors) izveido kopigu standarta kontu bez paroles, kuru lietotajs nevar mainit

 Palaist admin PowerShell loga:
   powershell -ExecutionPolicy Bypass -File .\openlab-konti.ps1
   powershell -ExecutionPolicy Bypass -File .\openlab-konti.ps1 -Lektors
#>
#Requires -RunAsAdministrator
param(
    [switch]$Lektors,
    [string]$LektorsVards = 'Lektors',
    [string]$Domens = 'piuac.lv',
    [string]$TenantId          # ja nav dots, nosaka automatiski pec domena
)
$ErrorActionPreference = 'Stop'

function Set-Reg([string]$Path, [string]$Name, $Value, [string]$Type = 'DWord') {
    if (-not (Test-Path $Path)) { New-Item -Path $Path -Force | Out-Null }
    New-ItemProperty -Path $Path -Name $Name -Value $Value -PropertyType $Type -Force | Out-Null
    Write-Host ("   {0} \ {1} = {2}" -f $Path, $Name, $Value)
}

# Iestades Microsoft 365 tenant ID pec domena
if (-not $TenantId) {
    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        $cfg = Invoke-RestMethod "https://login.microsoftonline.com/$Domens/v2.0/.well-known/openid-configuration"
        $TenantId = ($cfg.issuer -split '/')[3]
    } catch {
        Write-Warning "Neizdevas noteikt tenant ID domenam $Domens ($($_.Exception.Message))"
    }
}
$g = [guid]::Empty
if ($TenantId -and [guid]::TryParse($TenantId, [ref]$g)) {
    Write-Host "Domens $Domens -> tenant ID $TenantId"
} else {
    $TenantId = $null
    Write-Warning "Tenant ID nav zinams - OneDrive tenant ierobezojums tiks izlaists (palaidiet ar -TenantId <GUID>)"
}

# --- 6. Kopigais konts (pirms Office iestatijumiem, lai tie nonak ari ta profila) ---
if ($Lektors) {
    Write-Host "6. Standarta konts '$LektorsVards'"
    if (-not (Get-LocalUser -Name $LektorsVards -ErrorAction SilentlyContinue)) {
        New-LocalUser -Name $LektorsVards -NoPassword -UserMayNotChangePassword `
            -AccountNeverExpires -Description 'Kopigs konts lektoriem' | Out-Null
        Write-Host "   izveidots"
    } else {
        Write-Host "   jau eksiste"
    }
    Set-LocalUser -Name $LektorsVards -PasswordNeverExpires $true
    $users = Get-LocalGroupMember -SID 'S-1-5-32-545' | Where-Object { $_.Name -like "*\$LektorsVards" }
    if (-not $users) { Add-LocalGroupMember -SID 'S-1-5-32-545' -Member $LektorsVards }
    $admins = Get-LocalGroupMember -SID 'S-1-5-32-544' | Where-Object { $_.Name -like "*\$LektorsVards" }
    if ($admins) { Remove-LocalGroupMember -SID 'S-1-5-32-544' -Member $LektorsVards; Write-Host "   iznemts no Administrators" }
    Write-Host "   grupa: Users (nav administrators)"
}

# --- 1-4. Datora politikas (HKLM) ---
Write-Host '1. Windows: Microsoft konti bloketi'
Set-Reg 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System' 'NoConnectedUser' 3

Write-Host '2. Office/Teams nepiesaista datoru iestades Entra ID'
Set-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WorkplaceJoin' 'BlockAADWorkplaceJoin' 1

Write-Host '3. OneDrive: personigie konti bloketi'
Set-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\OneDrive' 'DisablePersonalSync' 1
if ($TenantId) {
    Write-Host "   OneDrive: atlauts tikai $Domens tenant"
    Set-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\OneDrive\AllowTenantList' $TenantId $TenantId 'String'
}

Write-Host '4. Parluki (Edge, Chrome): publisks dators'
$edgeP   = 'HKLM:\SOFTWARE\Policies\Microsoft\Edge'
$chromeP = 'HKLM:\SOFTWARE\Policies\Google\Chrome'
foreach ($b in $edgeP, $chromeP) {
    Set-Reg $b 'BrowserSignin' 0                 # nevar pieteikties parluka profila
    Set-Reg $b 'SyncDisabled' 1
    Set-Reg $b 'ForceEphemeralProfiles' 0        # profils saglabajas (iestatijumi, spraudni); dati tiek dzesti aizverot (zemak)
    Set-Reg $b 'PasswordManagerEnabled' 0        # nepiedava saglabat paroles
    Set-Reg $b 'BackgroundModeEnabled' 0         # aizverot logu, parluks tiesam beidz darbu -> dati tiek izdzesti
    Set-Reg $b 'PromotionalTabsEnabled' 0
    Set-Reg $b 'DefaultBrowserSettingEnabled' 0  # neprasa "padarit par nokluseto parluku"
    # Nokluseta meklesana = Google -> nav mekletaja izveles loga
    Set-Reg $b 'DefaultSearchProviderEnabled' 1
    Set-Reg $b 'DefaultSearchProviderName' 'Google' 'String'
    Set-Reg $b 'DefaultSearchProviderSearchURL' 'https://www.google.com/search?q={searchTerms}' 'String'
    Set-Reg $b 'DefaultSearchProviderSuggestURL' 'https://www.google.com/complete/search?output=chrome&q={searchTerms}' 'String'
}
# Edge: bez pirma starta vedna, nav "Startup boost" (citadi Edge nekad neaizveras), dzest visu aizverot
Set-Reg $edgeP 'HideFirstRunExperience' 1
Set-Reg $edgeP 'StartupBoostEnabled' 0
Set-Reg $edgeP 'ClearBrowsingDataOnExit' 1
# Chrome: bez "Ad privacy" logiem, dzest datus aizverot
Set-Reg $chromeP 'PrivacySandboxPromptEnabled' 0
$clr = "$chromeP\ClearBrowsingDataOnExitList"
if (Test-Path $clr) { Remove-Item $clr -Recurse -Force }
$i = 1
foreach ($t in 'browsing_history', 'download_history', 'cookies_and_other_site_data',
               'cached_images_and_files', 'password_signin', 'autofill') {
    Set-Reg $clr "$i" $t 'String'; $i++
}
# Chrome: Google pakalpojumos atlauti tikai $Domens Google konti (personigie Gmail - ne)
Set-Reg $chromeP 'AllowedDomainsForApps' $Domens 'String'

# Spraudni, ko uzstadijusas programmas (piem. eParaksts) - piespiedu karta ieslegti,
# lai parluks neprasa "New extension added - enable?"
$ext = @(
    @{ Pol = $chromeP; Def = 'https://clients2.google.com/service/update2/crx'
       Src = 'HKLM:\SOFTWARE\Google\Chrome\Extensions', 'HKLM:\SOFTWARE\WOW6432Node\Google\Chrome\Extensions' },
    @{ Pol = $edgeP;   Def = 'https://edge.microsoft.com/extensionwebstorebase/v1/crx'
       Src = 'HKLM:\SOFTWARE\Microsoft\Edge\Extensions', 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Edge\Extensions' }
)
foreach ($e in $ext) {
    $ids = [ordered]@{}
    foreach ($s in $e.Src) {
        if (-not (Test-Path $s)) { continue }
        foreach ($k in Get-ChildItem $s) {
            $u = (Get-ItemProperty $k.PSPath -ErrorAction SilentlyContinue).update_url
            if (-not $u) { $u = $e.Def }
            $ids[$k.PSChildName] = $u
        }
    }
    $fl = "$($e.Pol)\ExtensionInstallForcelist"
    if (Test-Path $fl) { Remove-Item $fl -Recurse -Force }
    $i = 1
    foreach ($id in $ids.Keys) { Set-Reg $fl "$i" "$id;$($ids[$id])" 'String'; $i++ }
    if ($ids.Count -eq 0) { Write-Host "   $($e.Pol): programmu spraudnu nav" }
}

# --- 5. Office: tikai iestades konts (lietotaja politika, katram profilam) ---
# SignInOptions: 0 = abi, 1 = tikai Microsoft konts, 2 = tikai iestades konts, 3 = neviens
Write-Host '5. Office: tikai iestades konts (SignInOptions = 2)'
$rel = 'Software\Policies\Microsoft\Office\16.0\Common\SignIn'

function Set-OfficeOrgOnly([string]$HiveRoot) {
    Set-Reg "Registry::$HiveRoot\$rel" 'SignInOptions' 2
}

function Invoke-OnHive([string]$DatFile, [string]$Label) {
    $tmp = 'HKU\OpenLabTmp'
    & reg.exe load $tmp $DatFile | Out-Null
    if ($LASTEXITCODE -ne 0) { Write-Warning "   $Label - neizdevas ieladet $DatFile"; return }
    try {
        Write-Host "   $Label"
        Set-OfficeOrgOnly 'HKEY_USERS\OpenLabTmp'
    } finally {
        [gc]::Collect(); [gc]::WaitForPendingFinalizers()
        & reg.exe unload $tmp | Out-Null
    }
}

# a) noklusejuma profils - visi nakotnes lietotaji (ari '$LektorsVards' pirmaja pieteiksanas reize)
Invoke-OnHive 'C:\Users\Default\NTUSER.DAT' 'Default (jauni profili)'

# b) esosie profili
$profiles = Get-CimInstance Win32_UserProfile | Where-Object { -not $_.Special -and $_.LocalPath -like 'C:\Users\*' }
foreach ($p in $profiles) {
    $name = Split-Path $p.LocalPath -Leaf
    if ($name -in @('defaultuser0', 'Public', 'Default')) { continue }
    if ($p.Loaded) {
        Write-Host "   $name (pieteicies)"
        Set-OfficeOrgOnly "HKEY_USERS\$($p.SID)"
    } else {
        Invoke-OnHive (Join-Path $p.LocalPath 'NTUSER.DAT') $name
    }
}

Write-Host ''
Write-Host 'GATAVS. Restartejiet datoru, lai visas politikas staj speka.'
