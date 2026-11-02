<#
============================================================
 wol-test.ps1   (palaizams NO ADMIN DATORA; tam jabut tajaa pasaa
                 tikla segmenta (192.168.3.x) ka klases datoriem)

 Wake-on-LAN tests visiem 13 klases datoriem.

   -Action Status   : TIKAI parada, kuri datori ir ieslegti (neko nemaina)
   -Action Shutdown : izslegt datorus, kas ir ieslegti (shutdown /s, ka ciklam),
                      un gaida, kamer visi ir izslegti (lidz 4 min).
                      Katram datoram parada, vai komanda pienemta vai kluda.
                      Ar -Force (tikai testam) tiek aizvertas atvertas programmas.
   -Action Wake     : nosuta modinasanas paketes izslegtajiem datoriem un
                      mera, cik sekundes katrs ieslegsanas aiznem

 Datora stavokli nosaka pec WinRM porta 5985 (NEVIS ping, jo ping ir bloketas).

 Lietosana:
   $cred = Get-Credential
   & "C:\Scripts\wol-test.ps1" -Action Status
   & "C:\Scripts\wol-test.ps1" -Action Shutdown -Credential $cred
   & "C:\Scripts\wol-test.ps1" -Action Wake
============================================================
#>

param(
    [Parameter(Mandatory = $true)]
    [ValidateSet("Status", "Shutdown", "Wake")]
    [string]$Action,

    [System.Management.Automation.PSCredential]$Credential,

    [string]$Broadcast = "192.168.3.255",

    [int]$WaitMinutes = 8,

    # TIKAI TESTAM, kad klase noteikti tuksa: aizver atvertas programmas (shutdown /f).
    # Nesaglabats darbs lietotaju sesijas tiek ZAUDETS.
    [switch]$Force
)

$computers = @(
    [PSCustomObject]@{ Name = "DATORKLASE-01";   Ip = "192.168.3.187"; Mac = "74:56:3C:66:98:A8" },
    [PSCustomObject]@{ Name = "DATORKLASE-02";   Ip = "192.168.3.151"; Mac = "74:56:3C:66:98:A7" },
    [PSCustomObject]@{ Name = "DATORKLASE-03";   Ip = "192.168.3.149"; Mac = "74:56:3C:66:9D:B7" },
    [PSCustomObject]@{ Name = "DATORKLASE-04";   Ip = "192.168.3.150"; Mac = "74:56:3C:64:DD:90" },
    [PSCustomObject]@{ Name = "DATORKLASE-05";   Ip = "192.168.3.156"; Mac = "74:56:3C:64:D4:FB" },
    [PSCustomObject]@{ Name = "DATORKLASE-06";   Ip = "192.168.3.155"; Mac = "74:56:3C:66:9D:B9" },
    [PSCustomObject]@{ Name = "DATORKLASE-07";   Ip = "192.168.3.154"; Mac = "74:56:3C:66:9D:CA" },
    [PSCustomObject]@{ Name = "DATORKLASE-08";   Ip = "192.168.3.153"; Mac = "74:56:3C:66:98:7C" },
    [PSCustomObject]@{ Name = "DATORKLASE-09";   Ip = "192.168.3.157"; Mac = "74:56:3C:66:9D:BB" },
    [PSCustomObject]@{ Name = "DATORKLASE-10";   Ip = "192.168.3.158"; Mac = "74:56:3C:66:9D:BA" },
    [PSCustomObject]@{ Name = "DATORKLASE-11";   Ip = "192.168.3.160"; Mac = "74:56:3C:64:DB:4B" },
    [PSCustomObject]@{ Name = "DATORKLASE-12";   Ip = "192.168.3.161"; Mac = "74:56:3C:66:9D:CD" },
    [PSCustomObject]@{ Name = "DATORKLASE-PASN"; Ip = "192.168.3.159"; Mac = "74:56:3C:66:9D:B8" }
)

function Get-PortStates {
    # Vienlaikus pamegina savienoties ar WinRM portu visiem datoriem; atgriez hashtable Nosaukums -> $true/$false
    param($Items, [int]$Port = 5985, [int]$TimeoutMs = 1200)
    $clients = @{}
    $tasks = @{}
    foreach ($i in $Items) {
        $c = New-Object System.Net.Sockets.TcpClient
        $clients[$i.Name] = $c
        $tasks[$i.Name] = $c.ConnectAsync($i.Ip, $Port)
    }
    Start-Sleep -Milliseconds $TimeoutMs
    $res = @{}
    foreach ($i in $Items) {
        $t = $tasks[$i.Name]
        $res[$i.Name] = [bool]($t.IsCompleted -and (-not $t.IsFaulted) -and (-not $t.IsCanceled) -and $clients[$i.Name].Connected)
        try { $clients[$i.Name].Close() } catch { }
    }
    return $res
}

function Send-MagicPacket {
    param([string]$Mac, [string]$BroadcastAddress)
    $m = [byte[]]($Mac -split "[-:]" | ForEach-Object { [Convert]::ToByte($_, 16) })
    $pkt = [byte[]](@(255, 255, 255, 255, 255, 255) + ($m * 16))
    $udp = New-Object System.Net.Sockets.UdpClient
    $udp.EnableBroadcast = $true
    [void]$udp.Send($pkt, $pkt.Length, $BroadcastAddress, 9)
    $udp.Close()
}

function Show-States {
    param($States)
    $rows = @()
    foreach ($c in $computers) {
        $text = "IZSLEGTS (WinRM neatbild)"
        if ($States[$c.Name]) { $text = "IESLEGTS (WinRM atbild)" }
        $rows += [PSCustomObject]@{ Dators = $c.Name; IP = $c.Ip; Stavoklis = $text }
    }
    $rows | Format-Table -AutoSize
}

