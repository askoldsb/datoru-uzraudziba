<#
============================================================
 config-panel.ps1
 Grafisks panelis device-schedule.csv parvaldibai.
 Palaizams administratora datora PEC VAJADZIBAS (nav
 Scheduled Task - tas ir interaktivs rediesanas rikis).

 Lasa/raksta tieso pasu CSV failu, ko lasa client-install.ps1
 (Get-ScheduleDecision funkcija) - tatad sis panelis ir tikai
 erta "seja" pari jau esosajam, vienkarsajam mehanismam. Ja
 panelis kadreiz nedarbotos, CSV joprojam var redigeet manuali
 ar Excel.
============================================================
#>

param(
    [string]$NasRoot = "\\PIUAC_CLOUD\Updates",

    # ESET portala adrese (ESET Business Account / ESET PROTECT Hub), ko atver poga
    # "Atvert ESET portalu". Ierakstiet TIKAI stabilu adresi (https://...) - NEKAD ne
    # lietotajvardu vai paroli un ne garu pieteiksanas saiti ar parametriem (tie ir
    # vienreizeji). Pieteiksanos nodrosina parlukprogrammas saglabata parole.
    [string]$EsetPortalUrl = "https://eba.eset.com/"
)

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$ScheduleFile = Join-Path $NasRoot "Config\device-schedule.csv"
$ValidDays = @("Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun")

# Inventara atskaite ir atsevisks fails (inventory-report.ps1) tajaa pasaa mapee ka sis panelis.
# Ja to neizdodas ieladet, panelis darbojas ka lidz saim.
$script:inventoryReportAvailable = $false
try {
    $inventoryReportFile = Join-Path $PSScriptRoot "inventory-report.ps1"
    if (Test-Path $inventoryReportFile) {
        . $inventoryReportFile
        $script:inventoryReportAvailable = $true
    }
} catch {
    $script:inventoryReportAvailable = $false
}

# Programmu saraksta redaktors un profilu kopiju parvaldiba (atsevisku failu logi, tajaa pasaa mapee).
$script:appsEditorAvailable = $false
try {
    $f = Join-Path $PSScriptRoot "apps-managed-editor.ps1"
    if (Test-Path $f) { . $f; $script:appsEditorAvailable = $true }
} catch { $script:appsEditorAvailable = $false }
$script:backupManagerAvailable = $false
try {
    $f = Join-Path $PSScriptRoot "backup-manager.ps1"
    if (Test-Path $f) { . $f; $script:backupManagerAvailable = $true }
} catch { $script:backupManagerAvailable = $false }

if (-not (Test-Path $NasRoot)) {
    [System.Windows.Forms.MessageBox]::Show("NAS ($NasRoot) nav sasniedzams. Parbaudiet tikla savienojumu.", "Kluda", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error) | Out-Null
    exit 1
}

# ---------- PALIGFUNKCIJAS ----------

function Load-Schedule {
    param([string]$Path)
    if (Test-Path $Path) {
        return @(Import-Csv -Path $Path -Encoding UTF8)
    }
    return @()
}

function Save-Schedule {
    param([array]$Rows, [string]$Path)

    if (Test-Path $Path) {
        Copy-Item -Path $Path -Destination ($Path + ".bak") -Force
    }
    $Rows | Export-Csv -Path $Path -NoTypeInformation -Encoding UTF8
}

function Show-DayPicker {
    param([string]$CurrentValue)

    $dlg = New-Object System.Windows.Forms.Form
    $dlg.AutoScaleMode = [System.Windows.Forms.AutoScaleMode]::None
    $dlg.Text = "Izveleties dienas"
    $dlg.Size = New-Object System.Drawing.Size(240, 300)
    $dlg.StartPosition = "CenterParent"
    $dlg.FormBorderStyle = "FixedDialog"
    $dlg.MaximizeBox = $false
    $dlg.MinimizeBox = $false

    $allCheck = New-Object System.Windows.Forms.CheckBox
    $allCheck.Text = "Visas dienas (All)"
    $allCheck.Location = New-Object System.Drawing.Point(20, 15)
    $allCheck.Width = 190
    $dlg.Controls.Add($allCheck)

    $sep = New-Object System.Windows.Forms.Label
    $sep.BorderStyle = "Fixed3D"
    $sep.Location = New-Object System.Drawing.Point(15, 40)
    $sep.Size = New-Object System.Drawing.Size(200, 2)
    $dlg.Controls.Add($sep)

    $dayChecks = @{}
    $y = 50
    foreach ($d in $ValidDays) {
        $cb = New-Object System.Windows.Forms.CheckBox
        $cb.Text = $d
        $cb.Location = New-Object System.Drawing.Point(30, $y)
        $cb.Width = 150
        $dlg.Controls.Add($cb)
        $dayChecks[$d] = $cb
        $y += 24
    }

    if ($CurrentValue -eq "All" -or [string]::IsNullOrWhiteSpace($CurrentValue)) {
        $allCheck.Checked = $true
    } else {
        $picked = $CurrentValue -split "," | ForEach-Object { $_.Trim() }
        foreach ($d in $picked) {
            if ($dayChecks.ContainsKey($d)) { $dayChecks[$d].Checked = $true }
        }
    }

    foreach ($cb in $dayChecks.Values) { $cb.Enabled = -not $allCheck.Checked }
    $allCheck.Add_CheckedChanged({
        foreach ($cb in $dayChecks.Values) { $cb.Enabled = -not $allCheck.Checked }
    })

    $buttonY = $y + 15

    $okBtn = New-Object System.Windows.Forms.Button
    $okBtn.Text = "OK"
    $okBtn.Location = New-Object System.Drawing.Point(30, $buttonY)
    $okBtn.DialogResult = [System.Windows.Forms.DialogResult]::OK
    $dlg.Controls.Add($okBtn)
    $dlg.AcceptButton = $okBtn

    $cancelBtn = New-Object System.Windows.Forms.Button
    $cancelBtn.Text = "Atcelt"
    $cancelBtn.Location = New-Object System.Drawing.Point(120, $buttonY)
    $cancelBtn.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
    $dlg.Controls.Add($cancelBtn)
    $dlg.CancelButton = $cancelBtn

    if ($dlg.ShowDialog() -ne [System.Windows.Forms.DialogResult]::OK) {
        return $CurrentValue
    }

    if ($allCheck.Checked) { return "All" }

    $selected = $ValidDays | Where-Object { $dayChecks[$_].Checked }
    if (-not $selected -or $selected.Count -eq 0) {
        [System.Windows.Forms.MessageBox]::Show("Nav atlasita neviena diena - iestatu 'All'.", "Piezime") | Out-Null
        return "All"
    }
    return ($selected -join ",")
}

# ---------- ATSKAITES LOGS ----------

