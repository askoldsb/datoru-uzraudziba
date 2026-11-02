<#
 apps-managed-editor.ps1
 Logs apps-managed.csv redigesanai. Ielade config-panel.ps1 (tajaa pasaa mapee) un atver ar pogu
 "Programmu saraksts". Var palaist ari atseviski:  . .\apps-managed-editor.ps1; Show-AppsManagedEditor
 Saglaba uz NAS ar rezerves kopiju apps-managed.csv.bak-yyyyMMdd-HHmmss.
#>

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$script:AppsCols = @("Enabled","Key","DisplayName","WingetId","DisplayNamePattern","ExcludePattern","InstallType","SilentArgs","Mode","Architecture","DlInstallerType","Targets")

function Show-TargetsPicker {
    param([string]$ScheduleFile, [string]$Current)
    $names = @()
    if (Test-Path $ScheduleFile) { $names = @(Import-Csv -Path $ScheduleFile -Encoding UTF8 | ForEach-Object { [string]$_.ComputerName } | Where-Object { $_ } | Sort-Object -Unique) }
    $sel = @{}
    foreach ($t in ($Current -split ";")) { if ($t.Trim()) { $sel[$t.Trim().ToUpper()] = $true } }
    foreach ($k in @($sel.Keys)) { if (-not ($names | Where-Object { $_.ToUpper() -eq $k })) { $names += $k } }
    $names = @($names | Sort-Object -Unique)

    $dlg = New-Object System.Windows.Forms.Form
    $dlg.Text = "Merka datori (tuksh = VISI datori)"
    $dlg.Size = New-Object System.Drawing.Size(420, 560)
    $dlg.StartPosition = "CenterParent"
    $clb = New-Object System.Windows.Forms.CheckedListBox
    $clb.Location = New-Object System.Drawing.Point(10, 40)
    $clb.Size = New-Object System.Drawing.Size(385, 420)
    $clb.CheckOnClick = $true
    foreach ($n in $names) { $i = $clb.Items.Add($n); if ($sel.ContainsKey($n.ToUpper())) { $clb.SetItemChecked($i, $true) } }
    $dlg.Controls.Add($clb)
    $lbl = New-Object System.Windows.Forms.Label
    $lbl.Text = "Atzimeejiet datorus, kuriem programma tiek uzstadita/atjaunota. Neviens = visi."
    $lbl.Location = New-Object System.Drawing.Point(10, 8); $lbl.Size = New-Object System.Drawing.Size(385, 30)
    $dlg.Controls.Add($lbl)
    $btnAll = New-Object System.Windows.Forms.Button
    $btnAll.Text = "Notiirit (visi)"; $btnAll.Location = New-Object System.Drawing.Point(10, 470); $btnAll.Size = New-Object System.Drawing.Size(120, 32)
    $btnAll.Add_Click({ for ($i = 0; $i -lt $clb.Items.Count; $i++) { $clb.SetItemChecked($i, $false) } })
    $dlg.Controls.Add($btnAll)
    $ok = New-Object System.Windows.Forms.Button
    $ok.Text = "OK"; $ok.Location = New-Object System.Drawing.Point(230, 470); $ok.Size = New-Object System.Drawing.Size(80, 32)
    $ok.DialogResult = [System.Windows.Forms.DialogResult]::OK
    $dlg.Controls.Add($ok); $dlg.AcceptButton = $ok
    $cn = New-Object System.Windows.Forms.Button
    $cn.Text = "Atcelt"; $cn.Location = New-Object System.Drawing.Point(315, 470); $cn.Size = New-Object System.Drawing.Size(80, 32)
    $cn.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
    $dlg.Controls.Add($cn); $dlg.CancelButton = $cn
    if ($dlg.ShowDialog() -ne [System.Windows.Forms.DialogResult]::OK) { return $null }
    $res = @(); foreach ($x in $clb.CheckedItems) { $res += [string]$x }
    return ($res -join ";")
}

