<#
 profile-size-survey.ps1  (TIKAI LASISANA, datoros nekas netiek mainits)
 Palaist uz admin datora (PIUAC-ASKOLDS), PowerShell kaa administrators.
 Nolasa no NAS Config\device-schedule.csv datorus ar Group=staff un Enabled=Yes,
 IP nem no Logs\Inventory\<DATORS>.json, pieslegtas pa WinRM un saskaita
 rezerves kopijai paredzeto datu apjomu katra lietotaja profila.
 Rezultats: C:\Users\Public\profile-size-survey.csv + tabula ekraanaa.
#>
param(
    [string]$NasRoot = "\\192.168.3.31\Updates",
    [string]$Group   = "staff",
    [string]$Out     = "C:\Users\Public\profile-size-survey.csv"
)

$ErrorActionPreference = "Stop"
$csv = Join-Path $NasRoot "Config\device-schedule.csv"
$rows = @(Import-Csv $csv | Where-Object { $_.Group -eq $Group -and $_.Enabled -eq "Yes" })
"Datori ar Group=$Group : $($rows.Count)"
if ($rows.Count -eq 0) { return }

$c = Get-Credential -UserName "Administrator" -Message "Datoru lokalais administrators"
$user = ($c.UserName -split '\\')[-1]
$opt  = New-PSSessionOption -OpenTimeout 8000 -OperationTimeout 600000

$sb = {
    # Mapes, ko planojam kopet (lietotaja profilaa), un meklejamie faili
    $result = @()
    $profiles = Get-ChildItem C:\Users -Directory -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -notin 'Public','Default','Default User','All Users' -and $_.Name -notlike 'defaultuser*' }
    foreach ($p in $profiles) {
        $paths = [ordered]@{
            Desktop    = "$($p.FullName)\Desktop"
            Documents  = "$($p.FullName)\Documents"
            Outlook    = "$($p.FullName)\AppData\Roaming\Microsoft\Signatures"
            Chrome     = "$($p.FullName)\AppData\Local\Google\Chrome\User Data\Default"
            Edge       = "$($p.FullName)\AppData\Local\Microsoft\Edge\User Data\Default"
            Firefox    = "$($p.FullName)\AppData\Roaming\Mozilla\Firefox\Profiles"
            Downloads  = "$($p.FullName)\Downloads"
            Pictures   = "$($p.FullName)\Pictures"
        }
        $o = [ordered]@{ Profils = $p.Name }
        foreach ($k in $paths.Keys) {
            $sz = 0
            if (Test-Path $paths[$k]) {
                if ($k -in 'Chrome','Edge') {
                    # tikai gramatzimes/preferences, nevis kesu
                    foreach ($f in 'Bookmarks','Preferences','Login Data','Favicons') {
                        $fp = Join-Path $paths[$k] $f
                        if (Test-Path $fp) { $sz += (Get-Item $fp -Force).Length }
                    }
                } else {
                    $m = Get-ChildItem $paths[$k] -Recurse -File -Force -ErrorAction SilentlyContinue |
                         Measure-Object Length -Sum
                    if ($m.Sum) { $sz = $m.Sum }
                }
            }
            $o[$k] = [math]::Round($sz / 1MB)
        }
        # PST/OST/OLM faili jebkur citur D:, E: (tikai PST, OST neskaitam)
        $result += [PSCustomObject]$o
    }
    # PST faili citos diskos (parasti E:\Outlook Files)
    $pst = 0
    foreach ($d in (Get-PSDrive -PSProvider FileSystem | Where-Object { $_.Name -ne 'C' -and $_.Root -match '^[A-Z]:\\$' })) {
        $m = Get-ChildItem $d.Root -Recurse -File -Force -Filter *.pst -ErrorAction SilentlyContinue | Measure-Object Length -Sum
        if ($m.Sum) { $pst += $m.Sum }
    }
    [PSCustomObject]@{ Profiles = $result; PstOtherDrivesMB = [math]::Round($pst / 1MB) }
}

$report = @()
foreach ($r in $rows) {
    $name = $r.ComputerName
    $invFile = Join-Path $NasRoot "Logs\Inventory\$name.json"
    $ip = ""
    if (Test-Path $invFile) {
        $inv = Get-Content $invFile -Raw -Encoding UTF8 | ConvertFrom-Json
        foreach ($a in @($inv.Network.Adapters)) {
            foreach ($i in @($a.IPv4)) { if ($i -match '^192\.168\.') { $ip = [string]$i; break } }
            if ($ip) { break }
        }
    }
    $target = if ($ip) { $ip } else { $name }
    Write-Host "$name ($target) ..." -NoNewline
    try {
        $cred = New-Object System.Management.Automation.PSCredential(($name + "\" + $user), $c.Password)
        $res = Invoke-Command -ComputerName $target -Credential $cred -SessionOption $opt -ScriptBlock $sb -ErrorAction Stop
        foreach ($p in @($res.Profiles)) {
            $total = $p.Desktop + $p.Documents + $p.Outlook + $p.Chrome + $p.Edge + $p.Firefox + $p.Downloads + $p.Pictures
            $report += [PSCustomObject]@{
                Dators = $name; Profils = $p.Profils
                Desktop_MB = $p.Desktop; Documents_MB = $p.Documents; Paraksti_MB = $p.Outlook
                Chrome_MB = $p.Chrome; Edge_MB = $p.Edge; Firefox_MB = $p.Firefox
                Downloads_MB = $p.Downloads; Pictures_MB = $p.Pictures
                PST_citi_diski_MB = $res.PstOtherDrivesMB
                KOPA_bez_Downloads_Pictures_MB = $total - $p.Downloads - $p.Pictures
                KOPA_MB = $total
            }
        }
        Write-Host " OK"
    } catch {
        $m = $_.Exception.Message; if ($m.Length -gt 80) { $m = $m.Substring(0,80) + "..." }
        Write-Host " KLUDA: $m" -ForegroundColor Yellow
        $report += [PSCustomObject]@{ Dators = $name; Profils = "KLUDA: $m" }
    }
}

$report | Export-Csv $Out -NoTypeInformation -Encoding UTF8
$report | Format-Table Dators, Profils, Desktop_MB, Documents_MB, PST_citi_diski_MB, Downloads_MB, KOPA_bez_Downloads_Pictures_MB, KOPA_MB -AutoSize
$ok = @($report | Where-Object { $null -ne $_.KOPA_MB })
$sumMin = ($ok | Measure-Object KOPA_bez_Downloads_Pictures_MB -Sum).Sum
$sumAll = ($ok | Measure-Object KOPA_MB -Sum).Sum
$pstAll = ($ok | Group-Object Dators | ForEach-Object { $_.Group[0].PST_citi_diski_MB } | Measure-Object -Sum).Sum
"KOPA (bez Downloads/Pictures): {0:N1} GB   ar Downloads/Pictures: {1:N1} GB   PST citos diskos: {2:N1} GB" -f ($sumMin/1024), ($sumAll/1024), ($pstAll/1024)
"Csv: $Out"
