<#
============================================================
 publish-filiale.ps1
 Admin dators (PIUAC-ASKOLDS), parasts PowerShell ar Askolda
 kontu (sertifikats ir CurrentUser\My).

 Sagatavo un PARAKSTA filiales publikaciju un ieliek to NAS
 \\...\Filiales\<Branch>\Skripti, no kurienes Synology Drive
 to nogada filiales hub datoram (hub-sync.ps1 parbauda parakstu
 un SHA256 un tikai tad parnes uz hub Updates).

 Avota mape ($Source) atkarto merka strukturu:
   Scripts\  -> hub C:\Hub\Updates\Scripts   (client-install.ps1 u.c.)
   Config\   -> hub C:\Hub\Updates\Config    (device-schedule.csv, apps-managed.csv ...)
   Modules\  -> hub C:\Hub\Updates\Modules   (PSWindowsUpdate)
   Tools\    -> hub C:\Hub\Tools             (hub-sync.ps1, sertifikata .cer)

 -RefreshFromNas: pirms publicesanas iekope avota mape dzivas
 versijas no Dobeles NAS (Scripts: client-install.ps1,
 collect-inventory.ps1, update-notice.ps1; Modules\PSWindowsUpdate).
 Config\ NETIEK parrakstits (filiales grafiks ir savs).

 Piemers:
   .\publish-filiale.ps1 -Branch Auce -RefreshFromNas -WhatIf
   .\publish-filiale.ps1 -Branch Auce -RefreshFromNas
============================================================
#>

param(
    [string]$Branch = "Auce",
    [string]$Source = "",
    [string]$Destination = "",
    [string]$NasUpdates = "\\192.168.3.31\Updates",
    [string]$CertSubject = "CN=PIUAC filiales skripti",
    [switch]$RefreshFromNas,
    [switch]$WhatIf
)

$ErrorActionPreference = "Stop"

if (-not $Source)      { $Source = "C:\Scripts\Filiales\$Branch" }
if (-not $Destination) { $Destination = "\\192.168.3.31\Filiales\$Branch\Skripti" }

$AllowedTop = @("Scripts", "Config", "Modules", "Tools")
$NasScriptNames = @("client-install.ps1", "collect-inventory.ps1", "update-notice.ps1")

function Write-Step { param([string]$T) Write-Host "`n=== $T ===" -ForegroundColor Cyan }

# ---------- PARBAUDES ----------

if ($Destination -notmatch '\\Filiales\\[^\\]+\\Skripti\\?$') {
    Write-Host "KLUDA: -Destination jabeidzas ar \Filiales\<filiale>\Skripti ($Destination)." -ForegroundColor Red
    exit 1
}
if (-not (Test-Path $Destination)) {
    Write-Host "KLUDA: $Destination nav pieejams (NAS, tiesibas?)." -ForegroundColor Red
    exit 1
}

$cert = @(Get-ChildItem Cert:\CurrentUser\My -CodeSigningCert | Where-Object { $_.Subject -eq $CertSubject -and $_.HasPrivateKey -and $_.NotAfter -gt (Get-Date) } | Sort-Object NotAfter -Descending)
if ($cert.Count -eq 0) {
    Write-Host "KLUDA: nav deriga koda parakstisanas sertifikata '$CertSubject' (CurrentUser\My). Palaidiet new-signing-cert.ps1." -ForegroundColor Red
    exit 1
}
$cert = $cert[0]
Write-Host "Sertifikats: $($cert.Subject)  thumbprint $($cert.Thumbprint)  lidz $($cert.NotAfter.ToString('yyyy-MM-dd'))"

# ---------- AVOTA ATJAUNOSANA NO NAS ----------

if ($RefreshFromNas) {
    Write-Step "Dzivas versijas no $NasUpdates"
    $sd = Join-Path $Source "Scripts"
    if (-not (Test-Path $sd)) { New-Item -ItemType Directory -Path $sd -Force | Out-Null }
    foreach ($n in $NasScriptNames) {
        $from = Join-Path $NasUpdates "Scripts\$n"
        if (Test-Path $from) {
            Copy-Item -LiteralPath $from -Destination (Join-Path $sd $n) -Force
            Write-Host "  Scripts\$n"
        } else {
            Write-Host "  BRIDINAJUMS: nav $from" -ForegroundColor Yellow
        }
    }
    $modFrom = Join-Path $NasUpdates "Modules\PSWindowsUpdate"
    if (Test-Path $modFrom) {
        $modTo = Join-Path $Source "Modules\PSWindowsUpdate"
        if (Test-Path $modTo) { Remove-Item $modTo -Recurse -Force }
        Copy-Item -LiteralPath $modFrom -Destination $modTo -Recurse -Force
        Write-Host "  Modules\PSWindowsUpdate"
    } else {
        Write-Host "  BRIDINAJUMS: nav $modFrom" -ForegroundColor Yellow
    }
}

