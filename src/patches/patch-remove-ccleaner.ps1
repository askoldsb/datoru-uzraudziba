<#
 patch-remove-ccleaner.ps1   (palaist VIENU REIZI uz admin PC PIUAC-ASKOLDS, ka administrators)
 Pielabo NAS client-install.ps1: katra atjauninasanas cikla (kad grafiks atlauj) sakuma
 klienta dators atinstale CCleaner, ja tas ir uzstadits. Tas sedz ari nakotnes datorus.
 Saraksts: $RemoveAppNames (seit ielikts "CCleaner"). Atinstalesana notiek klusi (/S), bez restarta.
 Rezerves kopija .bak-*. Skripts ir idempotents.
#>
param(
    [string]$ClientPath = "\\PIUAC_CLOUD\Updates\Scripts\client-install.ps1"
)

if (-not (Test-Path $ClientPath)) { Write-Host "KLUDA: nav atrasts $ClientPath" -ForegroundColor Red; return }
$raw = [System.IO.File]::ReadAllText($ClientPath)
if ($raw.Contains("RemoveAppNames")) {
    Write-Host "client-install.ps1 : jau pielabots - izlaizu." -ForegroundColor Yellow
    return
}
$crlf = $raw.Contains("`r`n")
$text = $raw.Replace("`r`n", "`n")

$anchor = '$wuReboot = $false'
$cnt = ([regex]::Matches($text, [regex]::Escape($anchor))).Count
if ($cnt -ne 1) {
    Write-Host "KLUDA: enkurs atrasts $cnt reizes (gaidits 1). Nekas netika mainits." -ForegroundColor Red
    return
}

$block = @'

# Nevelamo programmu nonemsana (CCleaner). Saraksts - DisplayName precizi.
$RemoveAppNames = @("CCleaner")
try {
    $rmPaths = @("HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*", "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*")
    foreach ($rmName in $RemoveAppNames) {
        $rmEntries = @(Get-ItemProperty -Path $rmPaths -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName -eq $rmName })
        foreach ($rm in $rmEntries) {
            $rmUs = [string]$rm.UninstallString
            $rmExe = ""
            if ($rmUs -match '^"([^"]+)"') { $rmExe = $Matches[1] } else { $rmExe = ($rmUs -split ' ')[0] }
            if ((-not $rmExe) -or (-not (Test-Path $rmExe))) {
                Write-Log "$rmName : atinstaletajs nav atrasts ($rmExe) - izlaists." "WARN"
                continue
            }
            Write-Log "$rmName $($rm.DisplayVersion): atinstalesana (nevelama programma)."
            Get-Process -Name "CCleaner", "CCleaner64", "CCUpdate" -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
            Start-Process -FilePath $rmExe -ArgumentList "/S" -WindowStyle Hidden
            $rmGone = $false
            for ($rmI = 0; $rmI -lt 18; $rmI++) {
                Start-Sleep -Seconds 5
                if (@(Get-ItemProperty -Path $rmPaths -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName -eq $rmName }).Count -eq 0) { $rmGone = $true; break }
            }
            if ($rmGone) {
                Write-Log "$rmName : atinstalets."
                $installedApps += "Atinstalets: $rmName"
            } else {
                Write-Log "$rmName : ieraksts pec 90 s joprojam ir." "WARN"
                $failedApps += "$rmName (atinstalesana nepabeigta)"
            }
        }
    }
} catch {
    Write-Log "Nevelamo programmu nonemsana: kluda - $_" "WARN"
}
'@
$text = $text.Replace($anchor, ($anchor + "`n" + $block.Replace("`r`n", "`n")))
if ($crlf) { $text = $text.Replace("`n", "`r`n") }
Copy-Item $ClientPath ($ClientPath + ".bak-" + (Get-Date -Format "yyyyMMdd-HHmmss"))
[System.IO.File]::WriteAllText($ClientPath, $text, (New-Object System.Text.UTF8Encoding($true)))
Write-Host "client-install.ps1 : pielabots (CCleaner nonemsana), rezerves kopija .bak-*." -ForegroundColor Green
