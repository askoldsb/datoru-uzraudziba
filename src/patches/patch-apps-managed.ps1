<#
 patch-apps-managed.ps1   (palaist VIENU REIZI uz admin PC PIUAC-ASKOLDS, ka administrators)
 1) Pielabo C:\Scripts\downloader.ps1: papildus programmas lasa no NAS Config\apps-managed.csv
 2) Pielabo NAS Scripts\client-install.ps1: tas pats CSV; InstallType "auto"; exit 1638/1641 = OK
 3) Nokope apps-managed.csv uz NAS Config (ja tur vel nav)
 Katram failam pirms izmainam tiek izveidota rezerves kopija .bak-*. Ja kads enkurs nav atrasts - nekas netiek mainits.
 Pirmaja versija programmas ar aizpilditu Targets darbojas TIKAI uz noraditajiem datoriem (testa aplis).
#>
param(
    [string]$DownloaderPath = "C:\Scripts\downloader.ps1",
    [string]$ClientPath     = "\\PIUAC_CLOUD\Updates\Scripts\client-install.ps1",
    [string]$CsvSource      = "C:\Scripts\apps-managed.csv",
    [string]$CsvTarget      = "\\PIUAC_CLOUD\Updates\Config\apps-managed.csv"
)

function Apply-Edits {
    param([string]$Path, [string]$Marker, [array]$Edits, [string]$Title)
    if (-not (Test-Path $Path)) { Write-Host "KLUDA: nav atrasts $Path" -ForegroundColor Red; return $false }
    $raw = [System.IO.File]::ReadAllText($Path)
    if ($raw.Contains($Marker)) { Write-Host "$Title : jau pielabots - izlaizu." -ForegroundColor Yellow; return $true }
    $crlf = $raw.Contains("`r`n")
    $text = $raw.Replace("`r`n", "`n")
    foreach ($e in $Edits) {
        $old = [string]$e[0]; $new = [string]$e[1]
        if ($e.Count -gt 2 -and $e[2] -eq "optional" -and $text -match $e[3]) { continue }
        $cnt = ([regex]::Matches($text, [regex]::Escape($old))).Count
        if ($cnt -ne 1) {
            Write-Host ("KLUDA ({0}): enkurs atrasts {1} reizes (gaidits 1): {2}" -f $Title, $cnt, $old.Trim()) -ForegroundColor Red
            Write-Host "Nekas netika mainits." -ForegroundColor Red
            return $false
        }
        $text = $text.Replace($old, $new)
    }
    if ($crlf) { $text = $text.Replace("`n", "`r`n") }
    Copy-Item $Path ($Path + ".bak-" + (Get-Date -Format "yyyyMMdd-HHmmss"))
    [System.IO.File]::WriteAllText($Path, $text, (New-Object System.Text.UTF8Encoding($true)))
    Write-Host "$Title : pielabots (rezerves kopija .bak-*)." -ForegroundColor Green
    return $true
}

# ---------------- DOWNLOADER ----------------
$d = @()
$a = @'
$logFile = Join-Path $LogDir "downloader-$(Get-Date -Format yyyyMMdd-HHmmss).log"
'@
$n = @'
$logFile = Join-Path $LogDir "downloader-$(Get-Date -Format yyyyMMdd-HHmmss).log"

# --- apps-managed.csv: papildus programmas (Enabled=1) ---
$managedCsv = Join-Path $ConfigDir "apps-managed.csv"
if (Test-Path $managedCsv) {
    try {
        foreach ($row in @(Import-Csv -Path $managedCsv -Encoding UTF8)) {
            if ([string]$row.Enabled -ne "1") { continue }
            if ([string]::IsNullOrWhiteSpace($row.Key) -or [string]::IsNullOrWhiteSpace($row.WingetId)) { continue }
            if ($Apps | Where-Object { $_.Key -eq $row.Key }) { continue }
            $m = @{ Key = [string]$row.Key; WingetId = [string]$row.WingetId }
            if ($row.DlInstallerType) { $m.InstallerType = [string]$row.DlInstallerType }
            if ($row.Architecture)    { $m.Architecture   = [string]$row.Architecture }
            $Apps += $m
        }
    } catch {
        Write-Host "BRIDINAJUMS: neizdevas nolasit apps-managed.csv ($_)" -ForegroundColor Yellow
    }
}
'@
$d += ,@($a, $n)

$a = @'
        $metaExtensions = @(".yaml", ".yml", ".json", ".txt", ".log", ".xml")
'@
$n = @'
        # Informativi: ieraksta manifesta instalatora veidu/sledzus loga (palidz parbaudit SilentArgs CSV)
        foreach ($y in ($allFiles | Where-Object { $_.Extension -in ".yaml", ".yml" })) {
            $yl = Select-String -Path $y.FullName -Pattern '^\s*-?\s*(InstallerType|Silent|SilentWithProgress|Architecture|Scope):' -ErrorAction SilentlyContinue |
                  ForEach-Object { $_.Line.Trim() } | Select-Object -First 12
            Write-Log "$key : manifests $($y.Name) -> $($yl -join ' | ')"
        }
        $metaExtensions = @(".yaml", ".yml", ".json", ".txt", ".log", ".xml")