$script:ColorManaged = [System.Drawing.Color]::FromArgb(226, 242, 222)
$script:ColorNewApp  = [System.Drawing.Color]::FromArgb(255, 249, 196)

function Get-NormAppName {
    param([string]$Name)
    $x = $Name
    $x = $x -replace '\s*\((x64|x86|64-bit|32-bit|64 bit|32 bit)[^)]*\)', ''
    $x = $x -replace '\s+(version\s+)?v?\d+([\.\-]\d+)+.*$', ''
    $x = $x -replace '\s+\d+(\.\d+)*$', ''
    return $x.Trim()
}

function Get-InventoryAppCandidates {
    # Nolasa NAS Logs\Inventory\*.json, savac programmas pec nosaukuma, atmet jau parvaldamas,
    # sistemas troksni un ignoreto sarakstu (Config\apps-ignore.txt).
    param([string]$NasRoot, [object[]]$ManagedRows)

    $invDir = Join-Path $NasRoot "Logs\Inventory"
    if (-not (Test-Path $invDir)) { return @() }

    $ignoreFile = Join-Path $NasRoot "Config\apps-ignore.txt"
    $ignore = @{}
    if (Test-Path $ignoreFile) {
        foreach ($l in @(Get-Content -Path $ignoreFile -Encoding UTF8)) { if ($l.Trim()) { $ignore[$l.Trim().ToLower()] = $true } }
    }

    $noiseName = '^(Microsoft Visual C\+\+|Microsoft \.NET|Microsoft Windows Desktop Runtime|Microsoft ASP\.NET|Windows |Update for|Security Update|Hotfix|Microsoft Edge|Microsoft Update Health|Microsoft OneDrive|Microsoft Teams|Microsoft 365|Microsoft Office|Office |ESET|Microsoft Visual Studio|Intel\(R\)|Intel |Realtek|NVIDIA|AMD |Java Auto Updater|Teams Machine-Wide|WinRAR archiver$|Microsoft Windows)'
    $noisePub  = '^(Microsoft|Intel|Realtek|NVIDIA|Advanced Micro Devices|AMD|Synaptics|ASUSTeK|ASUS|Dell|HP|Hewlett|Lenovo|Qualcomm|MediaTek)'

    # Programmas, kas jau ir iebuveta client-install.ps1 ($Apps) - nav apps-managed.csv
    $builtin = @(
        [PSCustomObject]@{ DisplayNamePattern = "Mozilla *";           ExcludePattern = "" },
        [PSCustomObject]@{ DisplayNamePattern = "Google Chrome";       ExcludePattern = "" },
        [PSCustomObject]@{ DisplayNamePattern = "Zoom*";               ExcludePattern = "" },
        [PSCustomObject]@{ DisplayNamePattern = "TeamViewer*";         ExcludePattern = "" },
        [PSCustomObject]@{ DisplayNamePattern = "VLC media player*";   ExcludePattern = "" },
        [PSCustomObject]@{ DisplayNamePattern = "eParakst*";           ExcludePattern = "*Token Signing*" },
        [PSCustomObject]@{ DisplayNamePattern = "PowerShell 7-x64";    ExcludePattern = "" }
    )
    $ManagedRows = @($ManagedRows) + $builtin

    $groups = @{}
    foreach ($f in @(Get-ChildItem -Path $invDir -Filter "*.json" -File -ErrorAction SilentlyContinue)) {
        try { $inv = Get-Content -Path $f.FullName -Raw -Encoding UTF8 | ConvertFrom-Json } catch { continue }
        if (-not $inv -or -not $inv.Software -or -not $inv.Software.Programs) { continue }
        $pc = [string]$inv.ComputerName
        if (-not $pc) { $pc = [IO.Path]::GetFileNameWithoutExtension($f.Name) }
        foreach ($p in @($inv.Software.Programs)) {
            $raw = [string]$p.Name
            if (-not $raw) { continue }
            if ($raw -match $noiseName) { continue }
            if (([string]$p.Publisher) -match $noisePub) { continue }

            $managed = $false
            foreach ($m in $ManagedRows) {
                $pat = [string]$m.DisplayNamePattern
                if (-not $pat) { continue }
                if ($raw -like $pat) {
                    $ex = [string]$m.ExcludePattern
                    if ($ex -and ($raw -like $ex)) { continue }
                    $managed = $true; break
                }
            }
            if ($managed) { continue }

            $norm = Get-NormAppName $raw
            if (-not $norm) { continue }
            if ($ignore.ContainsKey($norm.ToLower())) { continue }
            $k = $norm.ToLower()
            if (-not $groups.ContainsKey($k)) {
                $groups[$k] = [PSCustomObject]@{ Name = $norm; Raw = $raw; Publisher = [string]$p.Publisher; Version = [string]$p.Version; PCs = @{} }
            }
            $groups[$k].PCs[$pc] = $true
        }
    }
    return @($groups.Values | Sort-Object @{ Expression = { $_.PCs.Count }; Descending = $true }, Name)
}

