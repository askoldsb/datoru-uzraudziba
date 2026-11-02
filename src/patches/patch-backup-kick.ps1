<#
 patch-backup-kick.ps1   (palaist VIENU REIZI uz admin PC PIUAC-ASKOLDS, ka administrators)
 Pielabo NAS client-install.ps1: katra cikla sakuma, ja datoraa ir uzdevums LabProfileBackup, bet nav
 SYSTEM uzdevuma LabProfileBackup-Kick (ik stundu bez beigam, palaiz LabProfileBackup), to izveido.
 Tas risina situaciju, kad dators 03:30 gul un ikdienas trigera stundas atkartosana nesakas.
 Rezerves kopija .bak-*. Skripts ir idempotents.
#>
param(
    [string]$ClientPath = "\\PIUAC_CLOUD\Updates\Scripts\client-install.ps1"
)

if (-not (Test-Path $ClientPath)) { Write-Host "KLUDA: nav atrasts $ClientPath" -ForegroundColor Red; return }
$raw = [System.IO.File]::ReadAllText($ClientPath)
if ($raw.Contains("LabProfileBackup-Kick")) {
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

# Profilu kopesanas palaisanas uzdevums (ja kopesana uzstadita): SYSTEM uzdevums ik stundu palaiz LabProfileBackup,
# jo ikdienas trigera atkartosana nesakas, ja dators 03:30 gul. Kluda cikla neietekme.
try {
    if ((Get-ScheduledTask -TaskName "LabProfileBackup" -ErrorAction SilentlyContinue) -and (-not (Get-ScheduledTask -TaskName "LabProfileBackup-Kick" -ErrorAction SilentlyContinue))) {
        $bkA = New-ScheduledTaskAction -Execute "schtasks.exe" -Argument '/Run /TN "LabProfileBackup"'
        $bkT = New-ScheduledTaskTrigger -Once -At "2026-10-15 00:15" -RepetitionInterval (New-TimeSpan -Hours 1) -RepetitionDuration (New-TimeSpan -Days 3650)
        $bkP = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest
        $bkS = New-ScheduledTaskSettingsSet -StartWhenAvailable -MultipleInstances IgnoreNew -ExecutionTimeLimit (New-TimeSpan -Minutes 5)
        Register-ScheduledTask -TaskName "LabProfileBackup-Kick" -Action $bkA -Trigger $bkT -Principal $bkP -Settings $bkS -Force | Out-Null
        Write-Log "Uzdevums LabProfileBackup-Kick izveidots (ik stundu palaiz profilu kopesanu)."
    }
} catch {
    Write-Log "LabProfileBackup-Kick: kluda - $_" "WARN"
}
'@
$text = $text.Replace($anchor, ($anchor + "`n" + $block.Replace("`r`n", "`n")))
if ($crlf) { $text = $text.Replace("`n", "`r`n") }
Copy-Item $ClientPath ($ClientPath + ".bak-" + (Get-Date -Format "yyyyMMdd-HHmmss"))
[System.IO.File]::WriteAllText($ClientPath, $text, (New-Object System.Text.UTF8Encoding($true)))
Write-Host "client-install.ps1 : pielabots (LabProfileBackup-Kick), rezerves kopija .bak-*." -ForegroundColor Green
