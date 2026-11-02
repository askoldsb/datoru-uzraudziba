<#
 patch-eparaksts-heal2.ps1   (palaist VIENU REIZI uz admin PC PIUAC-ASKOLDS, ka administrators)
 Papildina iepriekseju patch-eparaksts-heal.ps1:
  - eParaksts pasalabosana tagad nosaka arii NEPILNIGU instalaciju (app mape satur < 40 .jar failu;
    pilnaja 1.11.0 ir 46), nevis tikai veco exe;
  - pirms uzstadisanas veic TIRU atinstalesanu (msiexec /x visiem eParakstitajs MSI ierakstiem + mapes dzesana),
    jo parasta parinstalesana tajaa pasaa versija nepilnigo instalaciju nelabo.
 Rezerves kopija .bak-*. Skripts ir idempotents.
#>
param(
    [string]$ClientPath = "\\PIUAC_CLOUD\Updates\Scripts\client-install.ps1"
)

if (-not (Test-Path $ClientPath)) { Write-Host "KLUDA: nav atrasts $ClientPath" -ForegroundColor Red; return }
$raw = [System.IO.File]::ReadAllText($ClientPath)
if (-not $raw.Contains("eparaksts-heal.txt")) { Write-Host "KLUDA: vispirms palaid patch-eparaksts-heal.ps1" -ForegroundColor Red; return }
if ($raw.Contains("jar faili =")) {
    Write-Host "client-install.ps1 : jau pielabots (heal2) - izlaizu." -ForegroundColor Yellow
    return
}
$crlf = $raw.Contains("`r`n")
$text = $raw.Replace("`r`n", "`n")

$old = @'
                    if ([string]::IsNullOrWhiteSpace($eFileVer) -or ([version]$eFileVer -lt [version]$latestVersion)) {
                        $healEparaksts = $true
                        Write-Log "eParaksts : registra versija aktuala, bet Program Files exe = '$eFileVer' (vecaks vai nav) - parinstaleju datoram kopigi."
'@
$old = $old.Replace("`r`n", "`n")
$cnt = ([regex]::Matches($text, [regex]::Escape($old))).Count
if ($cnt -ne 1) {
    Write-Host "KLUDA: enkurs atrasts $cnt reizes (gaidits 1). Nekas netika mainits." -ForegroundColor Red
    return
}

$new = @'
                    $eJars = @(Get-ChildItem "C:\Program Files\eparakstitajs3\app" -Recurse -Filter *.jar -File -ErrorAction SilentlyContinue).Count
                    $eOld = ([string]::IsNullOrWhiteSpace($eFileVer) -or ([version]$eFileVer -lt [version]$latestVersion))
                    if ($eOld -or ($eJars -lt 40)) {
                        $healEparaksts = $true
                        Write-Log "eParaksts : registra versija aktuala, bet Program Files exe = '$eFileVer', jar faili = $eJars - veicu tiru parinstalesanu datoram kopigi."
                        # Tira atinstalesana: nepilnigu instalaciju parasta parinstalesana nelabo.
                        Get-Process -Name "eparakstitajs3" -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
                        $eUninst = @("HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*", "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*")
                        foreach ($ePr in @(Get-ItemProperty -Path $eUninst -ErrorAction SilentlyContinue | Where-Object { ($_.DisplayName -like "eParakst*") -and ($_.DisplayName -notlike "*Token Signing*") -and ($_.WindowsInstaller -eq 1) })) {
                            $ePx = Start-Process -FilePath "msiexec.exe" -ArgumentList @("/x", $ePr.PSChildName, "/qn", "/norestart") -PassThru -WindowStyle Hidden
                            [void]$ePx.WaitForExit(180000)
                        }
                        if (Test-Path "C:\Program Files\eparakstitajs3") { Remove-Item "C:\Program Files\eparakstitajs3" -Recurse -Force -ErrorAction SilentlyContinue }
'@
$new = $new.Replace("`r`n", "`n")

$text = $text.Replace($old, $new)
if ($crlf) { $text = $text.Replace("`n", "`r`n") }
Copy-Item $ClientPath ($ClientPath + ".bak-" + (Get-Date -Format "yyyyMMdd-HHmmss"))
[System.IO.File]::WriteAllText($ClientPath, $text, (New-Object System.Text.UTF8Encoding($true)))
Write-Host "client-install.ps1 : pielabots (eParaksts tira parinstalesana + jar parbaude), rezerves kopija .bak-*." -ForegroundColor Green
