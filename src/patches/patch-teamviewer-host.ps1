<#
 patch-teamviewer-host.ps1
 Pielabo NAS failu Scripts\client-install.ps1: TeamViewer HOST atbalsts (Host atjauninasana, pilna klienta neskarsana
 datoros ar Host, Always_Online=1 parbaude). Citas izmainas netiek skartas.
 Pirms izmainam tiek izveidota rezerves kopija .bak-*. Palaist VIENU REIZI.
#>
param(
    [string]$Path = "\\192.168.3.31\Updates\Scripts\client-install.ps1"
)

if (-not (Test-Path $Path)) { Write-Host "KLUDA: nav atrasts $Path" -ForegroundColor Red; exit 1 }
$raw = [System.IO.File]::ReadAllText($Path)
if ($raw.Contains("function Confirm-TeamViewerAlwaysOnline")) { Write-Host "Jau pielabots - nekas nav jadara." -ForegroundColor Yellow; exit 0 }

$crlf = $raw.Contains("`r`n")
$text = $raw.Replace("`r`n", "`n")
$edits = @()
$a1 = @'
    @{ Key = "TeamViewer"; DisplayNamePattern = "TeamViewer*";           InstallType = "zip-msi"; SilentArgs = @("/quiet", "/norestart", "ACCEPT_EULA=1") },
'@
$n1 = @'
    # Pilna TeamViewer versija: NEskar datorus, kuros ir TeamViewer HOST (tur tiek atjaunots tikai Host).
    @{ Key = "TeamViewer"; DisplayNamePattern = "TeamViewer*";           ExcludePattern = "TeamViewer Host*"; SkipIfInstalledPattern = "TeamViewer Host*"; InstallType = "zip-msi"; SilentArgs = @("/quiet", "/norestart", "ACCEPT_EULA=1") },
    # TeamViewer HOST: TIKAI atjauninam tur, kur jau instalets (pirmo instalaciju veic administrators ar savu
    # Host moduli no Cache\TeamViewerHost\). Host pats neatjauninas (AutoUpdates=Disabled), tapec so dara sis cikls.
    @{ Key = "TeamViewerHost"; DisplayNamePattern = "TeamViewer Host*"; InstallType = "exe"; SilentArgs = @("/S"); UpdateOnly = $true },
'@
$edits += ,@($a1, $n1)
$a2 = @'
    $entry = $versions.$key
    if (-not $entry) {
'@
$n2 = @'
    if ($app.SkipIfInstalledPattern -and (Get-InstalledVersion -DisplayNamePattern $app.SkipIfInstalledPattern)) {
        Write-Log "$key : sim datoram ir instalets '$($app.SkipIfInstalledPattern)' - sis variants netiek instalets/atjauninats."
        continue
    }

    $entry = $versions.$key
    if (-not $entry) {
'@
$edits += ,@($a2, $n2)
$a3 = @'
        if ($key -eq "TeamViewer") {
            Repair-TeamViewerAutostart
'@
$n3 = @'
        if (($key -eq "TeamViewer") -or ($key -eq "TeamViewerHost")) {
            Repair-TeamViewerAutostart
'@
$edits += ,@($a3, $n3)
$a4 = @'
    $effectiveSkipApps += "TeamViewer"
'@
$n4 = @'
    $effectiveSkipApps += "TeamViewer"
    $effectiveSkipApps += "TeamViewerHost"
'@
$edits += ,@($a4, $n4)
$a5 = @'
function Repair-TeamViewerAutostart {
'@
$n5 = @'
function Confirm-TeamViewerAlwaysOnline {
    <#
        TeamViewer (Full un Host): ja registra vertiba Always_Online ir 0, TeamViewer serviss paliek
        OFFLINE (nav ID, nav pieslegsanas) - tas notika pec MSI instalacijas. Katra cikla DROSA parbaude:
        mainam TIKAI tad, ja vertiba eksiste un ir 0; tad iestatam 1 un pareistartejam servisu.
    #>
    try {
        $reg = "HKLM:\SOFTWARE\TeamViewer"
        if (-not (Test-Path $reg)) { return }
        if (-not (Get-InstalledVersion -DisplayNamePattern "TeamViewer*")) { return }
        $cur = (Get-ItemProperty -Path $reg -Name "Always_Online" -ErrorAction SilentlyContinue).Always_Online
        if (($null -ne $cur) -and ([int]$cur -eq 0)) {
            Set-ItemProperty -Path $reg -Name "Always_Online" -Value 1 -ErrorAction Stop
            Write-Log "TeamViewer: Always_Online bija 0 - iestatits uz 1, restartejam servisu."
            $svc = Get-Service -Name "TeamViewer" -ErrorAction SilentlyContinue
            if ($svc) { Restart-Service -Name "TeamViewer" -Force -ErrorAction SilentlyContinue }
        }
    } catch {
        Write-Log "TeamViewer Always_Online parbaude neizdevas: $_" "WARN"
    }
}

function Repair-TeamViewerAutostart {
'@
$edits += ,@($a5, $n5)
$a6 = @'
Confirm-TeamViewerHealthCheck

# Lokala konfiguracija bridinajuma logam
'@
$n6 = @'
Confirm-TeamViewerHealthCheck
Confirm-TeamViewerAlwaysOnline

# Lokala konfiguracija bridinajuma logam
'@
$edits += ,@($a6, $n6)

foreach ($e in $edits) {
    $old = [string]$e[0]; $new = [string]$e[1]
    $cnt = ([regex]::Matches($text, [regex]::Escape($old))).Count
    if ($cnt -ne 1) {
        Write-Host ("KLUDA: anchor atrasts {0} reizes (gaidits 1): {1}" -f $cnt, $old.Trim()) -ForegroundColor Red
        Write-Host "Fails ir mainits kops ta pielabosanas? Nekas netika mainits." -ForegroundColor Red
        exit 1
    }
    $text = $text.Replace($old, $new)
}

if ($crlf) { $text = $text.Replace("`n", "`r`n") }
Copy-Item $Path ($Path + ".bak-" + (Get-Date -Format "yyyyMMdd-HHmmss"))
[System.IO.File]::WriteAllText($Path, $text, (New-Object System.Text.UTF8Encoding($true)))
Write-Host "Gatavs: client-install.ps1 pielabots ar TeamViewer Host atbalstu (rezerves kopija .bak-*)." -ForegroundColor Green
