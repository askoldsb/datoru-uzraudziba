<#
 patch-update-now.ps1
 Palaizams VIENU REIZI no administratora datora. Pielabo NAS failu Scripts\client-install.ps1:
 pievieno atbalstu administratora komandai UpdateNow (Config\Commands\<DATORS>.json).
 Citas izmainas (ieskaitot TeamViewer tokenu un iestregusa cikla aizsardzibu) netiek skartas.
 Pirms izmainam tiek izveidota rezerves kopija .bak-*.
#>
param(
    [string]$Path = "\\192.168.3.31\Updates\Scripts\client-install.ps1"
)

if (-not (Test-Path $Path)) { Write-Host "KLUDA: nav atrasts $Path" -ForegroundColor Red; exit 1 }
$raw = [System.IO.File]::ReadAllText($Path)
if ($raw -like "*function Get-PendingCommand*") { Write-Host "Jau pielabots - nekas nav jadara." -ForegroundColor Yellow; exit 0 }

$crlf = $raw.Contains("`r`n")
$text = $raw.Replace("`r`n", "`n")
$edits = @()
$a1 = @'
function Get-OfficeInfo {
'@
$n1 = @'
# ---------- ADMINISTRATORA KOMANDAS (Config\Commands\<DATORS>.json) ----------
# Panelis ieraksta komandas failu; klients to nolasa katra cikla sakuma (ik 15 min), izpilda un
# apstiprina ar Logs\Status\<DATORS>.command.json. Apstradatas komandas Id glabajas lokali
# (State\last-command-id.txt), tapec viena komanda tiek izpildita tikai VIENU reizi.

function Get-PendingCommand {
    param([string]$NasRoot, [string]$ComputerName, [string]$StateFile)
    $path = Join-Path $NasRoot ("Config\Commands\" + $ComputerName + ".json")
    if (-not (Test-Path $path)) { return $null }
    try {
        $c = Get-Content -Path $path -Raw -Encoding UTF8 -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
    } catch {
        Write-Log "Komandas fails nav nolasams ($path): $_" "WARN"
        return $null
    }
    $id = [string]$c.Id
    $cmd = [string]$c.Command
    if ([string]::IsNullOrWhiteSpace($id) -or [string]::IsNullOrWhiteSpace($cmd)) { return $null }

    $last = ""
    if (Test-Path $StateFile) { $last = [string](Get-Content -Path $StateFile -ErrorAction SilentlyContinue | Select-Object -First 1) }
    if ($last.Trim() -eq $id) { return $null }

    $expired = $true
    try {
        $exp = [datetime]::ParseExact([string]$c.ExpiresAt, "yyyy-MM-dd HH:mm:ss", [System.Globalization.CultureInfo]::InvariantCulture)
        $expired = ($exp -lt (Get-Date))
    } catch { $expired = $true }

    return [PSCustomObject]@{
        Id        = $id
        Command   = $cmd
        CreatedBy = [string]$c.CreatedBy
        CreatedAt = [string]$c.CreatedAt
        Expired   = $expired
    }
}

function Set-CommandHandled {
    param([string]$StateFile, [string]$Id)
    try {
        $dir = Split-Path $StateFile -Parent
        if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
        Set-Content -Path $StateFile -Value $Id -Encoding UTF8
    } catch {
        Write-Log "Neizdevas saglabat apstradatas komandas Id: $_" "WARN"
    }
}

function Write-CommandAck {
    param([string]$NasRoot, [string]$ComputerName, $Command, [string]$Status, [string]$Details = "")
    $obj = [ordered]@{
        Id        = $Command.Id
        Command   = $Command.Command
        Status    = $Status
        UpdatedAt = (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
        Details   = $Details
    }
    $path = Join-Path $NasRoot ("Logs\Status\" + $ComputerName + ".command.json")
    try {
        ($obj | ConvertTo-Json) | Set-Content -Path $path -Encoding UTF8
    } catch {
        Write-Log "Neizdevas rakstit komandas apstiprinajumu ($path): $_" "WARN"
    }
}

function Get-OfficeInfo {
'@
$edits += ,@($a1, $n1)
$a2 = @'
        [string]$DailyMarkerFile,
        [int]$ToleranceMinutes = 20
    )
'@
$n2 = @'
        [string]$DailyMarkerFile,
        [int]$ToleranceMinutes = 20,
        [bool]$IgnoreSchedule = $false
    )
'@
$edits += ,@($a2, $n2)
$a3 = @'
    $todayAbbrev = (Get-Date).DayOfWeek.ToString().Substring(0, 3)  # piem.
'@
$n3 = @'
    # Administratora komanda UpdateNow: dienu, laika un "jau izpildits sodien" ierobezojumi netiek piemeroti
    # (Enabled un ThirdPartyApps/WindowsUpdate joprojam jaatbilst). Izslegsana pec cikla netiek ieplanota.
    if ($IgnoreSchedule) {
        $result.ShutdownAfterRequested = $false
        $result.Allowed = $true
        $result.Reason = "Atlauts (administratora komanda UpdateNow - grafiks ignorets)."
        return $result
    }

    $todayAbbrev = (Get-Date).DayOfWeek.ToString().Substring(0, 3)  # piem.
'@
$edits += ,@($a3, $n3)
$a4 = @'
$schedule = Get-ScheduleDecision -Path $ScheduleFile -ComputerName $computerName -DailyMarkerFile $DailyMarkerFile
'@
$n4 = @'
$CommandStateFile = "C:\ProgramData\LabUpdates\State\last-command-id.txt"
$pendingCmd = $null
$ignoreSchedule = $false
try {
    $pendingCmd = Get-PendingCommand -NasRoot $NasRoot -ComputerName $computerName -StateFile $CommandStateFile
} catch {
    Write-Log "Komandu parbaude neizdevas: $_" "WARN"
}
if ($pendingCmd) {
    Set-CommandHandled -StateFile $CommandStateFile -Id $pendingCmd.Id
    if ($pendingCmd.Expired) {
        Write-Log ("Administratora komanda '{0}' ({1}) ir novecojusi - neizpildu." -f $pendingCmd.Command, $pendingCmd.Id) "WARN"
        Write-CommandAck -NasRoot $NasRoot -ComputerName $computerName -Command $pendingCmd -Status "Expired" -Details "Komandas derigums beidzies, pirms dators to panema."
        $pendingCmd = $null
    } elseif ($pendingCmd.Command -eq "UpdateNow") {
        Write-Log ("Administratora komanda UpdateNow ({0}, nosutija {1}) - atjauninu uzreiz, grafiks ignorets." -f $pendingCmd.Id, $pendingCmd.CreatedBy)
        Write-CommandAck -NasRoot $NasRoot -ComputerName $computerName -Command $pendingCmd -Status "Started" -Details "Atjauninasana sakta."
        $ignoreSchedule = $true
    } else {
        Write-Log ("Administratora komanda '{0}' nav atbalstita so klienta versija - izlaizu." -f $pendingCmd.Command) "WARN"
        Write-CommandAck -NasRoot $NasRoot -ComputerName $computerName -Command $pendingCmd -Status "Rejected" -Details "Komanda nav atbalstita."
        $pendingCmd = $null
    }
}
$schedule = Get-ScheduleDecision -Path $ScheduleFile -ComputerName $computerName -DailyMarkerFile $DailyMarkerFile -IgnoreSchedule $ignoreSchedule
'@
$edits += ,@($a4, $n4)
$a5 = @'
    Write-Log "=== Klienta atjauninasana pabeigta (izlaista pec grafika) ==="
'@
$n5 = @'
    if ($pendingCmd) {
        Write-CommandAck -NasRoot $NasRoot -ComputerName $computerName -Command $pendingCmd -Status "Rejected" -Details $schedule.Reason
    }
    Write-Log "=== Klienta atjauninasana pabeigta (izlaista pec grafika) ==="
'@
$edits += ,@($a5, $n5)
$a6 = @'
Write-Log "=== Klienta atjauninasana pabeigta ==="
'@
$n6 = @'
Write-Log "=== Klienta atjauninasana pabeigta ==="

if ($pendingCmd) {
    Write-CommandAck -NasRoot $NasRoot -ComputerName $computerName -Command $pendingCmd -Status "Done" -Details ("Rezultats: " + $statusResult + ". " + $statusDetails)
}
'@
$edits += ,@($a6, $n6)

foreach ($e in $edits) {
    $old = [string]$e[0]; $new = [string]$e[1]
    $cnt = ([regex]::Matches($text, [regex]::Escape($old))).Count
    if ($cnt -ne 1) {
        Write-Host ("KLUDA: anchor atrasts {0} reizes (gaidits 1): {1}" -f $cnt, $old.Substring(0, [Math]::Min(60, $old.Length))) -ForegroundColor Red
        Write-Host "Fails ir mainits kops ta pielabosanas? Nekas netika mainits." -ForegroundColor Red
        exit 1
    }
    $text = $text.Replace($old, $new)
}

if ($crlf) { $text = $text.Replace("`n", "`r`n") }
Copy-Item $Path ($Path + ".bak-" + (Get-Date -Format "yyyyMMdd-HHmmss"))
[System.IO.File]::WriteAllText($Path, $text, (New-Object System.Text.UTF8Encoding($true)))
Write-Host "Gatavs: client-install.ps1 pielabots ar UpdateNow atbalstu (rezerves kopija .bak-*)." -ForegroundColor Green
