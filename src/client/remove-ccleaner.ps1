<#
============================================================
 remove-ccleaner.ps1
 Vienreizeja attalinata CCleaner atinstalesana klases datoriem.
 (Aizstaj iepriekseju uninstall-old-software.ps1, kura eParakstitaja dala
  izrazijas bistama un ir iznemta.)

 Lietosana (no admina datora, uz vairakiem datoriem vienlaikus):
   Invoke-Command -ComputerName "DATORS-01","DATORS-02" -Credential $cred -FilePath "C:\Scripts\remove-ccleaner.ps1" -ArgumentList "Preview"

 Mode: "Preview" (noklusejums) = TIKAI paradit, ko darits, neko nemaina;
       "Run" = atinstale.
 Dators netiek restartets.
============================================================
#>

param(
    [string]$Mode = "Preview"
)

$ErrorActionPreference = "Continue"
$doRun = ($Mode -eq "Run")

$uninstallPaths = @(
    "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*",
    "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*"
)

function Get-CCleanerEntries {
    return @(Get-ItemProperty -Path $uninstallPaths -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName -eq "CCleaner" })
}

$text = @()
$entries = Get-CCleanerEntries
if ($entries.Count -eq 0) { $text += "Nav uzstadits" }

foreach ($c in $entries) {
    $us = [string]$c.UninstallString
    $exe = ""
    if ($us -match '^"([^"]+)"') { $exe = $Matches[1] } else { $exe = ($us -split ' ')[0] }

    if ((-not $exe) -or (-not (Test-Path $exe))) {
        $text += "CCleaner $($c.DisplayVersion): atinstaletajs nav atrasts ($exe)"
        continue
    }
    if (-not $doRun) {
        $text += "Atinstaletu CCleaner $($c.DisplayVersion)"
        continue
    }

    # apturam CCleaner procesus, lai atinstalesana neapstajas uz atvertiem failiem
    Get-Process -Name "CCleaner", "CCleaner64", "CCUpdate" -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue

    # NSIS atinstaletajs atgriezas uzreiz, tapec gaidam, kamer registra ieraksts pazud (lidz 90 s)
    Start-Process -FilePath $exe -ArgumentList "/S" -WindowStyle Hidden
    $gone = $false
    for ($i = 0; $i -lt 18; $i++) {
        Start-Sleep -Seconds 5
        if ((Get-CCleanerEntries).Count -eq 0) { $gone = $true; break }
    }
    if ($gone) {
        $text += "Atinstalets CCleaner $($c.DisplayVersion)"
    } else {
        $text += "KLUDA: CCleaner ieraksts pec 90 s joprojam ir"
    }
}

[PSCustomObject]@{
    Computer = $env:COMPUTERNAME
    Mode     = $Mode
    CCleaner = ($text -join "; ")
}
