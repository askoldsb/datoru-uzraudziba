<#
 patch-eparaksts-heal.ps1   (palaist VIENU REIZI uz admin PC PIUAC-ASKOLDS, ka administrators)
 Problema: eParakstitajs registra (ARP) rada aktualo versiju (piem. 1.11.0), bet faktiskais
 C:\Program Files\eparakstitajs3\eparakstitajs3.exe ir vecs (1.10.0), jo jaunaka versija tika uzstadita
 tikai lietotaja profila. Klienta cikls tada gadijuma neko nedara.
 Risinajums: NAS client-install.ps1 eParaksts bloka - ja registra versija ir aktuala, bet exe ir vecaks
 vai nav, tiek palaists tas pats MSI (jau ar ALLUSERS=1) un exe tiek atjaunots. Mekinajums ne biezak
 ka 1 reizi dienaa (marker C:\ProgramData\LabUpdates\eparaksts-heal.txt), lai nav ciklu.
 Rezerves kopija .bak-*. Skripts ir idempotents.
#>
param(
    [string]$ClientPath = "\\PIUAC_CLOUD\Updates\Scripts\client-install.ps1"
)

if (-not (Test-Path $ClientPath)) { Write-Host "KLUDA: nav atrasts $ClientPath" -ForegroundColor Red; return }
$raw = [System.IO.File]::ReadAllText($ClientPath)
if ($raw.Contains("eparaksts-heal.txt")) {
    Write-Host "client-install.ps1 : jau pielabots - izlaizu." -ForegroundColor Yellow
    return
}
$crlf = $raw.Contains("`r`n")
$text = $raw.Replace("`r`n", "`n")

$old = @'
    if (-not (Compare-Versions -Installed $installedVersion -Latest $latestVersion)) {
        Write-Log "$key : jau aktuala versija, instalesana nav vajadziga."
        continue
    }
'@
$old = $old.Replace("`r`n", "`n")
$cnt = ([regex]::Matches($text, [regex]::Escape($old))).Count
if ($cnt -ne 1) {
    Write-Host "KLUDA: enkurs atrasts $cnt reizes (gaidits 1). Nekas netika mainits." -ForegroundColor Red
    return
}

$new = @'
    $healEparaksts = $false
    if (-not (Compare-Versions -Installed $installedVersion -Latest $latestVersion)) {
        # eParaksts: registrs rada aktualo versiju, bet C:\Program Files exe var but vecs (versija uzstadita tikai
        # lietotaja profila). Tada gadijuma parinstalejam datoram kopigi (ne biezak ka 1 reizi dienaa).
        if ($key -eq "eParaksts") {
            try {
                $eExe = "C:\Program Files\eparakstitajs3\eparakstitajs3.exe"
                $eMarker = "C:\ProgramData\LabUpdates\eparaksts-heal.txt"
                $eStamp = "$latestVersion|" + (Get-Date -Format "yyyyMMdd")
                $eDone = ""
                if (Test-Path $eMarker) { $eDone = [string](Get-Content $eMarker -ErrorAction SilentlyContinue | Select-Object -First 1) }
                if ($eDone -ne $eStamp) {
                    $eFileVer = ""
                    if (Test-Path $eExe) { $eFileVer = [string](Get-Item $eExe).VersionInfo.FileVersion }
                    if ([string]::IsNullOrWhiteSpace($eFileVer) -or ([version]$eFileVer -lt [version]$latestVersion)) {
                        $healEparaksts = $true
                        Write-Log "eParaksts : registra versija aktuala, bet Program Files exe = '$eFileVer' (vecaks vai nav) - parinstaleju datoram kopigi."
                        if (-not (Test-Path (Split-Path $eMarker))) { New-Item -ItemType Directory -Path (Split-Path $eMarker) -Force | Out-Null }
                        Set-Content -Path $eMarker -Value $eStamp -Encoding ASCII
                    }
                }
            } catch {
                Write-Log "eParaksts : exe parbaude neizdevas - $_" "WARN"
            }
        }
        if (-not $healEparaksts) {
            Write-Log "$key : jau aktuala versija, instalesana nav vajadziga."
            continue
        }
    }
'@
$new = $new.Replace("`r`n", "`n")

$text = $text.Replace($old, $new)
if ($crlf) { $text = $text.Replace("`n", "`r`n") }
Copy-Item $ClientPath ($ClientPath + ".bak-" + (Get-Date -Format "yyyyMMdd-HHmmss"))
[System.IO.File]::WriteAllText($ClientPath, $text, (New-Object System.Text.UTF8Encoding($true)))
Write-Host "client-install.ps1 : pielabots (eParaksts exe pasalabosana), rezerves kopija .bak-*." -ForegroundColor Green
