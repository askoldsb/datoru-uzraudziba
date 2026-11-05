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
        try { $since = [datetime]::ParseExact((Get-Content $PendingFile -TotalCount 1), "yyyy-MM-dd HH:mm:ss", $null) } catch { $since = $null }
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
    if (Test-Path $SeqFile) { [void][long]::TryParse((Get-Content $SeqFile -TotalCount 1), [ref]$lastSeq) }
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
        if (Test-Path $SeqFile) { $seq = Get-Content $SeqFile -TotalCount 1 }
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
        }
        $obj | ConvertTo-Json -Depth 4 | Set-Content -Path (Join-Path $dir "$($env:COMPUTERNAME).json") -Encoding UTF8
    } catch {
        Write-HubLog "Hub statusu neizdevas ierakstit: $_" "WARN"
    }
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
