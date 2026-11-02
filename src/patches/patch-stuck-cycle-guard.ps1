<#
 patch-stuck-cycle-guard.ps1
 Palaizams VIENU REIZI no administratora datora.
 Pielabo NAS faila Scripts\client-install.ps1 mutex bloku: ja cits cikls darbojas
 ilgak par $MaxCycleHours stundam, tas tiek apturets un sis cikls turpinas.
 Citas izmainas (ieskaitot TeamViewer tokenu) netiek skartas. Pirms izmainam - rezerves kopija.
#>
param(
    [string]$Path = "\\192.168.3.31\Updates\Scripts\client-install.ps1"
)

$old = @'
    if (-not $mutexCreated) {
        Write-Log "Cits klienta skripta cikls jau darbojas sim datoram - so palaisanu izlaizu."
        exit 0
    }
'@

$new = @'
    if (-not $mutexCreated) {
        # Iestregusa cikla aizsardziba: ja vecais cikls darbojas ilgak par $MaxCycleHours h, to apturam.
        $MaxCycleHours = 4
        $stale = @(Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" -ErrorAction SilentlyContinue |
            Where-Object { $_.ProcessId -ne $PID -and $_.CommandLine -like "*client-install.ps1*" -and $_.CreationDate -lt (Get-Date).AddHours(-$MaxCycleHours) })
        if ($stale.Count -eq 0) {
            Write-Log "Cits klienta skripta cikls jau darbojas sim datoram - so palaisanu izlaizu."
            exit 0
        }
        foreach ($p in $stale) {
            Write-Log ("Iestregis cikls (PID {0}, sakts {1}) darbojas ilgak par {2} h - apturu." -f $p.ProcessId, $p.CreationDate, $MaxCycleHours) "WARN"
            Get-CimInstance Win32_Process -Filter "ParentProcessId=$($p.ProcessId)" -ErrorAction SilentlyContinue | ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
            Stop-Process -Id $p.ProcessId -Force -ErrorAction SilentlyContinue
        }
        try { [void]$instanceMutex.WaitOne(15000) } catch [System.Threading.AbandonedMutexException] { }
    }
'@

if (-not (Test-Path $Path)) { Write-Host "KLUDA: nav atrasts $Path" -ForegroundColor Red; exit 1 }
$raw = [System.IO.File]::ReadAllText($Path)
if ($raw -like "*Iestregusa cikla aizsardziba*") { Write-Host "Jau pielabots - nekas nav jadara." -ForegroundColor Yellow; exit 0 }

# darbojas gan ar CRLF, gan LF
$crlf = $raw.Contains("`r`n")
$oldN = $old.Replace("`r`n", "`n"); $newN = $new.Replace("`r`n", "`n")
if ($crlf) { $oldN = $oldN.Replace("`n", "`r`n"); $newN = $newN.Replace("`n", "`r`n") }

if (-not $raw.Contains($oldN)) { Write-Host "KLUDA: mutex bloks faila nav atrasts (fails ir mainits?). Nekas netika mainits." -ForegroundColor Red; exit 1 }

Copy-Item $Path ($Path + ".bak-" + (Get-Date -Format "yyyyMMdd-HHmmss"))
$out = $raw.Replace($oldN, $newN)
$enc = New-Object System.Text.UTF8Encoding($true)
[System.IO.File]::WriteAllText($Path, $out, $enc)
Write-Host "Gatavs: client-install.ps1 pielabots (rezerves kopija .bak-*)." -ForegroundColor Green
