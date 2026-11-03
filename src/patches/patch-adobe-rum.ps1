<#
 patch-adobe-rum.ps1   (palaist VIENU REIZI uz admin PC PIUAC-ASKOLDS, ka administrators)
 Pielabo NAS client-install.ps1: cikla beigas (pec parvaldito lietotnu un Office, pirms
 statusa atskaites un izslegsanas) datoros no saraksta Config\adobe-rum.txt tiek palaists
 Adobe Remote Update Manager (RUM) - atjaunina VISAS uzstaditas Adobe CC lietotnes.
   - Darbojas tikai, ja grafiks atlauj ThirdPartyApps=Yes.
   - Prasa: Admin Console pakotne (Shared Device), RUM datora:
       C:\Program Files (x86)\Common Files\Adobe\OOBE_Enterprise\RemoteUpdateManager\
   - Atvertas Adobe lietotnes RUM pats izlaiz.
   - Limits $RumMaxMinutes (180 min); izvade -> C:\ProgramData\LabUpdates\State\rum-last.log,
     pedejas rindas -> cikla zurnals.
 Ja Config\adobe-rum.txt nav, tas tiek izveidots ar OPENLAB-1 un OPENLAB-2.
 Rezerves kopija .bak-*. Skripts ir idempotents.
#>
param(
    [string]$ClientPath = "\\PIUAC_CLOUD\Updates\Scripts\client-install.ps1",
    [string]$ListPath   = "\\PIUAC_CLOUD\Updates\Config\adobe-rum.txt"
)

if (-not (Test-Path $ClientPath)) { Write-Host "KLUDA: nav atrasts $ClientPath" -ForegroundColor Red; return }

if (-not (Test-Path $ListPath)) {
    $listText = "# Datori, kuros cikla beigas palaiz Adobe Remote Update Manager (viens vards rinda)`r`nOPENLAB-1`r`nOPENLAB-2`r`n"
    [System.IO.File]::WriteAllText($ListPath, $listText, (New-Object System.Text.UTF8Encoding($false)))
    Write-Host "Izveidots $ListPath (OPENLAB-1, OPENLAB-2)." -ForegroundColor Green
} else {
    Write-Host "$ListPath jau ir - nemainu."
}

$raw = [System.IO.File]::ReadAllText($ClientPath)
if ($raw.Contains("AdobeRUM :")) {
    Write-Host "client-install.ps1 : jau pielabots (AdobeRUM) - izlaizu." -ForegroundColor Yellow
    return
}
$crlf = $raw.Contains("`r`n")
$text = $raw.Replace("`r`n", "`n")

$anchor = '# Sakopsana - iztiram lokalo darba mapi'
$cnt = ([regex]::Matches($text, [regex]::Escape($anchor))).Count
if ($cnt -ne 1) {
    Write-Host "KLUDA: enkurs atrasts $cnt reizes (gaidits 1). Nekas netika mainits." -ForegroundColor Red
    return
}

$block = @'
# Adobe CC lietotnu atjauninasana ar Remote Update Manager (saraksts Config\adobe-rum.txt)
if ($schedule.ThirdPartyAppsRequested) {
    try {
        $rumListFile = Join-Path $NasRoot "Config\adobe-rum.txt"
        $rumTargets = @()
        if (Test-Path $rumListFile) {
            $rumTargets = @(Get-Content $rumListFile | ForEach-Object { $_.Trim() } | Where-Object { $_ -and -not $_.StartsWith("#") })
        }
        if ($rumTargets -contains $computerName) {
            $rumExe = "C:\Program Files (x86)\Common Files\Adobe\OOBE_Enterprise\RemoteUpdateManager\RemoteUpdateManager.exe"
            $RumMaxMinutes = 180
            if (-not (Test-Path $rumExe)) {
                Write-Log "AdobeRUM : RemoteUpdateManager nav atrasts ($rumExe) - izlaists." "WARN"
                $failedApps += "AdobeRUM (RUM nav atrasts)"
            } else {
                $rumState = "C:\ProgramData\LabUpdates\State"
                if (-not (Test-Path $rumState)) { New-Item -ItemType Directory -Path $rumState -Force | Out-Null }
                $rumOut = Join-Path $rumState "rum-last.log"
                $rumErr = Join-Path $rumState "rum-last.err.log"
                Write-Log "AdobeRUM : palaizu RemoteUpdateManager --action=install (limits $RumMaxMinutes min)..."
                $rumProc = Start-Process -FilePath $rumExe -ArgumentList "--action=install" -NoNewWindow -PassThru -RedirectStandardOutput $rumOut -RedirectStandardError $rumErr
                if (-not $rumProc.WaitForExit($RumMaxMinutes * 60 * 1000)) {
                    try { $rumProc.Kill() } catch { }
                    Write-Log "AdobeRUM : parsniegts $RumMaxMinutes min limits - process aptureets." "WARN"
                    $failedApps += "AdobeRUM (laika limits)"
                } else {
                    $rumCode = $rumProc.ExitCode
                    $rumText = ""
                    if (Test-Path $rumOut) { $rumText = [System.IO.File]::ReadAllText($rumOut) }
                    $rumTail = @($rumText -split "`r?`n" | Where-Object { $_.Trim() -and $_ -notmatch '^\*+$' } | Select-Object -Last 30)
                    foreach ($rumLine in $rumTail) { Write-Log ("AdobeRUM > " + $rumLine.Trim()) }
                    if ($rumCode -eq 0) {
                        if ($rumText -match "(?i)successfully installed") {
                            Write-Log "AdobeRUM : atjauninajumi uzstaditi (exit code 0)."
                            $installedApps += "Adobe CC lietotnes (RUM)"
                        } else {
                            Write-Log "AdobeRUM : pabeigts (exit code 0), jaunu atjauninajumu nebija."
                        }
                    } else {
                        Write-Log "AdobeRUM : beidzas ar exit code $rumCode (sk. $rumOut)." "WARN"
                        $failedApps += "AdobeRUM (exit $rumCode)"
                    }
                }
            }
        }
    } catch {
        Write-Log "AdobeRUM : kluda - $_" "WARN"
        $failedApps += "AdobeRUM (kluda)"
    }
}

'@
$text = $text.Replace($anchor, ($block.Replace("`r`n", "`n") + $anchor))
if ($crlf) { $text = $text.Replace("`n", "`r`n") }
Copy-Item $ClientPath ($ClientPath + ".bak-" + (Get-Date -Format "yyyyMMdd-HHmmss"))
[System.IO.File]::WriteAllText($ClientPath, $text, (New-Object System.Text.UTF8Encoding($true)))
Write-Host "client-install.ps1 : pielabots (AdobeRUM cikla beigas), rezerves kopija .bak-*." -ForegroundColor Green
