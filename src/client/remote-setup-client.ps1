<#
============================================================
 remote-setup-client.ps1
 Palaizams no ADMINISTRATORA datora. Nokopee un attalinati
 palaiz setup-client.ps1 uz VAIRAKIEM merka datoriem reize,
 izmantojot PowerShell Remoting (WinRM).

 PRIEKSNOSACIJUMS: katram merka datoram jau jabuut palaistam
 enable-remoting-bootstrap.ps1 (VIENU REIZI, caur TeamViewer).

 Lietosana:
   .\remote-setup-client.ps1 -ComputerNames "192.168.3.41","192.168.3.42","192.168.3.43"

 Prasa: lokala administratora akreditacijas dati, kas strada
 VISOS merka datoros (parasti sakrit, ja datori klonet no viena
 un ta pasha image).
============================================================
#>

param(
    [Parameter(Mandatory = $true)]
    [string]$ComputerNames,

    [string]$LocalSetupScript = "C:\Scripts\setup-client.ps1"
)

# PIEZIME: parametrs apzinati pienem VIENU komatu-atdalitu virkni
# (nevis [string[]] masivu), jo palaisana caur "powershell.exe -File"
# (kas nepieciesams, lai palaistu no vina PowerShell loga ar
# -ExecutionPolicy Bypass) NESADALA komatu-atdalitu masiva sintaksi
# ("A","B","C") atsevishkos elementos - tie salust VIENA virkne ar
# komatiem. Tapec seit skaidri sadalam pashi, kas strada uzticami
# neatkarigi no izsauksanas veida.
$ComputerNamesList = $ComputerNames -split "," | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne "" }

if ($ComputerNamesList.Count -eq 0) {
    Write-Host "KLUDA: nav noraditi merka datori." -ForegroundColor Red
    exit 1
}

if (-not (Test-Path $LocalSetupScript)) {
    Write-Host "KLUDA: $LocalSetupScript nav atrasts. Parliecinieties, ka setup-client.ps1 (jaunaka versija) atrodas sajaa cela." -ForegroundColor Red
    exit 1
}

Write-Host "Merka datori: $($ComputerNamesList -join ', ')" -ForegroundColor Cyan
$cred = Get-Credential -Message "Ievadiet lokala administratora kontu, kas derigs VISOS merka datoros"

# ---------- TrustedHosts atjauninasana ----------
# Workgroup vide (bez domena/Kerberos) PowerShell Remoting prasa, lai
# merka dators butu sarakstaa TrustedHosts - citadi autentifikacija
# neizdodas pat ar pareiziem akreditacijas datiem.

try {
    $existing = (Get-Item WSMan:\localhost\Client\TrustedHosts -ErrorAction SilentlyContinue).Value
    if ([string]::IsNullOrWhiteSpace($existing)) { $existing = "" }

    $toAdd = @($ComputerNamesList | Where-Object { $existing -notmatch [regex]::Escape($_) })
    if ($toAdd.Count -gt 0) {
        foreach ($c in $toAdd) {
            $cStr = [string]$c
            Set-Item WSMan:\localhost\Client\TrustedHosts -Value $cStr -Concatenate -Force
        }
        Write-Host "TrustedHosts atjaunots, pievienoti: $($toAdd -join ', ')" -ForegroundColor Green
    } else {
        Write-Host "TrustedHosts jau satur visus merka datorus."
    }
} catch {
    Write-Host "BRIDINAJUMS: neizdevas atjauninat TrustedHosts: $_" -ForegroundColor Yellow
}

# ---------- Katra datora apstrade ----------

$results = @()

foreach ($computer in $ComputerNamesList) {
    Write-Host ""
    Write-Host "=== $computer ===" -ForegroundColor Cyan

    $status = "Neizdevas"
    $details = ""

    try {
        $session = New-PSSession -ComputerName $computer -Credential $cred -ErrorAction Stop
        Write-Host "$computer : PSSession izveidota."

        Invoke-Command -Session $session -ScriptBlock {
            New-Item -ItemType Directory -Path "C:\Scripts" -Force | Out-Null
        } | Out-Null

        Copy-Item -Path $LocalSetupScript -Destination "C:\Scripts\setup-client.ps1" -ToSession $session -Force
        Write-Host "$computer : setup-client.ps1 nokopets."

        Write-Host "$computer : palaizu setup-client.ps1 (sis var paiet minuti)..."
        $output = Invoke-Command -Session $session -ScriptBlock {
            powershell.exe -ExecutionPolicy Bypass -File "C:\Scripts\setup-client.ps1" 2>&1 | Out-String
        }
        Write-Host $output

        if ($output -match "=== GATAVS ===") {
            $status = "Veiksmigi"
        } else {
            $status = "Pabeigts, bet parbaudiet izvadi"
        }
        $details = $output

        Remove-PSSession $session

    } catch {
        $status = "KLUDA"
        $details = "$_"
        Write-Host "$computer : KLUDA - $_" -ForegroundColor Red
    }

    $results += [PSCustomObject]@{
        Computer = $computer
        Status   = $status
    }
}

Write-Host ""
Write-Host "=== KOPSAVILKUMS ===" -ForegroundColor Cyan
$results | Format-Table -AutoSize
