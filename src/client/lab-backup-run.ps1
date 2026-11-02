<#
 lab-backup-run.ps1   (2. versija - rokas rezims + automatiskais rezims)

 Profila darba vides kopija uz NAS (restic).

 Automatiskais rezims (-Unattended): to palaiz Scheduled Task "LabProfileBackup" (labupdate konts).
   - akreditacijas nolasa no C:\ProgramData\LabBackup\secrets.dat (DPAPI, LocalMachine) + config.json
   - nekopee biezak ka reizi $MinHoursBetween stundas (ja pedeja kopija veiksmiga)
   - ja NAS nav pieejams - kluss iziet (uzdevums meginas velreiz pec stundas)
   - PST skenesana visos diskos tikai reizi $PstScanEveryDays dienas, pa starplaiku lieto kesu
   - zema prioritate (BelowNormal)
   - statuss: C:\ProgramData\LabBackup\status.json un \\NAS\ProfiluKopijas\_status\<DATORS>.json

 Rokas rezims: -NasCred -RepoPassword -NasHost (kaa lidz sim).
 Versiju ierobezosanu (forget/prune) klienti NEVEIC - to dara lab-backup-prune.ps1 no admin datora.
#>
param(
    [pscredential]$NasCred,
    [securestring]$RepoPassword,
    [string]$NasHost,
    [string]$Share = "ProfiluKopijas",
    [string]$BaseDir = "C:\ProgramData\LabBackup",
    [string]$NasRoot = "\\192.168.3.31\Updates",
    [switch]$Unattended,
    [switch]$Force,
    [switch]$SkipCollect,
    [switch]$DryRun,
    [int]$MinHoursBetween = 18,
    [int]$PstScanEveryDays = 7
)

$ErrorActionPreference = "Continue"
$comp = $env:COMPUTERNAME
$stateDir = Join-Path $BaseDir "state"
$restic = Join-Path $BaseDir "restic.exe"
$log = Join-Path $BaseDir "backup.log"
$stampFile = Join-Path $BaseDir "last-success.json"
$pstCache = Join-Path $BaseDir "pst-cache.csv"
$started = Get-Date

if (-not (Test-Path $BaseDir)) { New-Item -ItemType Directory -Path $BaseDir -Force | Out-Null }
if ((Test-Path $log) -and ((Get-Item $log).Length -gt 2MB)) { Move-Item $log ($log + ".old") -Force -ErrorAction SilentlyContinue }

function Log([string]$m) {
    $l = "{0:yyyy-MM-dd HH:mm:ss} {1}" -f (Get-Date), $m
    Add-Content -Path $log -Value $l -Encoding UTF8
    Write-Host $l
}

# viens vienlaicigs palaidums
$mutexCreated = $false
$mutex = New-Object System.Threading.Mutex($true, "Global\LabProfileBackup", [ref]$mutexCreated)
if (-not $mutexCreated) { Log "Cita kopesana jau darbojas - iziet"; return }

$status = [ordered]@{ Computer = $comp; Started = $started.ToString("s"); Result = "FAILED"; Detail = ""; Snapshot = ""; Added = ""; Mode = $(if ($Unattended) { "auto" } else { "manual" }) }
$unc = $null

