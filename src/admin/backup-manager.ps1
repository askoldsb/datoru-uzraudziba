<#
 backup-manager.ps1
 Profilu kopiju (restic) parvaldibas logs. Ielade config-panel.ps1 (tajaa pasaa mapee) un atver ar pogu
 "Profilu kopijas". Var palaist ari atseviski:  . .\backup-manager.ps1; Show-BackupManager
 Lasa:  \\NAS\ProfiluKopijas\_status\<DATORS>.json  un  ProfiluKopijas\<DATORS>\ (repozitoriji)
 Darbibas: statusu saraksts, apjomu aprekins, kopijas palaisana attalinati, atjaunosana no NAS, versiju tirisana.
#>

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# Restic repozitoriju parole (pēc lietotāja pieprasījuma glabājas šajā failā; fails jāglabā tikai admin datorā, mapē C:\Scripts).
$script:ResticPasswordDefault = ''

# Latviski saukti zinojumu logi (standarta MessageBox pogas ir valodas, kura uzstadita Windows, tekstos).
$script:MB = New-Object PSObject
Add-Member -InputObject $script:MB -MemberType ScriptMethod -Name Show -Value {
    param([string]$Text, [string]$Title = "Info", [string]$Buttons = "OK", [string]$Icon = "", [string[]]$Labels = @())
    $f = New-Object System.Windows.Forms.Form
    $f.Text = $Title; $f.StartPosition = "CenterParent"; $f.FormBorderStyle = "FixedDialog"
    $f.MaximizeBox = $false; $f.MinimizeBox = $false; $f.ShowInTaskbar = $false
    $f.ClientSize = New-Object System.Drawing.Size(520, 190)
    $l = New-Object System.Windows.Forms.Label
    $l.Text = $Text; $l.Location = New-Object System.Drawing.Point(15, 15); $l.Size = New-Object System.Drawing.Size(490, 120)
    $f.Controls.Add($l)
    switch ($Buttons) {
        "YesNo" { $vals = @("Yes", "No"); $txt = @("J" + [char]0x0101, "N" + [char]0x0113) }
        "YesNoCancel" { $vals = @("Yes", "No", "Cancel"); $txt = @("J" + [char]0x0101, "N" + [char]0x0113, "Atcelt") }
        default { $vals = @("OK"); $txt = @("Labi") }
    }
    if ($Labels.Count -eq $vals.Count) { $txt = $Labels }
    $script:mbResult = $vals[$vals.Count - 1]
    $x = 505
    for ($i = $vals.Count - 1; $i -ge 0; $i--) {
        $b = New-Object System.Windows.Forms.Button
        $b.Text = $txt[$i]; $b.Tag = $vals[$i]
        $b.Size = New-Object System.Drawing.Size(150, 34)
        $x -= 155
        $b.Location = New-Object System.Drawing.Point(($x + 5), 145)
        $b.Add_Click({ $script:mbResult = [string]$this.Tag; $f.Close() })
        $f.Controls.Add($b)
        if ($i -eq 0) { $f.AcceptButton = $b }
    }
    [void]$f.ShowDialog()
    return $script:mbResult
}

function Get-BackupRows {
    param([string]$Root, [string]$ScheduleFile)
    $statusDir = Join-Path $Root "_status"
    $rows = @{}
    if (Test-Path $Root) {
        foreach ($d in @(Get-ChildItem $Root -Directory -ErrorAction SilentlyContinue | Where-Object { $_.Name -notin '_status','#recycle','@eaDir' })) {
            $rows[$d.Name.ToUpper()] = [ordered]@{ PC = $d.Name; Repo = (Test-Path (Join-Path $d.FullName 'config')); Result = ""; Finished = $null; Duration = ""; Snapshot = ""; Added = ""; Mode = ""; Detail = ""; SizeMB = "" }
        }
    }
    if (Test-Path $statusDir) {
        foreach ($f in @(Get-ChildItem $statusDir -Filter *.json -File -ErrorAction SilentlyContinue)) {
            try {
                $j = Get-Content $f.FullName -Raw -Encoding UTF8 | ConvertFrom-Json
                $name = [string]$j.Computer; if (-not $name) { $name = [IO.Path]::GetFileNameWithoutExtension($f.Name) }
                $k = $name.ToUpper()
                if (-not $rows.ContainsKey($k)) { $rows[$k] = [ordered]@{ PC = $name; Repo = $false; Result = ""; Finished = $null; Duration = ""; Snapshot = ""; Added = ""; Mode = ""; Detail = ""; SizeMB = "" } }
                $r = $rows[$k]
                $r.Result = [string]$j.Result
                try { $r.Finished = [datetime]$j.Finished } catch { $r.Finished = $null }
                $r.Duration = [string]$j.DurationMin
                $r.Snapshot = [string]$j.Snapshot
                $r.Added = [string]$j.Added
                $r.Mode = [string]$j.Mode
                $r.Detail = [string]$j.Detail
            } catch { }
        }
    }
    return @($rows.Values | ForEach-Object { [PSCustomObject]$_ } | Sort-Object PC)
}

