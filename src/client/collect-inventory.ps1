<#
============================================================
 collect-inventory.ps1
 Ievac datora aparaturas un programmatura inventaru (TIKAI LASISANA:
 neko neinstale, nemaina un nerakst sistema) un sagatavo vienu JSON.

 Lietosana:
   Testam attalinati no admina datora (JSON atnak teksta veida):
     $json = Invoke-Command -ComputerName "DATORS" -Credential $cred -FilePath "C:\Scripts\collect-inventory.ps1" -ArgumentList "\\192.168.3.31\Updates","Json"

   Uz pasa datora (ar NAS piekluvi) ieraksta NAS Logs\Inventory\DATORS.json:
     powershell.exe -ExecutionPolicy Bypass -File collect-inventory.ps1

 Ievaktie dati: aparatura, Windows, instaletas programmas ar versijam,
 tikla adapteri. NETIEK ievaktas: lietotaju vardi, parlukosanas vesture,
 monitoru serijas numuri.
 Programmu saraksts: dators + patlaban ielogoto lietotaju profili.
============================================================
#>

param(
    [string]$NasRoot = "\\192.168.3.31\Updates",

    # "Nas"  = ieraksta NAS Logs\Inventory\<dators>.json
    # "Json" = atgriez JSON tekstu (testam vai attalinatai palaisanai)
    [string]$Mode = "Nas"
)

$ErrorActionPreference = "Continue"
$started = Get-Date
$script:errors = @()

# ---------- Palidzfunkcijas ----------

function Get-Clean {
    param($Value)
    if ($null -eq $Value) { return "" }
    return ([string]$Value).Trim()
}

function Get-CleanSerial {
    # Daudzas matesplates BIOS atstaj razotaja ligumiskas vertibas ("Default string",
    # "To be filled by O.E.M."), kas NAV serijas numurs - tas tiek aizstats ar tuksu vertibu.
    param($Value)
    $text = Get-Clean $Value
    $placeholders = @("default string", "to be filled by o.e.m.", "system serial number", "not specified", "not applicable", "none", "n/a", "123456789", "serial number", "unknown", "o.e.m.", "oem")
    if ($placeholders -contains $text.ToLower()) { return "" }
    if ($text -match '^0+$') { return "" }
    return $text
}

function Format-DateOnly {
    param($Value)
    if ($null -eq $Value) { return "" }
    try { return ([datetime]$Value).ToString("yyyy-MM-dd") } catch { return "" }
}

function Convert-Chars {
    # WMI monitoru teksta lauki ir masivs ar rakstzimju kodiem
    param($Codes)
    if (-not $Codes) { return "" }
    $text = ""
    foreach ($c in $Codes) {
        if ($c -ne 0) { $text = $text + [string][char]$c }
    }
    return $text.Trim()
}

function Invoke-Section {
    # Katra sadala darbojas atseviski: ja viena neizdodas, parejas sadalas tiek ievaktas,
    # un kluda tiek ierakstita saraksta Errors.
    param([string]$Name, [scriptblock]$Code)
    try {
        return (& $Code)
    } catch {
        $script:errors += ("{0}: {1}" -f $Name, $_.Exception.Message)
        return $null
    }
}

# ---------- Dators ----------

$computer = Invoke-Section "Computer" {
    $cs = Get-CimInstance Win32_ComputerSystem
    $bios = Get-CimInstance Win32_BIOS | Select-Object -First 1
    $enc = Get-CimInstance Win32_SystemEnclosure | Select-Object -First 1

    $chassisMap = @{ 3 = "Desktop"; 4 = "Low Profile Desktop"; 6 = "Mini Tower"; 7 = "Tower"; 8 = "Portable"; 9 = "Laptop"; 10 = "Notebook"; 13 = "All in One"; 14 = "Sub Notebook"; 30 = "Tablet"; 31 = "Convertible"; 35 = "Mini PC"; 36 = "Stick PC" }
    $chassis = ""
    $chassisCode = 0
    if ($enc -and $enc.ChassisTypes) {
        $chassisCode = [int]($enc.ChassisTypes | Select-Object -First 1)
        if ($chassisMap.ContainsKey($chassisCode)) { $chassis = $chassisMap[$chassisCode] } else { $chassis = "Kods $chassisCode" }
    }

    # Portativais vai stacionarais: vispirms pec korpusa koda (SMBIOS), tad pec sistemas tipa,
    # un tikai beigas pec baterijas (jo dazam stacionaram datoram "baterijas" ierice ir UPS).
    $battery = Get-CimInstance Win32_Battery -ErrorAction SilentlyContinue | Select-Object -First 1
    $pcType = [int]$cs.PCSystemType
    $category = "Unknown"
    if (@(8, 9, 10, 11, 14, 30, 31, 32) -contains $chassisCode) {
        $category = "Portable"
    } elseif (@(3, 4, 5, 6, 7, 13, 15, 16, 17, 23, 24, 33, 34, 35, 36) -contains $chassisCode) {
        $category = "Stationary"
    } elseif ($pcType -eq 2) {
        $category = "Portable"
    } elseif (@(1, 3, 4, 5, 6, 7) -contains $pcType) {
        $category = "Stationary"
    } elseif ($battery) {
        $category = "Portable"
    }

    [ordered]@{
        Name         = $env:COMPUTERNAME
        Manufacturer = (Get-Clean $cs.Manufacturer)
        Model        = (Get-Clean $cs.Model)
        Type         = $chassis
        ChassisCode  = $chassisCode
        Category     = $category
        HasBattery   = [bool]$battery
        PCSystemType = $pcType
        Serial       = (Get-CleanSerial $bios.SerialNumber)
        BiosVendor   = (Get-Clean $bios.Manufacturer)
        BiosVersion  = (Get-Clean $bios.SMBIOSBIOSVersion)
        BiosDate     = (Format-DateOnly $bios.ReleaseDate)
        Workgroup    = (Get-Clean $cs.Domain)
    }
}

