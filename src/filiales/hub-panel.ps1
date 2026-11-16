<#
============================================================
 hub-panel.ps1
 Filiales hub dators (AUCEUPDATE-PC), administrators.
 Darbvirsmas ikona "Auces panelis" (to izveido hub-sync.ps1).

 Atver TO PASU Dobeles paneli (config-panel.ps1 + inventory-report.ps1,
 kas atnak parakstiti caur Tools\Panelis\) ar -NasRoot C:\Hub\Updates:
   - grafiks (TIKAI apskate - grafiku maina PIUAC-ASKOLDS "Auce grafiks",
     jo tikai tur ir parakstisanas sertifikats);
   - "Paradit atskaite" - statuss ar krasam (dati uz vietas, svaigi);
   - "Inventara atskaite" - Pamodinat / Izslegt / Restartet / Atjaunot tagad
     (WoL no hub, WinRM uz datoriem, komandas Config\Commands).

 Originals C:\Hub\Tools\Panelis netiek mainits: kopija tiek veidota
 %LOCALAPPDATA%\PIUAC-panelis, kur paslepj grafika labosanas pogas un
 Dobeles WoL apraides adresi aizstaj ar hub tikla adresi.
============================================================
#>
param(
    [string]$Branch = "Auce",
    [string]$UpdatesRoot = "C:\Hub\Updates",
    [string]$PanelDir = "C:\Hub\Tools\Panelis",
    [string[]]$HideButtons = @("Pievienot datoru", "Dzest atlasito", "Importet sarakstu", "Saglabat uz NAS",
                               "Atvert ESET portalu", "Profilu kopijas", "Programmu saraksts")
)

Add-Type -AssemblyName System.Windows.Forms
function Show-Msg { param([string]$Text, [string]$Icon = "Information")
    [void][System.Windows.Forms.MessageBox]::Show($Text, "$Branch panelis", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::$Icon) }

$panelSrc = Join-Path $PanelDir "config-panel.ps1"
$invSrc   = Join-Path $PanelDir "inventory-report.ps1"
foreach ($p in @($UpdatesRoot, $panelSrc)) {
    if (-not (Test-Path $p)) { Show-Msg "Nav atrasts: $p`n`nPanelis atnak ar publicesanu no PIUAC-ASKOLDS (publish-filiale.ps1)." "Error"; exit 1 }
}

$run = Join-Path $env:LOCALAPPDATA "PIUAC-panelis"
if (-not (Test-Path $run)) { New-Item -ItemType Directory -Path $run -Force | Out-Null }

# Hub tikla apraides adreses (/24) Dobeles 192.168.3.255 vieta
$bcast = @()
try {
    foreach ($a in @(Get-NetIPAddress -AddressFamily IPv4 -ErrorAction Stop | Where-Object { $_.IPAddress -notlike '169.254.*' -and $_.IPAddress -ne '127.0.0.1' -and $_.PrefixLength -eq 24 })) {
        $o = $a.IPAddress -split '\.'; $bcast += ($o[0] + '.' + $o[1] + '.' + $o[2] + '.255')
    }
} catch { }
$bcast = @($bcast | Select-Object -Unique)
if ($bcast.Count -eq 0) { $bcast = @("255.255.255.255") }
$bcastText = ($bcast | ForEach-Object { '"' + $_ + '"' }) -join ", "

# Panelis: paslept grafika labosanas pogas, cits virsraksts un piezime
$txt = [System.IO.File]::ReadAllText($panelSrc)
foreach ($h in $HideButtons) {
    $pattern = '(?m)^([ \t]*)(\$\w+)\.Text\s*=\s*"' + [regex]::Escape($h) + '"'
    if ([regex]::IsMatch($txt, $pattern)) { $txt = [regex]::Replace($txt, $pattern, '$0; $2.Visible = $false') }
}
$txt = [regex]::Replace($txt, '(?m)^(\$infoLabel\.Text\s*=\s*)".*"', ('$1"' + "$Branch hub: grafiks TIKAI apskatei - maina PIUAC-ASKOLDS (ikona '$Branch grafiks'). Pamodinat / Izslegt / Atjaunot tagad - poga 'Inventara atskaite'." + '"'))
$txt = $txt.Replace('$form.Controls.Add($grid)', '$form.Controls.Add($grid); $grid.ReadOnly = $true')
$txt = $txt.Replace('$form.Text ="Atjauninasanas grafika parvaldiba - $NasRoot"', ('$form.Text = "' + $Branch + ' panelis (AUCEUPDATE-PC) - $NasRoot"'))
[System.IO.File]::WriteAllText((Join-Path $run "config-panel.ps1"), $txt, (New-Object System.Text.UTF8Encoding($true)))

# Inventara atskaite: WoL uz hub tikla apraidi
if (Test-Path $invSrc) {
    $inv = [System.IO.File]::ReadAllText($invSrc)
    $inv = $inv.Replace('"255.255.255.255", "192.168.3.255"', ('"255.255.255.255", ' + $bcastText))
    [System.IO.File]::WriteAllText((Join-Path $run "inventory-report.ps1"), $inv, (New-Object System.Text.UTF8Encoding($true)))
} else {
    Remove-Item (Join-Path $run "inventory-report.ps1") -Force -ErrorAction SilentlyContinue
}
# Lieki faili no agrakam reizem (pogas paslepta, bet lai tie netiktu ieladeti)
foreach ($n in @("apps-managed-editor.ps1", "backup-manager.ps1")) { Remove-Item (Join-Path $run $n) -Force -ErrorAction SilentlyContinue }

& (Join-Path $run "config-panel.ps1") -NasRoot $UpdatesRoot
