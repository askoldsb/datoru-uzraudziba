<#
 patch-exe-nowait.ps1   (palaist VIENU REIZI uz admin PC PIUAC-ASKOLDS, ka administrators)
 Pielabo NAS client-install.ps1: exe instalatori vairs negaida visu apakspocesu koku (Start-Process -Wait),
 bet tikai pasa instalatora procesu, ar 10 min limitu. Tas novers karasanos, kad instalators
 (piem. Adobe Creative Cloud) atstaj fona procesus. Rezerves kopija .bak-*. Idempotents.
#>
param(
    [string]$ClientPath = "\\PIUAC_CLOUD\Updates\Scripts\client-install.ps1"
)

if (-not (Test-Path $ClientPath)) { Write-Host "KLUDA: nav atrasts $ClientPath" -ForegroundColor Red; return }
$raw = [System.IO.File]::ReadAllText($ClientPath)
if ($raw.Contains("exe-nowait")) {
    Write-Host "client-install.ps1 : jau pielabots - izlaizu." -ForegroundColor Yellow
    return
}
$crlf = $raw.Contains("`r`n")
$text = $raw.Replace("`r`n", "`n")

$old = '            $p = Start-Process -FilePath $localFile -ArgumentList $SilentArgs -Wait -PassThru -WindowStyle Hidden' + "`n" + '            return $p.ExitCode'
$cnt = ([regex]::Matches($text, [regex]::Escape($old))).Count
if ($cnt -ne 1) {
    Write-Host "KLUDA: enkurs atrasts $cnt reizes (gaidits 1). Nekas netika mainits." -ForegroundColor Red
    return
}

$new = @'
            # exe-nowait: gaidam tikai pasa instalatora procesu (ne apakspocesu koku), max 10 min
            $p = Start-Process -FilePath $localFile -ArgumentList $SilentArgs -PassThru -WindowStyle Hidden
            if (-not $p.WaitForExit(600000)) {
                Write-Log "$Key : instalators darbojas ilgak par 10 min - turpinu tālāk." "WARN"
                return 0
            }
            return $p.ExitCode
'@.TrimEnd("`r", "`n")
$new = $new.Replace("tālāk", "talak")

$text = $text.Replace($old, $new)
if ($crlf) { $text = $text.Replace("`n", "`r`n") }
Copy-Item $ClientPath ($ClientPath + ".bak-" + (Get-Date -Format "yyyyMMdd-HHmmss"))
[System.IO.File]::WriteAllText($ClientPath, $text, (New-Object System.Text.UTF8Encoding($true)))
Write-Host "client-install.ps1 : pielabots (exe bez apakspocesu gaidisanas), rezerves kopija .bak-*." -ForegroundColor Green
