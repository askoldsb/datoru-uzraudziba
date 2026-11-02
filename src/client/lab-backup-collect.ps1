<#
 lab-backup-collect.ps1   (1. IZMEGINAJUMA VERSIJA - TIKAI SAGATAVO, NEKUR NESUTA)

 Ko dara (datora lokali, tikai lasisana + raksta savu mapi StateDir):
  - sakrajs datora "stavokli": programmas, sistema, printeri, tikla, lietotaji, reg eksporti u.c.
  - katram lietotaja profilam atrod REALO Desktop atrasanas vietu (User Shell Folders)
  - atrod Outlook PST failus (Outlook profila reg + atrasanas skenesana visos diskos)
  - atrod PostgreSQL datu mapi
  - sastada backup-paths.txt / exclude.txt (to velak izmantos restic) un aprekina apjomus

 Palaist: no admin datora ar Invoke-Command -FilePath (sk. instrukciju) vai lokali kaa administrators.
#>
param(
    [string]$StateDir = "C:\ProgramData\LabBackup\state",
    [switch]$SkipPstScan,
    [string]$PstCache = ""      # CSV ar iepriekseja pilna PST skena rezultatiem (lai nakts palaisanas neskenetu visu)
)

$ErrorActionPreference = "Continue"
if (Test-Path $StateDir) { Remove-Item (Join-Path $StateDir "*") -Recurse -Force -ErrorAction SilentlyContinue }
$null = New-Item -ItemType Directory -Force -Path $StateDir
$log = Join-Path $StateDir "collect.log"

function Log([string]$m) {
    $l = "{0:HH:mm:ss} {1}" -f (Get-Date), $m
    Add-Content -Path $log -Value $l -Encoding UTF8
    Write-Host $l
}
function Save-Csv($obj, [string]$name) {
    if ($null -ne $obj) { @($obj) | Export-Csv (Join-Path $StateDir $name) -NoTypeInformation -Encoding UTF8 }
}
function Try-Do([scriptblock]$b, [string]$what) {
    try { & $b } catch { Log ("KLUDA ({0}): {1}" -f $what, $_.Exception.Message) }
}
function Reg-Export([string]$key, [string]$file) {
    & reg.exe export $key $file /y 2>&1 | Out-Null
}

# ---------- katalogu nosaukumi, ko neiekljaujam (kesi u.c.) ----------
$exNames = @('Cache','Code Cache','GPUCache','GrShaderCache','ShaderCache','DawnCache','Crashpad','CacheStorage','Service Worker','cache2','startupCache','Temp','logs')
Set-Content (Join-Path $StateDir "exclude.txt") -Value ($exNames + @('*.tmp')) -Encoding ASCII

function Get-PathSize([string]$p) {
    if (-not (Test-Path -LiteralPath $p)) { return 0 }
    if (Test-Path -LiteralPath $p -PathType Leaf) { return (Get-Item -LiteralPath $p -Force).Length }
    $total = [int64]0
    $stack = New-Object System.Collections.Stack
    $stack.Push($p)
    while ($stack.Count -gt 0) {
        $d = New-Object IO.DirectoryInfo ([string]$stack.Pop())
        try {
            foreach ($f in $d.EnumerateFiles()) { $total += $f.Length }
            foreach ($s in $d.EnumerateDirectories()) {
                if ($exNames -contains $s.Name) { continue }
                if ($s.Attributes -band [IO.FileAttributes]::ReparsePoint) { continue }
                $stack.Push($s.FullName)
            }
        } catch { }
    }
    return $total
}

