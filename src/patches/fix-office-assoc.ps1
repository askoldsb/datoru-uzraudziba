<#
 fix-office-assoc.ps1   (palaist uz merka datora, PowerShell ka administrators)
 Labo Office failu ikonas/asociacijas pec Win10 -> Win11 jauninasanas:
  1) HKLM: .docx/.doc/.xlsx/.xls/.pptx/.ppt/... -> pareizie Office ProgID (ja tie eksiste)
  2) Katram ieladetajam lietotaja profilam:
     - izdzes kludainu UserChoice (Applications\WINWORD.EXE / EXCEL.EXE / POWERPNT.EXE),
       ieprieks nonemot dzesanas liegumu (ACL)
     - izdzes lietotaja klasu parrakstijumu *_auto_file
  Pec tam lietotajam jaizlogojas un jaielogojas.
 Profili, kas nav ieladeti (lietotajs nav piesledzies), netiek aiztikti - palaid velreiz, kad lietotajs ir piesledzies.
#>
$map = [ordered]@{
    '.docx' = 'Word.Document.12'
    '.doc'  = 'Word.Document.8'
    '.docm' = 'Word.DocumentMacroEnabled.12'
    '.dotx' = 'Word.Template.12'
    '.xlsx' = 'Excel.Sheet.12'
    '.xls'  = 'Excel.Sheet.8'
    '.xlsm' = 'Excel.SheetMacroEnabled.12'
    '.pptx' = 'PowerPoint.Show.12'
    '.ppt'  = 'PowerPoint.Show.8'
}

$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) { Write-Host "KLUDA: palaid PowerShell kA ADMINISTRATORS." -ForegroundColor Red; return }

# 1) HKLM
foreach ($e in $map.Keys) {
    $prog = $map[$e]
    if (Test-Path "Registry::HKEY_CLASSES_ROOT\$prog") {
        $key = "Registry::HKEY_LOCAL_MACHINE\SOFTWARE\Classes\$e"
        if (-not (Test-Path $key)) { New-Item -Path $key -Force | Out-Null }
        $cur = (Get-ItemProperty $key -ErrorAction SilentlyContinue).'(default)'
        if ($cur -ne $prog) {
            Set-ItemProperty -Path $key -Name '(default)' -Value $prog
            Write-Host "HKLM $e : $cur -> $prog" -ForegroundColor Green
        }
    }
}

# 2) ieladetie lietotaju profili
$sids = Get-ChildItem 'Registry::HKEY_USERS' | Where-Object { $_.PSChildName -match '^S-1-5-21-' -and $_.PSChildName -notmatch '_Classes$' } | ForEach-Object { $_.PSChildName }
foreach ($sid in $sids) {
    foreach ($e in $map.Keys) {
        # UserChoice
        $ucRel = "$sid\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\FileExts\$e\UserChoice"
        $uc = Get-ItemProperty "Registry::HKEY_USERS\$ucRel" -ErrorAction SilentlyContinue
        if ($uc -and ([string]$uc.ProgId) -like 'Applications\*') {
            $bad = [string]$uc.ProgId
            $done = $false
            try {
                $k = [Microsoft.Win32.Registry]::Users.OpenSubKey($ucRel, [Microsoft.Win32.RegistryKeyPermissionCheck]::ReadWriteSubTree, ([System.Security.AccessControl.RegistryRights]::ChangePermissions -bor [System.Security.AccessControl.RegistryRights]::ReadKey))
                $a = $k.GetAccessControl()
                $a.SetAccessRuleProtection($true, $true)
                foreach ($r in @($a.GetAccessRules($true, $false, [System.Security.Principal.NTAccount]))) {
                    if ($r.AccessControlType -eq 'Deny') { [void]$a.RemoveAccessRule($r) }
                }
                $a.AddAccessRule((New-Object System.Security.AccessControl.RegistryAccessRule([System.Security.Principal.WindowsIdentity]::GetCurrent().Name, 'FullControl', 'Allow')))
                $k.SetAccessControl($a)
                $k.Close()
                Remove-Item "Registry::HKEY_USERS\$ucRel" -Force -ErrorAction Stop
                $done = $true
            } catch {
                Write-Host "UserChoice $e ($($sid.Substring($sid.Length-4))): neizdevas - $_" -ForegroundColor Yellow
            }
            if ($done) { Write-Host "Profils ...$($sid.Substring($sid.Length-4)) $e : izdzests UserChoice $bad" -ForegroundColor Green }
        }
        # lietotaja klasu parrakstijums
        $ck = "Registry::HKEY_USERS\${sid}_Classes\$e"
        if (Test-Path $ck) {
            $v = [string](Get-ItemProperty $ck -ErrorAction SilentlyContinue).'(default)'
            if ($v -like '*_auto_file') {
                Remove-Item $ck -Recurse -Force -ErrorAction SilentlyContinue
                Write-Host "Profils ...$($sid.Substring($sid.Length-4)) $e : izdzests klases parrakstijums $v" -ForegroundColor Green
            }
        }
    }
}

Write-Host ""
foreach ($e in '.docx', '.xlsx', '.pptx') {
    Write-Host ("{0} -> {1}" -f $e, (Get-ItemProperty "Registry::HKEY_CLASSES_ROOT\$e" -ErrorAction SilentlyContinue).'(default)')
}
ie4uinit.exe -show
Write-Host "Gatavs. Lietotajam jaizlogojas un jaielogojas." -ForegroundColor Cyan
