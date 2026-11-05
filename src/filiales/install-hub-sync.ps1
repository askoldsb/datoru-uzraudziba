<#
============================================================
 install-hub-sync.ps1
 VIENREIZ filiales hub datora (piem. AUCEUPDATE-PC),
 PowerShell ka administrators. Palaiz no Drive mapes:

   powershell -ExecutionPolicy Bypass -File C:\Hub\Sync\Skripti\Tools\install-hub-sync.ps1 -ExpectedThumbprint <THUMBPRINT>

 <THUMBPRINT> nolasi no new-signing-cert.ps1 izvades UZ
 PIUAC-ASKOLDS (neatkarigs kanals) - ta parliecinamies, ka .cer,
 kas atnaca caur Drive, ir tiesam musu.

 Dara:
   1. Parbauda .cer thumbprint = -ExpectedThumbprint.
   2. Ieliek .cer LocalMachine\Root (lai paraksts ir "Valid").
   3. Parbauda manifest.psd1 parakstu un hub-sync.ps1 SHA256.
   4. Iekope hub-sync.ps1 uz C:\Hub\Tools, mapes State/Tools.
   5. Registre uzdevumu 'Hub-Sync' (SYSTEM, ik 15 min + startejot)
      un palaiz to vienreiz.
============================================================
#>

param(
    [Parameter(Mandatory = $true)]
    [string]$ExpectedThumbprint,
    [string]$Branch = "Auce",
    [string]$HubRoot = "C:\Hub",
    [string]$TaskName = "Hub-Sync"
)

$ErrorActionPreference = "Stop"
$ExpectedThumbprint = ($ExpectedThumbprint -replace '\s', '').ToUpperInvariant()

$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) { Write-Host "KLUDA: palaidiet ka Administrators." -ForegroundColor Red; exit 1 }

$incoming = Join-Path $HubRoot "Sync\Skripti"
$cerPath  = @(Get-ChildItem -Path (Join-Path $incoming "Tools") -Filter *.cer -File -ErrorAction SilentlyContinue)
$manifest = Join-Path $incoming "manifest.psd1"
$syncSrc  = Join-Path $incoming "Tools\hub-sync.ps1"

if ($cerPath.Count -ne 1) { Write-Host "KLUDA: Sync\Skripti\Tools jabut tiesi vienam .cer failam (ir $($cerPath.Count))." -ForegroundColor Red; exit 1 }
foreach ($p in @($manifest, $syncSrc)) {
    if (-not (Test-Path $p)) { Write-Host "KLUDA: nav $p (vai Drive jau sinhronizeja?)." -ForegroundColor Red; exit 1 }
}

# 1. Sertifikats
$cer = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2($cerPath[0].FullName)
Write-Host "Sertifikats: $($cer.Subject)  thumbprint $($cer.Thumbprint)  lidz $($cer.NotAfter.ToString('yyyy-MM-dd'))"
if ($cer.Thumbprint.ToUpperInvariant() -ne $ExpectedThumbprint) {
    Write-Host "KLUDA: thumbprint NESAKRIT ar -ExpectedThumbprint. NEKO nedaru." -ForegroundColor Red
    exit 1
}

# 2. Uzticams sakne (tikai sis viens pasparakstitais koda parakstisanas sertifikats)
$inRoot = Get-ChildItem Cert:\LocalMachine\Root | Where-Object { $_.Thumbprint -eq $cer.Thumbprint }
if (-not $inRoot) {
    Import-Certificate -FilePath $cerPath[0].FullName -CertStoreLocation Cert:\LocalMachine\Root | Out-Null
    Write-Host "Sertifikats ielikts LocalMachine\Root."
} else {
    Write-Host "Sertifikats jau ir LocalMachine\Root."
}

# 3. Manifesta paraksts un hub-sync.ps1 hash
$sig = Get-AuthenticodeSignature -FilePath $manifest
if ($sig.Status -ne "Valid" -or $sig.SignerCertificate.Thumbprint -ne $cer.Thumbprint) {
    Write-Host "KLUDA: manifest.psd1 paraksts: $($sig.Status) ($($sig.StatusMessage)), parakstitajs $($sig.SignerCertificate.Thumbprint)." -ForegroundColor Red
    exit 1
}
$m = Import-PowerShellDataFile -Path $manifest
if ([string]$m.Branch -ne $Branch) { Write-Host "KLUDA: manifest Branch '$($m.Branch)' nav '$Branch'." -ForegroundColor Red; exit 1 }
$want = [string]$m.Files["Tools\hub-sync.ps1"]
$have = (Get-FileHash -LiteralPath $syncSrc -Algorithm SHA256).Hash
if (-not $want -or $want.ToUpperInvariant() -ne $have) {
    Write-Host "KLUDA: hub-sync.ps1 SHA256 nesakrit ar manifestu (vai Drive vel sinhronize?)." -ForegroundColor Red
    exit 1
}
Write-Host "Manifests (Sequence $($m.Sequence)) un hub-sync.ps1 parbauditi."

# 4. Mapes un skripts
foreach ($d in @("Tools", "State")) {
    $p = Join-Path $HubRoot $d
    if (-not (Test-Path $p)) { New-Item -ItemType Directory -Path $p -Force | Out-Null }
}
$syncDst = Join-Path $HubRoot "Tools\hub-sync.ps1"
Copy-Item -LiteralPath $syncSrc -Destination $syncDst -Force

# 5. Planotais uzdevums
$arg = "-NoProfile -NonInteractive -ExecutionPolicy Bypass -File `"$syncDst`" -SignerThumbprint $($cer.Thumbprint) -Branch $Branch -HubRoot `"$HubRoot`""
$action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument $arg
$t1 = New-ScheduledTaskTrigger -Once -At (Get-Date).AddMinutes(1) -RepetitionInterval (New-TimeSpan -Minutes 15)
$t2 = New-ScheduledTaskTrigger -AtStartup
$t2.Delay = "PT2M"
$principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest
$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -MultipleInstances IgnoreNew -ExecutionTimeLimit (New-TimeSpan -Minutes 30)
Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger @($t1, $t2) -Principal $principal -Settings $settings -Description "Filiales hub: parakstitu skriptu publicesana un atskaites (hub-sync.ps1)." -Force | Out-Null
Write-Host "Uzdevums '$TaskName' registrets (SYSTEM, ik 15 min + startejot)."

Start-ScheduledTask -TaskName $TaskName
Start-Sleep -Seconds 20
$info = Get-ScheduledTaskInfo -TaskName $TaskName
Write-Host "Pirma palaisana: LastTaskResult = $($info.LastTaskResult) (0 = OK)"
$log = Join-Path $HubRoot "State\hub-sync.log"
if (Test-Path $log) { Write-Host "`n--- hub-sync.log (beigas) ---"; Get-Content $log -Tail 10 }
