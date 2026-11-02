<#
============================================================
 enable-remoting-bootstrap.ps1
 Palaizams VIENU REIZI uz katra JAUNA datora (caur TeamViewer
 vai klatiene), lai ieslegtu PowerShell Remoting (WinRM).

 Pec sa sola dators kluust sasniedzams attalinati no
 administratora datora (remote-setup-client.ps1 un citiem
 turpmakiem uzdevumiem) - BEZ TeamViewer nepieciesamibas.

 Prasa: Administrators PowerShell logs.
============================================================
#>

$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Host "KLUDA: sis skripts japalaiz ka Administrators." -ForegroundColor Red
    exit 1
}

Write-Host "Ieslegzu PowerShell Remoting (WinRM)..." -ForegroundColor Cyan

try {
    Enable-PSRemoting -Force -SkipNetworkProfileCheck -ErrorAction Stop
    Write-Host "WinRM veiksmigi ieslegts." -ForegroundColor Green
} catch {
    Write-Host "KLUDA ieslegzot WinRM: $_" -ForegroundColor Red
    exit 1
}

# Pamata parbaude - vai WinRM pakalpojums tiesam darbojas
$svc = Get-Service -Name WinRM
Write-Host "WinRM pakalpojuma statuss: $($svc.Status)"

$ip = (Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue |
    Where-Object { $_.IPAddress -notlike "169.254.*" -and $_.IPAddress -ne "127.0.0.1" } |
    Select-Object -First 1).IPAddress

Write-Host ""
Write-Host "GATAVS. Sis dators ($env:COMPUTERNAME, $ip) tagad ir sasniedzams attalinati." -ForegroundColor Green
Write-Host "Administratora dators varetu pirms pirmas lietosanas pievienot so IP/vardu"
Write-Host "TrustedHosts sarakstam - to automatiski dara remote-setup-client.ps1."
