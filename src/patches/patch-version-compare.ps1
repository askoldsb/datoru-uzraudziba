<#
 patch-version-compare.ps1   (palaist VIENU REIZI uz admin PC PIUAC-ASKOLDS, ka administrators)
 Pielabo NAS client-install.ps1 funkciju Compare-Versions: ja instaletajai versijai ir mazak komponentu
 nekas pieejamajai (piem. instaleta 1.55, pieejama 1.55.0.133), salidzina tikai kopigas komponentes.
 Tas novers bezgaligo "atjauninasanu" (Recuva: instaleta 1.55 vs 1.55.0.133, installer avare katru ciklu).
 Rezerves kopija .bak-*. Skripts ir idempotents.
#>
param(
    [string]$ClientPath = "\\PIUAC_CLOUD\Updates\Scripts\client-install.ps1"
)

if (-not (Test-Path $ClientPath)) { Write-Host "KLUDA: nav atrasts $ClientPath" -ForegroundColor Red; return }
$raw = [System.IO.File]::ReadAllText($ClientPath)
if ($raw.Contains("kopigas komponentes")) {
    Write-Host "client-install.ps1 : jau pielabots - izlaizu." -ForegroundColor Yellow
    return
}
$crlf = $raw.Contains("`r`n")
$text = $raw.Replace("`r`n", "`n")

$old = '        return ([version]$Latest) -gt ([version]$Installed)'
$cnt = ([regex]::Matches($text, [regex]::Escape($old))).Count
if ($cnt -ne 1) {
    Write-Host "KLUDA: enkurs atrasts $cnt reizes (gaidits 1). Nekas netika mainits." -ForegroundColor Red
    return
}

$new = @'
        $vInst = [version]$Installed
        $vLat  = [version]$Latest
        # Ja instaletajai versijai ir mazak komponentu (piem. 1.55 pret 1.55.0.133), salidzinam tikai
        # kopigas komponentes - citadi katru ciklu tiktu mekleta "jaunaka" versija.
        $nInst = @($Installed -split '\.').Count
        $nLat  = @($Latest -split '\.').Count
        if (($nInst -ge 2) -and ($nInst -lt $nLat)) {
            $vLat = [version](($Latest -split '\.')[0..($nInst - 1)] -join '.')
        }
        return $vLat -gt $vInst
'@.TrimEnd("`r", "`n")

$text = $text.Replace($old, $new)
if ($crlf) { $text = $text.Replace("`n", "`r`n") }
Copy-Item $ClientPath ($ClientPath + ".bak-" + (Get-Date -Format "yyyyMMdd-HHmmss"))
[System.IO.File]::WriteAllText($ClientPath, $text, (New-Object System.Text.UTF8Encoding($true)))
Write-Host "client-install.ps1 : pielabots (Compare-Versions, kopigas komponentes), rezerves kopija .bak-*." -ForegroundColor Green