'@
$d += ,@($a, $n)

# Architecture atbalsts, ja vel nav (patch-downloader-host.ps1 to jau var but pievienojis)
$a = @'
            Write-Log "$key : piespiezu instalatora veidu '$($app.InstallerType)'."
        }
'@
$n = @'
            Write-Log "$key : piespiezu instalatora veidu '$($app.InstallerType)'."
        }
        if ($app.Architecture) {
            $dlArgs += @("--architecture", [string]$app.Architecture)
        }
'@
$raw = if (Test-Path $DownloaderPath) { [System.IO.File]::ReadAllText($DownloaderPath) } else { "" }
if ($raw -notmatch 'app\.Architecture') { $d += ,@($a, $n) }

$ok1 = Apply-Edits -Path $DownloaderPath -Marker "apps-managed.csv" -Edits $d -Title "downloader.ps1"

# ---------------- CLIENT ----------------
$c = @()
$a = @'
# TeamViewer piesaistes parametri jabuv nodefinet SEIT
'@
$n = @'
# --- apps-managed.csv: papildus programmas no NAS (Enabled=1) ---
# Targets (ja aizpildits) = datoru vardi, kuros programma tiek apstradata (testa aplis); tukss = visi.
$managedCsvPath = Join-Path $NasRoot "Config\apps-managed.csv"
if (Test-Path $managedCsvPath) {
    try {
        foreach ($row in @(Import-Csv -Path $managedCsvPath -Encoding UTF8)) {
            if ([string]$row.Enabled -ne "1") { continue }
            if ([string]::IsNullOrWhiteSpace($row.Key) -or [string]::IsNullOrWhiteSpace($row.DisplayNamePattern)) { continue }
            if ($Apps | Where-Object { $_.Key -eq $row.Key }) { continue }
            if (-not [string]::IsNullOrWhiteSpace($row.Targets)) {
                $tg = @($row.Targets -split '[;,]' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
                if ($tg.Count -gt 0 -and ($tg -notcontains $env:COMPUTERNAME)) { continue }
            }
            $m = @{
                Key                = [string]$row.Key
                DisplayNamePattern = [string]$row.DisplayNamePattern
                InstallType        = $(if ($row.InstallType) { [string]$row.InstallType } else { "auto" })
                SilentArgs         = @(([string]$row.SilentArgs) -split '\s+' | Where-Object { $_ })
            }
            if ($row.ExcludePattern) { $m.ExcludePattern = [string]$row.ExcludePattern }
            if ([string]$row.Mode -ne "Install") { $m.UpdateOnly = $true }
            $Apps += $m
        }
    } catch {
        Write-Host "BRIDINAJUMS: neizdevas nolasit apps-managed.csv ($_)" -ForegroundColor Yellow
    }
}

# TeamViewer piesaistes parametri jabuv nodefinet SEIT
'@
$c += ,@($a, $n)

$a = @'
    switch ($InstallType) {
'@
$n = @'
    # "auto": .msi -> msi, citi -> exe ar SilentArgs no CSV
    if ($InstallType -eq "auto") { $InstallType = $(if ($localFile -like "*.msi") { "msi" } else { "exe" }) }
    if ($InstallType -eq "msi" -and (-not $SilentArgs -or $SilentArgs.Count -eq 0)) { $SilentArgs = @("/qn", "/norestart") }
    if ($InstallType -eq "exe" -and (-not $SilentArgs -or $SilentArgs.Count -eq 0)) {
        Write-Log "$Key : nav noradits SilentArgs exe instalatoram (apps-managed.csv) - izlaizu." "ERROR"
        return -1
    }

    switch ($InstallType) {
'@
$c += ,@($a, $n)

$a = @'
    if ($exitCode -eq 0 -or $exitCode -eq 3010) {
'@
$n = @'
    # 1638 = jau uzstadita ta pati/jaunaka versija; 1641 = veiksmigi, restarts iniciets
    if ($exitCode -eq 0 -or $exitCode -eq 3010 -or $exitCode -eq 1638 -or $exitCode -eq 1641) {
'@
$c += ,@($a, $n)

$ok2 = Apply-Edits -Path $ClientPath -Marker "apps-managed.csv" -Edits $c -Title "client-install.ps1"

# ---------------- CSV uz NAS ----------------
if ($ok1 -and $ok2) {
    if (Test-Path $CsvTarget) {
        Write-Host "apps-managed.csv NAS jau eksiste - NEparrakstu (labo to tiesi NAS)." -ForegroundColor Yellow
    } elseif (Test-Path $CsvSource) {
        Copy-Item $CsvSource $CsvTarget
        Write-Host "apps-managed.csv nokopets uz NAS Config." -ForegroundColor Green
    } else {
        Write-Host "BRIDINAJUMS: nav atrasts $CsvSource - nokope CSV uz NAS Config ar roku." -ForegroundColor Yellow
    }
}
