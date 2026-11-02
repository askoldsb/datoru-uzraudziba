# 00-common.ps1 - kopigie iestatijumi un funkcijas TeamViewer testam.
# Tiek ielasits (dot-source) no citiem skriptiem; atseviski nav jaizpilda.
# Testa dators nomainams SEIT.

# Testa dators: pec noklusejuma 01; citam datoram pirms skriptu palaisanas: $env:TV_TEST_PC = "DATORKLASE-02"
$PC      = if ($env:TV_TEST_PC) { $env:TV_TEST_PC } else { "DATORKLASE-01" }
$NasRoot = "\\192.168.3.31\Updates"
$OutDir  = "C:\Temp\tv-test"

$ErrorActionPreference = "Stop"
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
if (-not (Test-Path $OutDir)) { New-Item -ItemType Directory -Path $OutDir -Force | Out-Null }

# Administratora akreditacijas tiek jautatas vienreiz uz PowerShell sesiju
if (-not $global:TvTestCred) {
    $global:TvTestCred = Get-Credential -Message "Administratora konts datoram $PC"
}
$cred = $global:TvTestCred

function Get-TvToken {
    # Token netiek glabats sajos skriptos - tas tiek nolasits no NAS client-install.ps1
    $m = Select-String -Path (Join-Path $NasRoot "Scripts\client-install.ps1") -Pattern 'TeamViewerApiToken\s*=\s*"([^"]+)"' | Select-Object -First 1
    if (-not $m) { throw "Neizdevas atrast TeamViewerApiToken failaa Scripts\client-install.ps1" }
    return $m.Matches[0].Groups[1].Value
}

function Get-TvApiDevice {
    # TeamViewer Web API: atgriez ierices pec aliasa (var nebut, ja tokenam nav lasisanas tiesibu)
    param([string]$Token, [string]$Name)
    try {
        $h = @{ Authorization = "Bearer $Token" }
        $r = Invoke-RestMethod -Uri "https://webapi.teamviewer.com/api/v1/devices?full_list=true" -Headers $h -Method Get
        return @($r.devices | Where-Object { $_.alias -like "$Name*" } |
            Select-Object alias, device_id, remotecontrol_id, groupid, online_state)
    } catch {
        Write-Warning "TeamViewer API nav pieejams ($($_.Exception.Message)). Tas nav kluda - ierices piesaisti pariet pec konsoles."
        return @()
    }
}

function Get-TvState {
    # Nolasa TeamViewer stavokli uz attalinata datora (saja PSSession)
    param([Parameter(Mandatory)]$Session)
    Invoke-Command -Session $Session -ScriptBlock {
        $uninst = @(Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*","HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*" -ErrorAction SilentlyContinue |
            Where-Object { $_.DisplayName -like "TeamViewer*" })
        $clientId = $null
        foreach ($p in "HKLM:\SOFTWARE\TeamViewer","HKLM:\SOFTWARE\WOW6432Node\TeamViewer") {
            if (Test-Path $p) {
                $v = Get-ItemProperty $p
                if (($null -ne $v.ClientID) -and ($null -eq $clientId)) { $clientId = [string]$v.ClientID }
            }
        }
        $auto = $null
        foreach ($p in "HKLM:\SOFTWARE\WOW6432Node\TeamViewer\DefaultSettings","HKLM:\SOFTWARE\TeamViewer\DefaultSettings") {
            if (Test-Path $p) {
                $v = Get-ItemProperty $p
                if ($null -ne $v.Autostart_GUI) { $auto = [string]$v.Autostart_GUI; break }
            }
        }
        $svc = Get-Service -Name "TeamViewer" -ErrorAction SilentlyContinue
        $svcStatus = "nav"; $svcStart = "nav"
        if ($svc) { $svcStatus = [string]$svc.Status; $svcStart = [string]$svc.StartType }
        [PSCustomObject]@{
            Computer     = $env:COMPUTERNAME
            Time         = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
            ClientID     = $clientId
            Version      = (@($uninst | ForEach-Object { $_.DisplayVersion }) -join ", ")
            ProductCodes = (@($uninst | ForEach-Object { $_.PSChildName }) -join ", ")
            Service      = $svcStatus
            StartType    = $svcStart
            AutostartGUI = $auto
        }
    } | Select-Object Computer, Time, ClientID, Version, ProductCodes, Service, StartType, AutostartGUI
}
