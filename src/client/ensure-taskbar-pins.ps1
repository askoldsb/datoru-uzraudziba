<#
 ensure-taskbar-pins.ps1   (NAS Scripts; izsauc client-install.ps1 cikla beigas)
 Windows 11: piespraud programmu ikonas pie taskbar visiem lietotajiem, nolasot Config\taskbar-pins.csv.
 CSV kolonnas: Enabled,Key,Name,ExePattern,Targets
   ExePattern - cels ar aizstajzimem (piem. C:\Program Files\Blender Foundation\*\blender.exe); ja vairaki, nem pedejo pec nosaukuma.
   Targets    - datoru nosaukumu paraugi ar aizstajzimem (-like), atdaliti ar ';' (piem. DATORKLASE-*;DN0*;PC0*). Tukss = visi.
 Ikona tiek pievienota TIKAI ja programma ir uzstadita. Windows 10 (build < 22000) tiek izlaists.
 Mehanisms: stabilas saisnes C:\ProgramData\LabUpdates\Pins\<Name>.lnk + taskbar-layout.xml + registrs
 HKLM\SOFTWARE\Policies\Microsoft\Windows\Explorer (StartLayoutFile, LockedStartLayout=1). Stajas speka pec izlogosanas/ielogosanas.
#>
param(
    [string]$NasRoot = "\\192.168.3.31\Updates"
)

function Write-PinLog {
    param([string]$Message, [string]$Level = "INFO")
    if (Get-Command Write-Log -ErrorAction SilentlyContinue) { Write-Log $Message $Level }
    else { Write-Host "[$Level] $Message" }
}

try {
    $build = [int](Get-CimInstance Win32_OperatingSystem).BuildNumber
    if ($build -lt 22000) { return }

    $csvPath = Join-Path $NasRoot "Config\taskbar-pins.csv"
    if (-not (Test-Path $csvPath)) { return }

    $pc = $env:COMPUTERNAME
    $pins = @()
    foreach ($r in @(Import-Csv -Path $csvPath -Encoding UTF8)) {
        if ([string]$r.Enabled -ne "1") { continue }
        if ([string]::IsNullOrWhiteSpace($r.Name) -or [string]::IsNullOrWhiteSpace($r.ExePattern)) { continue }
        $targets = @(([string]$r.Targets) -split ';' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
        if ($targets.Count -gt 0) {
            $hit = $false
            foreach ($t in $targets) { if ($pc -like $t) { $hit = $true } }
            if (-not $hit) { continue }
        }
        $exe = Get-ChildItem -Path ([string]$r.ExePattern) -ErrorAction SilentlyContinue | Sort-Object FullName | Select-Object -Last 1
        if (-not $exe) { continue }
        $pins += [pscustomobject]@{ Name = ([string]$r.Name).Trim(); Exe = $exe.FullName }
    }
    if ($pins.Count -eq 0) { return }

    $dir = "C:\ProgramData\LabUpdates\Pins"
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }

    $changed = $false
    $w = New-Object -ComObject WScript.Shell
    foreach ($p in $pins) {
        $lnk = Join-Path $dir ($p.Name + ".lnk")
        $need = $true
        if (Test-Path $lnk) {
            $cur = $w.CreateShortcut($lnk)
            if ($cur.TargetPath -eq $p.Exe) { $need = $false }
        }
        if ($need) {
            $s = $w.CreateShortcut($lnk)
            $s.TargetPath = $p.Exe
            $s.WorkingDirectory = Split-Path $p.Exe
            $s.Save()
            $changed = $true
            Write-PinLog "Taskbar pins: saisne $($p.Name) -> $($p.Exe)"
        }
    }

    $lines = @(
        '<?xml version="1.0" encoding="utf-8"?>',
        '<LayoutModificationTemplate xmlns="http://schemas.microsoft.com/Start/2014/LayoutModification" xmlns:defaultlayout="http://schemas.microsoft.com/Start/2014/FullDefaultLayout" xmlns:start="http://schemas.microsoft.com/Start/2014/StartLayout" xmlns:taskbar="http://schemas.microsoft.com/Start/2014/TaskbarLayout" Version="1">',
        '<CustomTaskbarLayoutCollection>',
        '<defaultlayout:TaskbarLayout>',
        '<taskbar:TaskbarPinList>'
    )
    foreach ($p in $pins) {
        $lines += ('<taskbar:DesktopApp DesktopApplicationLinkPath="' + (Join-Path $dir ($p.Name + ".lnk")) + '"/>')
    }
    $lines += @('</taskbar:TaskbarPinList>', '</defaultlayout:TaskbarLayout>', '</CustomTaskbarLayoutCollection>', '</LayoutModificationTemplate>')
    $xml = ($lines -join "`r`n") + "`r`n"

    $xmlPath = Join-Path $dir "taskbar-layout.xml"
    $old = ""
    if (Test-Path $xmlPath) { $old = [System.IO.File]::ReadAllText($xmlPath) }
    if ($old -ne $xml -or $changed) {
        [System.IO.File]::WriteAllText($xmlPath, $xml, (New-Object System.Text.UTF8Encoding($true)))
        Write-PinLog "Taskbar pins: izkartojums atjaunots ($(($pins | ForEach-Object { $_.Name }) -join ', ')); stasies speka pec izlogosanas/ielogosanas."
    }

    $k = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Explorer"
    if (-not (Test-Path $k)) { New-Item -Path $k -Force | Out-Null }
    $cur = Get-ItemProperty -Path $k -ErrorAction SilentlyContinue
    if ($cur.StartLayoutFile -ne $xmlPath) {
        New-ItemProperty -Path $k -Name StartLayoutFile -Value $xmlPath -PropertyType ExpandString -Force | Out-Null
    }
    if ($cur.LockedStartLayout -ne 1) {
        New-ItemProperty -Path $k -Name LockedStartLayout -Value 1 -PropertyType DWord -Force | Out-Null
    }
} catch {
    Write-PinLog "Taskbar pins: kluda - $_" "WARN"
}
