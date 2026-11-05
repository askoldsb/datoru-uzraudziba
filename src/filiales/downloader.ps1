<#
============================================================
 downloader.ps1
 Palaizams administratora dators (Scheduled Task, piem. katru nakti).
 Parbauda, vai winget kataloga ir jaunaka versija konkreta
 programma, un, ja ir, lejupielade instalatoru uz NAS Cache mapi.
 Atjaunina Config\versions.json ar jaunako zinamo versiju un
 relativo celu uz instalatoru.

 Prasa: winget (Windows Package Manager), pieejams Windows 11
        pec noklusejuma. Palaist ar kontu, kuram ir Read/Write
        piekluve \\PIUAC_CLOUD\Updates share.
============================================================
#>

# FILIALES VERSIJA (src/filiales/downloader.ps1): vienigas izmainas pret NAS dzivo
# versiju (2026-11-05) - $NasRoot ir parametrs (filiales hub: C:\Hub\Updates) un
# clean-logs.ps1 tiek saukts tikai, ja tas eksiste blakus.

param(
    [string]$NasRoot = "C:\Hub\Updates"
)

# ---------- KONFIGURACIJA ----------

$CacheRoot  = Join-Path $NasRoot "Cache"
$ConfigDir  = Join-Path $NasRoot "Config"
$LogDir     = Join-Path $NasRoot "Logs"
$VersionsFile = Join-Path $ConfigDir "versions.json"

# Programmas, ko pagaidam parvaldam. Atslega = ieksejais nosaukums,
# kas izmantots ari mape Cache un versions.json.
$Apps = @(
    @{ Key = "Firefox";     WingetId = "Mozilla.Firefox" },
    @{ Key = "Chrome";      WingetId = "Google.Chrome" },
    @{ Key = "Zoom";        WingetId = "Zoom.Zoom" },
    @{ Key = "TeamViewer";  WingetId = "TeamViewer.TeamViewer" },
    # TeamViewer HOST atjauninajumiem (NSIS .exe, x64). Atseviska kesmape, lai NEdzestu ar roku ieliktu
    # Host moduli Cache\TeamViewerHost\TeamViewer_Host_Setup.exe (tas paredzets TIKAI jaunai instalacijai).
    @{ Key = "TeamViewerHost"; WingetId = "TeamViewer.TeamViewer.Host"; InstallerType = "nullsoft"; Architecture = "x64"; CacheFolder = "TeamViewerHost-Update" },
    @{ Key = "VLC";         WingetId = "VideoLAN.VLC" },
    @{ Key = "eParaksts";   WingetId = "eParaksts.eParakstitajs" },
    # InstallerType = piespiez konkretu instalatora veidu (winget --installer-type).
    # PowerShell pakotne satur gan MSI (wix), gan MSIX; musu klienta kods prot tikai MSI.
    @{ Key = "PowerShell";  WingetId = "Microsoft.PowerShell"; InstallerType = "wix" }
)

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

# ---------- PALIGFUNKCIJAS ----------

function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    $line = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')  [$Level]  $Message"
    Write-Host $line
    try {
        Add-Content -Path $logFile -Value $line -Encoding UTF8
    } catch {
        Write-Host "BRIDINAJUMS: neizdevas rakstit log failu ($_)" -ForegroundColor Yellow
    }
}

function Get-WingetExePath {
    <#
        Winget parasti tiek palaists caur "App Execution Alias" mehanismu,
        kas nestrada non-interaktivas sesijas (piem., Scheduled Task,
        kas palaista "whether user is logged on or not"). Tapec seit
        atrodam un izmantojam pilnu celu uz reali instaleto winget.exe.
    #>
    $pkg = Get-AppxPackage -Name "Microsoft.DesktopAppInstaller" -AllUsers -ErrorAction SilentlyContinue |
        Sort-Object -Property Version -Descending |
        Select-Object -First 1

    if ($pkg -and $pkg.InstallLocation) {
        $exePath = Join-Path $pkg.InstallLocation "winget.exe"
        if (Test-Path $exePath) {
            return $exePath
        }
    }
    return $null
}

