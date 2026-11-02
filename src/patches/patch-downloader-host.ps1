<#
 patch-downloader-host.ps1
 Pielabo downloader.ps1 (administratora datora): pievieno TeamViewer HOST (winget TeamViewer.TeamViewer.Host,
 NSIS exe, x64) atseviska kesmape Cache\TeamViewerHost-Update; ar roku ielikta Host moduli netiek dzesta.
 Pirms izmainam tiek izveidota rezerves kopija .bak-*. Palaist VIENU REIZI.
#>
param(
    [string]$Path = "C:\Scripts\downloader.ps1"
)

if (-not (Test-Path $Path)) { Write-Host "KLUDA: nav atrasts $Path" -ForegroundColor Red; exit 1 }
$raw = [System.IO.File]::ReadAllText($Path)
if ($raw.Contains("TeamViewerHost-Update")) { Write-Host "Jau pielabots - nekas nav jadara." -ForegroundColor Yellow; exit 0 }

$crlf = $raw.Contains("`r`n")
$text = $raw.Replace("`r`n", "`n")
$edits = @()
$a1 = @'
    @{ Key = "TeamViewer";  WingetId = "TeamViewer.TeamViewer" },
'@
$n1 = @'
    @{ Key = "TeamViewer";  WingetId = "TeamViewer.TeamViewer" },
    # TeamViewer HOST atjauninajumiem (NSIS .exe, x64). Atseviska kesmape, lai NEdzestu ar roku ieliktu
    # Host moduli Cache\TeamViewerHost\TeamViewer_Host_Setup.exe (tas paredzets TIKAI jaunai instalacijai).
    @{ Key = "TeamViewerHost"; WingetId = "TeamViewer.TeamViewer.Host"; InstallerType = "nullsoft"; Architecture = "x64"; CacheFolder = "TeamViewerHost-Update" },
'@
$edits += ,@($a1, $n1)
$a2 = @'
    $appCacheDir = Join-Path $CacheRoot $key
'@
$n2 = @'
    $cacheFolder = $key
    if ($app.CacheFolder) { $cacheFolder = [string]$app.CacheFolder }
    $appCacheDir = Join-Path $CacheRoot $cacheFolder
'@
$edits += ,@($a2, $n2)
$a3 = @'
        $relativePath = "Cache\$key\$($mainInstaller.Name)"
'@
$n3 = @'
        $relativePath = "Cache\$cacheFolder\$($mainInstaller.Name)"
'@
$edits += ,@($a3, $n3)
$a4 = @'
            Write-Log "$key : piespiezu instalatora veidu '$($app.InstallerType)'."
        }
'@
$n4 = @'
            Write-Log "$key : piespiezu instalatora veidu '$($app.InstallerType)'."
        }
        if ($app.Architecture) {
            $dlArgs += @("--architecture", [string]$app.Architecture)
        }
'@
$edits += ,@($a4, $n4)

foreach ($e in $edits) {
    $old = [string]$e[0]; $new = [string]$e[1]
    $cnt = ([regex]::Matches($text, [regex]::Escape($old))).Count
    if ($cnt -ne 1) {
        Write-Host ("KLUDA: anchor atrasts {0} reizes (gaidits 1): {1}" -f $cnt, $old.Trim()) -ForegroundColor Red
        Write-Host "Fails ir mainits kops ta pielabosanas? Nekas netika mainits." -ForegroundColor Red
        exit 1
    }
    $text = $text.Replace($old, $new)
}

if ($crlf) { $text = $text.Replace("`n", "`r`n") }
Copy-Item $Path ($Path + ".bak-" + (Get-Date -Format "yyyyMMdd-HHmmss"))
[System.IO.File]::WriteAllText($Path, $text, (New-Object System.Text.UTF8Encoding($true)))
Write-Host "Gatavs: downloader.ps1 pielabots ar TeamViewer Host (rezerves kopija .bak-*)." -ForegroundColor Green