# ---------- MANIFESTS ----------

Write-Step "Failu saraksts un SHA256 ($Source)"
if (-not (Test-Path $Source)) {
    Write-Host "KLUDA: avota mape $Source nav atrasta." -ForegroundColor Red
    exit 1
}
$srcFull = (Resolve-Path $Source).Path.TrimEnd('\')
$files = [ordered]@{}
foreach ($top in $AllowedTop) {
    $dir = Join-Path $srcFull $top
    if (-not (Test-Path $dir)) { continue }
    foreach ($f in @(Get-ChildItem -Path $dir -File -Recurse | Sort-Object FullName)) {
        $rel = $f.FullName.Substring($srcFull.Length + 1)
        if ($rel -match "['`"]") {
            Write-Host "KLUDA: faila nosaukuma nedrikst but pedinas: $rel" -ForegroundColor Red
            exit 1
        }
        $files[$rel] = (Get-FileHash -LiteralPath $f.FullName -Algorithm SHA256).Hash
        Write-Host ("  {0}  {1}" -f $files[$rel].Substring(0, 12), $rel)
    }
}
$unknown = @(Get-ChildItem -Path $srcFull -Directory | Where-Object { $AllowedTop -notcontains $_.Name })
foreach ($u in $unknown) { Write-Host "  (izlaista mape $($u.Name) - nav atlauta)" -ForegroundColor Yellow }
if ($files.Count -eq 0) {
    Write-Host "KLUDA: nav neviena faila publicesanai." -ForegroundColor Red
    exit 1
}

$seq = (Get-Date).ToString("yyyyMMddHHmmss")
$sb = New-Object System.Text.StringBuilder
[void]$sb.AppendLine("@{")
[void]$sb.AppendLine("    Branch    = '$Branch'")
[void]$sb.AppendLine("    Sequence  = $seq")
[void]$sb.AppendLine("    Created   = '$((Get-Date).ToString('yyyy-MM-dd HH:mm:ss'))'")
[void]$sb.AppendLine("    CreatedBy = '$env:COMPUTERNAME\$env:USERNAME'")
[void]$sb.AppendLine("    Files     = @{")
foreach ($k in $files.Keys) { [void]$sb.AppendLine("        '$k' = '$($files[$k])'") }
[void]$sb.AppendLine("    }")
[void]$sb.AppendLine("}")

$work = Join-Path $env:TEMP "publish-$Branch-$seq"
New-Item -ItemType Directory -Path $work -Force | Out-Null
$manifest = Join-Path $work "manifest.psd1"
[System.IO.File]::WriteAllText($manifest, $sb.ToString(), (New-Object System.Text.UTF8Encoding($true)))

Write-Step "Parakstisana"
$res = Set-AuthenticodeSignature -FilePath $manifest -Certificate $cert -HashAlgorithm SHA256
$chk = Get-AuthenticodeSignature -FilePath $manifest
if ($chk.SignerCertificate.Thumbprint -ne $cert.Thumbprint -or $chk.Status -eq "HashMismatch" -or $chk.Status -eq "NotSigned") {
    Write-Host "KLUDA: parakstisana neizdevas ($($res.Status) / $($chk.Status): $($chk.StatusMessage))." -ForegroundColor Red
    exit 1
}
Write-Host "manifest.psd1 parakstits (Sequence $seq, $($files.Count) faili). Lokala parbaude: $($chk.Status)"

if ($WhatIf) {
    Write-Host "`n-WhatIf: uz NAS nekas netika kopets. Manifests: $manifest" -ForegroundColor Yellow
    exit 0
}

# ---------- KOPESANA UZ NAS ----------

Write-Step "Kopesana uz $Destination"
# Vispirms faili (spogulis; manifest.psd1 izslegts), manifests - pedejais.
foreach ($top in $AllowedTop) {
    $from = Join-Path $srcFull $top
    $to = Join-Path $Destination $top
    if (Test-Path $from) {
        & robocopy.exe $from $to /MIR /R:2 /W:3 /NP /NJH /NJS /NDL | Out-Null
        if ($LASTEXITCODE -ge 8) { Write-Host "KLUDA: robocopy $top ($LASTEXITCODE)" -ForegroundColor Red; exit 1 }
    } elseif (Test-Path $to) {
        Remove-Item $to -Recurse -Force
    }
}
Copy-Item -LiteralPath $manifest -Destination (Join-Path $Destination "manifest.psd1") -Force
Remove-Item $work -Recurse -Force -ErrorAction SilentlyContinue

Write-Host "`nGATAVS: publicets $Branch Sequence $seq. Hub to panems ~15-30 min laika (Drive + Hub-Sync)." -ForegroundColor Green
Write-Host "Rezultats: NAS Filiales\$Branch\Atskaites\Hub\<hub>.json -> PublishResult / PublishedSequence."
