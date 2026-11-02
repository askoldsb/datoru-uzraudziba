# 08-rollback.ps1 - atgriez pilno TeamViewer klientu: atinstale Host, tad palaiz 03-reinstall.ps1 -Mode Upgrade.
. "$PSScriptRoot\00-common.ps1"
$s = New-PSSession -ComputerName $PC -Credential $cred
try {
    Invoke-Command -Session $s -ScriptBlock {
        foreach ($pn in "TeamViewer", "TeamViewer_Service", "tv_w32", "tv_x64") {
            Get-Process -Name $pn -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
        }
        Get-Service -Name "TeamViewer*" -ErrorAction SilentlyContinue | Stop-Service -Force -ErrorAction SilentlyContinue
        $u = @("C:\Program Files\TeamViewer\uninstall.exe", "C:\Program Files (x86)\TeamViewer\uninstall.exe") | Where-Object { Test-Path $_ } | Select-Object -First 1
        if ($u) { $p = Start-Process $u -ArgumentList "/S" -Wait -PassThru; "Host uninstall exit: $($p.ExitCode)" } else { "uninstall.exe nav atrasts (Host varbut jau nav)" }
    }
} finally { Remove-PSSession $s -ErrorAction SilentlyContinue }
& "$PSScriptRoot\03-reinstall.ps1" -Mode Upgrade
