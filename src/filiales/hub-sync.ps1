<#
============================================================
 hub-sync.ps1
 Filiales hub dators (piem. AUCEUPDATE-PC). Palaiz planotais
 uzdevums 'Hub-Sync' ar SYSTEM kontu ik 15 min.

 1) PUBLICESANA (centrs -> filiale)
    Avots: C:\Hub\Sync\Skripti (Synology Drive, Download only).
    Failus parnes uz C:\Hub\Updates\{Scripts,Config,Modules} un
    C:\Hub\Tools TIKAI tad, ja:
      - manifest.psd1 ir Authenticode parakstits, paraksts Valid,
        parakstitaja sertifikata thumbprint = -SignerThumbprint;
      - manifest Branch = -Branch, Sequence > pedeja publicetaa;
      - VISU manifesta failu SHA256 sakrit (viss vai nekas).
    Failus parbauda un kope no ATSEVISKAS kopijas (State\staging),
    lai tos nevar nomainit starp parbaudi un kopesanu.

 2) ATSKAITES (filiale -> centrs)
    C:\Hub\Updates\Logs\Status, Inventory, MsiLogs ->
    C:\Hub\Sync\Atskaites\... (Synology Drive, Upload only) +
    hub stavoklis Atskaites\Hub\<dators>.json.
    Logs\Clients paliek hub datora (tikai tiris pec -ClientLogDays).

 3) WAKE-ON-LAN PEC GRAFIKA (ka Dobeles NAS)
    Datoriem ar UpdateTime grafika (Config\device-schedule.csv) un sodienas
    dienu UpdateDays sarakstaa hub 1-50 min pirms UpdateTime nosuta magic
    packet (3x). Lidz 3 meginajumiem (katra Hub-Sync palaisana ik 15 min);
    datoru, kura statusa fails ir svaigs (<20 min), neaiztiek.
    MAC no Logs\Inventory\<dators>.json (vadu adapteris). State\wol-sent.txt.

 4) DARBVIRSMAS IKONA "<Filiale> panelis" (kopiga darbvirsma, ka administrators)
    -> Tools\hub-panel.ps1 (Dobeles panelis ar -NasRoot C:\Hub\Updates).

 Uzstadisana: skat. src/filiales/README.md.
============================================================
#>

param(
    [Parameter(Mandatory = $true)]
    [string]$SignerThumbprint,
    [string]$Branch = "Auce",
    [string]$HubRoot = "C:\Hub",
    [int]$ClientLogDays = 14,
    [int]$PendingErrorMinutes = 60
)

$ErrorActionPreference = "Stop"

$UpdatesRoot = Join-Path $HubRoot "Updates"
$ToolsRoot   = Join-Path $HubRoot "Tools"
$Incoming    = Join-Path $HubRoot "Sync\Skripti"
$Outgoing    = Join-Path $HubRoot "Sync\Atskaites"
$StateDir    = Join-Path $HubRoot "State"
$LogFile     = Join-Path $StateDir "hub-sync.log"
$SeqFile     = Join-Path $StateDir "published-sequence.txt"
$PendingFile = Join-Path $StateDir "publish-pending-since.txt"
$StagingDir  = Join-Path $StateDir "staging"

# Atlautie augsejie limeni manifesta un kurp tie tiek kopeti.
$TargetMap = @{
    "Scripts" = (Join-Path $UpdatesRoot "Scripts")
    "Config"  = (Join-Path $UpdatesRoot "Config")
    "Modules" = (Join-Path $UpdatesRoot "Modules")
    "Tools"   = $ToolsRoot
}

$SignerThumbprint = ($SignerThumbprint -replace '\s', '').ToUpperInvariant()

# ---------- PALIGFUNKCIJAS ----------

function Write-HubLog {
    param([string]$Message, [string]$Level = "INFO")
    $line = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')  [$Level]  $Message"
    try {
        if (-not (Test-Path $StateDir)) { New-Item -ItemType Directory -Path $StateDir -Force | Out-Null }
        if ((Test-Path $LogFile) -and ((Get-Item $LogFile).Length -gt 1MB)) {
            Move-Item -Path $LogFile -Destination ($LogFile + ".old") -Force
        }
        Add-Content -Path $LogFile -Value $line -Encoding UTF8
    } catch { }
    Write-Host $line
}