function Test-NasAvailable {
    param([string]$Path)
    return Test-Path -Path $Path -ErrorAction SilentlyContinue
}

function Get-WingetLatestVersion {
    <#
        Nolasa jaunako pieejamo versiju no winget, parsejot
        "winget show --id <id>" izvadi. Atgriez $null, ja neizdodas.
    #>
    param([string]$WingetId, [string]$WingetExe)

    try {
        $output = & $WingetExe show --id $WingetId --accept-source-agreements 2>$null
        $versionLine = $output | Where-Object { $_ -match '^Version:\s*(.+)$' }
        if ($versionLine) {
            return ($versionLine -replace '^Version:\s*', '').Trim()
        }
    } catch {
        Write-Log "Kluda izpildot 'winget show' prieks $WingetId : $_" "ERROR"
    }
    return $null
}

function Get-StoredVersions {
    param([string]$Path)
    if (Test-Path $Path) {
        try {
            $json = Get-Content $Path -Raw -Encoding UTF8 | ConvertFrom-Json
            # Parveido par hashtable, lai butu ergonomiski papildinat
            $result = @{}
            foreach ($prop in $json.PSObject.Properties) {
                $result[$prop.Name] = $prop.Value
            }
            return $result
        } catch {
            Write-Log "Neizdevas nolasit versions.json ($_), sakam ar tuksu." "WARN"
        }
    }
    return @{}
}

function Save-StoredVersions {
    param([hashtable]$Versions, [string]$Path)
    $Versions | ConvertTo-Json -Depth 5 | Set-Content -Path $Path -Encoding UTF8
}

# ---------- SAKUMS ----------

# Nodrosinam, ka mapes eksiste (lokali labs signals, ja NAS nav sasniedzams)
if (-not (Test-NasAvailable $NasRoot)) {
    Write-Host "NAS ($NasRoot) nav sasniedzams. Beidzam darbu, mekleisim nakamaja reize." -ForegroundColor Red
    exit 1
}

