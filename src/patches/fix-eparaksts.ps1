<#
============================================================
 fix-eparaksts.ps1   (palaizams NO ADMINA DATORA, nevis uz klienta)
 Uzstada eParakstitaju 1.10.0 DATORAM KOPIGI (ALLUSERS=1), lai to redz VISI
 lietotaji, nevis tikai labupdate profils. Msi tiek nokopets no NAS Cache.

 Pirms un pec uzstadisanas tiek PARBAUDITI FAILI (eparakstitajs3.exe, saisne),
 nevis tikai registra ieraksts.

 Lietosana:
   $cred = Get-Credential
   & "C:\Scripts\fix-eparaksts.ps1" -Computers "DATORKLASE-12" -Credential $cred -Mode Preview
   & "C:\Scripts\fix-eparaksts.ps1" -Computers "DATORKLASE-12" -Credential $cred -Mode Run

 Mode: "Preview" (noklusejums) = TIKAI nolasa stavokli; "Run" = uzstada.
 Dators pec uzstadisanas netiek restartets.
============================================================
#>

param(
    [Parameter(Mandatory = $true)]
    [string[]]$Computers,

    [Parameter(Mandatory = $true)]
    [System.Management.Automation.PSCredential]$Credential,

    [string]$NasRoot = "\\192.168.3.31\Updates",

    [string]$Mode = "Preview"
)

$doRun = ($Mode -eq "Run" -or $Mode -eq "Clean")
$doClean = ($Mode -eq "Clean")   # Clean = vispirms nonem visus esosos eParakstitaja MSI ierakstus un mapi, tad uzstada no jauna

$msi = Get-ChildItem (Join-Path $NasRoot "Cache\eParaksts\*.msi") -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 1
if ($doRun -and (-not $msi)) {
    Write-Error ("MSI nav atrasts: " + (Join-Path $NasRoot "Cache\eParaksts"))
    return
}
if ($msi) { Write-Host ("MSI: " + $msi.Name) }

# datora stavoklis (tikai lasisana) - izpilda attalinati
$stateBlock = {
    $uninst = @("HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*", "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*")
    $arp = @(Get-ItemProperty -Path $uninst -ErrorAction SilentlyContinue |
        Where-Object { ($_.DisplayName -like "eParakst*") -and ($_.DisplayName -notlike "*Token Signing*") -and ($_.WindowsInstaller -eq 1) } |
        ForEach-Object { [string]$_.DisplayVersion + " (" + [string]$_.Publisher + ")" })

    $exe = "C:\Program Files\eparakstitajs3\eparakstitajs3.exe"
    $exeVer = ""
    if (Test-Path $exe) { $exeVer = [string](Get-Item $exe).VersionInfo.FileVersion }

    [PSCustomObject]@{
        Exe         = [bool](Test-Path $exe)
        ExeVersija  = $exeVer
        Cfg         = [bool](Test-Path "C:\Program Files\eparakstitajs3\app\eparakstitajs3.cfg")
        Saisne      = [bool](Test-Path "C:\ProgramData\Microsoft\Windows\Start Menu\Programs\eParakst*\*.lnk")
        JarSk       = @(Get-ChildItem "C:\Program Files\eparakstitajs3\app" -Recurse -Filter *.jar -File -ErrorAction SilentlyContinue).Count
        MsiIeraksti = ($arp -join "; ")
    }
}

foreach ($c in $Computers) {
    $row = [ordered]@{ Computer = $c; Rezultats = ""; Pirms = ""; InstalKods = ""; Pec = "" }
    $s = $null
    try {
        $s = New-PSSession -ComputerName $c -Credential $Credential -ErrorAction Stop

        $before = Invoke-Command -Session $s -ScriptBlock $stateBlock
        $row.Pirms = "Exe=$($before.Exe) ($($before.ExeVersija)); Jar=$($before.JarSk); Cfg=$($before.Cfg); Saisne=$($before.Saisne); MSI: $($before.MsiIeraksti)"

        if (-not $doRun) {
            $row.Rezultats = "Preview: nekas nav mainits"
        } else {
            Invoke-Command -Session $s -ScriptBlock {
                $d = "C:\ProgramData\LabUpdates\Work"
                if (-not (Test-Path $d)) { New-Item -ItemType Directory -Path $d -Force | Out-Null }
            }
            if ($doClean) {
                Invoke-Command -Session $s -ScriptBlock {
                    Get-Process -Name "eparakstitajs3" -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
                    $uninst = @("HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*", "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*")
                    $prods = @(Get-ItemProperty -Path $uninst -ErrorAction SilentlyContinue |
                        Where-Object { ($_.DisplayName -like "eParakst*") -and ($_.DisplayName -notlike "*Token Signing*") -and ($_.WindowsInstaller -eq 1) })
                    foreach ($pr in $prods) {
                        $px = Start-Process -FilePath "msiexec.exe" -ArgumentList @("/x", $pr.PSChildName, "/qn", "/norestart") -PassThru -WindowStyle Hidden
                        [void]$px.WaitForExit(180000)
                    }
                    if (Test-Path "C:\Program Files\eparakstitajs3") { Remove-Item "C:\Program Files\eparakstitajs3" -Recurse -Force -ErrorAction SilentlyContinue }
                }
            }
            Copy-Item -Path $msi.FullName -Destination "C:\ProgramData\LabUpdates\Work\eparaksts-machine.msi" -ToSession $s -Force

            $code = Invoke-Command -Session $s -ScriptBlock {
                $d = "C:\ProgramData\LabUpdates\Work"
                $p = Start-Process -FilePath "msiexec.exe" -ArgumentList @("/i", "$d\eparaksts-machine.msi", "/qn", "/norestart", "ALLUSERS=1", "/l*v", "$d\install-machine.log") -PassThru -WindowStyle Hidden
                if (-not $p.WaitForExit(180000)) {
                    try { $p.Kill() } catch { }
                    return -1
                }
                return $p.ExitCode
            }
            $row.InstalKods = $code

            $after = Invoke-Command -Session $s -ScriptBlock $stateBlock
            $row.Pec = "Exe=$($after.Exe) ($($after.ExeVersija)); Jar=$($after.JarSk); Cfg=$($after.Cfg); Saisne=$($after.Saisne); MSI: $($after.MsiIeraksti)"

            if ((($code -eq 0) -or ($code -eq 3010)) -and $after.Exe -and $after.Cfg -and $after.Saisne -and ($after.JarSk -ge 40)) {
                $row.Rezultats = "OK"
            } else {
                $row.Rezultats = "PARBAUDIET (kods $code; zurnals C:\ProgramData\LabUpdates\Work\install-machine.log)"
            }
        }
    } catch {
        $row.Rezultats = "KLUDA: " + $_.Exception.Message
    } finally {
        if ($s) { Remove-PSSession $s -ErrorAction SilentlyContinue }
    }
    [PSCustomObject]$row
}
