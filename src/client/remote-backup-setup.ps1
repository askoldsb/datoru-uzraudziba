<#
 remote-backup-setup.ps1   (palaist no ADMIN datora, PowerShell kaa administrators)

 Uz katra merka datora (WinRM):
   - izveido C:\ProgramData\LabBackup (tikai SYSTEM + Administratori)
   - ieraksta config.json un secrets.dat (NAS lietotajs/parole, restic parole; DPAPI LocalMachine)
   - nokopee restic.exe
   - registre Scheduled Task "LabProfileBackup" (labupdate konts, 03:30 + ik stundu, StartWhenAvailable)
     kas palaiz \\NAS\Updates\Tools\lab-backup\lab-backup-run.ps1 -Unattended
 Parametri:  -ComputerNames "192.168.3.33,192.168.3.55"   (komatiem atdalita virkne)
             -NasHost PIUAC_CLOUD   -StartNow (uzreiz palaist pirmo kopiju)
 PIEZIME: PRIEKSNOSACIJUMS - skripti \\NAS\Updates\Tools\lab-backup\ (run + collect) un Tools\restic.exe.
#>
param(
    [Parameter(Mandatory = $true)][string]$ComputerNames,
    [string]$NasHost = "PIUAC_CLOUD",
    [string]$Share = "ProfiluKopijas",
    [string]$NasRoot = "\\192.168.3.31\Updates",
    [string]$Root = "\\192.168.3.31\ProfiluKopijas",
    [string]$LabUser = "labupdate",
    [string]$LabPassword = "",   # tukss = prasa palaisanas laika (parole repozitorija netiek glabata)
    [string]$ResticLocal = "C:\Scripts\restic.exe",
    [string]$TaskName = "LabProfileBackup",
    [switch]$StartNow,
    [switch]$SeparateRepoPassword   # ja vajag citu restic paroli neka NAS lietotaja parole
)

$list = $ComputerNames -split "," | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne "" }
if ($list.Count -eq 0) { Write-Host "Nav merka datoru." -ForegroundColor Red; return }

$resticSrc = $ResticLocal
if (-not (Test-Path $resticSrc)) { $resticSrc = Join-Path $NasRoot "Tools\restic.exe" }
if (-not (Test-Path $resticSrc)) { Write-Host "Nav atrasts restic.exe ($resticSrc)" -ForegroundColor Red; return }
$runScriptOnNas = Join-Path $NasRoot "Tools\lab-backup\lab-backup-run.ps1"
if (-not (Test-Path $runScriptOnNas)) { Write-Host "Nav atrasts $runScriptOnNas - vispirms ieliec skriptus NAS." -ForegroundColor Red; return }

if ([string]::IsNullOrEmpty($LabPassword)) { $LabPassword = (Get-Credential -UserName $LabUser -Message "Konta $LabUser parole").GetNetworkCredential().Password }
$adminCred = Get-Credential -Message "Merka datoru lokalais administrators"
$nasCred = Get-Credential -UserName "labprofilbackup" -Message "NAS lietotajs labprofilbackup"
$nasPlain = $nasCred.GetNetworkCredential().Password
if ($SeparateRepoPassword) {
    $repoPw = Read-Host "restic repozitorija parole (TA PATI, kas pirmajam datoram)" -AsSecureString
    $repoPw2 = Read-Host "ievadi paroli VELREIZ" -AsSecureString
    $repoPlain = (New-Object System.Net.NetworkCredential("", $repoPw)).Password
    if ($repoPlain -ne (New-Object System.Net.NetworkCredential("", $repoPw2)).Password) { Write-Host "Paroles nesakrit." -ForegroundColor Red; return }
} else {
    # noklusejuma: restic repozitorija parole = NAS lietotaja labprofilbackup parole (neko papildu neprasa)
    $repoPlain = $nasPlain
}

