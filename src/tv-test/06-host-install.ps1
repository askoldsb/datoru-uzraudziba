# 06-host-install.ps1 - nomaina pilno TeamViewer klientu uz TeamViewer Host ("Dobeles PIUAC" modulis).
# Solis: 1) atinstale pilno klientu (MSI), 2) kluji uzliek TeamViewer_Host_Setup.exe /S,
#        3) neobligati (-Assign) piesaista kontam ar API token (token tiek jautats, nekur netiek saglabats).
param([switch]$Assign, [switch]$UseId, [switch]$AssignOnly)
. "$PSScriptRoot\00-common.ps1"

$exe = Join-Path $NasRoot "Cache\TeamViewerHost\TeamViewer_Host_Setup.exe"
if ((-not $AssignOnly) -and (-not (Test-Path $exe))) { throw "Nav atrasts: $exe" }
if ($AssignOnly) { $Assign = $true }
Write-Host "Host instalators: $exe ($([math]::Round((Get-Item $exe).Length/1MB,1)) MB)"

$tokenPlain = $null
if ($Assign) {
    if ($UseId) {
        # assignment ID: vienreiz saglabajiet C:\Scripts\tv-test\assignment-id.txt (viena rinda; saja faila ieraksti script TOKENU)
        $idFile = Join-Path $PSScriptRoot "assignment-id.txt"
        if (-not (Test-Path $idFile)) { throw "Nav faila $idFile (ieraksti taja jauno script tokenu, viena rinda)" }
        $tokenPlain = (Get-Content $idFile -Raw).Trim()
        Write-Host "Token nolasits no assignment-id.txt (garums $($tokenPlain.Length))"
    } else {
        # API token no NAS client-install.ps1 (ta pats, ko lieto MSI instalacija)
        $tokenPlain = Get-TvToken
        Write-Host "API token nolasits no NAS client-install.ps1 (garums $($tokenPlain.Length))"
    }
}

$s = New-PSSession -ComputerName $PC -Credential $cred
try {
    $work = "C:\ProgramData\LabUpdates\Work\tvhost"
    Invoke-Command -Session $s -ArgumentList $work -ScriptBlock {
        param($w)
        if (Test-Path $w) { Remove-Item $w -Recurse -Force }
        New-Item -ItemType Directory -Path $w -Force | Out-Null
    }
    if (-not $AssignOnly) {
        Write-Host "Kopeju instalatoru uz $PC..."
        Copy-Item -Path $exe -Destination "$work\TeamViewer_Host_Setup.exe" -ToSession $s -Force
    }

    $res = Invoke-Command -Session $s -ArgumentList $work, $tokenPlain, $PC, $UseId.IsPresent, $AssignOnly.IsPresent -ScriptBlock {
        param($work, $token, $pcName, $useId, $assignOnly)
        $out = [ordered]@{}
        if (-not $assignOnly) {

        # 1) apturam un atinstalejam esoso TeamViewer (MSI ieraksti)
        foreach ($pn in "TeamViewer", "TeamViewer_Service", "tv_w32", "tv_x64") {
            Get-Process -Name $pn -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
        }
        Get-Service -Name "TeamViewer*" -ErrorAction SilentlyContinue | Stop-Service -Force -ErrorAction SilentlyContinue
        $codes = @(Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*","HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*" -ErrorAction SilentlyContinue |
            Where-Object { $_.DisplayName -like "TeamViewer*" -and $_.PSChildName -match '^\{' } | ForEach-Object { $_.PSChildName })
        $out.UninstalledCodes = ($codes -join ", ")
        foreach ($c in $codes) {
            $p = Start-Process msiexec.exe -ArgumentList @("/x", $c, "/qn", "/norestart") -Wait -PassThru -WindowStyle Hidden
            $out."Uninstall_$c" = $p.ExitCode
        }
        Start-Sleep -Seconds 3

        # 2) Host klusa instalesana
        $p = Start-Process "$work\TeamViewer_Host_Setup.exe" -ArgumentList "/S" -Wait -PassThru -WindowStyle Hidden
        $out.HostInstallExit = $p.ExitCode
        Start-Sleep -Seconds 10
        }

        $tvExe = @("C:\Program Files\TeamViewer\TeamViewer.exe", "C:\Program Files (x86)\TeamViewer\TeamViewer.exe") | Where-Object { Test-Path $_ } | Select-Object -First 1
        $out.TeamViewerExe = $tvExe

        # 3) piesaiste (tikai ar -Assign)
        if ($token -and $tvExe) {
            # -UseId: token tiek nemts no assignment-id.txt (jauns script token); citadi no NAS client-install.ps1
            $aargs = @("assign", "--api-token=$token", "--alias=$pcName", "--grant-easy-access", "--reassign")
            $a = Start-Process $tvExe -ArgumentList $aargs -Wait -PassThru -WindowStyle Hidden
            $out.AssignExit = $a.ExitCode
        }

        # autostarts
        $svc = Get-Service -Name "TeamViewer" -ErrorAction SilentlyContinue
        if ($svc) {
            if ($svc.StartType -ne "Automatic") { Set-Service -Name "TeamViewer" -StartupType Automatic }
            if ($svc.Status -ne "Running") { Start-Service -Name "TeamViewer" -ErrorAction SilentlyContinue }
            $out.Service = "$((Get-Service TeamViewer).Status) / $((Get-Service TeamViewer).StartType)"
        } else { $out.Service = "serviss nav atrasts" }

        Remove-Item $work -Recurse -Force -ErrorAction SilentlyContinue
        [PSCustomObject]$out
    }
    Write-Host "`n=== Rezultats ===" -ForegroundColor Cyan
    $res | Select-Object * -ExcludeProperty PSComputerName, RunspaceId, PSShowComputerName | Format-List
    Write-Host "Gaidiet ~1 min, tad palaidiet .\04-after.ps1 un paskatieties konsole (ID, grupa, alias, Online)." -ForegroundColor Green
} finally {
    Remove-PSSession $s -ErrorAction SilentlyContinue
    $tokenPlain = $null
}