# ---------- Matesplate ----------

$board = Invoke-Section "BaseBoard" {
    $b = Get-CimInstance Win32_BaseBoard | Select-Object -First 1
    [ordered]@{
        Manufacturer = (Get-Clean $b.Manufacturer)
        Model        = (Get-Clean $b.Product)
        Serial       = (Get-CleanSerial $b.SerialNumber)
    }
}

# ---------- Procesors ----------

$cpu = Invoke-Section "Processor" {
    $list = @(Get-CimInstance Win32_Processor)
    $cores = ($list | Measure-Object -Property NumberOfCores -Sum).Sum
    $threads = ($list | Measure-Object -Property NumberOfLogicalProcessors -Sum).Sum
    [ordered]@{
        Name        = (Get-Clean $list[0].Name)
        Sockets     = $list.Count
        Cores       = $cores
        Threads     = $threads
        MaxClockMHz = $list[0].MaxClockSpeed
    }
}

# ---------- Atmina ----------

$memory = Invoke-Section "Memory" {
    $typeMap = @{ 20 = "DDR"; 21 = "DDR2"; 24 = "DDR3"; 26 = "DDR4"; 30 = "LPDDR"; 31 = "LPDDR2"; 32 = "LPDDR3"; 33 = "LPDDR4"; 34 = "DDR5"; 35 = "LPDDR5" }
    $modules = @()
    foreach ($m in @(Get-CimInstance Win32_PhysicalMemory)) {
        $t = [int]$m.SMBIOSMemoryType
        $typeName = "Nezinams"
        if ($typeMap.ContainsKey($t)) { $typeName = $typeMap[$t] } elseif ($t -ne 0) { $typeName = "Kods $t" }
        $speed = $m.ConfiguredClockSpeed
        if (-not $speed) { $speed = $m.Speed }
        $modules += [ordered]@{
            Slot         = (Get-Clean $m.DeviceLocator)
            CapacityGB   = [math]::Round($m.Capacity / 1GB, 1)
            Type         = $typeName
            SpeedMHz     = $speed
            Manufacturer = (Get-Clean $m.Manufacturer)
            PartNumber   = (Get-Clean $m.PartNumber)
        }
    }
    $totalGB = [math]::Round((Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory / 1GB, 1)
    [ordered]@{ TotalGB = $totalGB; Modules = $modules }
}

# ---------- Diski ----------

$storage = Invoke-Section "Storage" {
    $physical = @()
    foreach ($d in @(Get-PhysicalDisk -ErrorAction Stop)) {
        $physical += [ordered]@{
            Model       = (Get-Clean $d.FriendlyName)
            MediaType   = (Get-Clean $d.MediaType)
            BusType     = (Get-Clean $d.BusType)
            SizeGB      = [math]::Round($d.Size / 1GB, 0)
            Health      = (Get-Clean $d.HealthStatus)
            Operational = (Get-Clean ($d.OperationalStatus -join ", "))
            Serial      = ((Get-Clean $d.SerialNumber).TrimEnd('.'))
        }
    }
    $volumes = @()
    foreach ($v in @(Get-CimInstance Win32_LogicalDisk -Filter "DriveType=3")) {
        $volumes += [ordered]@{
            Drive      = (Get-Clean $v.DeviceID)
            Label      = (Get-Clean $v.VolumeName)
            FileSystem = (Get-Clean $v.FileSystem)
            SizeGB     = [math]::Round($v.Size / 1GB, 1)
            FreeGB     = [math]::Round($v.FreeSpace / 1GB, 1)
        }
    }
    [ordered]@{ PhysicalDisks = $physical; Volumes = $volumes }
}

# ---------- Video karte ----------

$video = Invoke-Section "Video" {
    $adapters = @()
    foreach ($g in @(Get-CimInstance Win32_VideoController)) {
        $adapters += [ordered]@{
            Name          = (Get-Clean $g.Name)
            DriverVersion = (Get-Clean $g.DriverVersion)
            DriverDate    = (Format-DateOnly $g.DriverDate)
            AdapterRAM_MB = [math]::Round($g.AdapterRAM / 1MB, 0)
        }
    }
    [ordered]@{
        Adapters = $adapters
        Note     = "AdapterRAM nav uzticams virs 4 GB (Windows 32 bitu ierobezojums)"
    }
}

# ---------- Monitori (tikai modelis, bez serijas numura) ----------

$monitors = Invoke-Section "Monitors" {
    $list = @()
    foreach ($m in @(Get-CimInstance -Namespace "root\wmi" -ClassName WmiMonitorID -ErrorAction Stop)) {
        $list += [ordered]@{
            Manufacturer = (Convert-Chars $m.ManufacturerName)
            Model        = (Convert-Chars $m.UserFriendlyName)
            ProductCode  = (Convert-Chars $m.ProductCodeID)
            Year         = $m.YearOfManufacture
        }
    }
    [ordered]@{ Monitors = $list }
}

# ---------- Tikls ----------

$network = Invoke-Section "Network" {
    $adapters = @()
    foreach ($a in @(Get-NetAdapter -Physical -ErrorAction Stop)) {
        $ips = @()
        if ($a.Status -eq "Up") {
            $ips = @(Get-NetIPAddress -InterfaceIndex $a.ifIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue | Where-Object { $_.IPAddress -notlike "169.254.*" } | ForEach-Object { $_.IPAddress })
        }
        $adapters += [ordered]@{
            Name        = (Get-Clean $a.Name)
            Description = (Get-Clean $a.InterfaceDescription)
            Mac         = (Get-Clean $a.MacAddress)
            Status      = (Get-Clean $a.Status)
            LinkSpeed   = (Get-Clean $a.LinkSpeed)
            IPv4        = $ips
        }
    }
    [ordered]@{ Adapters = $adapters }
}

# ---------- Windows ----------

$osInfo = Invoke-Section "OperatingSystem" {
    $os = Get-CimInstance Win32_OperatingSystem
    $cv = Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion"

    $build = Get-Clean $cv.CurrentBuildNumber
    $full = $build
    if ($null -ne $cv.UBR) { $full = "$build." + [string]$cv.UBR }

    $display = Get-Clean $cv.DisplayVersion
    if ($display -eq "") { $display = Get-Clean $cv.ReleaseId }

    $activation = "Nezinams"
    try {
        $lic = Get-CimInstance SoftwareLicensingProduct -Filter "ApplicationId='55c92734-d682-4d71-983e-d6ec3f16059f' AND PartialProductKey IS NOT NULL" | Select-Object -First 1
        if ($lic) {
            $licMap = @{ 0 = "Nav licencets"; 1 = "Licencets"; 2 = "Papildlaiks (OOB)"; 3 = "Papildlaiks (OOT)"; 4 = "Nelikumigs (papildlaiks)"; 5 = "Pazinojums"; 6 = "Pagarinats papildlaiks" }
            $status = [int]$lic.LicenseStatus
            if ($licMap.ContainsKey($status)) { $activation = $licMap[$status] } else { $activation = "Kods $status" }
        }
    } catch {
        $activation = "Neizdevas nolasit"
    }

    $pending = (Test-Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired") -or (Test-Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending")

    $lastBoot = ""
    if ($os.LastBootUpTime) { $lastBoot = ([datetime]$os.LastBootUpTime).ToString("yyyy-MM-dd HH:mm") }

    [ordered]@{
        Caption       = (Get-Clean $os.Caption)
        Edition       = (Get-Clean $cv.EditionID)
        Version       = $display
        Build         = $full
        Architecture  = (Get-Clean $os.OSArchitecture)
        InstallDate   = (Format-DateOnly $os.InstallDate)
        LastBoot      = $lastBoot
        Activation    = $activation
        PendingReboot = $pending
    }
}

# ---------- Programmatura ----------

$software = Invoke-Section "Software" {
    $sources = @(
        @{ Path = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*"; Scope = "Dators" },
        @{ Path = "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*"; Scope = "Dators" }
    )

    # patlaban ieladeto lietotaju profili (bez lietotaju vardiem - tikai profila numurs)
    foreach ($hive in @(Get-ChildItem "Registry::HKEY_USERS" -ErrorAction SilentlyContinue)) {
        $sid = $hive.PSChildName
        if (($sid -match '^S-1-5-21-') -and ($sid -notmatch '_Classes$')) {
            $rid = $sid -replace '^.*-', ''
            $sources += @{ Path = "Registry::HKEY_USERS\$sid\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*"; Scope = "Lietotajs (profils $rid)" }
        }
    }

    $items = @()
    foreach ($source in $sources) {
        foreach ($p in @(Get-ItemProperty -Path $source.Path -ErrorAction SilentlyContinue)) {
            if ($null -eq $p) { continue }
            $name = Get-Clean $p.DisplayName
            if ($name -eq "") { continue }
            if ($p.SystemComponent -eq 1) { continue }
            if ($p.ParentKeyName) { continue }
            $items += [PSCustomObject]@{
                Name        = $name
                Version     = (Get-Clean $p.DisplayVersion)
                Publisher   = (Get-Clean $p.Publisher)
                InstallDate = (Get-Clean $p.InstallDate)
                Scope       = $source.Scope
            }
        }
    }
    $unique = @($items | Sort-Object Name, Version, Scope -Unique)

    $pick = {
        param($rx)
        foreach ($u in $unique) {
            if ($u.Name -match $rx) {
                [ordered]@{ Name = $u.Name; Version = $u.Version; Scope = $u.Scope }
            }
        }
    }

    $officeC2R = $null
    $c2r = Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Office\ClickToRun\Configuration" -ErrorAction SilentlyContinue
    if ($c2r) {
        $officeC2R = [ordered]@{
            Version  = (Get-Clean $c2r.VersionToReport)
            Products = (Get-Clean $c2r.ProductReleaseIds)
            Platform = (Get-Clean $c2r.Platform)
        }
    }

    $keyApps = [ordered]@{
        Office       = @(& $pick '^(Microsoft 365|Microsoft Office|LibreOffice|OpenOffice)')
        Antivirus    = @(& $pick '^ESET (Endpoint|Server Security|File Security|NOD32|Smart Security|Internet Security|Security)')
        EParaksts    = @(& $pick 'eParakst')
        Browsers     = @(& $pick '^(Mozilla Firefox|Google Chrome|Microsoft Edge$|Opera|Brave|Vivaldi)')
        Zoom         = @(& $pick '^Zoom')
        VLC          = @(& $pick '^VLC media player')
        PowerShell7  = @(& $pick '^PowerShell 7')
        TeamViewer   = @(& $pick '^TeamViewer')
    }

    [ordered]@{
        Count            = $unique.Count
        KeyApps          = $keyApps
        OfficeClickToRun = $officeC2R
        Programs         = @($unique)
    }
}

# ---------- Windows drosibas centra antivirusi (tikai nosaukumi) ----------

$securityCenter = Invoke-Section "SecurityCenter" {
    $names = @()
    foreach ($a in @(Get-CimInstance -Namespace "root\SecurityCenter2" -ClassName AntivirusProduct -ErrorAction Stop)) {
        $names += (Get-Clean $a.displayName)
    }
    [ordered]@{ Products = @($names | Sort-Object -Unique) }
}

# ---------- Kopejais rezultats ----------

$inv = [ordered]@{
    SchemaVersion   = 1
    CollectedAt     = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    ComputerName    = $env:COMPUTERNAME
    Computer        = $computer
    BaseBoard       = $board
    Processor       = $cpu
    Memory          = $memory
    Storage         = $storage
    Video           = $video
    Monitors        = $monitors
    Network         = $network
    OperatingSystem = $osInfo
    Software        = $software
    SecurityCenter  = $securityCenter
    Errors          = @($script:errors)
    DurationSeconds = [math]::Round(((Get-Date) - $started).TotalSeconds, 1)
}

$json = $inv | ConvertTo-Json -Depth 8

if ($Mode -eq "Json") {
    Write-Output $json
} else {
    $outDir = Join-Path $NasRoot "Logs\Inventory"
    if (-not (Test-Path $outDir)) { New-Item -ItemType Directory -Path $outDir -Force | Out-Null }
    $outFile = Join-Path $outDir ($env:COMPUTERNAME + ".json")
    $tmpFile = $outFile + ".tmp"
    Set-Content -Path $tmpFile -Value $json -Encoding UTF8 -ErrorAction Stop
    Move-Item -Path $tmpFile -Destination $outFile -Force -ErrorAction Stop
}
