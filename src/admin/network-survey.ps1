# network-survey.ps1
# Biroja tikla apskats no admin datora. Nekas netiek mainits; testa fails NAS tiek izdzests.
# Lietosana:
#   & "C:\Scripts\network-survey.ps1" -ComputerName DATORS1,DATORS2 -Credential $cred
#   & "C:\Scripts\network-survey.ps1"                  # tikai lokalais apskats un atrums uz NAS
param(
    [string[]]$ComputerName,
    [System.Management.Automation.PSCredential]$Credential,
    [string]$NasShare = "\\192.168.3.31\Updates",
    [int]$TestSizeMB = 512,
    [switch]$SkipSpeedTest
)

Write-Host "`n=== 1. Datoru tikla savienojuma atrums ===" -ForegroundColor Cyan
if ($ComputerName) {
    $args1 = @{ ComputerName = $ComputerName; ErrorAction = "SilentlyContinue"
                ScriptBlock = { Get-NetAdapter -Physical | Where-Object { $_.Status -eq "Up" } | Select-Object Name, LinkSpeed } }
    if ($Credential) { $args1.Credential = $Credential }
    Invoke-Command @args1 | Select-Object PSComputerName, Name, LinkSpeed | Sort-Object PSComputerName | Format-Table -AutoSize
} else {
    Write-Host "(parametrs -ComputerName nav dots, izlaists)"
}

Write-Host "`n=== 2. Lokalais dators un vartejs ===" -ForegroundColor Cyan
Get-NetAdapter -Physical | Where-Object { $_.Status -eq "Up" } | Select-Object Name, LinkSpeed | Format-Table -AutoSize
$gw = (Get-NetRoute -DestinationPrefix "0.0.0.0/0" | Sort-Object RouteMetric | Select-Object -First 1).NextHop
Write-Host "Noklusetais vartejs: $gw"

Write-Host "`n=== 3. Ierices apakstikla (slēdži, AP, printeri) ===" -ForegroundColor Cyan
function Test-Port($ip, $port) {
    $c = New-Object System.Net.Sockets.TcpClient
    try { $a = $c.BeginConnect($ip, $port, $null, $null); $ok = $a.AsyncWaitHandle.WaitOne(300); if ($ok -and $c.Connected) { $c.EndConnect($a); return $true } return $false }
    catch { return $false } finally { $c.Close() }
}
$neigh = Get-NetNeighbor -AddressFamily IPv4 -ErrorAction SilentlyContinue |
    Where-Object { $_.State -in "Reachable","Stale","Permanent" -and $_.IPAddress -notmatch "^(224|239|255)\." -and $_.LinkLayerAddress -and $_.LinkLayerAddress -ne "FF-FF-FF-FF-FF-FF" }
$rows = foreach ($n in $neigh) {
    $ports = foreach ($p in 22, 23, 80, 443) { if (Test-Port $n.IPAddress $p) { $p } }
    $title = ""
    if ($ports -contains 80) {
        try { $r = Invoke-WebRequest -Uri "http://$($n.IPAddress)" -UseBasicParsing -TimeoutSec 2 -ErrorAction Stop
              if ($r.Content -match "<title>(.*?)</title>") { $title = $Matches[1].Trim() } } catch { }
    }
    [PSCustomObject]@{ IP = $n.IPAddress; MAC = $n.LinkLayerAddress; OtvertiPorti = ($ports -join ","); Tīmeklis = $title }
}
$rows | Sort-Object { [version]($_.IP) } -ErrorAction SilentlyContinue | Format-Table -AutoSize
Write-Host "Ierices ar atvertiem portiem 22/80/443 visticamak ir parvaldamas (slēdzis, AP). MAC pirmos 3 baitus var ielikt OUI meklētājā, lai uzzinātu razotaju."

if (-not $SkipSpeedTest) {
    Write-Host "`n=== 4. Atrums uz NAS ($NasShare), $TestSizeMB MB ===" -ForegroundColor Cyan
    $dir = Join-Path $NasShare "_speedtest"
    $local = Join-Path $env:TEMP "speedtest.bin"
    $remote = Join-Path $dir "speedtest.bin"
    try {
        if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
        $fs = [System.IO.File]::Create($local); $buf = New-Object byte[] (1MB)
        (New-Object System.Random).NextBytes($buf)
        1..$TestSizeMB | ForEach-Object { $fs.Write($buf, 0, $buf.Length) }; $fs.Close()
        $sw = [System.Diagnostics.Stopwatch]::StartNew(); Copy-Item $local $remote -Force; $sw.Stop()
        "{0,-22} {1,7:N1} MB/s" -f "Rakstisana uz NAS:", ($TestSizeMB / $sw.Elapsed.TotalSeconds)
        Remove-Item $local -Force
        $sw.Restart(); Copy-Item $remote $local -Force; $sw.Stop()
        "{0,-22} {1,7:N1} MB/s" -f "Lasisana no NAS:", ($TestSizeMB / $sw.Elapsed.TotalSeconds)
    } catch { Write-Warning "Atruma tests neizdevas: $($_.Exception.Message)" }
    finally {
        Remove-Item $local -Force -ErrorAction SilentlyContinue
        Remove-Item $remote -Force -ErrorAction SilentlyContinue
        Remove-Item $dir -Force -ErrorAction SilentlyContinue
    }
    Write-Host "Atsauce: 1 Gb/s saite dod apmēram 110 MB/s, 2,5 Gb/s apmēram 280 MB/s, 100 Mb/s apmēram 11 MB/s."
}
