<#
 patch-kick-task.ps1   (palaist VIENU REIZI uz admin PC PIUAC-ASKOLDS, ka administrators)
 Problema: LabAppUpdate trigeris ir ikdienas ar atkartosanu 15 min tikai 23h59m no pusnakts.
 Ja dators pusnakti gul, atkartosana visu dienu nesakas (pec pamosanas notiek tikai viena palaisana).
 Risinajums: NAS client-install.ps1 katra cikla sakuma (ari izlaistaja pec grafika) parbauda, vai
 eksiste SYSTEM uzdevums 'LabAppUpdate-Kick' (ik 15 min bez beigam, palaiz LabAppUpdate), un ja nav - izveido.
 Visi klienti sevi salabos pirmaja ciklaa. Rezerves kopija .bak-*. Skripts ir idempotents.
#>
param(
    [string]$ClientPath = "\\PIUAC_CLOUD\Updates\Scripts\client-install.ps1"
)

if (-not (Test-Path $ClientPath)) { Write-Host "KLUDA: nav atrasts $ClientPath" -ForegroundColor Red; return }
$raw = [System.IO.File]::ReadAllText($ClientPath)
if ($raw.Contains("LabAppUpdate-Kick")) {
    Write-Host "client-install.ps1 : jau pielabots - izlaizu." -ForegroundColor Yellow
    return
}
$crlf = $raw.Contains("`r`n")
$text = $raw.Replace("`r`n", "`n")
$anchor = 'Write-Log "=== Klienta atjauninasana sakta uz $computerName ==="'
$cnt = ([regex]::Matches($text, [regex]::Escape($anchor))).Count
if ($cnt -ne 1) {
    Write-Host "KLUDA: enkurs atrasts $cnt reizes (gaidits 1). Nekas netika mainits." -ForegroundColor Red
    return
}
$block = @'

# Palaisanas uzdevums: nodrosina, ka cikls turpinas arii pec datora pamosanas no miega.
# (LabAppUpdate ikdienas trigeris pec pusnakts miega neatkarto ik 15 min.) Kluda cikla neietekme.
try {
    if (-not (Get-ScheduledTask -TaskName "LabAppUpdate-Kick" -ErrorAction SilentlyContinue)) {
        $kAct = New-ScheduledTaskAction -Execute "schtasks.exe" -Argument '/Run /TN "LabAppUpdate"'
        $kTrg = New-ScheduledTaskTrigger -Once -At "2026-10-15 00:00" -RepetitionInterval (New-TimeSpan -Minutes 15) -RepetitionDuration (New-TimeSpan -Days 3650)
        $kPri = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest
        $kSet = New-ScheduledTaskSettingsSet -StartWhenAvailable -MultipleInstances IgnoreNew -ExecutionTimeLimit (New-TimeSpan -Minutes 5)
        Register-ScheduledTask -TaskName "LabAppUpdate-Kick" -Action $kAct -Trigger $kTrg -Principal $kPri -Settings $kSet -Force | Out-Null
        Write-Log "Uzdevums LabAppUpdate-Kick izveidots (atkartosana ik 15 min bez beigam, parlaiz miegu)."
    }
} catch {
    Write-Log "LabAppUpdate-Kick: kluda - $_" "WARN"
}
'@
$text = $text.Replace($anchor, ($anchor + "`n" + $block.Replace("`r`n", "`n")))
if ($crlf) { $text = $text.Replace("`n", "`r`n") }
Copy-Item $ClientPath ($ClientPath + ".bak-" + (Get-Date -Format "yyyyMMdd-HHmmss"))
[System.IO.File]::WriteAllText($ClientPath, $text, (New-Object System.Text.UTF8Encoding($true)))
Write-Host "client-install.ps1 : pielabots (LabAppUpdate-Kick), rezerves kopija .bak-*." -ForegroundColor Green