# ---------- 1. sistema ----------
Log "1. Sistema, diski"
Try-Do {
    $cs = Get-CimInstance Win32_ComputerSystem
    $os = Get-CimInstance Win32_OperatingSystem
    $bios = Get-CimInstance Win32_BIOS
    $oem = (Get-CimInstance SoftwareLicensingService).OA3xOriginalProductKey
    [PSCustomObject]@{
        Name = $env:COMPUTERNAME; Manufacturer = $cs.Manufacturer; Model = $cs.Model; Serial = $bios.SerialNumber
        OS = $os.Caption; Build = $os.BuildNumber; InstallDate = [string]$os.InstallDate; OemKey = $oem; Domain = $cs.Domain
    } | ConvertTo-Json | Set-Content (Join-Path $StateDir "system.json") -Encoding UTF8
} "system"
Try-Do { Save-Csv (Get-Volume | Where-Object DriveLetter | Select-Object DriveLetter, FileSystemLabel, FileSystem, DriveType, Size, SizeRemaining) "volumes.csv" } "volumes"
Try-Do { Save-Csv (Get-Partition | Select-Object DiskNumber, PartitionNumber, DriveLetter, Type, Size) "partitions.csv" } "partitions"
Try-Do { & manage-bde.exe -status 2>&1 | Set-Content (Join-Path $StateDir "bitlocker.txt") -Encoding UTF8 } "bitlocker"

# ---------- 2. programmas ----------
Log "2. Programmas"
$progs = @()
foreach ($k in 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*', 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*') {
    try {
        $progs += Get-ItemProperty $k -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName } |
            Select-Object @{n='Scope';e={'machine'}}, DisplayName, DisplayVersion, Publisher, InstallDate, InstallLocation, UninstallString, @{n='Key';e={$_.PSChildName}}
    } catch { Log ("KLUDA (uninstall): " + $_.Exception.Message) }
}
Try-Do { Save-Csv (Get-AppxPackage -AllUsers | Where-Object { -not $_.IsFramework -and $_.SignatureKind -ne 'System' } | Select-Object Name, Version, PackageFullName) "store-apps.csv" } "appx"
Try-Do { Save-Csv (Get-WindowsOptionalFeature -Online | Where-Object State -eq 'Enabled' | Select-Object FeatureName) "windows-features.csv" } "features"
Try-Do { Reg-Export 'HKLM\SOFTWARE\Microsoft\Office\ClickToRun\Configuration' (Join-Path $StateDir "office-c2r.reg") } "office"
Try-Do {
    $w = Get-ChildItem "C:\Program Files\WindowsApps\Microsoft.DesktopAppInstaller_*\winget.exe" -ErrorAction SilentlyContinue | Sort-Object FullName | Select-Object -Last 1
    if ($w) { & $w.FullName export -o (Join-Path $StateDir "winget-export.json") --accept-source-agreements --disable-interactivity 2>&1 | Out-Null }
} "winget"

# ---------- 3. sistemas konfiguracija ----------
Log "3. Sistemas konfiguracija"
Try-Do { Reg-Export 'HKLM\SOFTWARE' (Join-Path $StateDir "HKLM-SOFTWARE.reg") } "hklm"
Try-Do { Save-Csv (Get-Printer | Select-Object Name, DriverName, PortName, Shared, ShareName) "printers.csv" } "printers"
Try-Do { Save-Csv (Get-PrinterPort | Select-Object Name, PrinterHostAddress, PortNumber) "printer-ports.csv" } "ports"
Try-Do { Save-Csv (Get-LocalUser | Select-Object Name, Enabled, LastLogon, @{n='SID';e={$_.SID.Value}}) "local-users.csv" } "users"
Try-Do { Save-Csv (Get-LocalGroupMember -Group 'Administrators' | Select-Object Name, ObjectClass) "local-admins.csv" } "admins"
Try-Do { Save-Csv (Get-SmbShare | Select-Object Name, Path, Description) "smb-shares.csv" } "smbshares"
Try-Do { Save-Csv (Get-CimInstance Win32_Service | Where-Object { $_.PathName -notmatch '(?i)\\windows\\' } | Select-Object Name, DisplayName, StartMode, State, StartName, PathName) "services-nonwindows.csv" } "services"
Try-Do {
    $envs = [Environment]::GetEnvironmentVariables('Machine')
    Save-Csv ($envs.Keys | ForEach-Object { [PSCustomObject]@{ Name = $_; Value = $envs[$_] } }) "env-machine.csv"
} "env"
Try-Do {
    $td = Join-Path $StateDir "tasks"; $null = New-Item -ItemType Directory -Force -Path $td
    foreach ($t in (Get-ScheduledTask | Where-Object { $_.TaskPath -notlike '\Microsoft\*' })) {
        $n = ($t.TaskPath + $t.TaskName) -replace '[\\/:*?"<>|]', '_'
        Export-ScheduledTask -TaskName $t.TaskName -TaskPath $t.TaskPath | Set-Content (Join-Path $td ($n + ".xml")) -Encoding UTF8
    }
} "tasks"
Try-Do { & dism.exe /online "/Export-DefaultAppAssociations:$StateDir\default-apps.xml" 2>&1 | Out-Null } "defaultapps"
Try-Do { & netsh.exe advfirewall export (Join-Path $StateDir "firewall.wfw") 2>&1 | Out-Null } "firewall"