function Show-NewAppsPicker {
    # Atgriez @{ Add = @(kandidati); Ignore = @(kandidati) } vai $null
    param([object[]]$Candidates)

    $dlg = New-Object System.Windows.Forms.Form
    $dlg.Text = "Jaunas programmas no datoru inventara"
    $dlg.Size = New-Object System.Drawing.Size(760, 600)
    $dlg.StartPosition = "CenterParent"
    $lbl = New-Object System.Windows.Forms.Label
    $lbl.Text = "Programmas, kuras ir datoros, bet nav parvaldamo saraksta (" + $Candidates.Count + "). Atzimejiet, ko pievienot vai ignoret."
    $lbl.Location = New-Object System.Drawing.Point(10, 8); $lbl.Size = New-Object System.Drawing.Size(730, 34)
    $dlg.Controls.Add($lbl)
    $clb = New-Object System.Windows.Forms.CheckedListBox
    $clb.Location = New-Object System.Drawing.Point(10, 45); $clb.Size = New-Object System.Drawing.Size(730, 455)
    $clb.CheckOnClick = $true
    $clb.Anchor = "Top,Bottom,Left,Right"
    foreach ($c in $Candidates) {
        $pubTxt = ""
        if ($c.Publisher) { $pubTxt = " | " + $c.Publisher }
        [void]$clb.Items.Add(("{0}  [datori: {1}]{2}" -f $c.Name, $c.PCs.Count, $pubTxt))
    }
    $dlg.Controls.Add($clb)

    $bAdd = New-Object System.Windows.Forms.Button
    $bAdd.Text = "Pievienot atzimetas"; $bAdd.Location = New-Object System.Drawing.Point(10, 515); $bAdd.Size = New-Object System.Drawing.Size(170, 34)
    $bAdd.Anchor = "Bottom,Left"
    $bAdd.Tag = "add"
    $bAdd.DialogResult = [System.Windows.Forms.DialogResult]::OK
    $dlg.Controls.Add($bAdd)
    $bIgn = New-Object System.Windows.Forms.Button
    $bIgn.Text = "Ignoret atzimetas"; $bIgn.Location = New-Object System.Drawing.Point(190, 515); $bIgn.Size = New-Object System.Drawing.Size(170, 34)
    $bIgn.Anchor = "Bottom,Left"
    $dlg.Controls.Add($bIgn)
    $script:newAppsAction = "add"
    $bAdd.Add_Click({ $script:newAppsAction = "add" })
    $bIgn.Add_Click({ $script:newAppsAction = "ignore"; $dlg.DialogResult = [System.Windows.Forms.DialogResult]::OK; $dlg.Close() })
    $cn = New-Object System.Windows.Forms.Button
    $cn.Text = "Aizvert"; $cn.Location = New-Object System.Drawing.Point(660, 515); $cn.Size = New-Object System.Drawing.Size(80, 34)
    $cn.Anchor = "Bottom,Right"
    $cn.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
    $dlg.Controls.Add($cn); $dlg.CancelButton = $cn

    if ($dlg.ShowDialog() -ne [System.Windows.Forms.DialogResult]::OK) { return $null }
    $sel = @()
    foreach ($i in $clb.CheckedIndices) { $sel += $Candidates[$i] }
    return @{ Action = $script:newAppsAction; Items = $sel }
}

