<#
 patch-eparaksts-allusers.ps1   (palaist VIENU REIZI uz admin PC PIUAC-ASKOLDS, ka administrators)
 NAS client-install.ps1: eParaksts rindai pievieno ALLUSERS=1, lai eParakstitajs tiktu uzstadits
 datoram kopigi (C:\Program Files\eparakstitajs3), nevis tikai viena lietotaja profila.
 Pirms izmainam tiek izveidota rezerves kopija .bak-*. Skripts ir idempotents.
#>
param(
    [string]$ClientPath = "\\PIUAC_CLOUD\Updates\Scripts\client-install.ps1"
)

if (-not (Test-Path $ClientPath)) { Write-Host "KLUDA: nav atrasts $ClientPath" -ForegroundColor Red; return }
$raw  = [System.IO.File]::ReadAllText($ClientPath)
$crlf = $raw.Contains("`r`n")
$text = $raw.Replace("`r`n", "`n")
$lines = $text.Split("`n")

$idx = @()
for ($i = 0; $i -lt $lines.Count; $i++) {
    if ($lines[$i] -match 'Key\s*=\s*"eParaksts"' -and $lines[$i] -match 'DisplayNamePattern') { $idx += $i }
}
if ($idx.Count -ne 1) { Write-Host "KLUDA: eParaksts rinda atrasta $($idx.Count) reizes (gaidits 1). Nekas netika mainits." -ForegroundColor Red; return }

$line = $lines[$idx[0]]
if ($line -match 'ALLUSERS=1') { Write-Host "Jau pielabots (ALLUSERS=1 ir) - izlaizu." -ForegroundColor Yellow; return }

$old = '@("/quiet", "/norestart")'
if (-not $line.Contains($old)) { Write-Host "KLUDA: SilentArgs forma neatbilst gaiditajai. Rinda: $line" -ForegroundColor Red; return }
$lines[$idx[0]] = $line.Replace($old, '@("/quiet", "/norestart", "ALLUSERS=1")')

$text = $lines -join "`n"
if ($crlf) { $text = $text.Replace("`n", "`r`n") }
Copy-Item $ClientPath ($ClientPath + ".bak-" + (Get-Date -Format "yyyyMMdd-HHmmss"))
[System.IO.File]::WriteAllText($ClientPath, $text, (New-Object System.Text.UTF8Encoding($true)))
Write-Host "client-install.ps1 : eParaksts SilentArgs tagad ar ALLUSERS=1 (rezerves kopija .bak-*)." -ForegroundColor Green
Write-Host ("Jauna rinda: " + $lines[$idx[0]].Trim())