function Get-PcIp {
    param([string]$NasRoot, [string]$Pc)
    $f = Join-Path $NasRoot ("Logs\Inventory\" + $Pc + ".json")
    if (-not (Test-Path $f)) { return "" }
    $t = Get-Content $f -Raw -Encoding UTF8
    $m = [regex]::Matches($t, '192\.168\.\d{1,3}\.\d{1,3}')
    if ($m.Count -gt 0) { return $m[0].Value }
    return ""
}

function Start-ResticWindow {
    # Atver redzamu PowerShell logu ar saspiestu skriptu; paroles tiek pieprasitas tur (nekad netiek glabatas).
    param([string]$Body, [string]$Title)
    $tmp = Join-Path $env:TEMP ("lab-backup-ui-" + [guid]::NewGuid().ToString("N").Substring(0, 8) + ".ps1")
    $hdr = @'
$Host.UI.RawUI.WindowTitle = "__TITLE__"
$ErrorActionPreference = "Continue"
'@
    Set-Content -Path $tmp -Value ($hdr.Replace("__TITLE__", $Title) + "`r`n" + $Body) -Encoding UTF8
    if ($script:ResticPasswordDefault) { $env:LAB_RESTIC_PW = $script:ResticPasswordDefault }
    Start-Process powershell.exe -ArgumentList @("-NoProfile", "-ExecutionPolicy", "Bypass", "-NoExit", "-File", $tmp)
    Remove-Item Env:\LAB_RESTIC_PW -ErrorAction SilentlyContinue
}

function Show-RestoreDialog {
    param([string]$Root, [string]$NasRoot, [string]$Pc)
    $dlg = New-Object System.Windows.Forms.Form
    $dlg.Text = "Atjaunot no NAS: $Pc"
    $dlg.Size = New-Object System.Drawing.Size(560, 330)
    $dlg.StartPosition = "CenterParent"
    $y = 15
    function Add-Lbl($t) { $l = New-Object System.Windows.Forms.Label; $l.Text = $t; $l.Location = New-Object System.Drawing.Point(10, $script:y); $l.Size = New-Object System.Drawing.Size(530, 18); $dlg.Controls.Add($l); $script:y += 20 }
    function Add-Tb($v) { $t = New-Object System.Windows.Forms.TextBox; $t.Text = $v; $t.Location = New-Object System.Drawing.Point(10, $script:y); $t.Size = New-Object System.Drawing.Size(425, 24); $dlg.Controls.Add($t); $script:y += 36; return $t }
    $script:y = 15
    Add-Lbl "Snapshot ID (latest = jaunakais):"
    $tbSnap = Add-Tb "latest"
    Add-Lbl "Atjaunot uz mapi (pagaidu mape; NEATJAUNOT tiesi uz darba datoru bez parbaudes):"
    $tbTarget = Add-Tb "D:\Atjaunots"
    $btnBrowse = New-Object System.Windows.Forms.Button
    $btnBrowse.Text = "..."; $btnBrowse.Location = New-Object System.Drawing.Point(445, $script:y - 38); $btnBrowse.Size = New-Object System.Drawing.Size(40, 26)
    $btnBrowse.Add_Click({ $fb = New-Object System.Windows.Forms.FolderBrowserDialog; if ($fb.ShowDialog() -eq "OK") { $tbTarget.Text = $fb.SelectedPath } })
    $dlg.Controls.Add($btnBrowse)
    Add-Lbl "Tikai sis cels (neobligati), piem. C:/Users/dace/Desktop  vai  *.pst  (tukshs = viss):"
    $tbInc = Add-Tb ""
    $info = New-Object System.Windows.Forms.Label
    $info.Text = "Atvērs PowerShell logu. Restic parole tiek ņemta no skripta; NAS paroli prasa tikai tad, ja koplietojums nav pieejams."
    $info.Location = New-Object System.Drawing.Point(10, $script:y); $info.Size = New-Object System.Drawing.Size(520, 36); $info.ForeColor = [System.Drawing.Color]::DimGray
    $dlg.Controls.Add($info)
    $btnSnaps = New-Object System.Windows.Forms.Button
    $btnSnaps.Text = "Parādīt snapshotus"; $btnSnaps.Location = New-Object System.Drawing.Point(10, 245); $btnSnaps.Size = New-Object System.Drawing.Size(150, 34)
    $dlg.Controls.Add($btnSnaps)
    $btnGo = New-Object System.Windows.Forms.Button
    $btnGo.Text = "Atjaunot"; $btnGo.Location = New-Object System.Drawing.Point(330, 245); $btnGo.Size = New-Object System.Drawing.Size(100, 34)
    $dlg.Controls.Add($btnGo)
    $btnX = New-Object System.Windows.Forms.Button
    $btnX.Text = "Aizvērt"; $btnX.Location = New-Object System.Drawing.Point(440, 245); $btnX.Size = New-Object System.Drawing.Size(90, 34)
    $btnX.Add_Click({ $dlg.Close() })
    $dlg.Controls.Add($btnX)

    $common = @'
$share = "__SHARE__"
$repo = "__REPO__"
$restic = "__RESTIC__"
$nasUser = "labprofilbackup"
if (-not (Test-Path $share)) {
    $p1 = Read-Host "NAS konta labprofilbackup parole" -AsSecureString
    $nasPass = (New-Object System.Net.NetworkCredential("", $p1)).Password
    net use $share /user:$nasUser $nasPass /persistent:no | Out-Null
}
if ($env:LAB_RESTIC_PW) { $env:RESTIC_PASSWORD = $env:LAB_RESTIC_PW }
else {
    $p2 = Read-Host "restic repozitorija parole" -AsSecureString
    $env:RESTIC_PASSWORD = (New-Object System.Net.NetworkCredential("", $p2)).Password
}
$env:RESTIC_REPOSITORY = $repo
$local = Join-Path $env:TEMP "restic-ui.exe"
Copy-Item $restic $local -Force
'@
    $common = $common.Replace("__SHARE__", $Root).Replace("__REPO__", (Join-Path $Root $Pc)).Replace("__RESTIC__", (Join-Path $NasRoot "Tools\restic.exe"))

    $btnSnaps.Add_Click({
        Start-ResticWindow -Title "Snapshots: $Pc" -Body ($common + "`r`n& `$local snapshots`r`nWrite-Host ''`r`nWrite-Host 'Gatavs. Logu var aizvert.'")
    })
    $btnGo.Add_Click({
        $t = $tbTarget.Text.Trim(); $s = $tbSnap.Text.Trim(); $inc = $tbInc.Text.Trim()
        if (-not $t -or -not $s) { $script:MB.Show("Aizpildiet snapshot un mērķa mapi.", "Info") | Out-Null; return }
        if ($t -match '^[A-Za-z]:\\?$' -or $t -match '^[A-Za-z]:\\(Users|Windows|Program Files)') {
            if ($script:MB.Show("Mērķa mape '$t' ir sistēmas vieta. Turpināt?", "Uzmanību", "YesNo", "Warning") -ne "Yes") { return }
        }
        $cmd = "& `$local restore '$s' --target '$t'"
        if ($inc) { $cmd += " --include '" + $inc.Replace("'", "''") + "'" }
        $body = $common + "`r`n" + $cmd + "`r`nWrite-Host ''`r`nWrite-Host 'Gatavs. Faili: $t'"
        Start-ResticWindow -Title "Atjaunosana: $Pc" -Body $body
    })
    [void]$dlg.ShowDialog()
}

function Show-AddBackupDialog {
    param([string]$Root, [string]$NasRoot, [string]$ScheduleFile)
    $dlg = New-Object System.Windows.Forms.Form
    $dlg.Text = "Pievienot datorus profilu kopēšanai"
    $dlg.Size = New-Object System.Drawing.Size(720, 560)
    $dlg.StartPosition = "CenterParent"

    $lbl = New-Object System.Windows.Forms.Label
    $lbl.Text = "Datori no device-schedule.csv / inventāra, kuriem vēl nav kopiju repozitārija. Atzīmējiet, kuriem uzstādīt kopēšanu (biroja datori; portātīvie un klases parasti NE)."
    $lbl.Location = New-Object System.Drawing.Point(10, 8); $lbl.Size = New-Object System.Drawing.Size(690, 34)
    $dlg.Controls.Add($lbl)

    $chk = New-Object System.Windows.Forms.CheckBox
    $chk.Text = "Rādīt arī datorus, kuriem kopijas jau ir"
    $chk.Location = New-Object System.Drawing.Point(10, 44); $chk.Size = New-Object System.Drawing.Size(300, 22)
    $dlg.Controls.Add($chk)

    $lv = New-Object System.Windows.Forms.ListView
    $lv.Location = New-Object System.Drawing.Point(10, 70); $lv.Size = New-Object System.Drawing.Size(690, 340)
    $lv.View = "Details"; $lv.CheckBoxes = $true; $lv.FullRowSelect = $true; $lv.GridLines = $true
    [void]$lv.Columns.Add("Dators", 150); [void]$lv.Columns.Add("Grupa", 130); [void]$lv.Columns.Add("Veids", 80); [void]$lv.Columns.Add("IP (no inventāra)", 130); [void]$lv.Columns.Add("Kopijas", 80)
    $dlg.Controls.Add($lv)

    $fill = {
        $lv.Items.Clear()
        $inv = @{}
        $im = Join-Path $NasRoot "Config\inventory-manual.csv"
        if (Test-Path $im) { foreach ($r in @(Import-Csv -Path $im -Encoding UTF8)) { $inv[[string]$r.ComputerName.ToUpper()] = $r } }
        $have = @{}
        if (Test-Path $Root) { foreach ($d in @(Get-ChildItem $Root -Directory -ErrorAction SilentlyContinue)) { if (Test-Path (Join-Path $d.FullName 'config')) { $have[$d.Name.ToUpper()] = $true } } }
        $names = @{}
        if (Test-Path $ScheduleFile) { foreach ($r in @(Import-Csv -Path $ScheduleFile -Encoding UTF8)) { if ($r.ComputerName) { $names[[string]$r.ComputerName.ToUpper()] = [string]$r.Group } } }
        foreach ($k in $inv.Keys) { if (-not $names.ContainsKey($k)) { $names[$k] = [string]$inv[$k].Group } }
        foreach ($k in ($names.Keys | Sort-Object)) {
            $has = $have.ContainsKey($k)
            if ($has -and -not $chk.Checked) { continue }
            $type = ""; if ($inv.ContainsKey($k)) { $type = [string]$inv[$k].Type }
            $ip = Get-PcIp -NasRoot $NasRoot -Pc $k
            $it = New-Object System.Windows.Forms.ListViewItem($k)
            [void]$it.SubItems.Add($names[$k]); [void]$it.SubItems.Add($type); [void]$it.SubItems.Add($ip); [void]$it.SubItems.Add($(if ($has) { "ir" } else { "nav" }))
            if (-not $ip) { $it.ForeColor = [System.Drawing.Color]::Gray }
            [void]$lv.Items.Add($it)
        }
    }
    $chk.Add_CheckedChanged({ & $fill })
    & $fill

    $ipLbl = New-Object System.Windows.Forms.Label
    $ipLbl.Text = "Papildus IP adreses (neobligāti, ar komatiem), ja datora nav inventārā:"
    $ipLbl.Location = New-Object System.Drawing.Point(10, 418); $ipLbl.Size = New-Object System.Drawing.Size(500, 18)
    $dlg.Controls.Add($ipLbl)
    $tbIp = New-Object System.Windows.Forms.TextBox
    $tbIp.Location = New-Object System.Drawing.Point(10, 438); $tbIp.Size = New-Object System.Drawing.Size(690, 24)
    $dlg.Controls.Add($tbIp)

    $go = New-Object System.Windows.Forms.Button
    $go.Text = "Uzstādīt atzīmētajiem"; $go.Location = New-Object System.Drawing.Point(430, 475); $go.Size = New-Object System.Drawing.Size(170, 34)
    $dlg.Controls.Add($go)
    $cl = New-Object System.Windows.Forms.Button
    $cl.Text = "Aizvērt"; $cl.Location = New-Object System.Drawing.Point(610, 475); $cl.Size = New-Object System.Drawing.Size(90, 34)
    $cl.Add_Click({ $dlg.Close() })
    $dlg.Controls.Add($cl)

    $go.Add_Click({
        $ips = @(); $noip = @()
        foreach ($it in $lv.CheckedItems) {
            $ip = $it.SubItems[3].Text
            if ($ip) { $ips += $ip } else { $noip += $it.Text }
        }
        foreach ($x in ($tbIp.Text -split ",")) { if ($x.Trim()) { $ips += $x.Trim() } }
        if ($noip.Count -gt 0) {
            $script:MB.Show("Nav zināmas IP adreses (izlaisti): " + ($noip -join ", ") + "`nIevadiet tās laukā zemāk.", "Info") | Out-Null
        }
        if ($ips.Count -eq 0) { return }
        $setup = Join-Path $PSScriptRoot "remote-backup-setup.ps1"
        if (-not (Test-Path $setup)) { $setup = "C:\Scripts\remote-backup-setup.ps1" }
        if (-not (Test-Path $setup)) { $script:MB.Show("remote-backup-setup.ps1 nav atrasts (C:\Scripts).", "Kļūda") | Out-Null; return }
        $list = ($ips | Sort-Object -Unique) -join ","
        if ($script:MB.Show("Uzstādīt profilu kopēšanu uz: $list ?`nAtvērs PowerShell logu; tur prasīs lokālo administratoru un labprofilbackup paroli.", "Apstiprināt", "YesNo") -ne "Yes") { return }
        $arg = @("-NoProfile", "-ExecutionPolicy", "Bypass", "-NoExit", "-File", $setup, "-ComputerNames", $list, "-StartNow")
        Start-Process powershell.exe -ArgumentList $arg
    })
    [void]$dlg.ShowDialog()
}

function Show-ProfilePicker {
    param([string]$NasRoot, [string]$Pc)
    $ip = Get-PcIp -NasRoot $NasRoot -Pc $Pc
    Add-Type -AssemblyName Microsoft.VisualBasic
    $ip = [Microsoft.VisualBasic.Interaction]::InputBox("Datora IP adrese (profilu saraksta nolasīšanai).", "Profili: $Pc", $ip)
    if (-not $ip) { return }
    $cred = Get-Credential -UserName "Administrator" -Message "Lokālais administrators datoram $Pc"
    if (-not $cred) { return }
    try {
        $info = Invoke-Command -ComputerName $ip -Credential $cred -ErrorAction Stop -ScriptBlock {
            $cfg = $null
            try { $cfg = Get-Content "C:\ProgramData\LabBackup\config.json" -Raw | ConvertFrom-Json } catch { }
            $sel = @(); if ($cfg -and $cfg.Profiles) { $sel = @($cfg.Profiles | ForEach-Object { [string]$_ }) }
            $list = @()
            foreach ($p in @(Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList\S-1-5-21-*' -ErrorAction SilentlyContinue)) {
                $path = [Environment]::ExpandEnvironmentVariables([string]$p.ProfileImagePath)
                $last = ""
                try { $last = (Get-Item (Join-Path $path "NTUSER.DAT") -Force -ErrorAction Stop).LastWriteTime.ToString("dd.MM.yyyy") } catch { }
                $list += [PSCustomObject]@{ Name = (Split-Path $path -Leaf); Last = $last }
            }
            $exs = @(); if ($cfg -and $cfg.ExcludePaths) { $exs = @($cfg.ExcludePaths | ForEach-Object { [string]$_ }) }
            [PSCustomObject]@{ Selected = $sel; Profiles = $list; HasConfig = [bool]$cfg; Excludes = $exs }
        }
    } catch {
        $script:MB.Show("Neizdevās nolasīt profilus: $_", "Kļūda") | Out-Null
        return
    }
    if (-not $info.HasConfig) {
        $script:MB.Show("Datora nav C:\ProgramData\LabBackup\config.json - profilu kopēšana nav uzstādīta. Vispirms «Pievienot datorus».", "Info") | Out-Null
        return
    }

    $dlg = New-Object System.Windows.Forms.Form
    $dlg.Text = "Kopējamie profili: $Pc"
    $dlg.Size = New-Object System.Drawing.Size(460, 600)
    $dlg.StartPosition = "CenterParent"
    $lbl = New-Object System.Windows.Forms.Label
    $lbl.Text = "Atzīmējiet profilus, ko kopēt. Neviens atzīmēts = kopēt VISUS profilus."
    $lbl.Location = New-Object System.Drawing.Point(10, 8); $lbl.Size = New-Object System.Drawing.Size(430, 34)
    $dlg.Controls.Add($lbl)
    $clb = New-Object System.Windows.Forms.CheckedListBox
    $clb.Location = New-Object System.Drawing.Point(10, 45); $clb.Size = New-Object System.Drawing.Size(425, 280); $clb.CheckOnClick = $true
    foreach ($pr in @($info.Profiles | Sort-Object Name)) {
        $i = $clb.Items.Add(("{0}   (pedeja lietosana {1})" -f $pr.Name, $pr.Last))
        if (@($info.Selected) -contains $pr.Name) { $clb.SetItemChecked($i, $true) }
    }
    $dlg.Controls.Add($clb)
    $exl = New-Object System.Windows.Forms.Label
    $exl.Text = "NEkopējamie ceļi (mape vai fails, katrs jaunā rindā, piem. D:\Ieva):"
    $exl.Location = New-Object System.Drawing.Point(10, 332); $exl.Size = New-Object System.Drawing.Size(430, 20)
    $dlg.Controls.Add($exl)
    $exb = New-Object System.Windows.Forms.TextBox
    $exb.Multiline = $true; $exb.ScrollBars = "Vertical"; $exb.AcceptsReturn = $true
    $exb.Location = New-Object System.Drawing.Point(10, 355); $exb.Size = New-Object System.Drawing.Size(425, 120)
    $exb.Text = (@($info.Excludes) -join "`r`n")
    $dlg.Controls.Add($exb)
    $ok = New-Object System.Windows.Forms.Button
    $ok.Text = "Saglabāt datoram"; $ok.Location = New-Object System.Drawing.Point(230, 490); $ok.Size = New-Object System.Drawing.Size(130, 34)
    $dlg.Controls.Add($ok)
    $cl = New-Object System.Windows.Forms.Button
    $cl.Text = "Atcelt"; $cl.Location = New-Object System.Drawing.Point(370, 490); $cl.Size = New-Object System.Drawing.Size(65, 34)
    $cl.Add_Click({ $dlg.Close() })
    $dlg.Controls.Add($cl)
    $ok.Add_Click({
        $chosen = @()
        foreach ($x in $clb.CheckedItems) { $chosen += ([string]$x -split "   \(")[0] }
        $excl = @(($exb.Text -split "`r?`n") | ForEach-Object { $_.Trim() } | Where-Object { $_ })
        try {
            Invoke-Command -ComputerName $ip -Credential $cred -ErrorAction Stop -ArgumentList (,$chosen), (,$excl) -ScriptBlock {
                param($chosen, $excl)
                $f = "C:\ProgramData\LabBackup\config.json"
                $h = @{}
                $j = Get-Content $f -Raw | ConvertFrom-Json
                foreach ($pp in $j.PSObject.Properties) { if ($pp.Name -ne "Profiles" -and $pp.Name -ne "ExcludePaths") { $h[$pp.Name] = $pp.Value } }
                if (@($chosen).Count -gt 0) { $h["Profiles"] = @($chosen) }
                if (@($excl).Count -gt 0) { $h["ExcludePaths"] = @($excl) }
                $h | ConvertTo-Json | Set-Content $f -Encoding ASCII
            }
            $txt = $(if ($chosen.Count -gt 0) { "Kopēs tikai: " + ($chosen -join ", ") } else { "Kopēs VISUS profilus" })
            $script:MB.Show("$txt`nStāsies spēkā nākamā kopijā («Palaist kopiju tagad»).", "Gatavs") | Out-Null
            $dlg.Close()
        } catch { $script:MB.Show("Neizdevās saglabāt: $_", "Kļūda") | Out-Null }
    })
    [void]$dlg.ShowDialog()
}

function Get-ResticPassword {
    # Parole tiek turēta tikai šī loga atmiņā (nekad netiek rakstīta diskā).
    if ($script:ResticPasswordDefault) { return $script:ResticPasswordDefault }
    if ($script:resticPassCache) { return $script:resticPassCache }
    $d = New-Object System.Windows.Forms.Form
    $d.Text = "Restic parole"; $d.StartPosition = "CenterParent"; $d.FormBorderStyle = "FixedDialog"
    $d.MaximizeBox = $false; $d.MinimizeBox = $false; $d.ClientSize = New-Object System.Drawing.Size(420, 130)
    $l = New-Object System.Windows.Forms.Label
    $l.Text = "Ievadiet restic repozitorija paroli (noklusēti = labprofilbackup parole). Tā netiek saglabāta diskā, tikai šī loga atmiņā."
    $l.Location = New-Object System.Drawing.Point(10, 10); $l.Size = New-Object System.Drawing.Size(400, 40)
    $d.Controls.Add($l)
    $tb = New-Object System.Windows.Forms.TextBox
    $tb.UseSystemPasswordChar = $true; $tb.Location = New-Object System.Drawing.Point(10, 55); $tb.Size = New-Object System.Drawing.Size(400, 24)
    $d.Controls.Add($tb)
    $ok = New-Object System.Windows.Forms.Button
    $ok.Text = "Labi"; $ok.Location = New-Object System.Drawing.Point(230, 90); $ok.Size = New-Object System.Drawing.Size(85, 30)
    $ok.DialogResult = [System.Windows.Forms.DialogResult]::OK; $d.Controls.Add($ok); $d.AcceptButton = $ok
    $cn = New-Object System.Windows.Forms.Button
    $cn.Text = "Atcelt"; $cn.Location = New-Object System.Drawing.Point(325, 90); $cn.Size = New-Object System.Drawing.Size(85, 30)
    $cn.DialogResult = [System.Windows.Forms.DialogResult]::Cancel; $d.Controls.Add($cn); $d.CancelButton = $cn
    if ($d.ShowDialog() -ne [System.Windows.Forms.DialogResult]::OK -or -not $tb.Text) { return $null }
    $script:resticPassCache = $tb.Text
    return $script:resticPassCache
}

function Show-BackupDetails {
    param([string]$Root, [string]$NasRoot, [string]$Pc, $Row)
    $win = New-Object System.Windows.Forms.Form
    $win.Text = "Kopiju detaļas: $Pc"
    $win.Size = New-Object System.Drawing.Size(1000, 620)
    $win.StartPosition = "CenterParent"
    $win.MinimumSize = New-Object System.Drawing.Size(700, 400)

    $head = New-Object System.Windows.Forms.Label
    $head.Location = New-Object System.Drawing.Point(10, 8); $head.Size = New-Object System.Drawing.Size(965, 80)
    $head.Anchor = "Top,Left,Right"
    $head.Font = New-Object System.Drawing.Font("Segoe UI", 9.5)
    $txt = "Dators: $Pc`r`nPēdējā kopija: " + $Row.Finished + "  (vecums " + $Row.AgeH + " h)    Rezultāts: " + $Row.Result + "    Ilgums: " + $Row.Duration + " min"
    if ($Row.Detail) { $txt += "`r`nPiezīmes: " + $Row.Detail }
    $head.Text = $txt
    $win.Controls.Add($head)

    $g = New-Object System.Windows.Forms.DataGridView
    $g.Location = New-Object System.Drawing.Point(10, 95); $g.Size = New-Object System.Drawing.Size(965, 410)
    $g.Anchor = "Top,Bottom,Left,Right"
    $g.AllowUserToAddRows = $false; $g.ReadOnly = $true; $g.RowHeadersVisible = $false
    $g.SelectionMode = [System.Windows.Forms.DataGridViewSelectionMode]::FullRowSelect
    $g.AutoGenerateColumns = $false
    foreach ($c in @(@("Id", "Snapshot", 90), @("Time", "Laiks", 140), @("AgeD", "Vecums (dienas)", 100), @("Added", "Pievienots (MiB)", 110), @("Files", "Faili", 80), @("SizeGB", "Apjoms (GiB)", 100), @("Tags", "Birkas", 90), @("Note", "Piezīmes", 230))) {
        $col = New-Object System.Windows.Forms.DataGridViewTextBoxColumn
        $col.Name = $c[0]; $col.DataPropertyName = $c[0]; $col.HeaderText = $c[1]; $col.Width = $c[2]; $col.SortMode = "Automatic"
        [void]$g.Columns.Add($col)
    }
    $win.Controls.Add($g)

    $sum = New-Object System.Windows.Forms.Label
    $sum.Location = New-Object System.Drawing.Point(10, 512); $sum.Size = New-Object System.Drawing.Size(965, 22)
    $sum.Anchor = "Bottom,Left,Right"
    $win.Controls.Add($sum)

    $btnLoad = New-Object System.Windows.Forms.Button
    $btnLoad.Text = "Ielādēt snapshotus"; $btnLoad.Location = New-Object System.Drawing.Point(10, 540); $btnLoad.Size = New-Object System.Drawing.Size(170, 34); $btnLoad.Anchor = "Bottom,Left"
    $win.Controls.Add($btnLoad)
    $btnSize = New-Object System.Windows.Forms.Button
    $btnSize.Text = "Repozitorija apjoms"; $btnSize.Location = New-Object System.Drawing.Point(190, 540); $btnSize.Size = New-Object System.Drawing.Size(170, 34); $btnSize.Anchor = "Bottom,Left"
    $win.Controls.Add($btnSize)
    $btnClose = New-Object System.Windows.Forms.Button
    $btnClose.Text = "Aizvērt"; $btnClose.Location = New-Object System.Drawing.Point(875, 540); $btnClose.Size = New-Object System.Drawing.Size(100, 34); $btnClose.Anchor = "Bottom,Right"
    $btnClose.Add_Click({ $win.Close() })
    $win.Controls.Add($btnClose)

    $script:bdRepoMB = ""
    $btnSize.Add_Click({
        $btnSize.Enabled = $false; $sum.Text = "Skaitu repozitorija apjomu..."; [System.Windows.Forms.Application]::DoEvents()
        try {
            $s = (Get-ChildItem (Join-Path $Root $Pc) -Recurse -File -Force -ErrorAction SilentlyContinue | Measure-Object Length -Sum).Sum
            $script:bdRepoMB = [math]::Round(([double]$s) / 1MB, 0)
            $sum.Text = "Repozitorija apjoms uz NAS: " + [math]::Round($script:bdRepoMB / 1024, 2) + " GB (" + $script:bdRepoMB + " MB)"
        } finally { $btnSize.Enabled = $true }
    })

    $btnLoad.Add_Click({
        $pw = Get-ResticPassword
        if (-not $pw) { return }
        $btnLoad.Enabled = $false; $sum.Text = "Lasu snapshotus (restic)..."; [System.Windows.Forms.Application]::DoEvents()
        try {
            $src = Join-Path $NasRoot "Tools\restic.exe"
            $local = Join-Path $env:TEMP "restic-ui.exe"
            if ((-not (Test-Path $local)) -or ((Get-Item $local).Length -ne (Get-Item $src).Length)) { Copy-Item $src $local -Force }
            $env:RESTIC_REPOSITORY = Join-Path $Root $Pc
            $env:RESTIC_PASSWORD = $pw
            $out = & $local snapshots --json 2>&1
            $code = $LASTEXITCODE
            Remove-Item Env:\RESTIC_PASSWORD -ErrorAction SilentlyContinue
            if ($code -ne 0) {
                $script:resticPassCache = $null
                $script:MB.Show("restic kļūda (iespējams, nepareiza parole):`n" + (($out | Select-Object -Last 3) -join "`n"), "Kļūda") | Out-Null
                $sum.Text = ""
                return
            }
            $snaps = @(($out -join "`n") | ConvertFrom-Json)
            $now = Get-Date
            $list = New-Object System.Collections.ArrayList
            foreach ($s in ($snaps | Sort-Object { [datetime]$_.time } -Descending)) {
                $tm = [datetime]$s.time
                $added = ""; $files = ""; $gb = ""
                if ($s.summary) {
                    if ($s.summary.data_added -ne $null) { $added = [math]::Round($s.summary.data_added / 1MB, 1) }
                    if ($s.summary.total_files_processed -ne $null) { $files = $s.summary.total_files_processed }
                    if ($s.summary.total_bytes_processed -ne $null) { $gb = [math]::Round($s.summary.total_bytes_processed / 1GB, 2) }
                }
                [void]$list.Add([PSCustomObject]@{
                    Id = [string]$s.short_id; Time = $tm.ToString("dd.MM.yyyy HH:mm"); AgeD = [math]::Round(($now - $tm).TotalDays, 1)
                    Added = $added; Files = $files; SizeGB = $gb; Tags = (@($s.tags) -join ","); Note = ""
                })
            }
            $g.DataSource = $null
            $g.DataSource = $list
            $n = $list.Count
            if ($n -gt 0) {
                $sum.Text = "Snapshotu skaits: $n    Jaunākais: " + $list[0].Time + " (pirms " + $list[0].AgeD + " d)    Vecākais: " + $list[$n - 1].Time + " (pirms " + $list[$n - 1].AgeD + " d)"
            } else { $sum.Text = "Snapshotu nav." }
        } catch {
            $script:MB.Show("Neizdevās nolasīt: $_", "Kļūda") | Out-Null
        } finally { $btnLoad.Enabled = $true }
    })

    $win.Add_Shown({ $btnLoad.PerformClick() })
    [void]$win.ShowDialog()
}

function Show-BackupManager {
    param([string]$NasRoot = "\\PIUAC_CLOUD\Updates", [string]$Root = "\\192.168.3.31\ProfiluKopijas")

    $schedFile = Join-Path $NasRoot "Config\device-schedule.csv"
    if (-not (Test-Path $Root)) {
        $script:MB.Show("Nav pieejams $Root. Savienojums: net use \\192.168.3.31\ProfiluKopijas /user:labprofilbackup", "Kļūda") | Out-Null
        return
    }

    $win = New-Object System.Windows.Forms.Form
    $win.Text = "Profilu kopijas - $Root"
    $win.Size = New-Object System.Drawing.Size(1320, 640)
    $win.StartPosition = "CenterParent"
    $win.MinimumSize = New-Object System.Drawing.Size(900, 450)

    $sum = New-Object System.Windows.Forms.Label
    $sum.Location = New-Object System.Drawing.Point(10, 8); $sum.Size = New-Object System.Drawing.Size(1280, 20)
    $sum.Anchor = "Top,Left,Right"
    $win.Controls.Add($sum)

    $g = New-Object System.Windows.Forms.DataGridView
    $g.Location = New-Object System.Drawing.Point(10, 32); $g.Size = New-Object System.Drawing.Size(1285, 470)
    $g.Anchor = "Top,Bottom,Left,Right"
    $g.AllowUserToAddRows = $false; $g.ReadOnly = $true; $g.RowHeadersVisible = $false
    $g.SelectionMode = [System.Windows.Forms.DataGridViewSelectionMode]::FullRowSelect
    $g.MultiSelect = $false
    $g.AutoGenerateColumns = $false
    $cols = @(
        @("PC", "Dators", 140), @("Result", "Rezultāts", 80), @("Finished", "Pēdējā kopija", 130), @("AgeH", "Vecums (h)", 70),
        @("Duration", "Ilgums (min)", 80), @("Snapshot", "Snapshot", 80), @("Added", "Pievienots", 100), @("Mode", "Rēžīms", 60),
        @("SizeMB", "Repozitārijs (MB)", 110), @("Repo", "Repo ir", 55), @("Detail", "Piezīmes", 330)
    )
    foreach ($c in $cols) {
        $col = New-Object System.Windows.Forms.DataGridViewTextBoxColumn
        $col.Name = $c[0]; $col.DataPropertyName = $c[0]; $col.HeaderText = $c[1]; $col.Width = $c[2]
        $col.SortMode = "Automatic"
        [void]$g.Columns.Add($col)
    }
    $win.Controls.Add($g)
    $g.Add_CellDoubleClick({ param($s, $e) if ($e.RowIndex -ge 0) { $n = [string]$g.Rows[$e.RowIndex].Cells["PC"].Value; $row = $script:bmRows | Where-Object { $_.PC -eq $n } | Select-Object -First 1; if ($row) { Show-BackupDetails -Root $Root -NasRoot $NasRoot -Pc $n -Row $row } } })

    $script:bmRows = @()
    function Set-BackupColors {
        foreach ($gr in $g.Rows) {
            $res = [string]$gr.Cells["Result"].Value
            $ageV = [string]$gr.Cells["AgeH"].Value
            $color = [System.Drawing.Color]::White
            if ($res -eq "FAILED") { $color = [System.Drawing.Color]::MistyRose }
            elseif ($res -eq "WARN") { $color = [System.Drawing.Color]::LemonChiffon }
            elseif ($ageV -ne "" -and ([double]$ageV) -gt 48) { $color = [System.Drawing.Color]::LemonChiffon }
            elseif ($res -eq "OK") { $color = [System.Drawing.Color]::Honeydew }
            $gr.DefaultCellStyle.BackColor = $color
        }
    }
    $g.Add_DataBindingComplete({ Set-BackupColors })

    function Reload-Backups {
        $rows = Get-BackupRows -Root $Root -ScheduleFile $schedFile
        $now = Get-Date
        $old = @{}; foreach ($r in $script:bmRows) { $old[$r.PC] = $r.SizeMB }
        $list = New-Object System.Collections.ArrayList
        $ok = 0; $bad = 0; $stale = 0
        foreach ($r in $rows) {
            $age = ""
            if ($r.Finished) { $age = [math]::Round(($now - $r.Finished).TotalHours, 1) }
            $sz = $r.SizeMB; if ($old.ContainsKey($r.PC) -and $old[$r.PC]) { $sz = $old[$r.PC] }
            $o = [PSCustomObject]@{
                PC = $r.PC; Result = $r.Result
                Finished = $(if ($r.Finished) { $r.Finished.ToString("dd.MM.yyyy HH:mm") } else { "" })
                AgeH = $age; Duration = $r.Duration; Snapshot = $r.Snapshot; Added = $r.Added; Mode = $r.Mode
                SizeMB = $sz; Repo = $(if ($r.Repo) { "Ja" } else { "Nav" }); Detail = $r.Detail
            }
            [void]$list.Add($o)
            if ($r.Result -in "OK", "WARN") { $ok++ } elseif ($r.Result) { $bad++ }
            if ($age -ne "" -and $age -gt 48) { $stale++ }
        }
        $script:bmRows = @($list)
        $g.DataSource = $null
        $g.DataSource = $list
        Set-BackupColors
        $sum.Text = "Datori: $($list.Count)     OK/WARN: $ok     Kļūdas (FAILED/NO-NAS): $bad     Vecāki par 48 h: $stale     (statuss: _status\*.json)"
    }
    Reload-Backups

    function New-Btn($text, $x, $w) {
        $b = New-Object System.Windows.Forms.Button
        $b.Text = $text; $b.Location = New-Object System.Drawing.Point($x, 515); $b.Size = New-Object System.Drawing.Size($w, 34)
        $b.Anchor = "Bottom,Left"; $win.Controls.Add($b); return $b
    }
    function Get-SelPc { if ($g.SelectedRows.Count -eq 0) { $script:MB.Show("Atlasiet datoru tabulā.", "Info") | Out-Null; return $null }; return [string]$g.SelectedRows[0].Cells["PC"].Value }

    $bRef = New-Btn "Atjaunāt sarakstu" 10 130
    $bRef.Add_Click({ Reload-Backups })

    $bSize = New-Btn "Aprēķināt apjomus" 150 140
    $bSize.Add_Click({
        $bSize.Enabled = $false
        try {
            foreach ($r in @($script:bmRows)) {
                $sum.Text = "Skaitīju apjomu: $($r.PC) ..."; [System.Windows.Forms.Application]::DoEvents()
                $p = Join-Path $Root $r.PC
                if (Test-Path $p) {
                    $s = (Get-ChildItem $p -Recurse -File -Force -ErrorAction SilentlyContinue | Measure-Object Length -Sum).Sum
                    $r.SizeMB = [math]::Round(([double]$s) / 1MB, 0)
                }
            }
            $keep = $script:bmRows
            $g.Refresh()
            foreach ($gr in $g.Rows) { $n = [string]$gr.Cells["PC"].Value; $m = $keep | Where-Object { $_.PC -eq $n } | Select-Object -First 1; if ($m) { $gr.Cells["SizeMB"].Value = $m.SizeMB } }
            $tot = ($keep | Where-Object { $_.SizeMB -ne "" } | Measure-Object SizeMB -Sum).Sum
            $sum.Text = "Kopējais apjoms: " + [math]::Round($tot / 1024, 1) + " GB  (" + $keep.Count + " datori)"
        } finally { $bSize.Enabled = $true }
    })

    $bRun = New-Btn "Palaist kopiju tagad" 300 160
    $bRun.Add_Click({
        $pc = Get-SelPc; if (-not $pc) { return }
        $ip = Get-PcIp -NasRoot $NasRoot -Pc $pc
        $ip = [Microsoft.VisualBasic.Interaction]::InputBox("Datora IP adrese (attālinātai palaišanai). Administratora konts tiks pieprasīts.", "Palaist kopiju: $pc", $ip)
        if (-not $ip) { return }
        $cred = Get-Credential -UserName "Administrator" -Message "Lokālais administrators datoram $pc"
        if (-not $cred) { return }
        try {
            $r = Invoke-Command -ComputerName $ip -Credential $cred -ErrorAction Stop -ScriptBlock {
                Remove-Item "C:\ProgramData\LabBackup\last-success.json" -Force -ErrorAction SilentlyContinue
                Start-ScheduledTask -TaskName "LabProfileBackup"
                (Get-ScheduledTask -TaskName "LabProfileBackup").State
            }
            $script:MB.Show("Uzdevums LabProfileBackup palaists uz $pc ($ip). Statuss: $r`nRezultats paradisies pec mazaks par stundu (Atjaunāt sarakstu).", "Gatavs") | Out-Null
        } catch {
            $script:MB.Show("Neizdevās: $_", "Kļūda") | Out-Null
        }
    })

    $bRestore = New-Btn "Atjaunot no NAS..." 470 150
    $bRestore.Add_Click({ $pc = Get-SelPc; if ($pc) { Show-RestoreDialog -Root $Root -NasRoot $NasRoot -Pc $pc } })

    $bPrune = New-Btn "Versiju tīrīšana..." 630 150
    $bPrune.Add_Click({
        $a = $script:MB.Show("Palaist lab-backup-prune.ps1 (atstāj 7 pēdējās + 4 nedēļu + 6 mēnešu kopijas)?`n`n«Tikai parādīt» = tikai uzrāda, ko dzēst (DryRun)`n«Dzēst tīkšham» = TIEŠĀM dzēst (ar pārbaudi)", "Versiju tīrīšana", "YesNoCancel", "", @("Tikai parādīt", "Dzēst tīšām", "Atcelt"))
        if ($a -eq "Cancel") { return }
        $prune = Join-Path $PSScriptRoot "lab-backup-prune.ps1"
        if (-not (Test-Path $prune)) { $prune = "C:\Scripts\lab-backup-prune.ps1" }
        if (-not (Test-Path $prune)) { $prune = Join-Path $NasRoot "Tools\lab-backup\lab-backup-prune.ps1" }
        if (-not (Test-Path $prune)) { $script:MB.Show("lab-backup-prune.ps1 nav atrasts (C:\Scripts).", "Kļūda") | Out-Null; return }
        $arg = @("-NoProfile", "-ExecutionPolicy", "Bypass", "-NoExit", "-File", $prune, "-Root", $Root)
        if ($a -eq "Yes") { $arg += "-DryRun" } else { $arg += "-Check" }
        Start-Process powershell.exe -ArgumentList $arg
    })

    $bOpen = New-Btn "Atvērt mapi" 790 100
    $bOpen.Add_Click({ $pc = Get-SelPc; if ($pc) { Start-Process explorer.exe (Join-Path $Root $pc) } })

    $bAddPc = New-Btn "Pievienot datorus..." 895 150
    $bAddPc.Add_Click({
        Show-AddBackupDialog -Root $Root -NasRoot $NasRoot -ScheduleFile $schedFile
        Reload-Backups
    })

    $bProf = New-Btn "Profili..." 1050 120
    $bProf.Add_Click({ $pc = Get-SelPc; if ($pc) { Show-ProfilePicker -NasRoot $NasRoot -Pc $pc } })

    $bDet = New-Btn "Detaļas..." 1180 100
    $bDet.Location = New-Object System.Drawing.Point(1180, 555); $bDet.Anchor = "Bottom,Right"
    $bDet.Add_Click({ $pc = Get-SelPc; if ($pc) { $row = $script:bmRows | Where-Object { $_.PC -eq $pc } | Select-Object -First 1; if ($row) { Show-BackupDetails -Root $Root -NasRoot $NasRoot -Pc $pc -Row $row } } })

    $bClose = New-Btn "Aizvērt" 1180 100
    $bClose.Anchor = "Bottom,Right"
    $bClose.Add_Click({ $win.Close() })

    $note = New-Object System.Windows.Forms.Label
    $note.Text = "Kopijas veic uzdevums LabProfileBackup katrā datorā (03:30 + ik stundu, ne biežāk kā ik 18 h). Krāsas: zāls = OK, dzeltens = WARN vai vecāks par 48 h, sarkans = FAILED. Parole netiek glabāta - atjaunošanas logs to pieprasa."
    $note.Location = New-Object System.Drawing.Point(10, 558); $note.Size = New-Object System.Drawing.Size(1160, 36)
    $note.Anchor = "Bottom,Left"; $note.ForeColor = [System.Drawing.Color]::DimGray
    $win.Controls.Add($note)

    Add-Type -AssemblyName Microsoft.VisualBasic
    [void]$win.ShowDialog()
}
