<#
============================================================
 generate-status-report.ps1
 Apkopo visu klientu statusa failus (Logs\Status\*.json, ko
 raksta client-install.ps1) viena parskatama CSV faila.

 Palaizams pec vajadzibas administratora datora (manuali, vai
 velak var pievienot ka Scheduled Task, piem. reizi stunda).
============================================================
#>

param(
    [string]$NasRoot = "\\PIUAC_CLOUD\Updates",
    [string]$OutputPath = ""
)

$StatusDir = Join-Path $NasRoot "Logs\Status"
if ([string]::IsNullOrWhiteSpace($OutputPath)) {
    $OutputPath = Join-Path $NasRoot "Reports\status-report.csv"
}

if (-not (Test-Path $StatusDir)) {
    Write-Host "Statusa mape nav atrasta ($StatusDir) - vel neviens klients nav palaidies ar jauno versiju." -ForegroundColor Yellow
    exit 0
}

$outputDir = Split-Path $OutputPath -Parent
if (-not (Test-Path $outputDir)) {
    New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
}

$statusFiles = Get-ChildItem -Path $StatusDir -Filter "*.json" -File
if ($statusFiles.Count -eq 0) {
    Write-Host "Nav atrasts neviens statusa fails $StatusDir." -ForegroundColor Yellow
    exit 0
}

$report = @()
foreach ($f in $statusFiles) {
    try {
        $data = Get-Content $f.FullName -Raw -Encoding UTF8 | ConvertFrom-Json

        $lastSuccess = if ($data.LastSuccessfulUpdate) { $data.LastSuccessfulUpdate } else { "(nav zinams)" }
        $daysSinceSuccess = ""
        if ($data.LastSuccessfulUpdate) {
            try {
                $parsed = [datetime]::ParseExact($data.LastSuccessfulUpdate, "yyyy-MM-dd HH:mm:ss", $null)
                $daysSinceSuccess = [math]::Round(((Get-Date) - $parsed).TotalDays, 1)
            } catch {
                $daysSinceSuccess = ""
            }
        }

        $report += [PSCustomObject]@{
            Dators                 = $data.ComputerName
            PedejaParbaude         = $data.LastCheck
            PedejaVeiksmigaAtj     = $lastSuccess
            DienasKopsPedejas      = $daysSinceSuccess
            Rezultats              = $data.LastResult
            Detalas                = $data.Details
        }
    } catch {
        Write-Host "Neizdevas nolasit $($f.Name): $_" -ForegroundColor Yellow
    }
}

$report = $report | Sort-Object Dators
$report | Export-Csv -Path $OutputPath -NoTypeInformation -Encoding UTF8

Write-Host "Atskaite izveidota: $OutputPath ($($report.Count) datori)" -ForegroundColor Green

# Isa versija ari uz ekrana
$report | Format-Table Dators, PedejaParbaude, PedejaVeiksmigaAtj, DienasKopsPedejas, Rezultats -AutoSize
