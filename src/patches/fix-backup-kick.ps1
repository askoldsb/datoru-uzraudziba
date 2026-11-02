<#
 fix-backup-kick.ps1   (palaist no ADMIN datora, PowerShell kaa administrators)
 Problema: LabProfileBackup ikdienas trigeris atkartojas ik stundu tikai 23 h no 03:30. Ja dators 03:30 gul,
 atkartosana nesakas un kopija netiek veikta (pec pamosanas tikai viena palaisana).
 Risinajums: uz katra datora SYSTEM uzdevums LabProfileBackup-Kick (ik stundu bez beigam, palaiz LabProfileBackup).
 Skripts pats nekopee biezak ka ik 18 h (to nodrosina lab-backup-run.ps1).
 Lietosana:
   .\fix-backup-kick.ps1                       (visi datori, kuriem ir repozitorijs ProfiluKopijas\<DATORS>)
   .\fix-backup-kick.ps1 -Computers "192.168.3.30,192.168.3.66"
#>
param(
    [string]$Computers = "",
    [string]$Root = "\\192.168.3.31\ProfiluKopijas",
    [string]$NasRoot = "\\192.168.3.31\Updates"
)
$targets = @()
if ($Computers) {
    foreach ($x in ($Computers -split ",")) { if ($x.Trim()) { $targets += [PSCustomObject]@{ Name = $x.Trim(); Ip = $x.Trim() } } }
} else {
    foreach ($d in @(Get-ChildItem $Root -Directory | Where-Object { $_.Name -notin '_status','#recycle','@eaDir' -and (Test-Path (Join-Path $_.FullName 'config')) })) {
        $f = Join-Path $NasRoot ("Logs\Inventory\" + $d.Name + ".json")
        $ip = ""
        if (Test-Path $f) { $m = [regex]::Match((Get-Content $f -Raw -Encoding UTF8), '192\.168\.\d+\.\d+'); if ($m.Success) { $ip = $m.Value } }
        $targets += [PSCustomObject]@{ Name = $d.Name; Ip = $ip }
    }
}
$cred = Get-Credential -UserName "Administrator" -Message "Lokalais administrators (flotes parole)"
foreach ($t in $targets) {
    if (-not $t.Ip) { Write-Host ("{0}: nav zinamas IP - izlaists" -f $t.Name) -ForegroundColor Yellow; continue }
    try {
        $r = Invoke-Command -ComputerName $t.Ip -Credential $cred -ErrorAction Stop -ScriptBlock {
            if (-not (Get-ScheduledTask -TaskName "LabProfileBackup" -ErrorAction SilentlyContinue)) { return "NAV uzdevuma LabProfileBackup" }
            $act = New-ScheduledTaskAction -Execute "schtasks.exe" -Argument '/Run /TN "LabProfileBackup"'
            $trg = New-ScheduledTaskTrigger -Once -At "2026-10-15 00:15" -RepetitionInterval (New-TimeSpan -Hours 1) -RepetitionDuration (New-TimeSpan -Days 3650)
            $pri = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest
            $set = New-ScheduledTaskSettingsSet -StartWhenAvailable -MultipleInstances IgnoreNew -ExecutionTimeLimit (New-TimeSpan -Minutes 5)
            Register-ScheduledTask -TaskName "LabProfileBackup-Kick" -Action $act -Trigger $trg -Principal $pri -Settings $set -Force | Out-Null
            "OK: " + (Get-ScheduledTask -TaskName "LabProfileBackup-Kick").State
        }
        Write-Host ("{0} ({1}): {2}" -f $t.Name, $t.Ip, $r)
    } catch {
        Write-Host ("{0} ({1}): KLUDA {2}" -f $t.Name, $t.Ip, $_.Exception.Message) -ForegroundColor Red
    }
}
