<#
============================================================
 create-desktop-shortcut.ps1
 Izveido saisni uz darbvirsmas, kas palaiz config-panel.ps1
 bez nepieciesamibas rakstit komandu katru reizi.

 Palaizams VIENU REIZI administratora dator.
============================================================
#>

param(
    [string]$ScriptPath = "C:\Scripts\config-panel.ps1",
    [string]$ShortcutName = "Atjauninasanas panelis"
)

if (-not (Test-Path $ScriptPath)) {
    Write-Host "KLUDA: $ScriptPath nav atrasts. Parliecinieties, ka config-panel.ps1 ir sajaa cela." -ForegroundColor Red
    exit 1
}

$desktopPath = [Environment]::GetFolderPath("Desktop")
$shortcutPath = Join-Path $desktopPath "$ShortcutName.lnk"

try {
    $WshShell = New-Object -ComObject WScript.Shell
    $Shortcut = $WshShell.CreateShortcut($shortcutPath)
    $Shortcut.TargetPath = "powershell.exe"
    $Shortcut.Arguments = '-WindowStyle Hidden -ExecutionPolicy Bypass -File "' + $ScriptPath + '"'
    $Shortcut.WorkingDirectory = Split-Path $ScriptPath -Parent
    $Shortcut.IconLocation = "shell32.dll,21"
    $Shortcut.Description = "Atver atjauninasanas grafika kontrolpaneli"
    $Shortcut.Save()

    Write-Host "Saisne izveidota: $shortcutPath" -ForegroundColor Green
    Write-Host "Tagad varat palaist paneli ar dubultklikskj uz darbvirsmas ikonas '$ShortcutName'."
} catch {
    Write-Host "KLUDA izveidojot saisni: $_" -ForegroundColor Red
    exit 1
}