function Test-SafeRelativePath {
    # Atlauj tikai "<Top>\...\fails" bez '..', diska burta, UNC vai absoluta cela.
    param([string]$RelPath)
    if ([string]::IsNullOrWhiteSpace($RelPath)) { return $false }
    if ($RelPath -match '(^|[\\/])\.\.([\\/]|$)') { return $false }
    if ($RelPath -match ':' -or $RelPath.StartsWith('\') -or $RelPath.StartsWith('/')) { return $false }
    $top = ($RelPath -split '[\\/]')[0]
    if (-not $TargetMap.ContainsKey($top)) { return $false }
    if (($RelPath -split '[\\/]').Count -lt 2) { return $false }
    return $true
}

function Get-TargetPath {
    param([string]$RelPath)
    $parts = $RelPath -split '[\\/]'
    $rest = ($parts[1..($parts.Count - 1)]) -join '\'
    return (Join-Path $TargetMap[$parts[0]] $rest)
}

function Set-Pending {
    param([string]$Reason)
    # Drive var piegadat manifestu agrak par failiem - pirmo reizi tikai gaidam.
    $now = Get-Date
    $since = $null
    if (Test-Path $PendingFile) {
        try { $since = [datetime]::ParseExact([string](Get-Content $PendingFile -TotalCount 1), "yyyy-MM-dd HH:mm:ss", $null) } catch { $since = $null }
    }
    if (-not $since) {
        Set-Content -Path $PendingFile -Value $now.ToString("yyyy-MM-dd HH:mm:ss") -Encoding ASCII
        $since = $now
    }
    $mins = [int]($now - $since).TotalMinutes
    if ($mins -ge $PendingErrorMinutes) {
        return @{ Result = "Error"; Details = "$Reason (jau $mins min)" }
    }
    return @{ Result = "Pending"; Details = "$Reason - gaidam Drive sinhronizaciju ($mins min)" }
}

function Clear-Pending {
    if (Test-Path $PendingFile) { Remove-Item $PendingFile -Force -ErrorAction SilentlyContinue }
}

# ---------- 1) PUBLICESANA ----------

function Invoke-Publish {
    $manifestIn = Join-Path $Incoming "manifest.psd1"
    if (-not (Test-Path $manifestIn)) {
        return @{ Result = "NoManifest"; Details = "Sync\Skripti nav manifest.psd1" }
    }

    if (Test-Path $StagingDir) { Remove-Item $StagingDir -Recurse -Force }
    New-Item -ItemType Directory -Path $StagingDir -Force | Out-Null

    $manifestStaged = Join-Path $StagingDir "manifest.psd1"
    Copy-Item -LiteralPath $manifestIn -Destination $manifestStaged -Force

    $sig = Get-AuthenticodeSignature -FilePath $manifestStaged
    if ($sig.Status -ne "Valid") {
        return @{ Result = "Rejected"; Details = "manifest paraksts nav derigs ($($sig.Status): $($sig.StatusMessage))" }
    }
    $thumb = [string]$sig.SignerCertificate.Thumbprint
    if ($thumb.ToUpperInvariant() -ne $SignerThumbprint) {
        return @{ Result = "Rejected"; Details = "manifestu parakstijis cits sertifikats ($thumb)" }
    }

    try {
        $m = Import-PowerShellDataFile -Path $manifestStaged
    } catch {
        return @{ Result = "Rejected"; Details = "manifest nav nolasams: $_" }
    }

    if ([string]$m.Branch -ne $Branch) {
        return @{ Result = "Rejected"; Details = "manifest Branch '$($m.Branch)' nav '$Branch'" }
    }
    $seq = 0L
    if (-not [long]::TryParse([string]$m.Sequence, [ref]$seq) -or $seq -le 0) {
        return @{ Result = "Rejected"; Details = "manifest Sequence nav derigs" }
    }
    $lastSeq = 0L
    if (Test-Path $SeqFile) { [void][long]::TryParse([string](Get-Content $SeqFile -TotalCount 1), [ref]$lastSeq) }
    if ($seq -lt $lastSeq) {
        return @{ Result = "Rejected"; Details = "manifest Sequence $seq ir vecaks par publiceto $lastSeq" }
    }
    if ($seq -eq $lastSeq) {
        Clear-Pending
        return @{ Result = "UpToDate"; Details = "Sequence $seq jau publicets"; Sequence = $seq }
    }
    if (-not ($m.Files -is [hashtable]) -or $m.Files.Count -eq 0) {
        return @{ Result = "Rejected"; Details = "manifestam nav Files saraksta" }
    }

    # Parbaude: visi faili - drosi celi, eksiste, SHA256 sakrit (stagingaa).
    foreach ($rel in $m.Files.Keys) {
        if (-not (Test-SafeRelativePath $rel)) {
            return @{ Result = "Rejected"; Details = "neatlauts cels manifesta: $rel" }
        }
        $src = Join-Path $Incoming $rel
        if (-not (Test-Path -LiteralPath $src -PathType Leaf)) {
            return (Set-Pending "trukst fails $rel")
        }
        $dst = Join-Path $StagingDir $rel
        $dstDir = Split-Path $dst -Parent
        if (-not (Test-Path $dstDir)) { New-Item -ItemType Directory -Path $dstDir -Force | Out-Null }
        Copy-Item -LiteralPath $src -Destination $dst -Force
        $h = (Get-FileHash -LiteralPath $dst -Algorithm SHA256).Hash
        if ($h -ne ([string]$m.Files[$rel]).ToUpperInvariant()) {
            return (Set-Pending "SHA256 nesakrit: $rel")
        }
    }

    # Viss parbaudits - kopejam no staging uz merki.
    $copied = 0
    foreach ($rel in $m.Files.Keys) {
        $from = Join-Path $StagingDir $rel
        $to = Get-TargetPath $rel
        $toDir = Split-Path $to -Parent
        if (-not (Test-Path $toDir)) { New-Item -ItemType Directory -Path $toDir -Force | Out-Null }
        Copy-Item -LiteralPath $from -Destination $to -Force
        $copied++
    }
    Set-Content -Path $SeqFile -Value ([string]$seq) -Encoding ASCII
    Clear-Pending
    Remove-Item $StagingDir -Recurse -Force -ErrorAction SilentlyContinue
    return @{ Result = "Published"; Details = "publiceti $copied faili (Sequence $seq, $($m.Created), $($m.CreatedBy))"; Sequence = $seq }
}

# ---------- 2) ATSKAITES ----------

function Invoke-Robocopy {
    param([string]$From, [string]$To, [string]$Filter = "*")
    if (-not (Test-Path $From)) { return "nav $From" }
    if (-not (Test-Path $To)) { New-Item -ItemType Directory -Path $To -Force | Out-Null }
    & robocopy.exe $From $To $Filter /MIR /R:1 /W:2 /NP /NJH /NJS /NFL /NDL | Out-Null
    $rc = $LASTEXITCODE
    if ($rc -ge 8) { return "robocopy kluda $rc ($From)" }
    return $null
}

function Invoke-Reports {
    $errors = @()
    $logs = Join-Path $UpdatesRoot "Logs"
    foreach ($sub in @("Status", "Inventory", "MsiLogs")) {
        $e = Invoke-Robocopy -From (Join-Path $logs $sub) -To (Join-Path $Outgoing $sub)
        if ($e) { $errors += $e }
    }
    # Klientu zurnali paliek hub datora; vecos dzesam.
    try {
        $cut = (Get-Date).AddDays(-$ClientLogDays)
        Get-ChildItem -Path (Join-Path $logs "Clients") -File -ErrorAction SilentlyContinue |
            Where-Object { $_.LastWriteTime -lt $cut } |
            Remove-Item -Force -ErrorAction SilentlyContinue
    } catch { $errors += "Clients tirisana: $_" }
    return $errors
}

function Write-HubStatus {
    param($Publish, [string[]]$ReportErrors)
    try {
        $dir = Join-Path $Outgoing "Hub"
        if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
        $os = Get-CimInstance Win32_OperatingSystem
        $disk = Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='C:'"
        $seq = $null
        if (Test-Path $SeqFile) { $seq = [string](Get-Content $SeqFile -TotalCount 1) }  # [string]: PS 5.1 citadi JSON ieraksta PSPath u.c.
        $obj = [ordered]@{
            ComputerName      = $env:COMPUTERNAME
            Branch            = $Branch
            Time              = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
            LastBoot          = $os.LastBootUpTime.ToString("yyyy-MM-dd HH:mm:ss")
            WindowsBuild      = "$($os.Version)"
            DiskFreeGB        = [math]::Round($disk.FreeSpace / 1GB, 1)
            PublishResult     = $Publish.Result
            PublishDetails    = $Publish.Details
            PublishedSequence = $seq
            ReportErrors      = @($ReportErrors)
            LastWake          = @($script:wakeLog)
        }
        $obj | ConvertTo-Json -Depth 4 | Set-Content -Path (Join-Path $dir "$($env:COMPUTERNAME).json") -Encoding UTF8
    } catch {
        Write-HubLog "Hub statusu neizdevas ierakstit: $_" "WARN"
    }
}

# ---------- 3. WAKE-ON-LAN PEC GRAFIKA ----------

function Find-InventoryAdapters {
    param($Obj)
    if ($null -eq $Obj) { return $null }
    if ($Obj -is [System.Management.Automation.PSCustomObject]) {
        foreach ($p in $Obj.PSObject.Properties) {
            if ($p.Name -eq 'Adapters') { return @($p.Value) }
            $r = Find-InventoryAdapters $p.Value
            if ($r) { return $r }
        }
    } elseif ($Obj -is [System.Array]) {
        foreach ($x in $Obj) { $r = Find-InventoryAdapters $x; if ($r) { return $r } }
    }
    return $null
}

function Get-InventoryMac {
    param([string]$ComputerName)
    $p = Join-Path $UpdatesRoot ("Logs\Inventory\" + $ComputerName + ".json")
    if (-not (Test-Path -LiteralPath $p)) { return $null }
    try { $inv = Get-Content -LiteralPath $p -Raw -Encoding UTF8 | ConvertFrom-Json } catch { return $null }
    $ad = @(Find-InventoryAdapters $inv | Where-Object { $_.Mac -and ([string]$_.Description + ' ' + [string]$_.Name) -notmatch 'Wi-?Fi|Wireless|802\.11|WLAN|Bluetooth' })
    if ($ad.Count -eq 0) { return $null }
    $up = @($ad | Where-Object { [string]$_.Status -eq 'Up' })
    if ($up.Count -gt 0) { return ([string]$up[0].Mac).ToUpperInvariant() }
    return ([string]$ad[0].Mac).ToUpperInvariant()
}

function Send-MagicPacket {
    param([string]$Mac)
    $bytes = [byte[]](($Mac -replace '[^0-9A-Fa-f]', '') -split '(..)' | Where-Object { $_ } | ForEach-Object { [Convert]::ToByte($_, 16) })
    if ($bytes.Count -ne 6) { throw "nederiga MAC $Mac" }
    $packet = [byte[]]((,0xFF * 6) + ($bytes * 16))
    $targets = @('255.255.255.255')
    try {
        foreach ($a in @(Get-NetIPAddress -AddressFamily IPv4 -ErrorAction Stop | Where-Object { $_.IPAddress -notlike '169.254.*' -and $_.IPAddress -ne '127.0.0.1' -and $_.PrefixLength -eq 24 })) {
            $o = $a.IPAddress -split '\.'; $targets += ($o[0] + '.' + $o[1] + '.' + $o[2] + '.255')
        }
    } catch { }
    $u = New-Object System.Net.Sockets.UdpClient
    try {
        $u.EnableBroadcast = $true
        foreach ($t in ($targets | Select-Object -Unique)) { [void]$u.Send($packet, $packet.Length, $t, 9) }
    } finally { $u.Close() }
}

function Invoke-ScheduledWake {
    # Modina datorus pirms grafika laika. Hub-Sync darbojas ik 15 min, tapec logs 1..50 min pirms
    # UpdateTime dod 3 meginajumus (piem. 03:15, 03:30, 03:45 pirms 04:00). Katra reize 3 paketes.
    # Datoru, kura statusa fails atjaunots pedejas 20 min (klients jau strada), neaiztiekam.
    param([datetime]$Now = (Get-Date), [int]$WindowMinutes = 50, [int]$MaxAttempts = 3, [int]$AliveMinutes = 20)
    $out = @()
    $csv = Join-Path $UpdatesRoot 'Config\device-schedule.csv'
    if (-not (Test-Path $csv)) { return $out }
    $stateFile = Join-Path $StateDir 'wol-sent.txt'
    $sent = @()
    if (Test-Path $stateFile) { $sent = @(Get-Content $stateFile) }
    $today = $Now.ToString('yyyy-MM-dd')
    $dow = $Now.DayOfWeek.ToString().Substring(0, 3)
    foreach ($r in @(Import-Csv -Path $csv -Encoding UTF8)) {
        if ([string]$r.Enabled -ne 'Yes') { continue }
        $t = ([string]$r.UpdateTime).Trim()
        if ($t -notmatch '^(\d{1,2}):(\d{2})$') { continue }
        $days = ([string]$r.UpdateDays).Trim()
        if ($days -ne 'All' -and (@($days -split ',' | ForEach-Object { $_.Trim() }) -notcontains $dow)) { continue }
        $target = $Now.Date.AddHours([int]$Matches[1]).AddMinutes([int]$Matches[2])
        $mins = ($target - $Now).TotalMinutes
        if ($mins -lt 1 -or $mins -gt $WindowMinutes) { continue }
        $name = [string]$r.ComputerName
        $prefix = "$today|$name"
        $attempts = @($sent | Where-Object { $_ -eq $prefix -or $_ -like "$prefix|*" }).Count
        if ($attempts -ge $MaxAttempts) { continue }
        $st = Join-Path $UpdatesRoot ("Logs\Status\" + $name + ".json")
        if ((Test-Path -LiteralPath $st) -and (((Get-Date) - (Get-Item -LiteralPath $st).LastWriteTime).TotalMinutes -lt $AliveMinutes)) {
            if ($attempts -gt 0) {
                $key = "$prefix|ok"
                if ($sent -notcontains $key) { Add-Content -Path $stateFile -Value $key; $sent += $key; $out += "WoL: $name ieslegts (statuss svaigs)" }
            }
            continue
        }
        if ($sent -contains "$prefix|ok") { continue }
        $mac = Get-InventoryMac $name
        if (-not $mac) { $out += "WoL: $name - MAC nav zinams (nav inventara)"; continue }
        try {
            1..3 | ForEach-Object { Send-MagicPacket $mac; Start-Sleep -Seconds 2 }
            $n = $attempts + 1
            $key = "$prefix|$n"
            Add-Content -Path $stateFile -Value $key
            $sent += $key
            $out += "WoL: $name ($mac) pamodinats pirms $t (meginajums $n/$MaxAttempts)"
        } catch { $out += "WoL: $name - kluda: $_" }
    }
    if ((Test-Path $stateFile) -and (@(Get-Content $stateFile).Count -gt 1000)) {
        Get-Content $stateFile | Select-Object -Last 600 | Set-Content $stateFile
    }
    return $out
}

function Set-HubShortcuts {
    # Kopigas darbvirsmas ikonas (visiem lietotajiem): "<Filiale> panelis" -> Tools\hub-panel.ps1 (ka administrators).
    $out = @()
    $panel = Join-Path $ToolsRoot "hub-panel.ps1"
    if (-not (Test-Path -LiteralPath $panel)) { return $out }
    $desk = [Environment]::GetFolderPath('CommonDesktopDirectory')
    if (-not $desk -or -not (Test-Path $desk)) { return $out }
    $lnk = Join-Path $desk ("$Branch panelis.lnk")
    $args1 = "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$panel`" -Branch $Branch"
    $ws = New-Object -ComObject WScript.Shell
    if (Test-Path -LiteralPath $lnk) {
        $cur = $ws.CreateShortcut($lnk)
        if ($cur.Arguments -eq $args1) { return $out }
    }
    $sc = $ws.CreateShortcut($lnk)
    $sc.TargetPath = Join-Path $env:SystemRoot "System32\WindowsPowerShell\v1.0\powershell.exe"
    $sc.Arguments = $args1
    $sc.WorkingDirectory = $ToolsRoot
    $sc.IconLocation = "shell32.dll,21"
    $sc.Description = "$Branch datoru panelis (grafiks, atskaite, pamodinat / izslegt / atjaunot)"
    $sc.Save()
    # "Palaist ka administrators" (Config\Commands raksta tikai administrators)
    $b = [System.IO.File]::ReadAllBytes($lnk)
    $b[0x15] = $b[0x15] -bor 0x20
    [System.IO.File]::WriteAllBytes($lnk, $b)
    $out += "Ikona: $lnk"
    return $out
}

# ---------- GALVENA DALA ----------

$publish = @{ Result = "Error"; Details = "nav palaists" }
try {
    $publish = Invoke-Publish
} catch {
    $publish = @{ Result = "Error"; Details = "publicesanas kluda: $_" }
}
$level = "INFO"
if ($publish.Result -in @("Rejected", "Error")) { $level = "ERROR" }
elseif ($publish.Result -eq "Pending") { $level = "WARN" }
if ($publish.Result -ne "UpToDate" -and $publish.Result -ne "NoManifest") {
    Write-HubLog "Publicesana: $($publish.Result) - $($publish.Details)" $level
}

$script:wakeLog = @()
try { $script:wakeLog = @(Invoke-ScheduledWake) } catch { $script:wakeLog = @("WoL kluda: $_") }
foreach ($w in $script:wakeLog) { Write-HubLog $w }

try { foreach ($l in @(Set-HubShortcuts)) { Write-HubLog $l } } catch { Write-HubLog "Ikonas kluda: $_" "WARN" }

$reportErrors = @()
try {
    $reportErrors = @(Invoke-Reports)
} catch {
    $reportErrors = @("atskaisu kluda: $_")
}
foreach ($e in $reportErrors) { Write-HubLog "Atskaites: $e" "WARN" }

Write-HubStatus -Publish $publish -ReportErrors $reportErrors

if ($level -eq "ERROR") { exit 1 }
exit 0