# ---------- STATUS ----------

if ($Action -eq "Status") {
    $states = Get-PortStates -Items $computers
    Show-States -States $states
    $onCount = @($computers | Where-Object { $states[$_.Name] }).Count
    Write-Host ("Ieslegti: {0} no {1}" -f $onCount, $computers.Count)
    return
}

# ---------- SHUTDOWN ----------

if ($Action -eq "Shutdown") {
    if (-not $Credential) { $Credential = Get-Credential -Message "Lokalais administrators klases datoriem" }

    $states = Get-PortStates -Items $computers
    $on = @($computers | Where-Object { $states[$_.Name] })
    if ($on.Count -eq 0) {
        Write-Host "Visi datori jau ir izslegti."
        Show-States -States $states
        return
    }

    $names = @($on | ForEach-Object { $_.Name })
    Write-Host ("Izslegsu {0} datorus: {1}" -f $names.Count, ($names -join ", "))
    $ivErr = @()
    if ($Force) {
        Write-Host "Ar -Force: atvertas programmas tiks aizvertas."
        $sent = @(Invoke-Command -ComputerName $names -Credential $Credential -ScriptBlock { shutdown.exe /s /f /t 10 /c "Wake-on-LAN tests"; $LASTEXITCODE } -ErrorAction SilentlyContinue -ErrorVariable ivErr)
    } else {
        $sent = @(Invoke-Command -ComputerName $names -Credential $Credential -ScriptBlock { shutdown.exe /s /t 10 /c "Wake-on-LAN tests"; $LASTEXITCODE } -ErrorAction SilentlyContinue -ErrorVariable ivErr)
    }

    # rezultats katram datoram: komanda pienemta (kods 0) vai kluda
    $accepted = @($sent | Where-Object { $_ -eq 0 } | ForEach-Object { $_.PSComputerName })
    Write-Host ("Izslegsanas komanda PIENEMTA: {0} no {1}" -f $accepted.Count, $names.Count)
    foreach ($e in $ivErr) {
        Write-Host ("KLUDA: " + $e.Exception.Message) -ForegroundColor Yellow
    }
    if ($accepted.Count -eq 0) {
        Write-Host "Neviens dators komandu nepienema. Parbaudiet kontu un paroli (Get-Credential) un ari to, vai kludu teksts augstak nav piekluves problema." -ForegroundColor Yellow
    }

    $deadline = (Get-Date).AddMinutes(4)
    $stillOn = $on
    while (((Get-Date) -lt $deadline) -and ($stillOn.Count -gt 0)) {
        Start-Sleep -Seconds 10
        $states = Get-PortStates -Items $computers
        $stillOn = @($computers | Where-Object { $states[$_.Name] })
        Write-Host ("{0}: vel ieslegti {1}" -f (Get-Date -Format "HH:mm:ss"), $stillOn.Count)
    }

    Show-States -States $states
    if ($stillOn.Count -eq 0) {
        Write-Host "Visi datori ir izslegti. Tagad var palaist -Action Wake."
    } else {
        Write-Host ("UZMANIBU: vel ieslegti: " + (($stillOn | ForEach-Object { $_.Name }) -join ", "))
    }
    return
}

# ---------- WAKE ----------

if ($Action -eq "Wake") {
    $states = Get-PortStates -Items $computers
    $already = @($computers | Where-Object { $states[$_.Name] })
    $off = @($computers | Where-Object { -not $states[$_.Name] })

    if ($already.Count -gt 0) {
        Write-Host ("Jau ieslegti (netiek modinati): " + (($already | ForEach-Object { $_.Name }) -join ", "))
    }
    if ($off.Count -eq 0) {
        Write-Host "Nav izslegtu datoru, ko modinat."
        return
    }

    foreach ($c in $off) { Send-MagicPacket -Mac $c.Mac -BroadcastAddress $Broadcast }
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    Write-Host ("{0}: paketes nosutitas {1} datoriem uz {2}. Gaidu lidz {3} min..." -f (Get-Date -Format "HH:mm:ss"), $off.Count, $Broadcast, $WaitMinutes)

    $up = @{}
    $deadline = (Get-Date).AddMinutes($WaitMinutes)
    while (((Get-Date) -lt $deadline) -and ($up.Count -lt $off.Count)) {
        Start-Sleep -Seconds 4
        $s = Get-PortStates -Items $off
        foreach ($c in $off) {
            if ($s[$c.Name] -and (-not $up.ContainsKey($c.Name))) { $up[$c.Name] = [int]$sw.Elapsed.TotalSeconds }
        }
    }

    $rows = @()
    foreach ($c in $off) {
        if ($up.ContainsKey($c.Name)) {
            $rows += [PSCustomObject]@{ Dators = $c.Name; Rezultats = "IESLEDZAS"; Sekundes = $up[$c.Name] }
        } else {
            $rows += [PSCustomObject]@{ Dators = $c.Name; Rezultats = "NEIESLEDZAS"; Sekundes = "-" }
        }
    }
    $rows | Format-Table -AutoSize

    $failed = @($rows | Where-Object { $_.Rezultats -eq "NEIESLEDZAS" })
    Write-Host ("Ieslegusies: {0} no {1}" -f ($off.Count - $failed.Count), $off.Count)
    if ($failed.Count -gt 0) {
        Write-Host ("NEIESLEDZAS: " + (($failed | ForEach-Object { $_.Dators }) -join ", "))
    }
    return
}