# ---------- 4. lietotaju profili ----------
Log "4. Lietotaju profili (Desktop, Outlook, parlukprogrammas)"
$paths = New-Object System.Collections.ArrayList     # Category, Owner, Path
# Pa-datoram izslegtie celi: config.json, lauks ExcludePaths (mapes vai faili; viss zem tiem netiek kopets)
$exPaths = @()
try {
    $cjx = Get-Content "C:\ProgramData\LabBackup\config.json" -Raw -ErrorAction Stop | ConvertFrom-Json
    if ($cjx.ExcludePaths) { $exPaths = @($cjx.ExcludePaths | ForEach-Object { ([string]$_).Trim().TrimEnd('\') } | Where-Object { $_ }) }
} catch { }
function Test-BkExcluded([string]$p) {
    foreach ($e in $exPaths) { if ($p -ieq $e -or $p.StartsWith($e + '\', [System.StringComparison]::OrdinalIgnoreCase)) { return $true } }
    return $false
}
function Add-BkPath([string]$cat, [string]$owner, [string]$p) {
    if ($p -and (Test-BkExcluded $p)) { Log ("  izslegts (ExcludePaths): " + $p); return }
    if ($p -and (Test-Path -LiteralPath $p)) {
        if (-not ($paths | Where-Object { $_.Path -ieq $p })) { [void]$paths.Add([PSCustomObject]@{ Category = $cat; Owner = $owner; Path = $p }) }
    }
}

$profiles = @()
foreach ($p in @(Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList\S-1-5-21-*' -ErrorAction SilentlyContinue)) {
    $path = [Environment]::ExpandEnvironmentVariables([string]$p.ProfileImagePath)
    $profiles += [PSCustomObject]@{ Sid = $p.PSChildName; Path = $path; Name = (Split-Path $path -Leaf) }
}

# Pa-datoram profilu izvele: C:\ProgramData\LabBackup\config.json, lauks Profiles (tuksh/nav = VISI profili)
$profFilter = @()
try {
    $cj = Get-Content "C:\ProgramData\LabBackup\config.json" -Raw -ErrorAction Stop | ConvertFrom-Json
    if ($cj.Profiles) { $profFilter = @($cj.Profiles | ForEach-Object { [string]$_ } | Where-Object { $_ }) }
} catch { }
if ($profFilter.Count -gt 0) {
    $profiles = @($profiles | Where-Object { $profFilter -contains $_.Name })
    Log ("Profilu filtrs: kopejam tikai " + ($profFilter -join ", ") + " (atrasti " + $profiles.Count + ")")
}

$shellMap = [ordered]@{ Desktop = 'Desktop'; Documents = 'Personal'; Downloads = '{374DE290-123F-4565-9164-39C4925E467B}'; Pictures = 'My Pictures'; Music = 'My Music'; Video = 'My Video' }
$folderRows = @(); $pstReg = @(); $userProgs = @()

foreach ($prof in $profiles) {
    Log ("  profils: " + $prof.Name)
    $pdir = Join-Path $StateDir ("profiles\" + $prof.Name); $null = New-Item -ItemType Directory -Force -Path $pdir

    # reg hive
    $root = "Registry::HKEY_USERS\$($prof.Sid)"; $hname = $prof.Sid; $loadedHere = $false
    if (-not (Test-Path $root)) {
        $nt = Join-Path $prof.Path 'NTUSER.DAT'
        if (Test-Path -LiteralPath $nt) {
            $hname = "LabBk_" + ($prof.Name -replace '[^A-Za-z0-9]', '')
            & reg.exe load "HKU\$hname" $nt 2>&1 | Out-Null
            if ($LASTEXITCODE -eq 0) { $root = "Registry::HKEY_USERS\$hname"; $loadedHere = $true } else { $root = $null }
        } else { $root = $null }
    }

    # reala shell mapju atrasanas vieta
    $sfRaw = $null
    if ($root) { $sfRaw = Get-ItemProperty "$root\Software\Microsoft\Windows\CurrentVersion\Explorer\User Shell Folders" -ErrorAction SilentlyContinue }
    foreach ($k in $shellMap.Keys) {
        $val = $null
        if ($sfRaw) { $pr = $sfRaw.PSObject.Properties[$shellMap[$k]]; if ($pr) { $val = [string]$pr.Value } }
        if (-not $val) { $val = Join-Path $prof.Path $(if ($k -eq 'Video') { 'Videos' } else { $k }) }
        $val = $val -ireplace '%USERPROFILE%', ([string]$prof.Path)
        $val = [Environment]::ExpandEnvironmentVariables($val)
        $isOd = ($val -match 'OneDrive')
        $folderRows += [PSCustomObject]@{ Profils = $prof.Name; Mape = $k; Cels = $val; Eksiste = (Test-Path -LiteralPath $val); OneDrive = $isOd }
        if ($k -eq 'Desktop') {
            Add-BkPath 'Desktop' $prof.Name $val
            Add-BkPath 'Desktop' $prof.Name (Join-Path $prof.Path 'Desktop')
        }
    }

    if ($root) {
        # reg eksporti (tikai lasa)
        foreach ($sub in 'Software', 'Network', 'Environment', 'Printers') {
            Reg-Export ("HKU\" + $hname + "\" + $sub) (Join-Path $pdir ("HKCU-" + $sub + ".reg"))
        }
        # lietotaja programmas
        $pn = $prof.Name
        try {
            $userProgs += Get-ItemProperty "$root\Software\Microsoft\Windows\CurrentVersion\Uninstall\*" -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName } |
                Select-Object @{n='Scope';e={'user:' + $pn}}, DisplayName, DisplayVersion, Publisher, InstallDate, InstallLocation, UninstallString, @{n='Key';e={$_.PSChildName}}
        } catch { Log ("KLUDA (userprogs): " + $_.Exception.Message) }
        # Outlook: pievienotie PST faili no profila reg
        try {
            foreach ($ver in '16.0', '15.0') {
                $op = "$root\Software\Microsoft\Office\$ver\Outlook\Profiles"
                if (-not (Test-Path $op)) { continue }
                foreach ($k in (Get-ChildItem $op -Recurse -ErrorAction SilentlyContinue)) {
                    $ip = Get-ItemProperty -LiteralPath $k.PSPath -ErrorAction SilentlyContinue
                    foreach ($vn in '001f6700', '001f6610') {
                        $pr = $ip.PSObject.Properties[$vn]
                        if ($pr -and $pr.Value -is [byte[]]) {
                            $s = [Text.Encoding]::Unicode.GetString($pr.Value).TrimEnd([char]0)
                            if ($s -match '\.pst$') { $pstReg += [PSCustomObject]@{ Profils = $prof.Name; Cels = $s } }
                        }
                    }
                }
            }
        } catch { Log ("KLUDA (outlookpst): " + $_.Exception.Message) }
    }
    if ($loadedHere) { [gc]::Collect(); Start-Sleep -Milliseconds 400; & reg.exe unload "HKU\$hname" 2>&1 | Out-Null }

    # faili: AppData\Roaming (bez kesiem), NTUSER.DAT, pariuku faili
    Add-BkPath 'Roaming' $prof.Name (Join-Path $prof.Path 'AppData\Roaming')
    Add-BkPath 'Registry' $prof.Name (Join-Path $prof.Path 'NTUSER.DAT')
    Add-BkPath 'Registry' $prof.Name (Join-Path $prof.Path 'AppData\Local\Microsoft\Windows\UsrClass.dat')
    foreach ($ub in (Join-Path $prof.Path 'AppData\Local\Google\Chrome\User Data'), (Join-Path $prof.Path 'AppData\Local\Microsoft\Edge\User Data')) {
        if (-not (Test-Path -LiteralPath $ub)) { continue }
        Add-BkPath 'Browser' $prof.Name (Join-Path $ub 'Local State')
        foreach ($pd in (Get-ChildItem -LiteralPath $ub -Directory -ErrorAction SilentlyContinue | Where-Object { $_.Name -eq 'Default' -or $_.Name -like 'Profile *' })) {
            foreach ($f in 'Bookmarks', 'Bookmarks.bak', 'Preferences', 'Secure Preferences', 'Login Data', 'Login Data For Account', 'Web Data') {
                Add-BkPath 'Browser' $prof.Name (Join-Path $pd.FullName $f)
            }
        }
    }
    Add-BkPath 'Outlook' $prof.Name (Join-Path $prof.Path 'AppData\Local\Microsoft\Outlook\RoamCache')
}
Save-Csv ($progs + $userProgs) "programs.csv"
Save-Csv $folderRows "profile-folders.csv"

# PST: pievienotie (reg) -> backup sarakstaa; ieraksts pst-files.csv
Log "5. PST faili"
$pstRows = @()
foreach ($r in ($pstReg | Sort-Object Cels -Unique)) {
    if (Test-Path -LiteralPath $r.Cels) {
        $fi = Get-Item -LiteralPath $r.Cels -Force
        $pstRows += [PSCustomObject]@{ Avots = 'pievienots Outlook'; Profils = $r.Profils; Fails = $r.Cels; MB = [math]::Round($fi.Length / 1MB); Mainits = $fi.LastWriteTime }
        Add-BkPath 'PST' $r.Profils $r.Cels
    } else {
        $pstRows += [PSCustomObject]@{ Avots = 'pievienots (FAILA NAV)'; Profils = $r.Profils; Fails = $r.Cels; MB = 0; Mainits = $null }
    }
}
if (-not $SkipPstScan) {
    foreach ($v in (Get-Volume | Where-Object { $_.DriveLetter -and $_.DriveType -eq 'Fixed' -and $_.FileSystem -in 'NTFS', 'ReFS' })) {
        $root = $v.DriveLetter + ":\"
        Log ("  skenes PST: " + $root)
        Get-ChildItem $root -Recurse -Filter *.pst -Force -ErrorAction SilentlyContinue |
            Where-Object { $_.FullName -notmatch '\\\$Recycle\.Bin\\|\\Windows\\|\\Program Files' } | ForEach-Object {
                $full = $_.FullName
                if (-not ($pstRows | Where-Object { $_.Fails -ieq $full })) {
                    $pstRows += [PSCustomObject]@{ Avots = 'atrasts diska (nav pievienots)'; Profils = ''; Fails = $full; MB = [math]::Round($_.Length / 1MB); Mainits = $_.LastWriteTime }
                }
            }
    }
}
if ($SkipPstScan -and $PstCache -and (Test-Path $PstCache)) {
    foreach ($c in @(Import-Csv $PstCache)) {
        if ((Test-Path -LiteralPath $c.Fails) -and -not ($pstRows | Where-Object { $_.Fails -ieq $c.Fails })) {
            $pstRows += [PSCustomObject]@{ Avots = $c.Avots; Profils = $c.Profils; Fails = $c.Fails; MB = [double]$c.MB; Mainits = $c.Mainits }
        }
    }
}
if ((-not $SkipPstScan) -and $PstCache) {
    @($pstRows | Where-Object { $_.Avots -like 'atrasts*' }) | Export-Csv $PstCache -NoTypeInformation -Encoding UTF8
}
foreach ($r in $pstRows) {
    if ($profFilter.Count -gt 0 -and $r.Fails -match '^[A-Za-z]:\\Users\\([^\\]+)\\') { if ($profFilter -notcontains $Matches[1]) { continue } }
    if ($r.Avots -like 'atrasts*' -and $r.MB -ge 1 -and $r.Fails -notmatch '\\AppData\\|\\Atgutie|\\Program Files') { Add-BkPath 'PST' 'disks' $r.Fails }
}
Save-Csv $pstRows "pst-files.csv"

# ---------- 6. PostgreSQL ----------
Log "6. PostgreSQL"
Try-Do {
    $pg = @(Get-CimInstance Win32_Service | Where-Object { $_.Name -match 'postgres' })
    $info = @()
    foreach ($s in $pg) {
        $info += ("{0} | {1} | {2} | {3}" -f $s.Name, $s.State, $s.StartName, $s.PathName)
        if ($s.PathName -match '-D\s+"?([^"]+?)"?(\s|$)') {
            $dd = $Matches[1].Trim()
            $info += ("   datu mape: " + $dd)
            Add-BkPath 'PostgresData' 'service' $dd
        }
    }
    if ($info.Count) { Set-Content (Join-Path $StateDir "postgres-info.txt") -Value $info -Encoding UTF8 }
} "postgres"

# ---------- 7. papildu fiksetie celi ----------
Add-BkPath 'System' 'machine' 'C:\Windows\System32\drivers\etc\hosts'
Add-BkPath 'System' 'machine' 'C:\Users\Public\Desktop'
Add-BkPath 'StateDir' 'machine' $StateDir

# ---------- 8. saraksts un apjomi ----------
Log "7. Apjomu aprekins"
$sizes = foreach ($e in $paths) {
    [PSCustomObject]@{ Category = $e.Category; Owner = $e.Owner; Path = $e.Path; MB = [math]::Round((Get-PathSize $e.Path) / 1MB, 1) }
}
$sizes | Export-Csv (Join-Path $StateDir "sizes.csv") -NoTypeInformation -Encoding UTF8
[IO.File]::WriteAllLines((Join-Path $StateDir "backup-paths.txt"), [string[]]@($paths | ForEach-Object { $_.Path }), (New-Object Text.UTF8Encoding $false))

Write-Host ""
Write-Host "=== $env:COMPUTERNAME : DESKTOP / DOKUMENTI / CITAS MAPES (reala atrasanas vieta) ==="
($folderRows | Where-Object { $_.Mape -in 'Desktop', 'Documents' } | Format-Table Profils, Mape, Cels, Eksiste, OneDrive -AutoSize | Out-String -Width 250) | Write-Host
Write-Host "=== PST faili ==="
($pstRows | Sort-Object MB -Descending | Format-Table Avots, Profils, Fails, MB -AutoSize | Out-String -Width 250) | Write-Host
Write-Host "=== KOPEJAMIE APJOMI (MB) pa kategorijam ==="
($sizes | Group-Object Category | ForEach-Object { [PSCustomObject]@{ Kategorija = $_.Name; MB = [math]::Round(($_.Group | Measure-Object MB -Sum).Sum) } } | Format-Table -AutoSize | Out-String) | Write-Host
$totalMb = [math]::Round(($sizes | Measure-Object MB -Sum).Sum)
$totalNoPst = [math]::Round((($sizes | Where-Object { $_.Category -notin 'PST', 'PostgresData' }) | Measure-Object MB -Sum).Sum)
Write-Host ("KOPA: {0:N1} GB   (bez PST un PostgreSQL: {1:N1} GB)" -f ($totalMb / 1024), ($totalNoPst / 1024))
Write-Host ("Programmu skaits: {0}   |   stavokla mape: {1}" -f (@($progs + $userProgs).Count), $StateDir)
$stateMb = [math]::Round((Get-PathSize $StateDir) / 1MB)
Write-Host ("StateDir izmers: {0} MB" -f $stateMb)
Log "Gatavs"
