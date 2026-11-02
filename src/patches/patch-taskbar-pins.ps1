<#
 patch-taskbar-pins.ps1   (palaist VIENU REIZI uz admin PC PIUAC-ASKOLDS, ka administrators)
 1) Nokope ensure-taskbar-pins.ps1 uz NAS Scripts
 2) Izveido NAS Config\taskbar-pins.csv (ja tada vel nav) ar Inkscape un Blender
 3) Pielabo NAS Scripts\client-install.ps1: pirms cikla beigu zurnala ieraksta izsauc ensure-taskbar-pins.ps1
 Pirms izmainam tiek izveidota rezerves kopija .bak-*. Skripts ir idempotents.
#>
param(
    [string]$ClientPath = "\\PIUAC_CLOUD\Updates\Scripts\client-install.ps1",
    [string]$ScriptSrc  = "C:\Scripts\ensure-taskbar-pins.ps1",
    [string]$ScriptDst  = "\\PIUAC_CLOUD\Updates\Scripts\ensure-taskbar-pins.ps1",
    [string]$CsvDst     = "\\PIUAC_CLOUD\Updates\Config\taskbar-pins.csv"
)

# 1) ensure-taskbar-pins.ps1 -> NAS
if (-not (Test-Path $ScriptSrc)) { Write-Host "KLUDA: nav atrasts $ScriptSrc" -ForegroundColor Red; return }
Copy-Item $ScriptSrc $ScriptDst -Force
Write-Host "ensure-taskbar-pins.ps1 nokopets uz NAS." -ForegroundColor Green

# 2) taskbar-pins.csv
if (-not (Test-Path $CsvDst)) {
    $rows = @(
        [pscustomobject]@{ Enabled = "1"; Key = "Inkscape"; Name = "Inkscape"; ExePattern = "C:\Program Files\Inkscape\bin\inkscape.exe"; Targets = "DATORKLASE-*;DN0*;PC0*" },
        [pscustomobject]@{ Enabled = "1"; Key = "Blender";  Name = "Blender";  ExePattern = "C:\Program Files\Blender Foundation\*\blender.exe"; Targets = "DATORKLASE-*;DN0*;PC0*" }
    )
    $rows | Export-Csv -Path $CsvDst -NoTypeInformation -Encoding UTF8
    Write-Host "taskbar-pins.csv izveidots." -ForegroundColor Green
} else {
    Write-Host "taskbar-pins.csv jau eksiste - netiek mainits." -ForegroundColor Yellow
}

# 3) client-install.ps1
if (-not (Test-Path $ClientPath)) { Write-Host "KLUDA: nav atrasts $ClientPath" -ForegroundColor Red; return }
$raw = [System.IO.File]::ReadAllText($ClientPath)
if ($raw.Contains("ensure-taskbar-pins")) {
    Write-Host "client-install.ps1 : jau pielabots - izlaizu." -ForegroundColor Yellow
    return
}
$crlf = $raw.Contains("`r`n")
$text = $raw.Replace("`r`n", "`n")
$anchor = 'Write-Log "=== Klienta atjauninasana pabeigta ==="'
$cnt = ([regex]::Matches($text, [regex]::Escape($anchor))).Count
if ($cnt -ne 1) {
    Write-Host "KLUDA: enkurs atrasts $cnt reizes (gaidits 1). Nekas netika mainits." -ForegroundColor Red
    return
}
$block = @'
# Windows 11 taskbar ikonas (Config\taskbar-pins.csv). Kluda cikla neietekme.
try {
    $pinScript = Join-Path $NasRoot "Scripts\ensure-taskbar-pins.ps1"
    if (Test-Path $pinScript) { & $pinScript -NasRoot $NasRoot }
} catch {
    Write-Log "Taskbar pins: kluda - $_" "WARN"
}

'@
$text = $text.Replace($anchor, ($block.Replace("`r`n", "`n") + $anchor))
if ($crlf) { $text = $text.Replace("`n", "`r`n") }
Copy-Item $ClientPath ($ClientPath + ".bak-" + (Get-Date -Format "yyyyMMdd-HHmmss"))
[System.IO.File]::WriteAllText($ClientPath, $text, (New-Object System.Text.UTF8Encoding($true)))
Write-Host "client-install.ps1 : pielabots (rezerves kopija .bak-*)." -ForegroundColor Green