# parbaude pret esosu repozitoriju (ja tads jau ir)
$existingRepo = Get-ChildItem $Root -Directory -ErrorAction SilentlyContinue | Where-Object { Test-Path (Join-Path $_.FullName 'config') } | Select-Object -First 1
if ($existingRepo) {
    $env:RESTIC_REPOSITORY = $existingRepo.FullName
    $env:RESTIC_PASSWORD = $repoPlain
    & $resticSrc cat config 2>&1 | Out-Null
    $okPw = ($LASTEXITCODE -eq 0)
    Remove-Item Env:\RESTIC_PASSWORD -ErrorAction SilentlyContinue
    if (-not $okPw) { Write-Host ("Parole NEATVER esoso repozitoriju " + $existingRepo.Name + " - parbaudi paroli.") -ForegroundColor Red; return }
    Write-Host ("Parole parbaudita pret " + $existingRepo.Name + ": OK") -ForegroundColor Green
}
$prep = {
    $b = "C:\ProgramData\LabBackup"
    New-Item -ItemType Directory -Path $b -Force | Out-Null
    & icacls.exe $b /inheritance:r /grant:r "*S-1-5-18:(OI)(CI)F" "*S-1-5-32-544:(OI)(CI)F" | Out-Null
}
$configure = {
    param($NasHost, $Share, $NasRoot, $NasUser, $NasPass, $RepoPass, $LabUser, $LabPassword, $TaskName, $StartNow)
    $b = "C:\ProgramData\LabBackup"
    Add-Type -AssemblyName System.Security
    $cfgNew = @{ NasHost = $NasHost; Share = $Share; NasRoot = $NasRoot }
    try {
        $cfgOld = Get-Content (Join-Path $b "config.json") -Raw -ErrorAction Stop | ConvertFrom-Json
        if ($cfgOld.Profiles) { $cfgNew.Profiles = @($cfgOld.Profiles) }   # saglaba pa-datoram profilu izveli
    } catch { }
    $cfgNew | ConvertTo-Json | Set-Content (Join-Path $b "config.json") -Encoding ASCII
    $json = @{ NasUser = $NasUser; NasPass = $NasPass; RepoPass = $RepoPass } | ConvertTo-Json
    $enc = [Security.Cryptography.ProtectedData]::Protect([Text.Encoding]::UTF8.GetBytes($json), $null, 'LocalMachine')
    [IO.File]::WriteAllBytes((Join-Path $b "secrets.dat"), $enc)

    if (-not (Get-LocalUser -Name $LabUser -ErrorAction SilentlyContinue)) { throw "konts $LabUser neeksiste - vispirms uzstadi atjauninasanas sistemu (setup-client)" }

    $script = Join-Path $NasRoot "Tools\lab-backup\lab-backup-run.ps1"
    $arg = '-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File "' + $script + '" -Unattended'
    $action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument $arg

    $helper = New-ScheduledTaskTrigger -Once -At "03:30" -RepetitionInterval (New-TimeSpan -Hours 1) -RepetitionDuration (New-TimeSpan -Hours 23)
    $trigger = New-ScheduledTaskTrigger -Daily -At "03:30"
    $trigger.Repetition = $helper.Repetition

    $settings = New-ScheduledTaskSettingsSet -StartWhenAvailable -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -DontStopOnIdleEnd `
        -ExecutionTimeLimit (New-TimeSpan -Hours 6) -MultipleInstances IgnoreNew
    $settings.Priority = 7

    Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false -ErrorAction SilentlyContinue
    Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger $trigger -Settings $settings -User $LabUser -Password $LabPassword -RunLevel Highest `
        -Description "Profila darba vides kopija uz NAS (restic)" -ErrorAction Stop | Out-Null
    # Palaisanas uzdevums: ja dators 03:30 gul, ikdienas trigera stundas atkartosana nesakas. SYSTEM uzdevums ik stundu palaiz kopesanu.
    try {
        $kA = New-ScheduledTaskAction -Execute "schtasks.exe" -Argument ('/Run /TN "' + $TaskName + '"')
        $kT = New-ScheduledTaskTrigger -Once -At "2026-10-15 00:15" -RepetitionInterval (New-TimeSpan -Hours 1) -RepetitionDuration (New-TimeSpan -Days 3650)
        $kP = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest
        $kS = New-ScheduledTaskSettingsSet -StartWhenAvailable -MultipleInstances IgnoreNew -ExecutionTimeLimit (New-TimeSpan -Minutes 5)
        Register-ScheduledTask -TaskName ($TaskName + "-Kick") -Action $kA -Trigger $kT -Principal $kP -Settings $kS -Force | Out-Null
    } catch { }
    if ($StartNow) { Start-ScheduledTask -TaskName $TaskName }
    $t = Get-ScheduledTask -TaskName $TaskName
    "Uzdevums '{0}': {1}" -f $TaskName, $t.State
}

$results = @()
foreach ($c in $list) {
    Write-Host ""
    Write-Host "=== $c ===" -ForegroundColor Cyan
    $res = "KLUDA"
    try {
        $s = New-PSSession -ComputerName $c -Credential $adminCred -ErrorAction Stop
        Invoke-Command -Session $s -ScriptBlock $prep
        Copy-Item -Path $resticSrc -Destination "C:\ProgramData\LabBackup\restic.exe" -ToSession $s -Force
        $out = Invoke-Command -Session $s -ScriptBlock $configure -ArgumentList $NasHost, $Share, $NasRoot, $nasCred.UserName, $nasPlain, $repoPlain, $LabUser, $LabPassword, $TaskName, $StartNow.IsPresent
        Write-Host $out
        $res = "OK"
        Remove-PSSession $s
    } catch {
        Write-Host ("KLUDA: " + $_.Exception.Message) -ForegroundColor Red
        $res = "KLUDA: " + $_.Exception.Message
    }
    $results += [PSCustomObject]@{ Dators = $c; Rezultats = $res }
}
Write-Host ""
Write-Host "=== KOPSAVILKUMS ===" -ForegroundColor Cyan
$results | Format-Table -AutoSize