function ConvertTo-ReportDate {
    param($Value)

    if ($null -eq $Value) { return $null }
    if ($Value -is [datetime]) { return $Value }

    $text = [string]$Value
    if ([string]::IsNullOrWhiteSpace($text)) { return $null }

    $parsed = [datetime]::MinValue
    $ok = [datetime]::TryParseExact($text, "yyyy-MM-dd HH:mm:ss", [System.Globalization.CultureInfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::None, [ref]$parsed)
    if ($ok) { return $parsed }
    return $null
}

function Get-StatusReportRows {
    # Apvieno CSV sarakstu (kuri datori VAJAG ziniot) ar klientu statusa
    # failiem (Logs\Status\*.json - ko tie PASI raksta) un katram datoram
    # nosaka statusu un krasu. Problemas tiek kartotas pirmas.
    #
    # Krasu nosaka pedeja PILNA atjauninasanas cikla vecums (LastCycle),
    # NEVIS pedeja instalesana: dators, kuram nav ko instalet, ir aktuals,
    # un tam nevajag kluit sarkanam tikai tapec, ka sen nekas nav instalets.
    param([string]$NasRoot, [string]$ScheduleFile)

    # Sliekssni (dienas) - viegli mainami seit:
    $greenDays   = 10   # lidz sim vecumam                 -> zals
    $orangeDays  = 14   # virs $greenDays un lidz sim       -> oranzs (virs tam sarkans)
    $notSeenDays = 1    # tik ilgi dators nav ziniojis      -> statusa piezime "nav ieslegts"

    $now = Get-Date

    $csvByName = @{}
    foreach ($r in @(Load-Schedule -Path $ScheduleFile)) {
        if ($r.ComputerName) { $csvByName[[string]$r.ComputerName] = $r }
    }

    $statusByName = @{}
    $statusDir = Join-Path $NasRoot "Logs\Status"
    if (Test-Path $statusDir) {
        foreach ($f in Get-ChildItem -Path $statusDir -Filter "*.json" -File -ErrorAction SilentlyContinue) {
            try {
                $s = Get-Content -Path $f.FullName -Raw -Encoding UTF8 | ConvertFrom-Json
                if ($s.ComputerName) { $statusByName[[string]$s.ComputerName] = $s }
            } catch {
                # Bojats fails - izlaizam to, nevis apturam visu atskaiti
            }
        }
    }

    $names = @{}
    foreach ($k in $csvByName.Keys) { $names[$k] = $true }
    foreach ($k in $statusByName.Keys) { $names[$k] = $true }

    $colorOk     = [System.Drawing.Color]::FromArgb(223, 240, 216)
    $colorOrange = [System.Drawing.Color]::FromArgb(255, 224, 178)
    $colorErr    = [System.Drawing.Color]::FromArgb(245, 205, 205)
    $colorInfo   = [System.Drawing.Color]::FromArgb(217, 235, 247)
    $colorGray   = [System.Drawing.Color]::FromArgb(238, 238, 238)

    $rows = @()
    foreach ($name in $names.Keys) {
        $csv = $csvByName[$name]
        $st  = $statusByName[$name]

        $lastCheck  = $null
        $lastCycle  = $null
        $lastUpdate = $null
        $result     = ""
        $details    = ""
        $skipReason = ""

        if ($st) {
            $lastCheck  = ConvertTo-ReportDate $st.LastCheck
            $lastCycle  = ConvertTo-ReportDate $st.LastCycle
            $lastUpdate = ConvertTo-ReportDate $st.LastSuccessfulUpdate

            if ($st.LastResult -and ([string]$st.LastResult -ne "Izlaists")) {
                $result = [string]$st.LastResult
                if ($st.Details) { $details = [string]$st.Details }
            }
            if ($st.LastSkipReason) { $skipReason = [string]$st.LastSkipReason }

            # Vecakas versijas statusa faili nesatur LastCycle. Ja zinams, kad
            # pedejo reizi kaut kas tika instalets, tas ir drosa apakseja robeza
            # (cikls bijis vismaz tad).
            if ((-not $lastCycle) -and $lastUpdate) { $lastCycle = $lastUpdate }
        }

        $cycleAge = $null
        if ($lastCycle) { $cycleAge = ($now - $lastCycle).TotalDays }
        $seenAge = $null
        if ($lastCheck) { $seenAge = ($now - $lastCheck).TotalDays }

        $status = ""
        $statusFull = ""
        $severity = 3
        $color = $colorGray
        $overdue = $false

        if (-not $csv) {
            $status = "Nav saraksta"
            $severity = 2
            $color = $colorInfo
        } elseif ([string]$csv.Enabled -ne "Yes") {
            $status = "Atslegts"
            $severity = 3
            $color = $colorGray
        } elseif (-not $st) {
            $status = "Nav datu"
            $severity = 1
            $color = $colorOrange
        } elseif ($result -eq "Dalejs") {
            $status = "Kludas"
            $severity = 0
            $color = $colorErr
        } elseif ($null -eq $cycleAge) {
            $status = "Gaida ciklu"
            $severity = 3
            $color = $colorGray
        } elseif ($cycleAge -le $greenDays) {
            $status = "OK"
            $severity = 4
            $color = $colorOk
        } else {
            $overdue = $true

            # Kapec nav atjauninats: dators sen nav ziniojis (izslegts/aizmidzis/
            # nav tikla), vai ziniojis nesen, bet cikls tomer nenotiek (skat. Piezimes).
            $reason = "cikls nenotiek"
            if (($null -ne $seenAge) -and ($seenAge -gt $notSeenDays)) { $reason = "nav ieslegts" }

            if ($cycleAge -le $orangeDays) {
                $status = "Nokavets"; $statusFull = "Nokavets - $reason"
                $severity = 1
                $color = $colorOrange
            } else {
                $status = "Ilgi nav atj."; $statusFull = "Ilgi nav atjaunots - $reason"
                $severity = 0
                $color = $colorErr
            }
        }

        # Piezimes: ja atjauninasana nokavetas, svarigak ir izlaisanas iemesls
        # (kapec cikls nenotiek), nevis veca cikla detalas.
        $note = ""
        if ($overdue -and ($reason -eq "nav ieslegts")) {
            $note = "Dators nav redzets tikla " + [math]::Floor($seenAge) + " d., tapec nav atjauninats"
            if ($skipReason -ne "") { $note = $note + " (" + $skipReason + ")" }
        } elseif ($overdue -and ($skipReason -ne "")) {
            $note = $skipReason
        } elseif ($details -ne "") {
            $note = $details
        } elseif ($skipReason -ne "") {
            $note = $skipReason
        }

        $days = $null
        if ($null -ne $cycleAge) { $days = [math]::Round($cycleAge, 1) }

        # ESET versija no statusa faila. Ja fails vel nesatur sho lauku (vecaka
        # klienta versija), versija nav zinama; ja lauks ir, bet tukss - ESET nav atrasts.
        $esetText = ""
        $esetKnown = $false
        $esetVer = $null
        if ($st -and $st.PSObject.Properties["EsetVersion"]) {
            $esetKnown = $true
            $esetText = [string]$st.EsetVersion
            $parsedVersion = $null
            if ([version]::TryParse($esetText, [ref]$parsedVersion)) { $esetVer = $parsedVersion }
        }

        # Windows versija no statusa faila (tapat ka ESET). Ja fails vel nesatur sho lauku
        # (vecaka klienta versija), versija nav zinama.
        $winKnown = $false
        $winText = ""
        $winBuild = $null
        if ($st -and $st.PSObject.Properties["WindowsBuild"]) {
            $winKnown = $true
            $winVersionText = ""
            if ($st.PSObject.Properties["WindowsVersion"]) { $winVersionText = [string]$st.WindowsVersion }
            $winBuildText = [string]$st.WindowsBuild
            $winText = $winVersionText
            if ($winBuildText -ne "") { $winText = ($winVersionText + " (" + $winBuildText + ")").Trim() }
            $parsedBuild = $null
            if ([version]::TryParse($winBuildText, [ref]$parsedBuild)) { $winBuild = $parsedBuild }
        }

        # Office produkts un versija no statusa faila - TIKAI atspogulojam (bez salidzinasanas
        # un krasas), jo dazi datori drikst lietot dazadus Office produktus un versijas.
        $officeText = ""
        if ($st -and $st.PSObject.Properties["OfficeVersion"]) {
            $officeProductText = ""
            if ($st.PSObject.Properties["OfficeProduct"]) { $officeProductText = [string]$st.OfficeProduct }
            $officeText = ($officeProductText + " " + [string]$st.OfficeVersion).Trim()
        }

        $rows += [PSCustomObject]@{
            Severity    = $severity
            Status      = $status
            StatusFull  = $(if ($statusFull -ne "") { $statusFull } else { $status })
            Name        = $name
            LastCheck   = $lastCheck
            LastCycle   = $lastCycle
            LastUpdate  = $lastUpdate
            Days        = $days
            Result      = $result
            Note        = $note
            Color       = $color
            EsetKnown   = $esetKnown
            EsetText    = $esetText
            EsetVer     = $esetVer
            EsetStatus  = ""
            EsetColor   = $null
            WinKnown    = $winKnown
            WinText     = $winText
            WinBuild    = $winBuild
            WinColor    = $null
            OfficeText  = $officeText
        }
    }

    # "Jaunaka" ESET versija = AUGSTAKA versija starp visiem datoriem, kas zino.
    # ESET pats neizplata jauno versiju visiem uzreiz (pakapeniska ieviesana), tapec
    # vecaka versija uzreiz pec jaunas izlaiduma NAV problema - problema ir, ja tas
    # velaks (piem. nedelam) neizlidzinas. Tas javersa pasam pec datora vecuma.
    $refVersion = $null
    foreach ($r in $rows) {
        if ($r.EsetVer) {
            if ((-not $refVersion) -or ($r.EsetVer -gt $refVersion)) { $refVersion = $r.EsetVer }
        }
    }

    foreach ($r in $rows) {
        if (-not $r.EsetKnown) {
            $r.EsetStatus = ""
        } elseif ($r.EsetText -eq "") {
            $r.EsetStatus = "Nav ESET"
            $r.EsetColor = $colorGray
        } elseif (-not $r.EsetVer) {
            $r.EsetStatus = "Versija nesalasama"
            $r.EsetColor = $colorGray
        } elseif ($r.EsetVer -ge $refVersion) {
            $r.EsetStatus = "Jaunaka versija"
            $r.EsetColor = $colorOk
        } else {
            $r.EsetStatus = "Prasas atjaunot (jaunaka: $refVersion)"
            $r.EsetColor = $colorOrange
        }
    }

    # Windows: atskaites punkts = VISBIEZAKAIS laidiens (build numurs, piem. 26200 = 25H2) parka,
    # un taja laidiena visbiezakais labojumu numurs. Zals = norma; gaiski zals = jaunaks laidiens
    # neka vairakumam; oranzs = tas pats laidiens, bet nav jaunako labojumu; sarkanigs = novecojis
    # laidiens (piem. 23H2); peleks = versija nav nolasama.
    $refMajor = $null; $refMinor = $null
    $mg = @($rows | Where-Object { $_.WinBuild } | Group-Object { $_.WinBuild.Major })
    if ($mg.Count -gt 0) {
        $best = ($mg | Measure-Object -Property Count -Maximum).Maximum
        foreach ($g in ($mg | Where-Object { $_.Count -eq $best })) {
            $m = [int]$g.Name
            if (($null -eq $refMajor) -or ($m -gt $refMajor)) { $refMajor = $m }
        }
        $ug = @($rows | Where-Object { $_.WinBuild -and ($_.WinBuild.Major -eq $refMajor) } | Group-Object { $_.WinBuild.Minor })
        $bestU = ($ug | Measure-Object -Property Count -Maximum).Maximum
        foreach ($g in ($ug | Where-Object { $_.Count -eq $bestU })) {
            $u = [int]$g.Name
            if (($null -eq $refMinor) -or ($u -gt $refMinor)) { $refMinor = $u }
        }
    }
    $colorAhead = [System.Drawing.Color]::FromArgb(165, 214, 167)
    $colorRedish = [System.Drawing.Color]::FromArgb(255, 171, 145)
    foreach ($r in $rows) {
        if (-not $r.WinKnown) {
            $r.WinColor = $null
        } elseif ((-not $r.WinBuild) -or ($null -eq $refMajor)) {
            $r.WinColor = $colorGray
        } elseif ($r.WinBuild.Major -lt $refMajor) {
            $r.WinColor = $colorRedish
            $r.WinText = $r.WinText + " - novecojis laidiens"
        } elseif ($r.WinBuild.Major -gt $refMajor) {
            $r.WinColor = $colorAhead
            $r.WinText = $r.WinText + " - jaunaks"
        } elseif ($r.WinBuild.Minor -lt $refMinor) {
            $r.WinColor = $colorOrange
            $r.WinText = $r.WinText + " - atpaliek"
        } else {
            $r.WinColor = $colorOk
        }
    }

    return @($rows | Sort-Object Severity, Name)
}

function New-ReportColumn {
    param([string]$Name, [string]$Header, [int]$Width)

    $c = New-Object System.Windows.Forms.DataGridViewTextBoxColumn
    $c.Name = $Name
    $c.HeaderText = $Header
    $c.Width = $Width
    return $c
}

function Update-ReportGrid {
    # Atsaucas uz $script: mainigajiem, jo so funkciju izsauc pogu notikumu apstradataji
    $grid = $script:reportGrid
    $rows = @(Get-StatusReportRows -NasRoot $script:reportNasRoot -ScheduleFile $script:reportScheduleFile)

    $grid.Rows.Clear()
    $countOk = 0
    $countWarn = 0
    $countErr = 0
    $countOther = 0
    $countEsetOld = 0
    $countWinOld = 0

    foreach ($r in $rows) {
        $i = $grid.Rows.Add()
        $gr = $grid.Rows[$i]
        $gr.Cells["Status"].Value = $r.Status
        $gr.Cells["Status"].ToolTipText = $r.StatusFull
        $gr.Cells["Name"].Value = $r.Name
        $gr.Cells["LastCheck"].Value = $r.LastCheck
        $gr.Cells["LastCycle"].Value = $r.LastCycle
        $gr.Cells["Days"].Value = $r.Days
        $gr.Cells["LastUpdate"].Value = $r.LastUpdate
        $gr.Cells["Result"].Value = $r.Result
        $gr.Cells["EsetVer"].Value = $r.EsetText
        $gr.Cells["EsetStatus"].Value = $r.EsetStatus
        $gr.Cells["Windows"].Value = $r.WinText
        $gr.Cells["Office"].Value = $r.OfficeText
        $gr.Cells["Note"].Value = $r.Note
        $gr.Cells["Note"].ToolTipText = $r.Note
        $gr.DefaultCellStyle.BackColor = $r.Color

        # ESET statusa sunai sava krasa (rindas krasu nemainam - tas attiecas uz atjauninasanu ciklu)
        if ($r.EsetColor) {
            $gr.Cells["EsetStatus"].Style.BackColor = $r.EsetColor
        }
        if ($r.EsetStatus -like "Prasas atjaunot*") { $countEsetOld++ }

        # Windows versijas sunai sava krasa (rindas krasu nemainam)
        if ($r.WinColor) {
            $gr.Cells["Windows"].Style.BackColor = $r.WinColor
        }
        if (($r.WinText -like "*- atpaliek") -or ($r.WinText -like "*- novecojis laidiens")) { $countWinOld++ }

        switch ($r.Severity) {
            0 { $countErr++ }
            1 { $countWarn++ }
            4 { $countOk++ }
            default { $countOther++ }
        }
    }

    $readTime = (Get-Date).ToString("HH:mm:ss")
    $script:reportSummary.Text = "Kopa: $($rows.Count)     OK: $countOk     Uzmanibu: $countWarn     Problemas: $countErr     Citi: $countOther     ESET jaatjauno: $countEsetOld     Windows atpaliek: $countWinOld     (dati nolasiti $readTime)"
}

function Show-StatusReportWindow {
    param([string]$NasRoot, [string]$ScheduleFile)

    $win = New-Object System.Windows.Forms.Form
    $win.AutoScaleMode = [System.Windows.Forms.AutoScaleMode]::None
    $win.Text = "Atjauninasanas atskaite - $NasRoot"
    $win.Size = New-Object System.Drawing.Size(1500, 620)
    $win.StartPosition = "CenterParent"
    $win.MinimumSize = New-Object System.Drawing.Size(800, 400)

    $summary = New-Object System.Windows.Forms.Label
    $summary.Location = New-Object System.Drawing.Point(10, 10)
    $summary.Size = New-Object System.Drawing.Size(1450, 24)
    $summary.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Left -bor [System.Windows.Forms.AnchorStyles]::Right
    $summary.Font = New-Object System.Drawing.Font($summary.Font, [System.Drawing.FontStyle]::Bold)
    $win.Controls.Add($summary)

    $rg = New-Object System.Windows.Forms.DataGridView
    $rg.Location = New-Object System.Drawing.Point(10, 40)
    $rg.Size = New-Object System.Drawing.Size(1465, 480)
    $rg.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Bottom -bor [System.Windows.Forms.AnchorStyles]::Left -bor [System.Windows.Forms.AnchorStyles]::Right
    $rg.ReadOnly = $true
    $rg.AllowUserToAddRows = $false
    $rg.AllowUserToDeleteRows = $false
    $rg.RowHeadersVisible = $false
    $rg.MultiSelect = $false
    $rg.SelectionMode = [System.Windows.Forms.DataGridViewSelectionMode]::FullRowSelect

    $cStatus = New-ReportColumn "Status" "Statuss" 85
    $cName   = New-ReportColumn "Name" "Dators" 125
    $cCheck  = New-ReportColumn "LastCheck" "Pedeja redzets (ieslegts)" 160
    $cCycle  = New-ReportColumn "LastCycle" "Pedejais cikls" 120
    $cDays   = New-ReportColumn "Days" "Dienas kops cikla" 100
    $cUpdate = New-ReportColumn "LastUpdate" "Pedeja instalesana" 120
    $cResult = New-ReportColumn "Result" "Rezultats" 80
    $cEsetV  = New-ReportColumn "EsetVer" "ESET versija" 105
    $cEsetS  = New-ReportColumn "EsetStatus" "ESET statuss" 230
    $cWin    = New-ReportColumn "Windows" "Windows" 190
    $cOffice = New-ReportColumn "Office" "Office" 200
    $cNote   = New-ReportColumn "Note" "Piezimes" 200
    $cNote.AutoSizeMode = [System.Windows.Forms.DataGridViewAutoSizeColumnMode]::Fill

    # Datumi tiek glabati ka REALI datumi (nevis teksts), tapec kartosana
    # pec kolonnas ir hronologiska; formats - Latvijas standarts dd.mm.gggg.
    $dateFormat = "dd.MM.yyyy HH:mm"
    $cCheck.DefaultCellStyle.Format = $dateFormat
    $cCycle.DefaultCellStyle.Format = $dateFormat
    $cUpdate.DefaultCellStyle.Format = $dateFormat
    $cDays.DefaultCellStyle.Format = "0.0"

    $cCheck.ToolTipText = "Pedeja reize, kad dators ziniojis NAS (parasti: bija ieslegts un tikla)."
    $cCycle.ToolTipText = "Pedejais pilns atjauninasanas cikls. Krasa atkarigs no sa cikla vecuma."
    $cDays.ToolTipText = "Cik dienu pagajusi kops pedeja pilna cikla: lidz 7 zals, 7-10 oranzs, 10+ sarkans."
    $cUpdate.ToolTipText = "Pedeja reize, kad kaut kas tika instalets (var but sena, ja datoram nav ko atjauninat)."

    $cEsetV.ToolTipText = "Pedeja zinama ESET antivirusa versija no sa datora."
    $cEsetS.ToolTipText = "Salidzina ar AUGSTAKO versiju starp visiem datoriem. ESET jauno versiju izplata pakapeniski, tapec vecaka versija uzreiz pec jaunas izlaiduma ir normala."
    $cOffice.ToolTipText = "Uzstadits Office produkts un versija no sa datora. Tikai atspogulojums, bez salidzinasanas (dazi datori lieto dazadus Office produktus). Tuksa sunu nozime, ka Office nav atrasts vai dators vel nav ziniojis ar jauno klienta versiju."
    $cWin.ToolTipText = "Windows versija un build numurs no sa datora. Salidzina ar VISBIEZAKO versiju parka: zals = norma, piesatinats zals = jaunaks laidiens neka vairakumam, oranzs = nav jaunako labojumu, sarkanigs = novecojis laidiens (piem. 23H2). Tuksa sunu nozime, ka dators vel nav ziniojis ar jauno klienta versiju."

    $reportColumns = [System.Windows.Forms.DataGridViewColumn[]]@($cStatus, $cName, $cCheck, $cCycle, $cDays, $cUpdate, $cResult, $cEsetV, $cEsetS, $cWin, $cOffice, $cNote)
    $rg.Columns.AddRange($reportColumns)
    $win.Controls.Add($rg)

    $btnRefresh = New-Object System.Windows.Forms.Button
    $btnRefresh.Text = "Atjaunot"
    $btnRefresh.Location = New-Object System.Drawing.Point(10, 530)
    $btnRefresh.Size = New-Object System.Drawing.Size(160, 32)
    $btnRefresh.Anchor = [System.Windows.Forms.AnchorStyles]::Bottom -bor [System.Windows.Forms.AnchorStyles]::Left
    $btnRefresh.Add_Click({ Update-ReportGrid })
    $win.Controls.Add($btnRefresh)

    $btnClose = New-Object System.Windows.Forms.Button
    $btnClose.Text = "Aizvert"
    $btnClose.Location = New-Object System.Drawing.Point(1315, 530)
    $btnClose.Size = New-Object System.Drawing.Size(160, 32)
    $btnClose.Anchor = [System.Windows.Forms.AnchorStyles]::Bottom -bor [System.Windows.Forms.AnchorStyles]::Right
    $btnClose.Add_Click({ $script:reportWindow.Close() })
    $win.Controls.Add($btnClose)

    $script:reportWindow = $win
    $script:reportGrid = $rg
    $script:reportSummary = $summary
    $script:reportNasRoot = $NasRoot
    $script:reportScheduleFile = $ScheduleFile

    Update-ReportGrid
    [void]$win.ShowDialog()
}

# ---------- SARAKSTA IMPORTS (no Excel starpliktuves) ----------

function Show-ImportDialog {
    # Ielimejiet datoru nosaukumus no Excel (viens dators katra rinda). Ja ir otra kolonna,
    # ta tiek lietota ka grupa. Visai partijai kopigie iestatijumi tiek noraditi seit.
    # Importetie datori tiek pievienoti NEAKTIVI; saglabasana notiek ar "Saglabat uz NAS".

    $defaultGroup = ""
    if ($grid.Rows.Count -gt 0) {
        $defaultGroup = [string]$grid.Rows[$grid.Rows.Count - 1].Cells["Group"].Value
    }

    $dlg = New-Object System.Windows.Forms.Form
    $dlg.AutoScaleMode = [System.Windows.Forms.AutoScaleMode]::None
    $dlg.Text = "Importet datoru sarakstu"
    $dlg.ClientSize = New-Object System.Drawing.Size(600, 520)
    $dlg.StartPosition = "CenterParent"
    $dlg.FormBorderStyle = "FixedDialog"
    $dlg.MaximizeBox = $false
    $dlg.MinimizeBox = $false

    $lblIntro = New-Object System.Windows.Forms.Label
    $lblIntro.Text = "Ielimejiet datoru nosaukumus no Excel (viens dators katra rinda). Ja ir otra kolonna, ta tiks lietota ka grupa."
    $lblIntro.Location = New-Object System.Drawing.Point(20, 15)
    $lblIntro.Size = New-Object System.Drawing.Size(560, 38)
    $dlg.Controls.Add($lblIntro)

    $tbList = New-Object System.Windows.Forms.TextBox
    $tbList.Multiline = $true
    $tbList.AcceptsReturn = $true
    $tbList.ScrollBars = [System.Windows.Forms.ScrollBars]::Vertical
    $tbList.Font = New-Object System.Drawing.Font("Consolas", 9)
    $tbList.Location = New-Object System.Drawing.Point(20, 58)
    $tbList.Size = New-Object System.Drawing.Size(560, 170)
    $dlg.Controls.Add($tbList)

    $lblGroup = New-Object System.Windows.Forms.Label
    $lblGroup.Text = "Noklusejuma grupa:"
    $lblGroup.Location = New-Object System.Drawing.Point(20, 247)
    $lblGroup.Size = New-Object System.Drawing.Size(170, 20)
    $dlg.Controls.Add($lblGroup)
    $tbGroup = New-Object System.Windows.Forms.TextBox
    $tbGroup.Text = $defaultGroup
    $tbGroup.Location = New-Object System.Drawing.Point(200, 244)
    $tbGroup.Size = New-Object System.Drawing.Size(380, 24)
    $dlg.Controls.Add($tbGroup)

    $lblDays = New-Object System.Windows.Forms.Label
    $lblDays.Text = "Dienas (All vai Mon,Tue,...):"
    $lblDays.Location = New-Object System.Drawing.Point(20, 282)
    $lblDays.Size = New-Object System.Drawing.Size(175, 20)
    $dlg.Controls.Add($lblDays)
    $tbDays = New-Object System.Windows.Forms.TextBox
    $tbDays.Text = "Mon,Tue,Wed,Thu,Fri"
    $tbDays.Location = New-Object System.Drawing.Point(200, 279)
    $tbDays.Size = New-Object System.Drawing.Size(380, 24)
    $dlg.Controls.Add($tbDays)

    $lblTime = New-Object System.Windows.Forms.Label
    $lblTime.Text = "Laiks (HH:mm, var atstat tuksu):"
    $lblTime.Location = New-Object System.Drawing.Point(20, 317)
    $lblTime.Size = New-Object System.Drawing.Size(175, 20)
    $dlg.Controls.Add($lblTime)
    $tbTime = New-Object System.Windows.Forms.TextBox
    $tbTime.Text = ""
    $tbTime.Location = New-Object System.Drawing.Point(200, 314)
    $tbTime.Size = New-Object System.Drawing.Size(120, 24)
    $dlg.Controls.Add($tbTime)

    $chkWU = New-Object System.Windows.Forms.CheckBox
    $chkWU.Text = "Windows Update"
    $chkWU.Checked = $true
    $chkWU.Location = New-Object System.Drawing.Point(20, 355)
    $chkWU.Size = New-Object System.Drawing.Size(170, 24)
    $dlg.Controls.Add($chkWU)

    $chkApps = New-Object System.Windows.Forms.CheckBox
    $chkApps.Text = "Programmas"
    $chkApps.Checked = $true
    $chkApps.Location = New-Object System.Drawing.Point(200, 355)
    $chkApps.Size = New-Object System.Drawing.Size(170, 24)
    $dlg.Controls.Add($chkApps)

    $chkNotify = New-Object System.Windows.Forms.CheckBox
    $chkNotify.Text = "Bridinat"
    $chkNotify.Checked = $false
    $chkNotify.Location = New-Object System.Drawing.Point(380, 355)
    $chkNotify.Size = New-Object System.Drawing.Size(170, 24)
    $dlg.Controls.Add($chkNotify)

    $chkShutdown = New-Object System.Windows.Forms.CheckBox
    $chkShutdown.Text = "Izslegt pec"
    $chkShutdown.Checked = $false
    $chkShutdown.Location = New-Object System.Drawing.Point(20, 385)
    $chkShutdown.Size = New-Object System.Drawing.Size(170, 24)
    $dlg.Controls.Add($chkShutdown)

    $chkTV = New-Object System.Windows.Forms.CheckBox
    $chkTV.Text = "TeamViewer"
    $chkTV.Checked = $false
    $chkTV.Location = New-Object System.Drawing.Point(200, 385)
    $chkTV.Size = New-Object System.Drawing.Size(170, 24)
    $dlg.Controls.Add($chkTV)

    $lblNote = New-Object System.Windows.Forms.Label
    $lblNote.Text = "Importetie datori tiks pievienoti NEAKTIVI (Aktivs nav ieliekseets), lai nekas nesaktos, kamer tos neieslegsiet. Pec importa parskatiet tabulu un nospiediet 'Saglabat uz NAS'."
    $lblNote.Location = New-Object System.Drawing.Point(20, 425)
    $lblNote.Size = New-Object System.Drawing.Size(560, 40)
    $dlg.Controls.Add($lblNote)

    $okButton = New-Object System.Windows.Forms.Button
    $okButton.Text = "Importet"
    $okButton.Location = New-Object System.Drawing.Point(360, 475)
    $okButton.Size = New-Object System.Drawing.Size(100, 32)
    $okButton.DialogResult = [System.Windows.Forms.DialogResult]::OK
    $dlg.Controls.Add($okButton)

    $cancelButton = New-Object System.Windows.Forms.Button
    $cancelButton.Text = "Atcelt"
    $cancelButton.Location = New-Object System.Drawing.Point(480, 475)
    $cancelButton.Size = New-Object System.Drawing.Size(100, 32)
    $cancelButton.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
    $dlg.Controls.Add($cancelButton)
    $dlg.CancelButton = $cancelButton

    $accepted = $false
    $listText = ""
    $groupText = ""
    $daysText = ""
    $timeText = ""
    $valWU = $true
    $valApps = $true
    $valNotify = $false
    $valShutdown = $false
    $valTV = $false

    try {
        while ($true) {
            $answer = $dlg.ShowDialog()
            if ($answer -ne [System.Windows.Forms.DialogResult]::OK) { break }

            $daysCandidate = $tbDays.Text.Trim()
            $timeCandidate = $tbTime.Text.Trim()

            if ($daysCandidate -notmatch '^(All|(Mon|Tue|Wed|Thu|Fri|Sat|Sun)(,(Mon|Tue|Wed|Thu|Fri|Sat|Sun))*)$') {
                [System.Windows.Forms.MessageBox]::Show("Dienas jaraksta ka All vai ka saraksts, piem. Mon,Tue,Wed,Thu,Fri", "Kluda") | Out-Null
                continue
            }
            if (($timeCandidate -ne "") -and ($timeCandidate -notmatch '^([01]\d|2[0-3]):[0-5]\d$')) {
                [System.Windows.Forms.MessageBox]::Show("Laiks jaraksta formata HH:mm (piem. 12:00) vai jaatstaj tuks.", "Kluda") | Out-Null
                continue
            }

            $listText = $tbList.Text
            $groupText = $tbGroup.Text.Trim()
            $daysText = $daysCandidate
            $timeText = $timeCandidate
            $valWU = $chkWU.Checked
            $valApps = $chkApps.Checked
            $valNotify = $chkNotify.Checked
            $valShutdown = $chkShutdown.Checked
            $valTV = $chkTV.Checked
            $accepted = $true
            break
        }
    } finally {
        $dlg.Dispose()
    }

    if (-not $accepted) { return }

    # esoso datoru nosaukumi (lai nepievienotu dublikatus)
    $existing = @{}
    foreach ($r in $grid.Rows) {
        $n = [string]$r.Cells["ComputerName"].Value
        if ($n) { $existing[$n.Trim().ToUpper()] = $true }
    }

    $added = 0
    $dupes = @()
    $invalid = @()
    $seen = @{}
    $firstLine = $true

    foreach ($rawLine in ($listText -split '\r?\n')) {
        $line = $rawLine.Trim()
        if ($line -eq "") { continue }

        $cells = $line -split '[\t;]'
        $name = $cells[0].Trim()

        # pirmo rindu atstajam, ja tas ir virsraksts (piem. "Dators")
        if ($firstLine) {
            $firstLine = $false
            if ($name -match '^(dators|computername|datora nosaukums|name)$') { continue }
        }
        if ($name -eq "") { continue }

        if ($name -notmatch '^[A-Za-z0-9-]{1,15}$') {
            $invalid += $name
            continue
        }

        $key = $name.ToUpper()
        if ($existing.ContainsKey($key) -or $seen.ContainsKey($key)) {
            $dupes += $name
            continue
        }
        $seen[$key] = $true

        $group = $groupText
        if (($cells.Count -ge 2) -and ($cells[1].Trim() -ne "")) { $group = $cells[1].Trim() }

        $i = $grid.Rows.Add()
        $gr = $grid.Rows[$i]
        $gr.Cells["ComputerName"].Value = $name
        $gr.Cells["Group"].Value = $group
        $gr.Cells["UpdateDays"].Value = $daysText
        $gr.Cells["UpdateTime"].Value = $timeText
        $gr.Cells["ShowNotification"].Value = $valNotify
        $gr.Cells["ShutdownAfter"].Value = $valShutdown
        $gr.Cells["WindowsUpdate"].Value = $valWU
        $gr.Cells["ThirdPartyApps"].Value = $valApps
        $gr.Cells["TeamViewer"].Value = $valTV
        $gr.Cells["Enabled"].Value = $false
        $added++
    }

    $nl = [Environment]::NewLine
    $msg = "Pievienoti: $added dat. (neaktivi)."
    if ($dupes.Count -gt 0) {
        $msg = $msg + $nl + $nl + "Izlaisti (jau sarakstaa vai atkartoti): " + $dupes.Count + $nl + (($dupes | Select-Object -First 10) -join ", ")
    }
    if ($invalid.Count -gt 0) {
        $msg = $msg + $nl + $nl + "Nederigi nosaukumi (atlauti burti, cipari un defise, max 15 rakstzimes): " + $invalid.Count + $nl + (($invalid | Select-Object -First 10) -join ", ")
    }
    if ($added -gt 0) {
        $msg = $msg + $nl + $nl + "Nospiediet 'Saglabat uz NAS', lai saglabatu."
    }
    [System.Windows.Forms.MessageBox]::Show($msg, "Importa rezultats") | Out-Null

    if ($added -gt 0) {
        try { $grid.FirstDisplayedScrollingRowIndex = $grid.Rows.Count - 1 } catch { }
    }
}

# ---------- GALVENAIS LOGS ----------

$form = New-Object System.Windows.Forms.Form
$form.AutoScaleMode = [System.Windows.Forms.AutoScaleMode]::None
$form.Text = "Atjauninasanas grafika parvaldiba - $NasRoot"
$form.Size = New-Object System.Drawing.Size(1170, 615)
$form.StartPosition = "CenterScreen"
$form.MinimumSize = New-Object System.Drawing.Size(700, 400)

$grid = New-Object System.Windows.Forms.DataGridView
$grid.Location = New-Object System.Drawing.Point(10, 10)
$grid.Size = New-Object System.Drawing.Size(1135, 390)
$grid.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Bottom -bor [System.Windows.Forms.AnchorStyles]::Left -bor [System.Windows.Forms.AnchorStyles]::Right
$grid.AllowUserToAddRows = $false
$grid.AllowUserToDeleteRows = $false
$grid.RowHeadersVisible = $false
$grid.MultiSelect = $false
$grid.SelectionMode = [System.Windows.Forms.DataGridViewSelectionMode]::FullRowSelect

function New-TextColumn($name, $header, $width) {
    $c = New-Object System.Windows.Forms.DataGridViewTextBoxColumn
    $c.Name = $name
    $c.HeaderText = $header
    $c.Width = $width
    return $c
}
function New-CheckColumn($name, $header, $width) {
    $c = New-Object System.Windows.Forms.DataGridViewCheckBoxColumn
    $c.Name = $name
    $c.HeaderText = $header
    $c.Width = $width
    return $c
}

$colComputer = New-TextColumn "ComputerName" "Dators" 170
$colGroup    = New-TextColumn "Group" "Grupa" 110
$colDays     = New-TextColumn "UpdateDays" "Dienas" 150
$colDays.ReadOnly = $true

$colDaysBtn = New-Object System.Windows.Forms.DataGridViewButtonColumn
$colDaysBtn.Name = "DaysButton"
$colDaysBtn.HeaderText = ""
$colDaysBtn.Text = "Mainit..."
$colDaysBtn.UseColumnTextForButtonValue = $true
$colDaysBtn.Width = 80

$colTime = New-TextColumn "UpdateTime" "Laiks (HH:mm)" 100

$colNotify   = New-CheckColumn "ShowNotification" "Bridinat" 75
$colShutdown = New-CheckColumn "ShutdownAfter" "Izslegt pec" 85
$colWU       = New-CheckColumn "WindowsUpdate" "Windows Update" 110
$colTPA      = New-CheckColumn "ThirdPartyApps" "Programmas" 100
$colTV       = New-CheckColumn "TeamViewer" "TeamViewer" 90
$colEnabled  = New-CheckColumn "Enabled" "Aktivs" 70

$columnsToAdd = [System.Windows.Forms.DataGridViewColumn[]]@($colComputer, $colGroup, $colDays, $colDaysBtn, $colTime, $colNotify, $colShutdown, $colWU, $colTPA, $colTV, $colEnabled)
$grid.Columns.AddRange($columnsToAdd)
$form.Controls.Add($grid)

# Checkbox vertibas apstiprinat uzreiz (WinForms DataGridView standarta risinajums)
$grid.Add_CurrentCellDirtyStateChanged({
    if ($grid.IsCurrentCellDirty) {
        $grid.CommitEdit([System.Windows.Forms.DataGridViewDataErrorContexts]::Commit)
    }
})

$grid.Add_CellContentClick({
    param($s, $e)
    if ($e.RowIndex -lt 0) { return }
    if ($grid.Columns[$e.ColumnIndex].Name -eq "DaysButton") {
        $cur = $grid.Rows[$e.RowIndex].Cells["UpdateDays"].Value
        $new = Show-DayPicker -CurrentValue $cur
        $grid.Rows[$e.RowIndex].Cells["UpdateDays"].Value = $new
    }
})

function Refresh-Grid {
    $grid.Rows.Clear()
    foreach ($row in $script:scheduleRows) {
        $i = $grid.Rows.Add()
        $gr = $grid.Rows[$i]
        $gr.Cells["ComputerName"].Value = $row.ComputerName
        $gr.Cells["Group"].Value = $row.Group
        $gr.Cells["UpdateDays"].Value = $row.UpdateDays
        $gr.Cells["UpdateTime"].Value = $row.UpdateTime
        $gr.Cells["ShowNotification"].Value = ($row.ShowNotification -eq "Yes")
        $gr.Cells["ShutdownAfter"].Value = ($row.ShutdownAfter -eq "Yes")
        $gr.Cells["WindowsUpdate"].Value = ($row.WindowsUpdate -eq "Yes")
        $gr.Cells["ThirdPartyApps"].Value = ($row.ThirdPartyApps -eq "Yes")
        $gr.Cells["TeamViewer"].Value = ($row.TeamViewer -ne "No")
        $gr.Cells["Enabled"].Value = ($row.Enabled -eq "Yes")
    }
}

$script:scheduleRows = @(Load-Schedule -Path $ScheduleFile)
Refresh-Grid

# ---------- POGAS ----------

$btnAdd = New-Object System.Windows.Forms.Button
$btnAdd.Text = "Pievienot datoru"
$btnAdd.Location = New-Object System.Drawing.Point(10, 410)
$btnAdd.Size = New-Object System.Drawing.Size(150, 32)
$btnAdd.Anchor = [System.Windows.Forms.AnchorStyles]::Bottom -bor [System.Windows.Forms.AnchorStyles]::Left
$btnAdd.Add_Click({
    $i = $grid.Rows.Add()
    $gr = $grid.Rows[$i]
    $gr.Cells["ComputerName"].Value = "JAUNS-DATORS"
    $gr.Cells["Group"].Value = ""
    $gr.Cells["UpdateDays"].Value = "All"
    $gr.Cells["UpdateTime"].Value = ""
    $gr.Cells["ShowNotification"].Value = $false
    $gr.Cells["ShutdownAfter"].Value = $false
    $gr.Cells["WindowsUpdate"].Value = $false
    $gr.Cells["ThirdPartyApps"].Value = $true
    $gr.Cells["TeamViewer"].Value = $true
    $gr.Cells["Enabled"].Value = $false
    $grid.CurrentCell = $gr.Cells["ComputerName"]
    $grid.BeginEdit($true)
})
$form.Controls.Add($btnAdd)

$btnDelete = New-Object System.Windows.Forms.Button
$btnDelete.Text = "Dzest atlasito"
$btnDelete.Location = New-Object System.Drawing.Point(170, 410)
$btnDelete.Size = New-Object System.Drawing.Size(150, 32)
$btnDelete.Anchor = [System.Windows.Forms.AnchorStyles]::Bottom -bor [System.Windows.Forms.AnchorStyles]::Left
$btnDelete.Add_Click({
    if ($grid.SelectedRows.Count -eq 0) {
        [System.Windows.Forms.MessageBox]::Show("Vispirms atlasiet rindu (klikskis uz rindas).", "Informacija") | Out-Null
        return
    }
    $name = $grid.SelectedRows[0].Cells["ComputerName"].Value
    $confirm = [System.Windows.Forms.MessageBox]::Show(
        "Vai tiesam dzest datoru '$name' no saraksta? (Lai tikai izslegtu, bez dzesanas, vieglak noemt kekseiti 'Aktivs'.)",
        "Apstiprinat dzesanu",
        [System.Windows.Forms.MessageBoxButtons]::YesNo,
        [System.Windows.Forms.MessageBoxIcon]::Warning
    )
    if ($confirm -eq [System.Windows.Forms.DialogResult]::Yes) {
        $grid.Rows.Remove($grid.SelectedRows[0])
    }
})
$form.Controls.Add($btnDelete)

$btnReload = New-Object System.Windows.Forms.Button
$btnReload.Text = "Parladet no NAS"
$btnReload.Location = New-Object System.Drawing.Point(330, 410)
$btnReload.Size = New-Object System.Drawing.Size(150, 32)
$btnReload.Anchor = [System.Windows.Forms.AnchorStyles]::Bottom -bor [System.Windows.Forms.AnchorStyles]::Left
$btnReload.Add_Click({
    $confirm = [System.Windows.Forms.MessageBox]::Show(
        "Nesaglabatas izmainas tiks zaudetas. Turpinat?",
        "Parladet",
        [System.Windows.Forms.MessageBoxButtons]::YesNo,
        [System.Windows.Forms.MessageBoxIcon]::Question
    )
    if ($confirm -eq [System.Windows.Forms.DialogResult]::Yes) {
        $script:scheduleRows = @(Load-Schedule -Path $ScheduleFile)
        Refresh-Grid
    }
})
$form.Controls.Add($btnReload)

$btnReport = New-Object System.Windows.Forms.Button
$btnReport.Text = "Paradit atskaiti"
$btnReport.Location = New-Object System.Drawing.Point(490, 410)
$btnReport.Size = New-Object System.Drawing.Size(150, 32)
$btnReport.Anchor = [System.Windows.Forms.AnchorStyles]::Bottom -bor [System.Windows.Forms.AnchorStyles]::Left
$btnReport.Add_Click({
    Show-StatusReportWindow -NasRoot $NasRoot -ScheduleFile $ScheduleFile
})
$form.Controls.Add($btnReport)

$btnPortal = New-Object System.Windows.Forms.Button
$btnPortal.Text = "Atvert ESET portalu"
$btnPortal.Location = New-Object System.Drawing.Point(650, 410)
$btnPortal.Size = New-Object System.Drawing.Size(150, 32)
$btnPortal.Anchor = [System.Windows.Forms.AnchorStyles]::Bottom -bor [System.Windows.Forms.AnchorStyles]::Left
$btnPortal.Add_Click({
    if ([string]::IsNullOrWhiteSpace($EsetPortalUrl)) {
        [System.Windows.Forms.MessageBox]::Show("ESET portala adrese nav iestatita. Atveriet config-panel.ps1 un ierakstiet adresi (https://...) parametra EsetPortalUrl noklusejuma vertiba faila sakuma.", "Informacija") | Out-Null
        return
    }
    if ($EsetPortalUrl -notmatch '^https://') {
        [System.Windows.Forms.MessageBox]::Show("ESET portala adresei jasakas ar https://", "Kluda") | Out-Null
        return
    }
    try {
        Start-Process $EsetPortalUrl
    } catch {
        [System.Windows.Forms.MessageBox]::Show("Neizdevas atvert parlukprogrammu: $_", "Kluda") | Out-Null
    }
})
$form.Controls.Add($btnPortal)

$btnImport = New-Object System.Windows.Forms.Button
$btnImport.Text = "Importet sarakstu"
$btnImport.Location = New-Object System.Drawing.Point(810, 410)
$btnImport.Size = New-Object System.Drawing.Size(150, 32)
$btnImport.Anchor = [System.Windows.Forms.AnchorStyles]::Bottom -bor [System.Windows.Forms.AnchorStyles]::Left
$btnImport.Add_Click({
    Show-ImportDialog
})
$form.Controls.Add($btnImport)

$btnSave = New-Object System.Windows.Forms.Button
$btnSave.Text = "Saglabat uz NAS"
$btnSave.Location = New-Object System.Drawing.Point(975, 405)
$btnSave.Size = New-Object System.Drawing.Size(170, 40)
$btnSave.Anchor = [System.Windows.Forms.AnchorStyles]::Bottom -bor [System.Windows.Forms.AnchorStyles]::Right
$btnSave.Font = New-Object System.Drawing.Font($btnSave.Font, [System.Drawing.FontStyle]::Bold)
$btnSave.Add_Click({
    $newRows = @()
    $seenNames = @{}
    $errorMsg = $null

    foreach ($gr in $grid.Rows) {
        $name = [string]$gr.Cells["ComputerName"].Value
        if ([string]::IsNullOrWhiteSpace($name)) { continue }
        $name = $name.Trim()

        if ($seenNames.ContainsKey($name)) {
            $errorMsg = "Dators '$name' saraksta parado vairak nekaa vienu reizi. Ludzu labojiet pirms saglabasanas."
            break
        }
        $seenNames[$name] = $true

        $days = [string]$gr.Cells["UpdateDays"].Value
        if ([string]::IsNullOrWhiteSpace($days)) { $days = "All" }

        $time = [string]$gr.Cells["UpdateTime"].Value
        if (-not [string]::IsNullOrWhiteSpace($time) -and $time -notmatch '^[0-2][0-9]:[0-5][0-9]$') {
            $errorMsg = "Datoram '$name' lauks 'Laiks' ('$time') nav derigs formats. Izmantojiet HH:mm (piem. 12:00) vai atstajiet tukshu."
            break
        }

        $newRows += [PSCustomObject]@{
            ComputerName   = $name
            Group          = [string]$gr.Cells["Group"].Value
            UpdateDays     = $days
            UpdateTime       = $time
            ShowNotification = if ($gr.Cells["ShowNotification"].Value) { "Yes" } else { "No" }
            ShutdownAfter    = if ($gr.Cells["ShutdownAfter"].Value) { "Yes" } else { "No" }
            WindowsUpdate  = if ($gr.Cells["WindowsUpdate"].Value) { "Yes" } else { "No" }
            ThirdPartyApps = if ($gr.Cells["ThirdPartyApps"].Value) { "Yes" } else { "No" }
            TeamViewer     = if ($gr.Cells["TeamViewer"].Value) { "Yes" } else { "No" }
            Enabled        = if ($gr.Cells["Enabled"].Value) { "Yes" } else { "No" }
        }
    }

    if ($errorMsg) {
        [System.Windows.Forms.MessageBox]::Show($errorMsg, "Kluda", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error) | Out-Null
        return
    }

    try {
        Save-Schedule -Rows $newRows -Path $ScheduleFile
        $script:scheduleRows = $newRows
        [System.Windows.Forms.MessageBox]::Show("Saglabats veiksmigi uz NAS ($ScheduleFile).", "Gatavs", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information) | Out-Null
    } catch {
        [System.Windows.Forms.MessageBox]::Show("Kluda saglabajot: $_", "Kluda", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error) | Out-Null
    }
})
$form.Controls.Add($btnSave)

$btnInventory = New-Object System.Windows.Forms.Button
$btnInventory.Text = "Inventara atskaite"
$btnInventory.Location = New-Object System.Drawing.Point(10, 490)
$btnInventory.Size = New-Object System.Drawing.Size(200, 36)
$btnInventory.Anchor = [System.Windows.Forms.AnchorStyles]::Bottom -bor [System.Windows.Forms.AnchorStyles]::Left
$btnInventory.Add_Click({
    if (-not $script:inventoryReportAvailable) {
        [System.Windows.Forms.MessageBox]::Show("Fails inventory-report.ps1 nav atrasts blakus config-panel.ps1 (vai to neizdevas ieladet). Nokopejiet to uz to pasu mapi (piem., C:\Scripts) un palaidiet panelo velreiz.", "Informacija") | Out-Null
        return
    }
    try {
        Show-InventoryReport -NasRoot $NasRoot
    } catch {
        [System.Windows.Forms.MessageBox]::Show("Inventara atskaite neizdevas: " + $_.Exception.Message, "Kluda") | Out-Null
    }
})
$form.Controls.Add($btnInventory)

$btnApps = New-Object System.Windows.Forms.Button
$btnApps.Text = "Programmu saraksts"
$btnApps.Location = New-Object System.Drawing.Point(220, 490)
$btnApps.Size = New-Object System.Drawing.Size(200, 36)
$btnApps.Anchor = [System.Windows.Forms.AnchorStyles]::Bottom -bor [System.Windows.Forms.AnchorStyles]::Left
$btnApps.Add_Click({
    if (-not $script:appsEditorAvailable) {
        [System.Windows.Forms.MessageBox]::Show("Fails apps-managed-editor.ps1 nav atrasts blakus config-panel.ps1. Nokopejiet to uz to pasu mapi (piem., C:\Scripts) un atveriet panelim no jauna.", "Info") | Out-Null
        return
    }
    try { Show-AppsManagedEditor -NasRoot $NasRoot } catch { [System.Windows.Forms.MessageBox]::Show("Programmu saraksts neizdevas: " + $_.Exception.Message, "Kluda") | Out-Null }
})
$form.Controls.Add($btnApps)

$btnBackups = New-Object System.Windows.Forms.Button
$btnBackups.Text = "Profilu kopijas"
$btnBackups.Location = New-Object System.Drawing.Point(430, 490)
$btnBackups.Size = New-Object System.Drawing.Size(200, 36)
$btnBackups.Anchor = [System.Windows.Forms.AnchorStyles]::Bottom -bor [System.Windows.Forms.AnchorStyles]::Left
$btnBackups.Add_Click({
    if (-not $script:backupManagerAvailable) {
        [System.Windows.Forms.MessageBox]::Show("Fails backup-manager.ps1 nav atrasts blakus config-panel.ps1. Nokopejiet to uz to pasu mapi (piem., C:\Scripts) un atveriet panelim no jauna.", "Info") | Out-Null
        return
    }
    try { Show-BackupManager -NasRoot $NasRoot } catch { [System.Windows.Forms.MessageBox]::Show("Profilu kopiju logs neizdevas: " + $_.Exception.Message, "Kluda") | Out-Null }
})
$form.Controls.Add($btnBackups)

$infoLabel = New-Object System.Windows.Forms.Label
$infoLabel.Text = "Piezime: 'Laiks' tuksh = bez ierobezojuma (ert testesanai). Izmainas stajas speka pec saglabasanas, kad dators veiks nakamo parbaudi (lidz 15 min)."
$infoLabel.Location = New-Object System.Drawing.Point(10, 455)
$infoLabel.Size = New-Object System.Drawing.Size(1130, 20)
$infoLabel.Anchor = [System.Windows.Forms.AnchorStyles]::Bottom -bor [System.Windows.Forms.AnchorStyles]::Left -bor [System.Windows.Forms.AnchorStyles]::Right
$infoLabel.Anchor = [System.Windows.Forms.AnchorStyles]::Bottom -bor [System.Windows.Forms.AnchorStyles]::Left
$infoLabel.ForeColor = [System.Drawing.Color]::DimGray
$form.Controls.Add($infoLabel)

# Ja ekrans ir mazaks par loga izmeru (piem., liels Windows merogs), logu sasaurina,
# lai tas ietilptu redzamaja laukuma (elementi ir noenkuroti, tapec pielagojas).
$workArea = [System.Windows.Forms.Screen]::PrimaryScreen.WorkingArea
if ($form.Height -gt $workArea.Height) { $form.Height = [int]($workArea.Height * 0.96) }
if ($form.Width -gt $workArea.Width) { $form.Width = [int]($workArea.Width * 0.98) }

[void]$form.ShowDialog()
