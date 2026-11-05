<#
============================================================
 new-signing-cert.ps1
 VIENREIZ uz admin datora (PIUAC-ASKOLDS), parasts PowerShell ar
 Askolda kontu (NE "Run as administrator" - sertifikats jaliek
 TAVA lietotaja kratuve CurrentUser\My).

 Izveido pasparakstitu koda parakstisanas sertifikatu filialu
 publikacijam. Privata atslega NAV eksportejama (paliek tikai
 saja datora/konta). Publisko dalu (.cer) eksporte, lai to
 ieliktu filiales hub datora (Tools\ caur publish-filiale.ps1).

 Ja sertifikats pazud (Windows parinstalesana u.c.) - izveido
 jaunu, publice ar to un hub datora atkartoti palaiz
 install-hub-sync.ps1 ar jauno thumbprint.
============================================================
#>

param(
    [string]$Subject = "CN=PIUAC filiales skripti",
    [int]$Years = 5,
    [string]$ExportCer = "C:\Scripts\Filiales\piuac-filiales-signing.cer",
    [switch]$Force
)

$ErrorActionPreference = "Stop"

$existing = @(Get-ChildItem Cert:\CurrentUser\My -CodeSigningCert | Where-Object { $_.Subject -eq $Subject -and $_.HasPrivateKey -and $_.NotAfter -gt (Get-Date) })
if ($existing.Count -gt 0 -and -not $Force) {
    $c = $existing | Sort-Object NotAfter -Descending | Select-Object -First 1
    Write-Host "Sertifikats jau eksiste: $($c.Subject)  thumbprint $($c.Thumbprint)  lidz $($c.NotAfter.ToString('yyyy-MM-dd'))" -ForegroundColor Yellow
    Write-Host "Jaunu NEVEIDOJU (lai veidotu tomer: -Force)."
} else {
    $c = New-SelfSignedCertificate -Type CodeSigningCert -Subject $Subject `
        -CertStoreLocation Cert:\CurrentUser\My -KeyExportPolicy NonExportable `
        -KeyAlgorithm RSA -KeyLength 3072 -HashAlgorithm SHA256 `
        -NotAfter (Get-Date).AddYears($Years)
    Write-Host "Izveidots: $($c.Subject)  thumbprint $($c.Thumbprint)  lidz $($c.NotAfter.ToString('yyyy-MM-dd'))" -ForegroundColor Green
}

$dir = Split-Path $ExportCer -Parent
if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
Export-Certificate -Cert $c -FilePath $ExportCer -Type CERT | Out-Null
Write-Host "Publiska dala (.cer): $ExportCer"
Write-Host ""
Write-Host "THUMBPRINT (pierakstit - vajadzigs hub datora):" -ForegroundColor Cyan
Write-Host "  $($c.Thumbprint)" -ForegroundColor Cyan