try {
    try { (Get-Process -Id $PID).PriorityClass = 'BelowNormal' } catch { }

    # ---------- akreditacijas ----------
    if ($Unattended) {
        Add-Type -AssemblyName System.Security
        $cfg = Get-Content (Join-Path $BaseDir "config.json") -Raw | ConvertFrom-Json
        $blob = [IO.File]::ReadAllBytes((Join-Path $BaseDir "secrets.dat"))
        $sec = [Text.Encoding]::UTF8.GetString([Security.Cryptography.ProtectedData]::Unprotect($blob, $null, 'LocalMachine')) | ConvertFrom-Json
        $NasHost = $cfg.NasHost; $Share = $cfg.Share
        if ($cfg.NasRoot) { $NasRoot = $cfg.NasRoot }
        $nasUser = $sec.NasUser; $nasPass = $sec.NasPass; $repoPass = $sec.RepoPass

        if ((-not $Force) -and (Test-Path $stampFile)) {
            $last = [datetime](Get-Content $stampFile -Raw | ConvertFrom-Json).Time
            if (((Get-Date) - $last).TotalHours -lt $MinHoursBetween) {
                Log ("Pedeja veiksmiga kopija pirms {0:N1} h - izlaizu" -f ((Get-Date) - $last).TotalHours)
                $status.Result = "SKIPPED"
                return
            }
        }
    } else {
        if (-not $NasCred -or -not $RepoPassword -or -not $NasHost) { throw "rokas rezima vajag -NasCred -RepoPassword -NasHost" }
        $nasUser = $NasCred.UserName
        $nasPass = $NasCred.GetNetworkCredential().Password
        $repoPass = (New-Object System.Net.NetworkCredential("", $RepoPassword)).Password
    }

    # ---------- restic.exe (no NAS, ja pieejams un atskiras) ----------
    $src = Join-Path $NasRoot "Tools\restic.exe"
    try {
        if (Test-Path -LiteralPath $src) {
            $si = Get-Item -LiteralPath $src
            if ((-not (Test-Path $restic)) -or ((Get-Item $restic).Length -ne $si.Length)) {
                Copy-Item -LiteralPath $src -Destination $restic -Force
                Log "restic.exe atjaunots no NAS"
            }
        }
    } catch { Log ("restic.exe kopesana neizdevas: " + $_.Exception.Message) }
    if (-not (Test-Path $restic)) { throw "nav restic.exe ($restic)" }

    # ---------- NAS pieslegums ----------
    $unc = "\\$NasHost\$Share"
    & net.exe use $unc /delete /y 2>&1 | Out-Null
    $o = & net.exe use $unc /user:$nasUser $nasPass /persistent:no 2>&1
    if ($LASTEXITCODE -ne 0) {
        $unc = $null
        if ($Unattended) { Log ("NAS nav pieejams (mekles velreiz): " + (($o -join ' ').Trim())); $status.Result = "NO-NAS"; return }
        throw ("net use kluda: " + ($o -join ' '))
    }
    Log "NAS pieslegts: $unc"

    # ---------- stavoklis ----------
    if (-not $SkipCollect) {
        $collect = Join-Path $PSScriptRoot "lab-backup-collect.ps1"
        if (-not (Test-Path $collect)) { $collect = Join-Path $BaseDir "lab-backup-collect.ps1" }
        $skipScan = $false
        if ($Unattended -and (Test-Path $pstCache) -and (((Get-Date) - (Get-Item $pstCache).LastWriteTime).TotalDays -lt $PstScanEveryDays)) { $skipScan = $true }
        Log ("Sagatavoju stavokli (" + $collect + "), PST pilna skenesana: " + (-not $skipScan))
        & $collect -StateDir $stateDir -SkipPstScan:$skipScan -PstCache $pstCache | Out-Null
    }
    if (-not (Test-Path (Join-Path $stateDir "backup-paths.txt"))) { throw "nav backup-paths.txt" }

    # ---------- restic ----------
    $env:RESTIC_REPOSITORY = "$unc\$comp"
    $env:RESTIC_PASSWORD = $repoPass
    $env:RESTIC_CACHE_DIR = Join-Path $BaseDir "cache"
    $env:RESTIC_PROGRESS_FPS = "0.0166"

    $repoDir = Join-Path $unc $comp
    if (Test-Path -LiteralPath (Join-Path $repoDir 'config')) {
        $o = & $restic cat config 2>&1
        if ($LASTEXITCODE -ne 0) { throw ("repozitorijs eksiste, bet nevar atvert (nepareiza restic parole?): " + (($o | Select-Object -Last 2) -join ' ')) }
    } else {
        Log "Repozitorijs nav atrasts - veidoju jaunu"
        $o = & $restic init 2>&1
        if ($LASTEXITCODE -ne 0) { throw ("restic init: " + ($o -join ' ')) }
    }

    $bargs = @('backup', '--files-from', (Join-Path $stateDir 'backup-paths.txt'), '--exclude-file', (Join-Path $stateDir 'exclude.txt'),
               '--use-fs-snapshot', '--exclude-caches', '--host', $comp, '--tag', 'profils')
    if ($DryRun) { $bargs += '--dry-run' }
    Log ("restic " + ($bargs -join ' '))
    & $restic @bargs 2>&1 | ForEach-Object {
        $line = [string]$_
        Log $line
        if ($line -match 'snapshot ([0-9a-f]{8}) saved') { $status.Snapshot = $Matches[1] }
        if ($line -match 'Added to the repository: (.+)$') { $status.Added = $Matches[1].Trim() }
    }
    $code = $LASTEXITCODE
    Log "restic backup exit code: $code"
    if ($code -eq 0) { $status.Result = "OK" }
    elseif ($code -eq 3) { $status.Result = "WARN"; $status.Detail = "dazi faili nebija nolasami" }
    else { $status.Result = "FAILED"; $status.Detail = "restic exit $code" }

    if (($status.Result -in 'OK', 'WARN') -and (-not $DryRun)) {
        @{ Time = (Get-Date).ToString("s"); Snapshot = $status.Snapshot } | ConvertTo-Json | Set-Content $stampFile -Encoding ASCII
    }
}
catch {
    $status.Detail = $_.Exception.Message
    Log ("KLUDA: " + $status.Detail)
}
finally {
    $status.Finished = (Get-Date).ToString("s")
    $status.DurationMin = [math]::Round(((Get-Date) - $started).TotalMinutes, 1)
    if ($status.Result -ne "SKIPPED") {
        try { $status | ConvertTo-Json | Set-Content (Join-Path $BaseDir "status.json") -Encoding UTF8 } catch { }
    }
    if ($unc -and $status.Result -notin 'NO-NAS', 'SKIPPED') {
        try {
            $sd = Join-Path $unc "_status"
            if (-not (Test-Path $sd)) { New-Item -ItemType Directory -Path $sd -Force | Out-Null }
            $status | ConvertTo-Json | Set-Content (Join-Path $sd "$comp.json") -Encoding UTF8
        } catch { Log ("statusa ieraksts uz NAS neizdevas: " + $_.Exception.Message) }
    }
    Remove-Item Env:\RESTIC_PASSWORD -ErrorAction SilentlyContinue
    if ($unc) { & net.exe use $unc /delete /y 2>&1 | Out-Null }
    try { $mutex.ReleaseMutex() } catch { }
}
Log ("Rezultats: " + $status.Result + "  " + $status.Detail)