function Show-AppsManagedEditor {
    param([string]$NasRoot = "\\PIUAC_CLOUD\Updates")

    $csv = Join-Path $NasRoot "Config\apps-managed.csv"
    $schedFile = Join-Path $NasRoot "Config\device-schedule.csv"
    if (-not (Test-Path $csv)) {
        [System.Windows.Forms.MessageBox]::Show("Nav atrasts $csv", "Kluda") | Out-Null
        return
    }

    $win = New-Object System.Windows.Forms.Form
    $win.Text = "Programmu saraksts (apps-managed.csv) - $NasRoot"
    $win.Size = New-Object System.Drawing.Size(1250, 600)
    $win.StartPosition = "CenterParent"
    $win.MinimumSize = New-Object System.Drawing.Size(800, 400)

    $g = New-Object System.Windows.Forms.DataGridView
    $g.Location = New-Object System.Drawing.Point(10, 10)
    $g.Size = New-Object System.Drawing.Size(1215, 460)
    $g.Anchor = "Top,Bottom,Left,Right"
    $g.AllowUserToAddRows = $false
    $g.RowHeadersVisible = $false
    $g.SelectionMode = [System.Windows.Forms.DataGridViewSelectionMode]::FullRowSelect
    $g.MultiSelect = $false
    $g.AutoSizeRowsMode = "None"

    $widths = @{ Enabled = 55; Key = 120; DisplayName = 170; WingetId = 190; DisplayNamePattern = 190; ExcludePattern = 110; InstallType = 80; SilentArgs = 180; Mode = 90; Architecture = 70; DlInstallerType = 90; Targets = 300 }
    foreach ($c in $script:AppsCols) {
        if ($c -eq "Enabled") { $col = New-Object System.Windows.Forms.DataGridViewCheckBoxColumn }
        elseif ($c -eq "InstallType") { $col = New-Object System.Windows.Forms.DataGridViewComboBoxColumn; [void]$col.Items.AddRange(@("auto","exe","msi","zip-msi")) }
        elseif ($c -eq "Mode") { $col = New-Object System.Windows.Forms.DataGridViewComboBoxColumn; [void]$col.Items.AddRange(@("UpdateOnly","Install")) }
        elseif ($c -eq "Architecture") { $col = New-Object System.Windows.Forms.DataGridViewComboBoxColumn; [void]$col.Items.AddRange(@("","x64","x86")) }
        else { $col = New-Object System.Windows.Forms.DataGridViewTextBoxColumn }
        $col.Name = $c; $col.HeaderText = $c; $col.Width = $widths[$c]
        if ($c -eq "Key") { $col.ReadOnly = $false }
        [void]$g.Columns.Add($col)
    }
    $win.Controls.Add($g)

    function Fill-AppsGrid {
        $g.Rows.Clear()
        foreach ($r in @(Import-Csv -Path $csv -Encoding UTF8)) {
            $i = $g.Rows.Add()
            $row = $g.Rows[$i]
            foreach ($c in $script:AppsCols) {
                $v = [string]$r.$c
                if ($c -eq "Enabled") { $row.Cells[$c].Value = ($v -eq "1" -or $v -eq "Yes" -or $v -eq "True") }
                elseif ($c -in @("InstallType","Mode","Architecture")) {
                    if ($v -and -not $row.Cells[$c].Items.Contains($v)) { [void]$row.Cells[$c].Items.Add($v) }
                    $row.Cells[$c].Value = $v
                } else { $row.Cells[$c].Value = $v }
            }
            $row.DefaultCellStyle.BackColor = $script:ColorManaged
        }
    }
    Fill-AppsGrid

    function New-Btn($text, $x, $w) {
        $b = New-Object System.Windows.Forms.Button
        $b.Text = $text; $b.Location = New-Object System.Drawing.Point($x, 485); $b.Size = New-Object System.Drawing.Size($w, 34)
        $b.Anchor = "Bottom,Left"
        $win.Controls.Add($b); return $b
    }
    $bAdd = New-Btn "Pievienot" 10 100
    $bAdd.Add_Click({
        $i = $g.Rows.Add(); $r = $g.Rows[$i]
        $r.Cells["Enabled"].Value = $true
        $r.Cells["InstallType"].Value = "auto"
        $r.Cells["Mode"].Value = "UpdateOnly"
        $g.CurrentCell = $r.Cells["Key"]; $g.BeginEdit($true)
    })
    $bDel = New-Btn "Dzest atlasito" 115 120
    $bDel.Add_Click({
        if ($g.SelectedRows.Count -eq 0) { return }
        $k = [string]$g.SelectedRows[0].Cells["Key"].Value
        if ([System.Windows.Forms.MessageBox]::Show("Dzest '$k'?", "Apstiprinat", "YesNo") -eq "Yes") { $g.Rows.Remove($g.SelectedRows[0]) }
    })
    $bTgt = New-Btn "Merka datori..." 240 130
    $bTgt.Add_Click({
        if ($g.SelectedRows.Count -eq 0) { [System.Windows.Forms.MessageBox]::Show("Atlasiet rindu.", "Info") | Out-Null; return }
        $cell = $g.SelectedRows[0].Cells["Targets"]
        $new = Show-TargetsPicker -ScheduleFile $schedFile -Current ([string]$cell.Value)
        if ($new -ne $null) { $cell.Value = $new }
    })
    $bReload = New-Btn "Parladet no NAS" 375 130
    $bReload.Add_Click({ Fill-AppsGrid })

    $bScan = New-Btn "Mekleet jaunas programmas..." 515 220
    $bScan.Add_Click({
        $managed = @()
        foreach ($gr in $g.Rows) {
            $managed += [PSCustomObject]@{ DisplayNamePattern = [string]$gr.Cells["DisplayNamePattern"].Value; ExcludePattern = [string]$gr.Cells["ExcludePattern"].Value }
        }
        $cands = @(Get-InventoryAppCandidates -NasRoot $NasRoot -ManagedRows $managed)
        if ($cands.Count -eq 0) {
            [System.Windows.Forms.MessageBox]::Show("Jaunu programmu nav (vai Logs\Inventory nav datu). Inventaru savac collect-inventory.ps1.", "Info") | Out-Null
            return
        }
        $res = Show-NewAppsPicker -Candidates $cands
        if ($null -eq $res -or $res.Items.Count -eq 0) { return }
        if ($res.Action -eq "ignore") {
            $ignoreFile = Join-Path $NasRoot "Config\apps-ignore.txt"
            try {
                $lines = @($res.Items | ForEach-Object { $_.Name })
                Add-Content -Path $ignoreFile -Value $lines -Encoding UTF8
                [System.Windows.Forms.MessageBox]::Show("Pievienotas ignoresanas sarakstam: " + $lines.Count, "Gatavs") | Out-Null
            } catch {
                [System.Windows.Forms.MessageBox]::Show("Kluda saglabajot ignoresanas sarakstu: $_", "Kluda") | Out-Null
            }
            return
        }
        $existing = @{}
        foreach ($gr in $g.Rows) { $existing[([string]$gr.Cells["Key"].Value).ToLower()] = $true }
        $added = 0
        foreach ($c in $res.Items) {
            $key = ($c.Name -replace '[^A-Za-z0-9]', '')
            if (-not $key -or $existing.ContainsKey($key.ToLower())) { continue }
            $existing[$key.ToLower()] = $true
            $i = $g.Rows.Add(); $r = $g.Rows[$i]
            $r.Cells["Enabled"].Value = $true
            $r.Cells["Key"].Value = $key
            $r.Cells["DisplayName"].Value = $c.Name
            $r.Cells["DisplayNamePattern"].Value = ([System.Management.Automation.WildcardPattern]::Escape($c.Name) + "*")
            $r.Cells["InstallType"].Value = "auto"
            $r.Cells["Mode"].Value = "UpdateOnly"
            $r.Cells["Targets"].Value = (@($c.PCs.Keys | Sort-Object) -join ";")
            $r.DefaultCellStyle.BackColor = $script:ColorNewApp
            $added++
        }
        if ($added -gt 0) { $g.FirstDisplayedScrollingRowIndex = [math]::Max(0, $g.Rows.Count - $added) }
        [System.Windows.Forms.MessageBox]::Show("Pievienotas $added rindas (gaiski dzeltenas). Aizpildiet WingetId (cmd: winget search <nosaukums>), parbaudiet Targets un nospiediet Saglabat. Nepiemerotas rindas dzesiet.", "Gatavs") | Out-Null
    })
    $bSave = New-Btn "Saglabat uz NAS" 1050 170
    $bSave.Anchor = "Bottom,Right"
    $bSave.Font = New-Object System.Drawing.Font($bSave.Font, [System.Drawing.FontStyle]::Bold)
    $bSave.Add_Click({
        $out = @(); $seen = @{}
        foreach ($gr in $g.Rows) {
            $key = ([string]$gr.Cells["Key"].Value).Trim()
            if (-not $key) { continue }
            if ($seen.ContainsKey($key.ToLower())) { [System.Windows.Forms.MessageBox]::Show("Key '$key' atkartojas.", "Kluda") | Out-Null; return }
            $seen[$key.ToLower()] = $true
            $o = [ordered]@{}
            foreach ($c in $script:AppsCols) {
                if ($c -eq "Enabled") { $o[$c] = $(if ($gr.Cells[$c].Value) { "1" } else { "0" }) }
                else { $o[$c] = ([string]$gr.Cells[$c].Value).Trim() }
            }
            if (-not $o["WingetId"]) { [System.Windows.Forms.MessageBox]::Show("'$key': WingetId nav aizpildits.", "Kluda") | Out-Null; return }
            if (-not $o["DisplayNamePattern"]) { [System.Windows.Forms.MessageBox]::Show("'$key': DisplayNamePattern nav aizpildits.", "Kluda") | Out-Null; return }
            if ($o["Targets"] -and -not $o["Targets"].EndsWith(";")) { $o["Targets"] = $o["Targets"] }
            $out += [PSCustomObject]$o
        }
        try {
            Copy-Item $csv ($csv + ".bak-" + (Get-Date -Format "yyyyMMdd-HHmmss")) -Force
            $out | Export-Csv -Path $csv -NoTypeInformation -Encoding UTF8
            [System.Windows.Forms.MessageBox]::Show("Saglabats ($($out.Count) programmas). Rezerves kopija: apps-managed.csv.bak-*`nIzmainas stajas speka nakamaja cikla.`nJaunai programmai downloader.ps1 (admin PC) ir japalaiz, lai Cache/versions.json paradas.", "Gatavs") | Out-Null
        } catch {
            [System.Windows.Forms.MessageBox]::Show("Kluda saglabajot: $_", "Kluda") | Out-Null
        }
    })

    $note = New-Object System.Windows.Forms.Label
    $note.Text = "Targets tuksh = visi datori. Mode: UpdateOnly = tikai atjauno, ja jau uzstadits; Install = uzstada ari jaunu. Atslega (Key) = mape Cache un versions.json. Pec jaunas programmas pievienosanas palaidiet downloader.ps1 uz admin PC."
    $note.Location = New-Object System.Drawing.Point(10, 528); $note.Size = New-Object System.Drawing.Size(1200, 36)
    $note.Anchor = "Bottom,Left"; $note.ForeColor = [System.Drawing.Color]::DimGray
    $win.Controls.Add($note)

    [void]$win.ShowDialog()
}