foreach ($dir in @($CacheRoot, $ConfigDir, $LogDir)) {
    if (-not (Test-Path $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
}

Write-Log "=== Downloader sakts ==="

$wingetExe = Get-WingetExePath
if (-not $wingetExe) {
    Write-Log "Neizdevas atrast winget.exe (Microsoft.DesktopAppInstaller pakotni). Beidzam darbu." "ERROR"
    exit 1
}
Write-Log "Izmantoju winget: $wingetExe"

$versions = Get-StoredVersions -Path $VersionsFile
$changed = $false

foreach ($app in $Apps) {
    $key = $app.Key
    $wingetId = $app.WingetId

    Write-Log "Parbaudu: $key ($wingetId)"

    $latest = Get-WingetLatestVersion -WingetId $wingetId -WingetExe $wingetExe
    if (-not $latest) {
        Write-Log "Neizdevas noteikt jaunako versiju prieks $key, izlaizu." "WARN"
        continue
    }

    $currentEntry = $versions[$key]
    $currentVersion = if ($currentEntry) { $currentEntry.version } else { $null }

    if ($currentVersion -eq $latest) {
        Write-Log "$key jau ir jaunaka versija ($latest), lejupielade nav vajadziga."
        continue
    }

    Write-Log "$key : jauna versija pieejama ($currentVersion -> $latest). Lejupieladeju..."

    $cacheFolder = $key
    if ($app.CacheFolder) { $cacheFolder = [string]$app.CacheFolder }
    $appCacheDir = Join-Path $CacheRoot $cacheFolder
    if (-not (Test-Path $appCacheDir)) {
        New-Item -ItemType Directory -Path $appCacheDir -Force | Out-Null
    }

    # Pagaidu lokala mape lejupieladei - izvairamies rakstit
    # tiesi NAS uz laiku, kamer fails vel nav pilns.
    $tempDir = Join-Path $env:TEMP "winget-dl-$key-$(Get-Random)"
    New-Item -ItemType Directory -Path $tempDir -Force | Out-Null

    try {
        $dlArgs = @(
            "download",
            "--id", $wingetId,
            "--version", $latest,
            "--download-directory", $tempDir,
            "--accept-source-agreements",
            "--accept-package-agreements"
        )
        if ($app.InstallerType) {
            $dlArgs += @("--installer-type", [string]$app.InstallerType)
            Write-Log "$key : piespiezu instalatora veidu '$($app.InstallerType)'."
        }
        if ($app.Architecture) {
            $dlArgs += @("--architecture", [string]$app.Architecture)
        }
        $process = Start-Process -FilePath $wingetExe -ArgumentList $dlArgs -Wait -PassThru -NoNewWindow

        if ($process.ExitCode -ne 0) {
            Write-Log "$key : winget download atgrieza kludas kodu $($process.ExitCode)." "ERROR"
            continue
        }

        $allFiles = Get-ChildItem -Path $tempDir -File -Recurse
        Write-Log "$key : lejupieladei mape satur $($allFiles.Count) failu(s): $(($allFiles | ForEach-Object { $_.Name }) -join ', ')"

        # Izslegam zinamos metadatu failus (nav pasi instalatori), un no
        # atlikusajiem pazemam lielako failu - tas parasti ir instalators,
        # neatkarigi no konkreta paplasinajuma (.exe/.msi/.msix/.zip/...).
        # Informativi: ieraksta manifesta instalatora veidu/sledzus loga (palidz parbaudit SilentArgs CSV)
        foreach ($y in ($allFiles | Where-Object { $_.Extension -in ".yaml", ".yml" })) {
            $yl = Select-String -Path $y.FullName -Pattern '^\s*-?\s*(InstallerType|Silent|SilentWithProgress|Architecture|Scope):' -ErrorAction SilentlyContinue |
                  ForEach-Object { $_.Line.Trim() } | Select-Object -First 12
            Write-Log "$key : manifests $($y.Name) -> $($yl -join ' | ')"
        }
        $metaExtensions = @(".yaml", ".yml", ".json", ".txt", ".log", ".xml")
        $candidates = $allFiles | Where-Object { $metaExtensions -notcontains $_.Extension.ToLower() }

        if (-not $candidates) {
            Write-Log "$key : lejupieladei nav atrasts instalacijas fails (tikai metadatu faili vai tukss)." "ERROR"
            continue
        }

        # Notirit veco versiju cache (paturam tikai jaunako, lai netaisitu nevajadzigu apjomu)
        Get-ChildItem -Path $appCacheDir -File -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue

        $mainInstaller = $candidates | Sort-Object Length -Descending | Select-Object -First 1
        $destPath = Join-Path $appCacheDir $mainInstaller.Name
        Copy-Item -Path $mainInstaller.FullName -Destination $destPath -Force

        # Papildus faili (piem., yaml apraksts) - kopejam ari, informativi
        foreach ($f in $candidates | Where-Object { $_.FullName -ne $mainInstaller.FullName }) {
            Copy-Item -Path $f.FullName -Destination (Join-Path $appCacheDir $f.Name) -Force
        }

        $relativePath = "Cache\$cacheFolder\$($mainInstaller.Name)"

        $versions[$key] = @{
            version      = $latest
            fileName     = $mainInstaller.Name
            relativePath = $relativePath
            updatedAt    = (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
        }
        $changed = $true

        Write-Log "$key : lejupielade veiksmiga -> $relativePath (versija $latest)."

    } catch {
        Write-Log "$key : neparedzeta kluda - $_" "ERROR"
    } finally {
        Remove-Item -Path $tempDir -Recurse -Force -ErrorAction SilentlyContinue
    }
}

if ($changed) {
    Save-StoredVersions -Versions $versions -Path $VersionsFile
    Write-Log "versions.json atjaunots."
} else {
    Write-Log "Nekas nav mainijies, versions.json netiek pariakstits."
}

Write-Log "=== Downloader pabeigts ==="

# Zurnalu sakopsana (neinteresanto dzesana)
$cleanLogs = Join-Path $PSScriptRoot 'clean-logs.ps1'
if (Test-Path $cleanLogs) {
    try { & $cleanLogs -Apply } catch { Write-Host "clean-logs kluda: $_" }
}

