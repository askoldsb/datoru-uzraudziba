<#
============================================================
 inventory-report.ps1
 Inventara atskaite: datoru saraksts, atskaite par katru datoru
 (klikskis uz datora) un eksports uz Excel un Word.

 Sis fails NAV palaizams pats par sevi - to ielade config-panel.ps1
 (dot-source). Ja so failu nevar ieladet, panelis darbojas ka lidz saim.

 Dati:
   Logs\Inventory\<DATORS>.json   aparatura, Windows, programmas   (tikai lasisana)
   Logs\Status\<DATORS>.json      pedejie atjauninasanas cikli      (tikai lasisana)
   Config\inventory-manual.csv    inventara nr., grupa, vieta, atbildigais, veids
                                  (datora kartite atlauj LABOT un SAGLABAT sos laukus;
                                   pirms saglabasanas tiek izveidota rezerves kopija .bak-*)
   Pogas Pamodinat / Izslegt / Restartet: WoL signals no sa datora; izslegsana un restarts caur WinRM
                                  (nekad netiek glabati velakam laikam - tikai, ja dators sasniedzams uzreiz).
   Config\Commands\<DATORS>.json  administratora komanda datoram (poga "Atjaunot tagad");
                                  klients to panem sava 15 min cikla un apstiprina ar
                                  Logs\Status\<DATORS>.command.json
============================================================
#>

# ---------- PALIGFUNKCIJAS ----------

function Get-InvProp {
    # Drosi nolasa ligzdotu ipasibu: Get-InvProp $obj @("A","B") = $obj.A.B (ja nav - $null)
    param($Object, [string[]]$Path)
    $cur = $Object
    foreach ($p in $Path) {
        if ($null -eq $cur) { return $null }
        $prop = $cur.PSObject.Properties[$p]
        if ($null -eq $prop) { return $null }
        $cur = $prop.Value
    }
    return $cur
}

function Get-InvText {
    param($Value)
    if ($null -eq $Value) { return "" }
    return ([string]$Value).Trim()
}

function Get-InvArray {
    # Lietot ka: @(Get-InvArray $x) - atgriez masivu ari tad, ja vertiba ir $null vai viens elements
    param($Value)
    if ($null -eq $Value) { return @() }
    return @($Value)
}

function ConvertTo-InvVersion {
    param([string]$Text)
    $v = $null
    if ([version]::TryParse($Text, [ref]$v)) { return $v }
    return $null
}

function Get-HighestVersionText {
    # No versiju tekstiem atgriez augstako; ja nevienu nevar nolasit, atgriez pirmo netuksu
    param($Texts)
    $best = $null
    $bestText = ""
    foreach ($t in @($Texts)) {
        $s = Get-InvText $t
        if ($s -eq "") { continue }
        $v = ConvertTo-InvVersion $s
        if ($v) {
            if ((-not $best) -or ($v -gt $best)) { $best = $v; $bestText = $s }
        } elseif ($bestText -eq "") {
            $bestText = $s
        }
    }
    return $bestText
}

function ConvertTo-InvTypeCode {
    # Cilveka ievadito veidu parversta uz CSV kodu (Stationary / Portable)
    param([string]$Text)
    $t = $Text.Trim()
    switch -Regex ($t.ToLower()) {
        '^(stacion|stationary)' { return "Stationary" }
        '^(portat|portable)'    { return "Portable" }
        default                 { return $t }
    }
}

function Save-InvManualEntry {
    # Ieraksta/atjauno vienu datora rindu Config\inventory-manual.csv (pec ComputerName, neatkarigi no burtu registra).
    # Saglaba esoso atdalitaju (, vai ;), kolonnu secibu, UTF-8 ar BOM. Pirms rakstisanas - rezerves kopija.
    param([string]$NasRoot, [string]$Name, [hashtable]$Fields)

    $path = Join-Path $NasRoot "Config\inventory-manual.csv"
    $required = @("ComputerName", "InventoryNumber", "Group", "Location", "Type", "Responsible")

    $delimiter = ","
    $headers = @()
    $existing = @()
    if (Test-Path $path) {
        $first = Get-Content -Path $path -TotalCount 1 -Encoding UTF8
        if ((($first -split ";").Count) -gt (($first -split ",").Count)) { $delimiter = ";" }
        $existing = @(Import-Csv -Path $path -Delimiter $delimiter -Encoding UTF8)
        if ($existing.Count -gt 0) {
            $headers = @($existing[0].PSObject.Properties | ForEach-Object { $_.Name })
        } else {
            $headers = @(($first.TrimStart([char]0xFEFF)) -split [regex]::Escape($delimiter) | ForEach-Object { $_.Trim('"').Trim() })
        }
        $bak = $path + ".bak-" + (Get-Date -Format "yyyyMMdd-HHmmss")
        Copy-Item -Path $path -Destination $bak -ErrorAction Stop
        # paturam tikai 5 jaunakas rezerves kopijas
        $olds = @(Get-ChildItem -Path (Split-Path $path) -Filter "inventory-manual.csv.bak-*" -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending)
        if ($olds.Count -gt 5) { $olds | Select-Object -Skip 5 | Remove-Item -ErrorAction SilentlyContinue }
    }
    foreach ($h in $required) { if ($headers -notcontains $h) { $headers += $h } }

    $out = @()
    $found = $false
    foreach ($e in $existing) {
        $o = [ordered]@{}
        foreach ($h in $headers) {
            $v = $e.PSObject.Properties[$h]
            if ($v) { $o[$h] = [string]$v.Value } else { $o[$h] = "" }
        }
        if (([string]$o["ComputerName"]).Trim().ToUpper() -eq $Name.ToUpper()) {
            foreach ($k in $Fields.Keys) { $o[$k] = [string]$Fields[$k] }
            $found = $true
        }
        $out += [PSCustomObject]$o
    }
    if (-not $found) {
        $o = [ordered]@{}
        foreach ($h in $headers) { $o[$h] = "" }
        $o["ComputerName"] = $Name
        foreach ($k in $Fields.Keys) { $o[$k] = [string]$Fields[$k] }
        $out += [PSCustomObject]$o
    }

    $lines = @($out | ConvertTo-Csv -NoTypeInformation -Delimiter $delimiter)
    $tmp = $path + ".tmp"
    [System.IO.File]::WriteAllLines($tmp, [string[]]$lines, (New-Object System.Text.UTF8Encoding($true)))
    Move-Item -Path $tmp -Destination $path -Force -ErrorAction Stop
}

function Send-InvCommand {
    # Ieraksta komandas failu Config\Commands\<DATORS>.json (klients to panem ik 15 min cikla)
    param([string]$NasRoot, [string]$Name, [string]$Command, [int]$ValidHours = 12)
    $dir = Join-Path $NasRoot "Config\Commands"
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    $now = Get-Date
    $fmt = "yyyy-MM-dd HH:mm:ss"
    $obj = [ordered]@{
        Id        = [guid]::NewGuid().ToString()
        Command   = $Command
        CreatedAt = $now.ToString($fmt)
        ExpiresAt = $now.AddHours($ValidHours).ToString($fmt)
        CreatedBy = ($env:USERNAME + "@" + $env:COMPUTERNAME)
    }
    $path = Join-Path $dir ($Name + ".json")
    $tmp = $path + ".tmp"
    [System.IO.File]::WriteAllText($tmp, ($obj | ConvertTo-Json), (New-Object System.Text.UTF8Encoding($true)))
    Move-Item -Path $tmp -Destination $path -Force -ErrorAction Stop
}

function Get-InvCommandText {
    # Viena rinda: kas notiek ar pedejo administratora komandu sim datoram
    param([string]$NasRoot, [string]$Name)
    $cmd = Read-InvJsonFile -Path (Join-Path $NasRoot ("Config\Commands\" + $Name + ".json"))
    $ack = Read-InvJsonFile -Path (Join-Path $NasRoot ("Logs\Status\" + $Name + ".command.json"))
    $cmdId = ""; if ($cmd) { $cmdId = Get-InvText $cmd.Id }
    $ackId = ""; if ($ack) { $ackId = Get-InvText $ack.Id }

    if ($cmd -and ($cmdId -ne $ackId)) {
        $line = "Komanda {0} nosutita {1}, gaida datoru (deriga lidz {2})." -f (Get-InvText $cmd.Command), (Get-InvText $cmd.CreatedAt), (Get-InvText $cmd.ExpiresAt)
        try {
            $exp = [datetime]::ParseExact((Get-InvText $cmd.ExpiresAt), "yyyy-MM-dd HH:mm:ss", [System.Globalization.CultureInfo]::InvariantCulture)
            if ($exp -lt (Get-Date)) { $line = "Komanda {0} ({1}) novecojusi - dators to nepanema." -f (Get-InvText $cmd.Command), (Get-InvText $cmd.CreatedAt) }
        } catch { }
        return $line
    }
    if ($ack) {
        $st = Get-InvText $ack.Status
        $when = Get-InvText $ack.UpdatedAt
        switch ($st) {
            "Started"  { return ("Komanda {0}: dators sak ({1})." -f (Get-InvText $ack.Command), $when) }
            "Done"     { return ("Komanda {0} izpildita {1}. {2}" -f (Get-InvText $ack.Command), $when, (Get-InvText $ack.Details)) }
            "Rejected" { return ("Komanda {0} noraidita {1}: {2}" -f (Get-InvText $ack.Command), $when, (Get-InvText $ack.Details)) }
            "Expired"  { return ("Komanda {0} novecojusi {1}." -f (Get-InvText $ack.Command), $when) }
            default    { return ("Komanda {0}: {1} ({2})" -f (Get-InvText $ack.Command), $st, $when) }
        }
    }
    return "Administratora komandu nav."
}

function Get-InvAdminCredential {
    # Viena vietejo administratora akreditacija sesijai (lietotajvards + parole); tiek prasita tikai pirmo reizi
    if ($script:invAdminUser -and $script:invAdminPass) { return $true }
    try {
        $c = Get-Credential -UserName "Administrator" -Message "Datoru lokala administratora konts (lai komanda tiktu palaista UZREIZ). Atcelt = datori komandu panems ik 15 min cikla."
    } catch { return $false }
    if (-not $c) { return $false }
    $script:invAdminUser = ($c.UserName -split '\\')[-1]
    $script:invAdminPass = $c.Password
    return $true
}

function Start-InvUpdateTaskNow {
    # Palaiz uzdevumu LabAppUpdate uz datora uzreiz (WinRM). Atgriez "OK" vai kludas tekstu.
    param([string]$Name, [string]$IpText)
    $ip = ([regex]::Match([string]$IpText, '\d{1,3}(\.\d{1,3}){3}')).Value
    if (-not $ip) { return "nav zinamas IP adreses" }
    $cred = New-Object System.Management.Automation.PSCredential(($Name + "\" + $script:invAdminUser), $script:invAdminPass)
    $opt = New-PSSessionOption -OpenTimeout 6000 -OperationTimeout 20000
    try {
        Invoke-Command -ComputerName $ip -Credential $cred -SessionOption $opt -ErrorAction Stop -ScriptBlock {
            Start-ScheduledTask -TaskName "LabAppUpdate" -ErrorAction Stop
        } | Out-Null
        return "OK"
    } catch {
        $m = $_.Exception.Message
        if ($m.Length -gt 90) { $m = $m.Substring(0, 90) + "..." }
        return $m
    }
}

function Send-InvWol {
    # Nosuta Wake-on-LAN magic packet uz visam MAC adresem, kas atrastas tekstaa. Atgriez nosutito skaitu.
    param([string]$MacText)
    $macs = @([regex]::Matches([string]$MacText, '(?i)(?:[0-9a-f]{2}[:-]){5}[0-9a-f]{2}') | ForEach-Object { $_.Value })
    $sent = 0
    foreach ($m in $macs) {
        $bytes = @($m -split '[:-]' | ForEach-Object { [Convert]::ToByte($_, 16) })
        $packet = [byte[]]((,[byte]255 * 6) + ($bytes * 16))
        $udp = New-Object System.Net.Sockets.UdpClient
        try {
            $udp.EnableBroadcast = $true
            foreach ($addr in "255.255.255.255", "192.168.3.255") {
                foreach ($port in 9, 7) { [void]$udp.Send($packet, $packet.Length, $addr, $port) }
            }
            $sent++
        } finally { $udp.Close() }
    }
    return $sent
}

function Start-InvPowerRemote {
    # Izslegsana / restarts uz datora caur WinRM ar 60 s bridinajumu. Atgriez "OK" vai kludas tekstu.
    param([string]$Name, [string]$IpText, [string]$Action)
    $ip = ([regex]::Match([string]$IpText, '\d{1,3}(\.\d{1,3}){3}')).Value
    if (-not $ip) { return "nav zinamas IP adreses" }
    $cred = New-Object System.Management.Automation.PSCredential(($Name + "\" + $script:invAdminUser), $script:invAdminPass)
    $opt = New-PSSessionOption -OpenTimeout 6000 -OperationTimeout 20000
    $flag = "/s"; if ($Action -eq "Restart") { $flag = "/r" }
    try {
        $code = Invoke-Command -ComputerName $ip -Credential $cred -SessionOption $opt -ErrorAction Stop -ArgumentList $flag -ScriptBlock {
            param($f)
            & shutdown.exe $f /t 60 /c "Administrators uzsaka datora darbibu. Saglabajiet darbu - dators izslegsies/restartesies pec 60 sekundem."
            $LASTEXITCODE
        }
        if ([int](@($code)[-1]) -eq 0) { return "OK" }
        return ("shutdown.exe exit code " + (@($code)[-1]))
    } catch {
        $m = $_.Exception.Message
        if ($m.Length -gt 90) { $m = $m.Substring(0, 90) + "..." }
        return $m
    }
}

function Invoke-InvPowerAction {
    # Action: Wake | Shutdown | Restart; vienam vai vairakiem datoriem
    param($Rows, [string]$Action)
    $rowsList = @($Rows | Where-Object { $_ })
    if ($rowsList.Count -eq 0) {
        [void][System.Windows.Forms.MessageBox]::Show("Izvelies vismaz vienu datoru.", "Datora darbiba", "OK", "Information")
        return $false
    }
    $nl = [Environment]::NewLine
    $names = ($rowsList | ForEach-Object { $_.Name }) -join ", "

    if ($Action -eq "Wake") {
        $msg = "Nosutit PAMODINASANAS signalu ({0}):{1}{1}{2}{1}{1}Dators pamodinas tikai, ja BIOS un tikla adapteris to atlauj, un dators ir tajaa pasa tikla segmenta ka sis dators (Wi-Fi portativie parasti nepamodinas)." -f $rowsList.Count, $nl, $names
        if ([System.Windows.Forms.MessageBox]::Show($msg, "Pamodinat", "YesNo", "Question") -ne [System.Windows.Forms.DialogResult]::Yes) { return $false }
        $ok = @(); $none = @()
        foreach ($r in $rowsList) {
            $n = 0
            try { $n = Send-InvWol -MacText $r.MacText } catch { $n = 0 }
            if ($n -gt 0) { $ok += $r.Name } else { $none += $r.Name }
        }
        $res = "Signals nosutits: {0}." -f $ok.Count
        if ($none.Count -gt 0) { $res += $nl + "Nav zinamas MAC adreses: " + ($none -join ", ") }
        [void][System.Windows.Forms.MessageBox]::Show($res, "Pamodinat", "OK", "Information")
        return ($ok.Count -gt 0)
    }

    $verb = "IZSLEGT"; if ($Action -eq "Restart") { $verb = "RESTARTET" }
    $msg = "{0} sadus datorus ({1}):{2}{2}{3}{2}{2}Dators saglabas lietotajam 60 sekunzu bridinajumu, bet nesaglabatie dati var tikt zaudeti. Darbojas tikai, ja dators ir sasniedzams (WinRM); komanda netiek glabata velakam laikam." -f $verb, $rowsList.Count, $nl, $names
    if ([System.Windows.Forms.MessageBox]::Show($msg, $verb, "YesNo", "Warning") -ne [System.Windows.Forms.DialogResult]::Yes) { return $false }
    if (-not (Get-InvAdminCredential)) { return $false }
    $ok = @(); $bad = @()
    $oldCursor = [System.Windows.Forms.Cursor]::Current
    [System.Windows.Forms.Cursor]::Current = [System.Windows.Forms.Cursors]::WaitCursor
    try {
        foreach ($r in $rowsList) {
            $res1 = Start-InvPowerRemote -Name $r.Name -IpText $r.IpText -Action $Action
            if ($res1 -eq "OK") { $ok += $r.Name } else { $bad += ($r.Name + " (" + $res1 + ")") }
        }
    } finally {
        [System.Windows.Forms.Cursor]::Current = $oldCursor
    }
    $res = "Komanda nosutita (60 s): {0}." -f $ok.Count
    if ($ok.Count -gt 0) { $res += $nl + ($ok -join ", ") }
    if ($bad.Count -gt 0) { $res += $nl + "Neizdevas: " + ($bad -join "; ") }
    [void][System.Windows.Forms.MessageBox]::Show($res, $verb, "OK", "Information")
    return ($ok.Count -gt 0)
}

function Add-InvPowerButtons {
    # Otra pogu rinda (pamodinat / izslegt / restartet); GetRows ir scriptblock, kas atgriez datoru rindas
    param($Panel, [scriptblock]$GetRows)
    $Panel.Height = 92
    $defs = @(@("Pamodinat", "Wake", 10), @("Izslegt", "Shutdown", 180), @("Restartet", "Restart", 350))
    foreach ($d in $defs) {
        $b = New-Object System.Windows.Forms.Button
        $b.Text = $d[0]
        $b.Location = New-Object System.Drawing.Point([int]$d[2], 51)
        $b.Size = New-Object System.Drawing.Size(160, 32)
        $b.Tag = @{ Action = $d[1]; GetRows = $GetRows }
        $b.Add_Click({
            param($sender, $e)
            $t = $sender.Tag
            [void](Invoke-InvPowerAction -Rows (& ($t.GetRows)) -Action $t.Action)
        })
        $Panel.Controls.Add($b)
    }
}

function Invoke-InvUpdateNow {
    # Apstiprinajuma dialogs un komandas nosutisana vienam vai vairakiem datoriem
    param($Rows)
    $rowsList = @($Rows | Where-Object { $_ })
    if ($rowsList.Count -eq 0) {
        [void][System.Windows.Forms.MessageBox]::Show("Izvelies vismaz vienu datoru.", "Atjaunot tagad", "OK", "Information")
        return $false
    }
    $names = ($rowsList | ForEach-Object { $_.Name }) -join ", "
    $nl = [Environment]::NewLine
    $msg = "Nosutit komandu ATJAUNOT TAGAD sadiem datoriem ({0})?{1}{1}{2}{1}{1}Dators komandu panems nakama 15 min cikla, kad tam bus pieejams NAS tikls, un atjauninas neatkarigi no grafika dienam un laika (bez izslegsanas pec cikla). Ja dators ir sasniedzams, atjaunosana sakas UZREIZ, citadi - nakama 15 min cikla. Komanda deriga 7 dienas." -f $rowsList.Count, $nl, $names
    $ans = [System.Windows.Forms.MessageBox]::Show($msg, "Atjaunot tagad", "YesNo", "Question")
    if ($ans -ne [System.Windows.Forms.DialogResult]::Yes) { return $false }
    $useNow = Get-InvAdminCredential
    $ok = @(); $bad = @(); $started = @(); $waiting = @()
    $oldCursor = [System.Windows.Forms.Cursor]::Current
    [System.Windows.Forms.Cursor]::Current = [System.Windows.Forms.Cursors]::WaitCursor
    try {
        foreach ($r in $rowsList) {
            try { Send-InvCommand -NasRoot $script:invNasRoot -Name $r.Name -Command "UpdateNow"; $ok += $r.Name }
            catch { $bad += ($r.Name + " (" + $_.Exception.Message + ")"); continue }
            if ($useNow) {
                $res1 = Start-InvUpdateTaskNow -Name $r.Name -IpText $r.IpText
                if ($res1 -eq "OK") { $started += $r.Name } else { $waiting += ($r.Name + " (" + $res1 + ")") }
            } else {
                $waiting += $r.Name
            }
        }
    } finally {
        [System.Windows.Forms.Cursor]::Current = $oldCursor
    }
    $res = "Komanda nosutita: {0}." -f $ok.Count
    if ($started.Count -gt 0) { $res += $nl + "Palaists uzreiz: " + ($started -join ", ") }
    if ($waiting.Count -gt 0) { $res += $nl + "Gaida datora 15 min ciklu: " + ($waiting -join "; ") }
    if ($bad.Count -gt 0) { $res += $nl + "Neizdevas: " + ($bad -join "; ") }
    [void][System.Windows.Forms.MessageBox]::Show($res, "Atjaunot tagad", "OK", "Information")
    return ($ok.Count -gt 0)
}

function New-InvPair {
    param($Label, $Value)
    return [PSCustomObject]@{ Label = [string]$Label; Value = [string]$Value }
}

function ConvertTo-InvTypeText {
    param([string]$Code)
    switch ($Code.Trim().ToLower()) {
        "stationary" { return "Stacionarais" }
        "portable"   { return "Portativais" }
        default      { return $Code.Trim() }
    }
}

function Read-InvJsonFile {
    param([string]$Path)
    try {
        if (-not (Test-Path $Path)) { return $null }
        $raw = Get-Content -Path $Path -Raw -Encoding UTF8 -ErrorAction Stop
        if ([string]::IsNullOrWhiteSpace($raw)) { return $null }
        return ($raw | ConvertFrom-Json -ErrorAction Stop)
    } catch {
        return $null
    }
}

function Read-InvManualCsv {
    # Nolasa inventory-manual.csv; atpazist gan komatu, gan semikolu (latviesu Excel saglaba ar semikolu)
    param([string]$Path)
    if (-not (Test-Path $Path)) { return @() }
    $first = Get-Content -Path $Path -TotalCount 1 -Encoding UTF8
    $delimiter = ","
    if ((($first -split ";").Count) -gt (($first -split ",").Count)) { $delimiter = ";" }
    return @(Import-Csv -Path $Path -Delimiter $delimiter -Encoding UTF8)
}

# Pamata programmu saraksts (atskaite un eksports)
$script:InvKeyAppDefs = @(
    @{ App = "ESET";          Group = "Antivirus";   Like = "ESET*" },
    @{ App = "Office";        Group = "Office";      Like = "*" },
    @{ App = "Chrome";        Group = "Browsers";    Like = "Google Chrome*" },
    @{ App = "Edge";          Group = "Browsers";    Like = "Microsoft Edge*" },
    @{ App = "Firefox";       Group = "Browsers";    Like = "Mozilla Firefox*" },
    @{ App = "Zoom";          Group = "Zoom";        Like = "*" },
    @{ App = "VLC";           Group = "VLC";         Like = "*" },
    @{ App = "TeamViewer";    Group = "TeamViewer";  Like = "*" },
    @{ App = "eParakstitajs"; Group = "EParaksts";   Like = "eParakst?t?js*" },
    @{ App = "PowerShell 7";  Group = "PowerShell7"; Like = "*" }
)

# Tehniskas programmas, ko pec noklusejuma neradam programmu saraksta
$script:InvNoiseRegex = '^(Microsoft Visual C\+\+|Microsoft Windows Application Compatibility|Windows datora darbsp|Intel\(R\)|Realtek|Microsoft Edge WebView2|Microsoft Update Health|Microsoft Teams Meeting Add-in|Windows Driver Package)'

function Get-InvKeyApps {
    # Atgriez pamata programmu versijas (augstaka versija + cik dazadas versijas ir instaletas)
    param($Inv)
    $result = @()
    $keyApps = Get-InvProp $Inv @("Software", "KeyApps")
    foreach ($def in $script:InvKeyAppDefs) {
        $items = @()
        if ($keyApps) {
            $grp = Get-InvProp $keyApps @($def.Group)
            foreach ($it in @(Get-InvArray $grp)) {
                if ((Get-InvText $it.Name) -like $def.Like) { $items += $it }
            }
        }
        $versions = @($items | ForEach-Object { Get-InvText $_.Version } | Where-Object { $_ -ne "" } | Select-Object -Unique)
        $best = Get-HighestVersionText $versions
        if ($def.App -eq "Office") {
            $c2r = Get-InvText (Get-InvProp $Inv @("Software", "OfficeClickToRun", "Version"))
            if ($c2r -ne "") { $best = $c2r; $versions = @($c2r) }
        }
        $result += [PSCustomObject]@{
            App      = $def.App
            Version  = $best
            Count    = $versions.Count
            Versions = ($versions -join ", ")
        }
    }
    return $result
}

function Get-InvOfficeProduct {
    # Office produkta nosaukums no inventara (Click-to-Run produktu ID vai pirmais atrastais ieraksts)
    param($Inv)
    $ids = Get-InvText (Get-InvProp $Inv @("Software", "OfficeClickToRun", "Products"))
    if ($ids -ne "") {
        if ($ids -match 'O365|Microsoft365') { return "Microsoft 365" }
        if ($ids -match '2024') { return "Office 2024" }
        if ($ids -match '2021') { return "Office 2021" }
        if ($ids -match '2019') { return "Office 2019" }
        if ($ids -match '2016') { return "Office 2016" }
        return "Office (Click-to-Run)"
    }
    $first = @(Get-InvArray (Get-InvProp $Inv @("Software", "KeyApps", "Office"))) | Select-Object -First 1
    if ($first) { return (Get-InvText $first.Name) }
    return ""
}

function ConvertTo-InvIpSortKey {
    # IP kartosanas atslega: katrs oktets 3 zimes (192.168.3.9 -> 192168003009), lai kartotu skaitliski
    param([string]$Text)
    $first = (($Text -split ";")[0]).Trim()
    $parts = $first -split "\."
    if ($parts.Count -ne 4) { return "zzz" + $first }
    $key = ""
    foreach ($part in $parts) {
        $n = 0
        if (-not [int]::TryParse($part, [ref]$n)) { return "zzz" + $first }
        $key = $key + $n.ToString("000")
    }
    return $key
}

function Get-InvAppVersion {
    param($Row, [string]$App)
    if (($App -eq "ESET") -and ($Row.EsetVer -ne "")) { return $Row.EsetVer }
    if (($App -eq "Office") -and ($Row.OfficeText -ne "")) { return $Row.OfficeText }
    foreach ($k in $Row.KeyApps) {
        if ($k.App -eq $App) { return $k.Version }
    }
    return ""
}

# ---------- DATU IELADE ----------

function New-InvRow {
    param([string]$Name, $Manual, $Inv, $Status)

    $hasInv = [bool]$Inv

    # manualie dati
    $invNo = ""; $group = ""; $location = ""; $typeManualCode = ""; $resp = ""
    if ($Manual) {
        $invNo = Get-InvText $Manual.InventoryNumber
        $group = Get-InvText $Manual.Group
        $location = Get-InvText $Manual.Location
        $typeManualCode = Get-InvText $Manual.Type
        $resp = Get-InvText $Manual.Responsible
    }

    $comp = Get-InvProp $Inv @("Computer")
    $board = Get-InvProp $Inv @("BaseBoard")
    $cpu = Get-InvProp $Inv @("Processor")
    $os = Get-InvProp $Inv @("OperatingSystem")

    $categoryCode = Get-InvText (Get-InvProp $comp @("Category"))

    # savaksanas laiks
    $collectedAt = $null
    $collectedText = ""
    $ct = Get-InvText (Get-InvProp $Inv @("CollectedAt"))
    if ($ct -ne "") {
        $collectedText = $ct
        try {
            $collectedAt = [datetime]::ParseExact($ct, "yyyy-MM-dd HH:mm:ss", [System.Globalization.CultureInfo]::InvariantCulture)
        } catch { $collectedAt = $null }
    }

    # atmina
    $ramLines = @()
    foreach ($m in @(Get-InvArray (Get-InvProp $Inv @("Memory", "Modules")))) {
        $ramLines += ("{0} GB {1} {2} MHz, {3} {4}" -f (Get-InvText $m.CapacityGB), (Get-InvText $m.Type), (Get-InvText $m.SpeedMHz), (Get-InvText $m.Manufacturer), (Get-InvText $m.PartNumber))
    }
    $ramTotal = Get-InvText (Get-InvProp $Inv @("Memory", "TotalGB"))
    $ramText = ""
    if ($ramTotal -ne "") { $ramText = $ramTotal + " GB" }
    if ($ramLines.Count -gt 0) {
        $short = @()
        foreach ($m in @(Get-InvArray (Get-InvProp $Inv @("Memory", "Modules")))) {
            $short += ("{0} GB {1} {2}" -f (Get-InvText $m.CapacityGB), (Get-InvText $m.Type), (Get-InvText $m.SpeedMHz))
        }
        $ramText = $ramText + " (" + ($short -join " + ") + ")"
    }

    # diski
    $diskLines = @()
    $diskBad = $false
    foreach ($d in @(Get-InvArray (Get-InvProp $Inv @("Storage", "PhysicalDisks")))) {
        $diskLines += ("{0}, {1} GB, {2} {3}, stavoklis: {4}" -f (Get-InvText $d.Model), (Get-InvText $d.SizeGB), (Get-InvText $d.MediaType), (Get-InvText $d.BusType), (Get-InvText $d.Health))
        if ((Get-InvText $d.Health) -ne "Healthy") { $diskBad = $true }
    }
    $volLines = @()
    $lowSpace = $false
    foreach ($v in @(Get-InvArray (Get-InvProp $Inv @("Storage", "Volumes")))) {
        $volLines += ("{0} {1} GB brivi no {2} GB" -f (Get-InvText $v.Drive), (Get-InvText $v.FreeGB), (Get-InvText $v.SizeGB))
        $sizeGb = 0.0; $freeGb = 0.0
        [void][double]::TryParse((Get-InvText $v.SizeGB), [System.Globalization.NumberStyles]::Float, [System.Globalization.CultureInfo]::InvariantCulture, [ref]$sizeGb)
        [void][double]::TryParse((Get-InvText $v.FreeGB), [System.Globalization.NumberStyles]::Float, [System.Globalization.CultureInfo]::InvariantCulture, [ref]$freeGb)
        if (($sizeGb -gt 0) -and ((Get-InvText $v.Drive) -eq "C:") -and (($freeGb / $sizeGb) -lt 0.15)) { $lowSpace = $true }
    }

    # video karte
    $gpuLines = @()
    foreach ($g in @(Get-InvArray (Get-InvProp $Inv @("Video", "Adapters")))) {
        $gpuLines += ("{0} (draiveris {1})" -f (Get-InvText $g.Name), (Get-InvText $g.DriverVersion))
    }

    # monitori
    $monLines = @()
    foreach ($mo in @(Get-InvArray (Get-InvProp $Inv @("Monitors", "Monitors")))) {
        $model = Get-InvText $mo.Model
        $unknown = ""
        if ($model -eq "") {
            $model = ((Get-InvText $mo.Manufacturer) + " " + (Get-InvText $mo.ProductCode)).Trim()
            $unknown = ", nenosakams modelis"
        }
        $year = Get-InvText $mo.Year
        if ($year -ne "") { $monLines += ("{0} ({1}{2})" -f $model, $year, $unknown) } else { $monLines += ($model + $unknown) }
    }

    # tikls
    $netLines = @()
    $netObjs = @()
    foreach ($a in @(Get-InvArray (Get-InvProp $Inv @("Network", "Adapters")))) {
        $ips = (@(Get-InvArray $a.IPv4) | ForEach-Object { Get-InvText $_ }) -join ", "
        $netLines += ("{0} | {1} | {2} | MAC {3} | IP {4}" -f (Get-InvText $a.Description), (Get-InvText $a.Status), (Get-InvText $a.LinkSpeed), (Get-InvText $a.Mac), $ips)
        $netObjs += [PSCustomObject]@{
            Description = (Get-InvText $a.Description)
            Status      = (Get-InvText $a.Status)
            LinkSpeed   = (Get-InvText $a.LinkSpeed)
            Mac         = (Get-InvText $a.Mac)
            Ip          = $ips
        }
    }
    # Galvenais MAC un IP: pieslegtie adapteri (Up) ar IP; ja tadu nav - visi adapteri
    $activeNet = @($netObjs | Where-Object { ($_.Status -eq "Up") -and ($_.Ip -ne "") })
    if ($activeNet.Count -eq 0) { $activeNet = @($netObjs) }
    $macText = (@($activeNet | ForEach-Object { $_.Mac } | Where-Object { $_ -ne "" }) -join "; ")
    $ipText = (@($activeNet | ForEach-Object { $_.Ip } | Where-Object { $_ -ne "" }) -join "; ")

    # Windows
    # Windows versiju vispirms nem no STATUSA faila (to klients atjauno ik pec 15 min), un tikai
    # ja tur nav - no inventara (to klients ievac reizi diena). Tad abas atskaites sakrit.
    $winVersion = Get-InvText (Get-InvProp $Status @("WindowsVersion"))
    $winBuild = Get-InvText (Get-InvProp $Status @("WindowsBuild"))
    if ($winBuild -eq "") {
        $winVersion = Get-InvText (Get-InvProp $os @("Version"))
        $winBuild = Get-InvText (Get-InvProp $os @("Build"))
    }
    $winText = $winVersion
    if ($winBuild -ne "") { $winText = ($winVersion + " (" + $winBuild + ")").Trim() }

    $keyApps = Get-InvKeyApps $Inv
    $esetVer = ""
    $officeVer = ""
    foreach ($k in $keyApps) {
        if ($k.App -eq "ESET") { $esetVer = $k.Version }
        if ($k.App -eq "Office") { $officeVer = $k.Version }
    }
    $esetLive = Get-InvText (Get-InvProp $Status @("EsetVersion"))
    if ($esetLive -ne "") { $esetVer = $esetLive }

    # Office: tikai atspogulojam produktu un versiju (bez salidzinasanas). Vispirms statusa fails.
    $officeProduct = Get-InvText (Get-InvProp $Status @("OfficeProduct"))
    $officeLive = Get-InvText (Get-InvProp $Status @("OfficeVersion"))
    if ($officeLive -ne "") {
        $officeVer = $officeLive
    } else {
        $officeProduct = Get-InvOfficeProduct $Inv
    }
    $officeText = ($officeProduct + " " + $officeVer).Trim()

    $pending = $false
    if ((Get-InvProp $os @("PendingReboot")) -eq $true) { $pending = $true }

    return [PSCustomObject]@{
        Name           = $Name
        InvNo          = $invNo
        Group          = $group
        Location       = $location
        TypeManualCode = $typeManualCode
        TypeManual     = (ConvertTo-InvTypeText $typeManualCode)
        TypeAuto       = (ConvertTo-InvTypeText $categoryCode)
        TypeAutoCode   = $categoryCode
        Responsible    = $resp
        HasInv         = $hasInv
        CollectedAt    = $collectedAt
        CollectedText  = $collectedText
        Manufacturer   = (Get-InvText (Get-InvProp $comp @("Manufacturer")))
        Model          = (Get-InvText (Get-InvProp $comp @("Model")))
        Serial         = (Get-InvText (Get-InvProp $comp @("Serial")))
        BiosText       = (((Get-InvText (Get-InvProp $comp @("BiosVendor"))) + " " + (Get-InvText (Get-InvProp $comp @("BiosVersion"))) + " (" + (Get-InvText (Get-InvProp $comp @("BiosDate"))) + ")").Trim())
        BoardText      = (((Get-InvText (Get-InvProp $board @("Manufacturer"))) + " " + (Get-InvText (Get-InvProp $board @("Model")))).Trim())
        BoardSerial    = (Get-InvText (Get-InvProp $board @("Serial")))
        CpuText        = (((Get-InvText (Get-InvProp $cpu @("Name"))) + ", " + (Get-InvText (Get-InvProp $cpu @("Cores"))) + " kodoli / " + (Get-InvText (Get-InvProp $cpu @("Threads"))) + " pavedieni").Trim())
        RamText        = $ramText
        RamLines       = $ramLines
        DiskLines      = $diskLines
        VolLines       = $volLines
        GpuLines       = $gpuLines
        MonLines       = $monLines
        NetLines       = $netLines
        NetAdapters    = $netObjs
        MacText        = $macText
        IpText         = $ipText
        OsCaption      = (Get-InvText (Get-InvProp $os @("Caption")))
        OsEdition      = (Get-InvText (Get-InvProp $os @("Edition")))
        WinVersion     = $winVersion
        WinBuild       = $winBuild
        WinText        = $winText
        WinBuildVer    = (ConvertTo-InvVersion $winBuild)
        Activation     = (Get-InvText (Get-InvProp $os @("Activation")))
        OsInstall      = (Get-InvText (Get-InvProp $os @("InstallDate")))
        LastBoot       = (Get-InvText (Get-InvProp $os @("LastBoot")))
        PendingReboot  = $pending
        EsetVer        = $esetVer
        EsetVerObj     = (ConvertTo-InvVersion $esetVer)
        OfficeVer      = $officeVer
        OfficeText     = $officeText
        KeyApps        = $keyApps
        Programs       = @(Get-InvArray (Get-InvProp $Inv @("Software", "Programs")))
        DiskBad        = $diskBad
        LowSpace       = $lowSpace
        StatusLastCheck  = (Get-InvText (Get-InvProp $Status @("LastCheck")))
        StatusLastCycle  = (Get-InvText (Get-InvProp $Status @("LastCycle")))
        StatusLastResult = (Get-InvText (Get-InvProp $Status @("LastResult")))
        StatusDetails    = (Get-InvText (Get-InvProp $Status @("Details")))
        History        = @(Get-InvArray (Get-InvProp $Status @("History")))
        WinLag         = $false
        WinAhead       = $false
        WinOld         = $false
        EsetLag        = $false
        Flags          = @()
    }
}

function Get-InvRows {
    param([string]$NasRoot)

    $manualPath = Join-Path $NasRoot "Config\inventory-manual.csv"
    $invDir = Join-Path $NasRoot "Logs\Inventory"
    $stDir = Join-Path $NasRoot "Logs\Status"

    $names = @{}
    foreach ($m in @(Read-InvManualCsv -Path $manualPath)) {
        $n = (Get-InvText $m.ComputerName).ToUpper()
        if ($n -ne "") { $names[$n] = $m }
    }
    if (Test-Path $invDir) {
        foreach ($f in @(Get-ChildItem -Path $invDir -Filter "*.json" -ErrorAction SilentlyContinue)) {
            $n = $f.BaseName.ToUpper()
            if (-not $names.ContainsKey($n)) { $names[$n] = $null }
        }
    }

    $rows = @()
    foreach ($n in @($names.Keys | Sort-Object)) {
        $inv = Read-InvJsonFile -Path (Join-Path $invDir ($n + ".json"))
        $st = Read-InvJsonFile -Path (Join-Path $stDir ($n + ".json"))
        $rows += (New-InvRow -Name $n -Manual $names[$n] -Inv $inv -Status $st)
    }

    # Windows atskaites punkts (divi limeni):
    #  1) laidiens (build numurs, piem. 26200 = 25H2): visbiezakais parka;
    #  2) labojumu numurs (UBR) taja pasa laidiena: visbiezakais starp tiem datoriem.
    # Vecaks laidiens = "Old" (spec. oranzs), tas pats laidiens ar zemaku labojumu = "Lag" (oranzs),
    # jaunaks laidiens neka vairakumam = "Ahead" (gaiski zals).
    $refEset = $null
    $refMajor = $null; $refMinor = $null
    $mg = @($rows | Where-Object { $_.WinBuildVer } | Group-Object { $_.WinBuildVer.Major })
    if ($mg.Count -gt 0) {
        $best = ($mg | Measure-Object -Property Count -Maximum).Maximum
        foreach ($g in ($mg | Where-Object { $_.Count -eq $best })) {
            $m = [int]$g.Name
            if (($null -eq $refMajor) -or ($m -gt $refMajor)) { $refMajor = $m }
        }
        $ug = @($rows | Where-Object { $_.WinBuildVer -and ($_.WinBuildVer.Major -eq $refMajor) } | Group-Object { $_.WinBuildVer.Minor })
        $bestU = ($ug | Measure-Object -Property Count -Maximum).Maximum
        foreach ($g in ($ug | Where-Object { $_.Count -eq $bestU })) {
            $u = [int]$g.Name
            if (($null -eq $refMinor) -or ($u -gt $refMinor)) { $refMinor = $u }
        }
    }
    foreach ($r in $rows) {
        if ($r.EsetVerObj) { if ((-not $refEset) -or ($r.EsetVerObj -gt $refEset)) { $refEset = $r.EsetVerObj } }
    }

    foreach ($r in $rows) {
        if ($r.WinBuildVer -and ($null -ne $refMajor)) {
            if ($r.WinBuildVer.Major -lt $refMajor) { $r.WinOld = $true; $r.WinLag = $true }
            elseif ($r.WinBuildVer.Major -gt $refMajor) { $r.WinAhead = $true }
            elseif ($r.WinBuildVer.Minor -lt $refMinor) { $r.WinLag = $true }
        }
        if ($r.EsetVerObj -and $refEset) { $r.EsetLag = [bool]($r.EsetVerObj -lt $refEset) }

        $flags = @()
        if (-not $r.HasInv) {
            $flags += "Nav inventara"
        } else {
            if ($r.CollectedAt) {
                $age = ((Get-Date) - $r.CollectedAt).TotalDays
                if ($age -gt 3) { $flags += ("Inventars vecs ({0:N0} d.)" -f $age) }
            }
            if ($r.PendingReboot) { $flags += "Gaida restartu" }
            if (($r.Activation -ne "") -and ($r.Activation -ne "Licencets")) { $flags += "Windows nav aktivizets" }
            if ($r.DiskBad) { $flags += "Diska problema" }
            if ($r.LowSpace) { $flags += "Maz vietas C:" }
            if (($r.TypeManualCode -ne "") -and ($r.TypeAutoCode -ne "") -and ($r.TypeAutoCode -ne "Unknown") -and ($r.TypeManualCode.ToLower() -ne $r.TypeAutoCode.ToLower())) { $flags += "Veids neatbilst" }
            foreach ($k in $r.KeyApps) {
                if (($k.Count -gt 1) -and ($k.App -ne "eParakstitajs")) { $flags += ("Vairakas versijas: " + $k.App) }
            }
        }
        if ($r.WinOld) { $flags += "Windows novecojis laidiens" }
        elseif ($r.WinLag) { $flags += "Windows atpaliek" }
        if ($r.EsetLag) { $flags += "ESET atpaliek" }
        $r.Flags = $flags
    }

    return $rows
}

# ---------- ATSKAITES SATURS (viens avots logam, Excel un Word) ----------

function Get-InvSections {
    param($Row)
    $r = $Row
    $sections = @()

    $s1 = New-Object System.Collections.ArrayList
    [void]$s1.Add((New-InvPair "Inventara numurs" $r.InvNo))
    [void]$s1.Add((New-InvPair "Datora nosaukums" $r.Name))
    [void]$s1.Add((New-InvPair "Grupa" $r.Group))
    [void]$s1.Add((New-InvPair "Atrasanas vieta" $r.Location))
    [void]$s1.Add((New-InvPair "Atbildigais" $r.Responsible))
    [void]$s1.Add((New-InvPair "Veids (manuals)" $r.TypeManual))
    [void]$s1.Add((New-InvPair "Veids (automatiski)" $r.TypeAuto))
    $sections += [PSCustomObject]@{ Title = "Datora dati"; Rows = $s1 }

    $s2 = New-Object System.Collections.ArrayList
    [void]$s2.Add((New-InvPair "Razotajs un modelis" (($r.Manufacturer + " " + $r.Model).Trim())))
    [void]$s2.Add((New-InvPair "Serijas numurs" $r.Serial))
    [void]$s2.Add((New-InvPair "BIOS" $r.BiosText))
    [void]$s2.Add((New-InvPair "Mateplate" $r.BoardText))
    [void]$s2.Add((New-InvPair "Procesors" $r.CpuText))
    [void]$s2.Add((New-InvPair "Atmina kopa" $r.RamText))
    foreach ($line in $r.RamLines) { [void]$s2.Add((New-InvPair "Atminas modulis" $line)) }
    foreach ($line in $r.DiskLines) { [void]$s2.Add((New-InvPair "Disks" $line)) }
    foreach ($line in $r.VolLines) { [void]$s2.Add((New-InvPair "Disku vieta" $line)) }
    foreach ($line in $r.GpuLines) { [void]$s2.Add((New-InvPair "Video karte" $line)) }
    foreach ($line in $r.MonLines) { [void]$s2.Add((New-InvPair "Monitors" $line)) }
    foreach ($na in $r.NetAdapters) {
        [void]$s2.Add((New-InvPair "Tikla adapteris" ("{0} | {1} | {2}" -f $na.Description, $na.Status, $na.LinkSpeed)))
        [void]$s2.Add((New-InvPair "MAC adrese" $na.Mac))
        [void]$s2.Add((New-InvPair "IP adrese" $na.Ip))
    }
    $sections += [PSCustomObject]@{ Title = "Aparatura"; Rows = $s2 }

    $s3 = New-Object System.Collections.ArrayList
    [void]$s3.Add((New-InvPair "Operacijas sistema" (($r.OsCaption + " " + $r.OsEdition).Trim())))
    [void]$s3.Add((New-InvPair "Versija un build" $r.WinText))
    [void]$s3.Add((New-InvPair "Aktivizacija" $r.Activation))
    [void]$s3.Add((New-InvPair "Uzstadisanas datums" $r.OsInstall))
    [void]$s3.Add((New-InvPair "Pedeja ieslegsana" $r.LastBoot))
    $pendingText = "Ne"
    if ($r.PendingReboot) { $pendingText = "Ja" }
    [void]$s3.Add((New-InvPair "Gaida restartu" $pendingText))
    [void]$s3.Add((New-InvPair "Inventars ievacts" $r.CollectedText))
    $sections += [PSCustomObject]@{ Title = "Windows"; Rows = $s3 }

    $s4 = New-Object System.Collections.ArrayList
    if ($r.Flags.Count -eq 0) {
        [void]$s4.Add((New-InvPair "Atzimes" "Nav"))
    } else {
        foreach ($f in $r.Flags) { [void]$s4.Add((New-InvPair "Atzime" $f)) }
    }
    $sections += [PSCustomObject]@{ Title = "Atzimes"; Rows = $s4 }

    return $sections
}

function Get-InvKeyAppRows {
    param($Row)
    $out = @()
    $winNote = ""
    if ($Row.WinOld) { $winNote = "atpaliek (novecojis laidiens)" }
    elseif ($Row.WinLag) { $winNote = "atpaliek (nav jaunako labojumu)" }
    elseif ($Row.WinAhead) { $winNote = "jaunaka neka vairakumam" }
    $out += [PSCustomObject]@{ App = "Windows"; Version = $Row.WinText; Note = $winNote }
    foreach ($k in $Row.KeyApps) {
        $note = ""
        if (($k.App -eq "ESET") -and $Row.EsetLag) { $note = "atpaliek" }
        if ($k.Count -gt 1) {
            if ($note -ne "") { $note = $note + "; " }
            $note = $note + "vairakas versijas: " + $k.Versions
        }
        $ver = $k.Version
        if (($k.App -eq "ESET") -and ($Row.EsetVer -ne "")) { $ver = $Row.EsetVer }
        if (($k.App -eq "Office") -and ($Row.OfficeText -ne "")) { $ver = $Row.OfficeText }
        if ($ver -eq "") { $ver = "nav atrasts" }
        $out += [PSCustomObject]@{ App = $k.App; Version = $ver; Note = $note }
    }
    return $out
}

function Get-InvProgramRows {
    param($Row, [bool]$ShowAll)
    $out = @()
    foreach ($p in $Row.Programs) {
        $name = Get-InvText $p.Name
        if ((-not $ShowAll) -and ($name -match $script:InvNoiseRegex)) { continue }
        $out += [PSCustomObject]@{
            Name      = $name
            Version   = (Get-InvText $p.Version)
            Scope     = (Get-InvText $p.Scope)
            Publisher = (Get-InvText $p.Publisher)
        }
    }
    return $out
}

function Get-InvHistoryRows {
    param($Row)
    $out = @()
    foreach ($h in $Row.History) {
        $reboot = "Ne"
        if ((Get-InvProp $h @("RebootRequired")) -eq $true) { $reboot = "Ja" }
        $out += [PSCustomObject]@{
            Time           = (Get-InvText (Get-InvProp $h @("Time")))
            Result         = (Get-InvText (Get-InvProp $h @("Result")))
            Installed      = ((@(Get-InvArray (Get-InvProp $h @("Installed"))) | ForEach-Object { Get-InvText $_ }) -join "; ")
            Failed         = ((@(Get-InvArray (Get-InvProp $h @("Failed"))) | ForEach-Object { Get-InvText $_ }) -join "; ")
            WindowsUpdates = ((@(Get-InvArray (Get-InvProp $h @("WindowsUpdates"))) | ForEach-Object { Get-InvText $_ }) -join "; ")
            Reboot         = $reboot
        }
    }
    if ($out.Count -eq 0) {
        $out += [PSCustomObject]@{ Time = "Vesture vel nav (aizpildisies pec nakama reala cikla)"; Result = ""; Installed = ""; Failed = ""; WindowsUpdates = ""; Reboot = "" }
    }
    return $out
}

# ---------- EKSPORTS ----------

function Get-InvSavePath {
    param([string]$Filter, [string]$DefaultName)
    $dlg = New-Object System.Windows.Forms.SaveFileDialog
    $dlg.Filter = $Filter
    $dlg.FileName = $DefaultName
    $dlg.InitialDirectory = [Environment]::GetFolderPath("MyDocuments")
    $dlg.OverwritePrompt = $true
    if ($dlg.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) { return $dlg.FileName }
    return ""
}

function Get-InvSafeSheetName {
    param([string]$Name)
    $clean = ($Name -replace '[\[\]\:\*\?\/\\]', '')
    if ($clean.Length -gt 31) { $clean = $clean.Substring(0, 31) }
    if ($clean -eq "") { $clean = "Lapa" }
    return $clean
}

function Export-InvExcelWorkbook {
    # $Sheets: masivs ar hashtable @{ Name = ...; Header = @(...); Rows = ArrayList no masiviem }
    param([string]$Path, $Sheets)

    $xl = $null
    $wb = $null
    try {
        $xl = New-Object -ComObject Excel.Application
        $xl.Visible = $false
        $xl.DisplayAlerts = $false
        $wb = $xl.Workbooks.Add()

        $first = $true
        foreach ($sheet in $Sheets) {
            if ($first) {
                $ws = $wb.Worksheets.Item(1)
                $first = $false
            } else {
                $ws = $wb.Worksheets.Add([System.Reflection.Missing]::Value, $wb.Worksheets.Item($wb.Worksheets.Count))
            }
            $ws.Name = (Get-InvSafeSheetName $sheet.Name)
            $ws.Cells.NumberFormat = "@"

            $colCount = $sheet.Header.Count
            $rowCount = 1 + $sheet.Rows.Count
            $data = New-Object 'object[,]' $rowCount, $colCount
            for ($c = 0; $c -lt $colCount; $c++) { $data[0, $c] = [string]$sheet.Header[$c] }
            for ($r = 0; $r -lt $sheet.Rows.Count; $r++) {
                $rowArr = $sheet.Rows[$r]
                for ($c = 0; $c -lt $colCount; $c++) {
                    $val = ""
                    if ($c -lt $rowArr.Count) { $val = [string]$rowArr[$c] }
                    $data[($r + 1), $c] = $val
                }
            }
            $range = $ws.Range($ws.Cells.Item(1, 1), $ws.Cells.Item($rowCount, $colCount))
            $range.Value2 = $data
            $ws.Rows.Item(1).Font.Bold = $true
            [void]$ws.Columns.AutoFit()
            for ($c = 1; $c -le $colCount; $c++) {
                $col = $ws.Columns.Item($c)
                if ($col.ColumnWidth -gt 70) { $col.ColumnWidth = 70 }
            }
        }

        $wb.SaveAs($Path, 51)
        return $true
    } finally {
        try { if ($wb) { $wb.Close($false) } } catch { }
        try { if ($xl) { $xl.Quit() } } catch { }
        try { if ($wb) { [void][System.Runtime.InteropServices.Marshal]::ReleaseComObject($wb) } } catch { }
        try { if ($xl) { [void][System.Runtime.InteropServices.Marshal]::ReleaseComObject($xl) } } catch { }
        [GC]::Collect()
        [GC]::WaitForPendingFinalizers()
    }
}

function ConvertTo-InvHtmlText {
    # Aizstaj specialas un ne-ASCII rakstzimes ar HTML kodiem (neatkarigi no kodejuma)
    param($Value)
    $s = [string]$Value
    $sb = New-Object System.Text.StringBuilder
    foreach ($ch in $s.ToCharArray()) {
        $code = [int]$ch
        if ($code -eq 38) { [void]$sb.Append("&amp;") }
        elseif ($code -eq 60) { [void]$sb.Append("&lt;") }
        elseif ($code -eq 62) { [void]$sb.Append("&gt;") }
        elseif ($code -eq 34) { [void]$sb.Append("&quot;") }
        elseif ($code -gt 126) { [void]$sb.Append("&#" + $code + ";") }
        else { [void]$sb.Append($ch) }
    }
    return $sb.ToString()
}

function Add-InvHtmlTable {
    param($Builder, [string[]]$Header, $Rows)
    [void]$Builder.AppendLine("<table border='1' cellspacing='0' cellpadding='4' style='border-collapse:collapse;font-size:10pt'>")
    $h = "<tr>"
    foreach ($c in $Header) { $h = $h + "<th style='background:#1F3A5F;color:#FFFFFF;text-align:left'>" + (ConvertTo-InvHtmlText $c) + "</th>" }
    [void]$Builder.AppendLine($h + "</tr>")
    foreach ($row in $Rows) {
        $line = "<tr>"
        foreach ($cell in $row) { $line = $line + "<td>" + (ConvertTo-InvHtmlText $cell) + "</td>" }
        [void]$Builder.AppendLine($line + "</tr>")
    }
    [void]$Builder.AppendLine("</table>")
}

function Get-InvHtml {
    param($Rows, [string]$Title)
    $sb = New-Object System.Text.StringBuilder
    [void]$sb.AppendLine("<html><head><meta charset='utf-8'><title>" + (ConvertTo-InvHtmlText $Title) + "</title></head>")
    [void]$sb.AppendLine("<body style='font-family:Calibri,Arial,sans-serif;font-size:11pt'>")
    [void]$sb.AppendLine("<h1>" + (ConvertTo-InvHtmlText $Title) + "</h1>")
    [void]$sb.AppendLine("<p>Izveidots: " + (Get-Date).ToString("dd.MM.yyyy HH:mm") + "</p>")

    $first = $true
    foreach ($r in $Rows) {
        $style = ""
        if (-not $first) { $style = " style='page-break-before:always'" }
        $first = $false
        [void]$sb.AppendLine("<h2" + $style + ">Dators: " + (ConvertTo-InvHtmlText $r.Name) + "</h2>")

        foreach ($sec in (Get-InvSections -Row $r)) {
            [void]$sb.AppendLine("<h3>" + (ConvertTo-InvHtmlText $sec.Title) + "</h3>")
            $tbl = @()
            foreach ($p in $sec.Rows) { $tbl += , @($p.Label, $p.Value) }
            Add-InvHtmlTable -Builder $sb -Header @("Lauks", "Vertiba") -Rows $tbl
        }

        [void]$sb.AppendLine("<h3>Pamata programmatura</h3>")
        $tbl = @()
        foreach ($k in (Get-InvKeyAppRows -Row $r)) { $tbl += , @($k.App, $k.Version, $k.Note) }
        Add-InvHtmlTable -Builder $sb -Header @("Programma", "Versija", "Piezime") -Rows $tbl

        [void]$sb.AppendLine("<h3>Pedejie atjauninasanas cikli</h3>")
        $tbl = @()
        foreach ($h in (Get-InvHistoryRows -Row $r)) { $tbl += , @($h.Time, $h.Result, $h.Installed, $h.Failed, $h.WindowsUpdates, $h.Reboot) }
        Add-InvHtmlTable -Builder $sb -Header @("Laiks", "Rezultats", "Instalets", "Kludas", "Windows atjauninajumi", "Restarts") -Rows $tbl

        [void]$sb.AppendLine("<h3>Instaletas programmas</h3>")
        $tbl = @()
        foreach ($p in (Get-InvProgramRows -Row $r -ShowAll $false)) { $tbl += , @($p.Name, $p.Version, $p.Scope, $p.Publisher) }
        Add-InvHtmlTable -Builder $sb -Header @("Programma", "Versija", "Tverums", "Izdevejs") -Rows $tbl
    }

    [void]$sb.AppendLine("</body></html>")
    return $sb.ToString()
}

function Export-InvToWord {
    param($Rows, [string]$Title, [string]$DocxPath)

    $html = Get-InvHtml -Rows $Rows -Title $Title
    $htmlPath = Join-Path $env:TEMP ("inv-report-" + (Get-Date -Format "yyyyMMdd-HHmmss") + ".html")
    [System.IO.File]::WriteAllText($htmlPath, $html, (New-Object System.Text.UTF8Encoding($true)))

    $word = $null
    $doc = $null
    $ok = $false
    try {
        $word = New-Object -ComObject Word.Application
        $word.Visible = $false
        $word.DisplayAlerts = 0
        $doc = $word.Documents.Open($htmlPath)
        try {
            $doc.SaveAs2($DocxPath, 16)
        } catch {
            $doc.SaveAs([ref]$DocxPath, [ref]16)
        }
        $ok = $true
    } catch {
        $ok = $false
    } finally {
        try { if ($doc) { $doc.Close($false) } } catch { }
        try { if ($word) { $word.Quit() } } catch { }
        try { if ($doc) { [void][System.Runtime.InteropServices.Marshal]::ReleaseComObject($doc) } } catch { }
        try { if ($word) { [void][System.Runtime.InteropServices.Marshal]::ReleaseComObject($word) } } catch { }
        [GC]::Collect()
        [GC]::WaitForPendingFinalizers()
    }

    if ($ok) {
        try { Remove-Item -Path $htmlPath -Force -ErrorAction SilentlyContinue } catch { }
        return ""
    }
    return $htmlPath
}

function Export-InvListToExcel {
    param($Rows, [string]$Path)

    $sheets = @()

    $s1 = New-Object System.Collections.ArrayList
    foreach ($r in $Rows) {
        [void]$s1.Add(@($r.InvNo, $r.Name, $r.IpText, $r.MacText, $r.Group, $r.Location, $r.TypeManual, $r.TypeAuto, $r.Responsible, $r.WinText, $r.EsetVer, $r.OfficeText, $r.CollectedText, ($r.Flags -join "; ")))
    }
    $sheets += @{ Name = "Datori"; Header = @("Inv. nr.", "Dators", "IP adrese", "MAC adrese", "Grupa", "Atrasanas vieta", "Veids (manuals)", "Veids (automatiski)", "Atbildigais", "Windows", "ESET", "Office", "Pedeja ievaksana", "Atzimes"); Rows = $s1 }

    $s2 = New-Object System.Collections.ArrayList
    foreach ($r in $Rows) {
        [void]$s2.Add(@($r.Name, $r.WinText, (Get-InvAppVersion $r "ESET"), (Get-InvAppVersion $r "Office"), (Get-InvAppVersion $r "Chrome"), (Get-InvAppVersion $r "Edge"), (Get-InvAppVersion $r "Firefox"), (Get-InvAppVersion $r "Zoom"), (Get-InvAppVersion $r "VLC"), (Get-InvAppVersion $r "TeamViewer"), (Get-InvAppVersion $r "eParakstitajs")))
    }
    $sheets += @{ Name = "Programmatura"; Header = @("Dators", "Windows", "ESET", "Office", "Chrome", "Edge", "Firefox", "Zoom", "VLC", "TeamViewer", "eParakstitajs"); Rows = $s2 }

    $s3 = New-Object System.Collections.ArrayList
    foreach ($r in $Rows) {
        [void]$s3.Add(@($r.Name, ($r.Manufacturer + " " + $r.Model).Trim(), $r.Serial, $r.BiosText, $r.BoardText, $r.CpuText, $r.RamText, ($r.DiskLines -join " | "), ($r.VolLines -join " | "), ($r.GpuLines -join " | "), ($r.MonLines -join " | "), (($r.NetAdapters | ForEach-Object { $_.Description }) -join " | "), (($r.NetAdapters | ForEach-Object { $_.LinkSpeed }) -join " | "), $r.MacText, $r.IpText))
    }
    $sheets += @{ Name = "Aparatura"; Header = @("Dators", "Razotajs un modelis", "Serijas nr.", "BIOS", "Mateplate", "Procesors", "Atmina", "Diski", "Disku vieta", "Video karte", "Monitori", "Tikla adapteris", "Savienojuma atrums", "MAC adrese", "IP adrese"); Rows = $s3 }

    $s5 = New-Object System.Collections.ArrayList
    foreach ($r in $Rows) {
        foreach ($na in $r.NetAdapters) {
            [void]$s5.Add(@($r.Name, $na.Description, $na.Status, $na.LinkSpeed, $na.Mac, $na.Ip))
        }
    }
    $sheets += @{ Name = "Tikls"; Header = @("Dators", "Adapteris", "Statuss", "Savienojuma atrums", "MAC adrese", "IP adrese"); Rows = $s5 }

    $s4 = New-Object System.Collections.ArrayList
    foreach ($r in $Rows) {
        foreach ($p in (Get-InvProgramRows -Row $r -ShowAll $true)) {
            [void]$s4.Add(@($r.Name, $p.Name, $p.Version, $p.Scope, $p.Publisher))
        }
    }
    $sheets += @{ Name = "Visas programmas"; Header = @("Dators", "Programma", "Versija", "Tverums", "Izdevejs"); Rows = $s4 }

    return (Export-InvExcelWorkbook -Path $Path -Sheets $sheets)
}

function Export-InvComputerToExcel {
    param($Row, [string]$Path)

    $sheets = @()

    $s1 = New-Object System.Collections.ArrayList
    foreach ($sec in (Get-InvSections -Row $Row)) {
        foreach ($p in $sec.Rows) { [void]$s1.Add(@($sec.Title, $p.Label, $p.Value)) }
    }
    $sheets += @{ Name = "Kopsavilkums"; Header = @("Sadala", "Lauks", "Vertiba"); Rows = $s1 }

    $s2 = New-Object System.Collections.ArrayList
    foreach ($k in (Get-InvKeyAppRows -Row $Row)) { [void]$s2.Add(@($k.App, $k.Version, $k.Note)) }
    $sheets += @{ Name = "Pamata programmatura"; Header = @("Programma", "Versija", "Piezime"); Rows = $s2 }

    $s3 = New-Object System.Collections.ArrayList
    foreach ($p in (Get-InvProgramRows -Row $Row -ShowAll $true)) { [void]$s3.Add(@($p.Name, $p.Version, $p.Scope, $p.Publisher)) }
    $sheets += @{ Name = "Visas programmas"; Header = @("Programma", "Versija", "Tverums", "Izdevejs"); Rows = $s3 }

    $s4 = New-Object System.Collections.ArrayList
    foreach ($h in (Get-InvHistoryRows -Row $Row)) { [void]$s4.Add(@($h.Time, $h.Result, $h.Installed, $h.Failed, $h.WindowsUpdates, $h.Reboot)) }
    $sheets += @{ Name = "Atjauninasanas cikli"; Header = @("Laiks", "Rezultats", "Instalets", "Kludas", "Windows atjauninajumi", "Restarts"); Rows = $s4 }

    return (Export-InvExcelWorkbook -Path $Path -Sheets $sheets)
}

function Show-InvExportResult {
    param([string]$What, [string]$Path)
    [System.Windows.Forms.MessageBox]::Show(($What + " saglabats:" + [Environment]::NewLine + $Path), "Eksports", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information) | Out-Null
}

function Invoke-InvExportExcel {
    param($Rows, [string]$DefaultName, [bool]$Single)
    $path = Get-InvSavePath -Filter "Excel darbgramata (*.xlsx)|*.xlsx" -DefaultName $DefaultName
    if ($path -eq "") { return }
    try {
        if ($Single) { [void](Export-InvComputerToExcel -Row $Rows[0] -Path $path) }
        else { [void](Export-InvListToExcel -Rows $Rows -Path $path) }
        Show-InvExportResult -What "Excel fails" -Path $path
    } catch {
        [System.Windows.Forms.MessageBox]::Show("Neizdevas izveidot Excel failu. Vai Excel ir uzstadits? Kluda: " + $_.Exception.Message, "Kluda", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error) | Out-Null
    }
}

function Invoke-InvExportWord {
    param($Rows, [string]$Title, [string]$DefaultName)
    $path = Get-InvSavePath -Filter "Word dokuments (*.docx)|*.docx" -DefaultName $DefaultName
    if ($path -eq "") { return }
    try {
        $htmlFallback = Export-InvToWord -Rows $Rows -Title $Title -DocxPath $path
        if ($htmlFallback -eq "") {
            Show-InvExportResult -What "Word dokuments" -Path $path
        } else {
            [System.Windows.Forms.MessageBox]::Show(("Neizdevas saglabat .docx (vai Word ir uzstadits?). Atskaite ir saglabata ka HTML, ko var atvert ar Word un saglabat ka dokumentu:" + [Environment]::NewLine + $htmlFallback), "Uzmanibu", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Warning) | Out-Null
        }
    } catch {
        [System.Windows.Forms.MessageBox]::Show("Eksports uz Word neizdevas: " + $_.Exception.Message, "Kluda", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error) | Out-Null
    }
}

# ---------- LOGI ----------

function Set-InvFormSize {
    # Logs nekad nav lielaks par redzamo ekrana laukumu (ar mazu rezervi) un tiek centrets
    param($Form, [int]$DesiredWidth, [int]$DesiredHeight)
    $wa = [System.Windows.Forms.Screen]::PrimaryScreen.WorkingArea
    $w = [math]::Min($DesiredWidth, [int]($wa.Width * 0.96))
    $h = [math]::Min($DesiredHeight, [int]($wa.Height * 0.92))
    $x = $wa.Left + [int](($wa.Width - $w) / 2)
    $y = $wa.Top + [int](($wa.Height - $h) / 2)
    $Form.StartPosition = [System.Windows.Forms.FormStartPosition]::Manual
    $Form.Size = New-Object System.Drawing.Size($w, $h)
    $Form.Location = New-Object System.Drawing.Point($x, $y)
}

function New-InvGridControl {
    # Tikai-lasams DataGridView, kas AIZPILDA savu konteineru (Dock = Fill) un vienmer rada ritjoslas.
    # Kolonnas: @(Name, Header, Width); pedeja kolonna aizpilda atlikuso platumu.
    param($Columns, [bool]$Wrap)

    $g = New-Object System.Windows.Forms.DataGridView
    $g.Dock = [System.Windows.Forms.DockStyle]::Fill
    $g.AllowUserToAddRows = $false
    $g.AllowUserToDeleteRows = $false
    $g.ReadOnly = $true
    $g.RowHeadersVisible = $false
    $g.MultiSelect = $false
    $g.SelectionMode = [System.Windows.Forms.DataGridViewSelectionMode]::FullRowSelect
    $g.AutoSizeColumnsMode = [System.Windows.Forms.DataGridViewAutoSizeColumnsMode]::None
    $g.ScrollBars = [System.Windows.Forms.ScrollBars]::Both
    $g.BackgroundColor = [System.Drawing.Color]::White

    if ($Wrap) {
        # garie teksti tiek parnesti uz nakamo rindu, lai VISS saturs butu redzams
        $g.DefaultCellStyle.WrapMode = [System.Windows.Forms.DataGridViewTriState]::True
        $g.AutoSizeRowsMode = [System.Windows.Forms.DataGridViewAutoSizeRowsMode]::AllCells
    }

    $cols = @()
    foreach ($c in $Columns) {
        $col = New-Object System.Windows.Forms.DataGridViewTextBoxColumn
        $col.Name = $c[0]
        $col.HeaderText = $c[1]
        $col.Width = [int]$c[2]
        $col.ReadOnly = $true
        $cols += $col
    }
    $g.Columns.AddRange([System.Windows.Forms.DataGridViewColumn[]]$cols)
    $g.Columns[$g.Columns.Count - 1].AutoSizeMode = [System.Windows.Forms.DataGridViewAutoSizeColumnMode]::Fill
    return $g
}

function New-InvBottomPanel {
    # Apaksejaa josla pogam (Dock = Bottom)
    $pnl = New-Object System.Windows.Forms.Panel
    $pnl.Dock = [System.Windows.Forms.DockStyle]::Bottom
    $pnl.Height = 50
    return $pnl
}

function Show-ComputerReport {
    param($Row)

    $script:invDetailRow = $Row

    $dlg = New-Object System.Windows.Forms.Form
    $dlg.AutoScaleMode = [System.Windows.Forms.AutoScaleMode]::None
    $dlg.Text = "Datora atskaite - " + $Row.Name
    $dlg.MinimumSize = New-Object System.Drawing.Size(700, 450)
    Set-InvFormSize -Form $dlg -DesiredWidth 1150 -DesiredHeight 800

    $tabs = New-Object System.Windows.Forms.TabControl
    $tabs.Dock = [System.Windows.Forms.DockStyle]::Fill

    # --- 1. cilne: aparatura un Windows ---
    $tab1 = New-Object System.Windows.Forms.TabPage
    $tab1.Text = "Aparatura un Windows"
    $g1 = New-InvGridControl -Columns @(@("Label", "Lauks", 240), @("Value", "Vertiba", 700)) -Wrap $true
    foreach ($sec in (Get-InvSections -Row $Row)) {
        $i = $g1.Rows.Add($sec.Title.ToUpper(), "")
        $g1.Rows[$i].DefaultCellStyle.BackColor = [System.Drawing.Color]::FromArgb(222, 230, 240)
        $g1.Rows[$i].DefaultCellStyle.Font = New-Object System.Drawing.Font($g1.Font, [System.Drawing.FontStyle]::Bold)
        foreach ($p in $sec.Rows) { [void]$g1.Rows.Add($p.Label, $p.Value) }
    }
    # manualie lauki (dzeltenie) ir labojami; pareja tabula ir tikai lasama
    $editMap = @{
        "Inventara numurs" = "InventoryNumber"
        "Grupa"            = "Group"
        "Atrasanas vieta"  = "Location"
        "Atbildigais"      = "Responsible"
        "Veids (manuals)"  = "Type"
    }
    $editColor = [System.Drawing.Color]::FromArgb(255, 249, 196)
    $g1.ReadOnly = $false
    $g1.Columns["Value"].ReadOnly = $false
    $g1.EditMode = [System.Windows.Forms.DataGridViewEditMode]::EditOnKeystrokeOrF2
    $g1.SelectionMode = [System.Windows.Forms.DataGridViewSelectionMode]::CellSelect
    $fieldByRow = @{}
    foreach ($gr in $g1.Rows) {
        $lab = [string]$gr.Cells["Label"].Value
        if ($editMap.ContainsKey($lab)) {
            $fieldByRow[$gr.Index] = $editMap[$lab]
            $gr.Cells["Value"].Style.BackColor = $editColor
        } else {
            $gr.Cells["Value"].ReadOnly = $true
        }
    }
    $script:invCardGrid = $g1
    $script:invCardFields = $fieldByRow
    $script:invCardDirty = $false
    $script:invCardChanged = $false
    $g1.Add_CellEndEdit({
        param($sender, $e)
        if ($script:invCardFields.ContainsKey($e.RowIndex)) { $script:invCardDirty = $true }
    })
    $tab1.Controls.Add($g1)
    [void]$tabs.TabPages.Add($tab1)

    # --- 2. cilne: programmas ---
    $tab2 = New-Object System.Windows.Forms.TabPage
    $tab2.Text = "Programmas"
    $g2 = New-InvGridControl -Columns @(@("Name", "Programma", 380), @("Version", "Versija", 140), @("Scope", "Tverums", 170), @("Publisher", "Izdevejs", 300)) -Wrap $false
    $chk = New-Object System.Windows.Forms.CheckBox
    $chk.Text = "Radit visas programmas (ari tehniskas: draiveri, Visual C++ u.c.)"
    $chk.Location = New-Object System.Drawing.Point(8, 6)
    $chk.Size = New-Object System.Drawing.Size(600, 22)
    $chkPanel = New-Object System.Windows.Forms.Panel
    $chkPanel.Dock = [System.Windows.Forms.DockStyle]::Top
    $chkPanel.Height = 34
    $chkPanel.Controls.Add($chk)
    # vispirms aizpildosais (Fill), tad augseja josla (Top), lai Fill aizpilda atlikuso vietu
    $tab2.Controls.Add($g2)
    $tab2.Controls.Add($chkPanel)
    [void]$tabs.TabPages.Add($tab2)
    $script:invProgramsGrid = $g2
    $script:invProgramsCheck = $chk

    $fillPrograms = {
        $grid = $script:invProgramsGrid
        $grid.Rows.Clear()
        $row = $script:invDetailRow

        $i = $grid.Rows.Add("PAMATA PROGRAMMATURA", "", "", "")
        $grid.Rows[$i].DefaultCellStyle.BackColor = [System.Drawing.Color]::FromArgb(222, 230, 240)
        $grid.Rows[$i].DefaultCellStyle.Font = New-Object System.Drawing.Font($grid.Font, [System.Drawing.FontStyle]::Bold)
        foreach ($k in (Get-InvKeyAppRows -Row $row)) {
            $j = $grid.Rows.Add($k.App, $k.Version, "", $k.Note)
            if ($k.Note -like "*atpaliek*") { $grid.Rows[$j].DefaultCellStyle.BackColor = [System.Drawing.Color]::FromArgb(255, 224, 178) }
        }

        $i = $grid.Rows.Add("INSTALETAS PROGRAMMAS", "", "", "")
        $grid.Rows[$i].DefaultCellStyle.BackColor = [System.Drawing.Color]::FromArgb(222, 230, 240)
        $grid.Rows[$i].DefaultCellStyle.Font = New-Object System.Drawing.Font($grid.Font, [System.Drawing.FontStyle]::Bold)
        foreach ($p in (Get-InvProgramRows -Row $row -ShowAll ([bool]$script:invProgramsCheck.Checked))) {
            [void]$grid.Rows.Add($p.Name, $p.Version, $p.Scope, $p.Publisher)
        }
    }
    $chk.Add_CheckedChanged($fillPrograms)
    & $fillPrograms

    # --- 3. cilne: atjauninasanas cikli ---
    $tab3 = New-Object System.Windows.Forms.TabPage
    $tab3.Text = "Atjauninasanas cikli"
    $g3 = New-InvGridControl -Columns @(@("Time", "Laiks", 140), @("Result", "Rezultats", 100), @("Installed", "Instaleta programmatura", 280), @("Failed", "Kludas", 150), @("Wu", "Windows atjauninajumi", 260), @("Reboot", "Restarts", 80)) -Wrap $true
    foreach ($h in (Get-InvHistoryRows -Row $Row)) {
        [void]$g3.Rows.Add($h.Time, $h.Result, $h.Installed, $h.Failed, $h.WindowsUpdates, $h.Reboot)
    }
    $lbl = New-Object System.Windows.Forms.Label
    $lbl.Dock = [System.Windows.Forms.DockStyle]::Fill
    $lbl.Padding = New-Object System.Windows.Forms.Padding(8, 6, 8, 0)
    $script:invCmdBase = (("Pedeja redzets: {0}     Pedejais cikls: {1}     Rezultats: {2}" -f $Row.StatusLastCheck, $Row.StatusLastCycle, $Row.StatusLastResult) + [Environment]::NewLine + $Row.StatusDetails)
    $lbl.Text = ($script:invCmdBase + [Environment]::NewLine + (Get-InvCommandText -NasRoot $script:invNasRoot -Name $Row.Name))
    $script:invCmdLabel = $lbl
    $lblPanel = New-Object System.Windows.Forms.Panel
    $lblPanel.Dock = [System.Windows.Forms.DockStyle]::Top
    $lblPanel.Height = 70
    $lblPanel.Controls.Add($lbl)
    $tab3.Controls.Add($g3)
    $tab3.Controls.Add($lblPanel)
    [void]$tabs.TabPages.Add($tab3)

    # --- apaksejaa pogu josla ---
    $pnl = New-InvBottomPanel

    $btnExcel = New-Object System.Windows.Forms.Button
    $btnExcel.Text = "Eksports uz Excel"
    $btnExcel.Location = New-Object System.Drawing.Point(10, 9)
    $btnExcel.Size = New-Object System.Drawing.Size(160, 32)
    $btnExcel.Add_Click({
        $r = $script:invDetailRow
        Invoke-InvExportExcel -Rows @($r) -DefaultName ("Dators-" + $r.Name + "-" + (Get-Date -Format "yyyy-MM-dd") + ".xlsx") -Single $true
    })
    $pnl.Controls.Add($btnExcel)

    $btnWord = New-Object System.Windows.Forms.Button
    $btnWord.Text = "Eksports uz Word"
    $btnWord.Location = New-Object System.Drawing.Point(180, 9)
    $btnWord.Size = New-Object System.Drawing.Size(160, 32)
    $btnWord.Add_Click({
        $r = $script:invDetailRow
        Invoke-InvExportWord -Rows @($r) -Title ("Datora atskaite: " + $r.Name) -DefaultName ("Dators-" + $r.Name + "-" + (Get-Date -Format "yyyy-MM-dd") + ".docx")
    })
    $pnl.Controls.Add($btnWord)

    $btnSave = New-Object System.Windows.Forms.Button
    $btnSave.Text = "Saglabat manualos laukus"
    $btnSave.Location = New-Object System.Drawing.Point(350, 9)
    $btnSave.Size = New-Object System.Drawing.Size(200, 32)
    $btnSave.Add_Click({
        $r = $script:invDetailRow
        $g = $script:invCardGrid
        try { [void]$g.EndEdit() } catch { }
        $vals = @{}
        foreach ($idx in $script:invCardFields.Keys) {
            $vals[$script:invCardFields[$idx]] = ([string]$g.Rows[$idx].Cells["Value"].Value).Trim()
        }
        $vals["Type"] = ConvertTo-InvTypeCode $vals["Type"]
        try {
            Save-InvManualEntry -NasRoot $script:invNasRoot -Name $r.Name -Fields $vals
        } catch {
            [void][System.Windows.Forms.MessageBox]::Show("Neizdevas saglabat: " + $_.Exception.Message + [Environment]::NewLine + "(Ja inventory-manual.csv ir atverts Excel, aizver to.)", "Kluda", "OK", "Error")
            return
        }
        $r.InvNo = $vals["InventoryNumber"]
        $r.Group = $vals["Group"]
        $r.Location = $vals["Location"]
        $r.Responsible = $vals["Responsible"]
        $r.TypeManualCode = $vals["Type"]
        $r.TypeManual = ConvertTo-InvTypeText $vals["Type"]
        foreach ($idx in $script:invCardFields.Keys) {
            if ($script:invCardFields[$idx] -eq "Type") { $g.Rows[$idx].Cells["Value"].Value = $r.TypeManual }
        }
        $script:invCardDirty = $false
        $script:invCardChanged = $true
        [void][System.Windows.Forms.MessageBox]::Show("Saglabats: Config\inventory-manual.csv", "Gatavs", "OK", "Information")
    })
    $pnl.Controls.Add($btnSave)

    $btnClose = New-Object System.Windows.Forms.Button
    $btnClose.Text = "Aizvert"
    $btnNow = New-Object System.Windows.Forms.Button
    $btnNow.Text = "Atjaunot tagad"
    $btnNow.Location = New-Object System.Drawing.Point(560, 9)
    $btnNow.Size = New-Object System.Drawing.Size(160, 32)
    $btnNow.Add_Click({
        $r = $script:invDetailRow
        if (Invoke-InvUpdateNow -Rows @($r)) {
            $script:invCmdLabel.Text = ($script:invCmdBase + [Environment]::NewLine + (Get-InvCommandText -NasRoot $script:invNasRoot -Name $r.Name))
        }
    })
    $pnl.Controls.Add($btnNow)
    Add-InvPowerButtons -Panel $pnl -GetRows { @($script:invDetailRow) }

    $btnClose.Location = New-Object System.Drawing.Point(730, 9)
    $btnClose.Size = New-Object System.Drawing.Size(160, 32)
    $btnClose.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
    $pnl.Controls.Add($btnClose)
    $dlg.CancelButton = $btnClose

    $dlg.Add_FormClosing({
        param($sender, $e)
        if ($script:invCardDirty) {
            $ans = [System.Windows.Forms.MessageBox]::Show("Ir nesaglabatas izmainas. Aizvert bez saglabasanas?", "Nesaglabatas izmainas", "YesNo", "Question")
            if ($ans -ne [System.Windows.Forms.DialogResult]::Yes) { $e.Cancel = $true }
        }
    })

    # vispirms aizpildosais (Fill), tad apaksejaa josla (Bottom)
    $dlg.Controls.Add($tabs)
    $dlg.Controls.Add($pnl)

    [void]$dlg.ShowDialog()

    # ja manualie lauki mainiti - atjaunojam sarakstu
    if ($script:invCardChanged -and $script:invGrid) { Update-InvGrid }
}

function Update-InvGrid {
    $script:invSummary.Text = "Ielade datus no NAS..."
    [System.Windows.Forms.Application]::DoEvents()

    try {
        $rows = @(Get-InvRows -NasRoot $script:invNasRoot)
    } catch {
        $script:invSummary.Text = "Kluda, nolasot datus: " + $_.Exception.Message
        return
    }
    $script:invRows = $rows

    $colorOrange = [System.Drawing.Color]::FromArgb(255, 224, 178)
    $colorGray = [System.Drawing.Color]::FromArgb(238, 238, 238)
    $colorGreen = [System.Drawing.Color]::FromArgb(220, 242, 214)
    $colorRed = [System.Drawing.Color]::FromArgb(255, 171, 145)

    $grid = $script:invGrid
    $grid.Rows.Clear()
    $withInv = 0
    $flagged = 0

    foreach ($r in $rows) {
        $i = $grid.Rows.Add()
        $gr = $grid.Rows[$i]
        $gr.Tag = $r
        $gr.Cells["InvNo"].Value = $r.InvNo
        $gr.Cells["Name"].Value = $r.Name
        $gr.Cells["Ip"].Value = $r.IpText
        $gr.Cells["Mac"].Value = $r.MacText
        $gr.Cells["Group"].Value = $r.Group
        $gr.Cells["Type"].Value = $r.TypeManual
        $gr.Cells["Responsible"].Value = $r.Responsible
        $gr.Cells["Windows"].Value = $r.WinText
        $gr.Cells["Eset"].Value = $r.EsetVer
        $gr.Cells["Office"].Value = $r.OfficeText
        $gr.Cells["Collected"].Value = $r.CollectedText
        $gr.Cells["Flags"].Value = ($r.Flags -join "; ")
        $gr.Cells["Flags"].ToolTipText = ($r.Flags -join "; ")

        if ($r.HasInv) { $withInv++ } else { $gr.DefaultCellStyle.BackColor = $colorGray }
        if ($r.WinOld) { $gr.Cells["Windows"].Style.BackColor = $colorRed; $gr.Cells["Windows"].ToolTipText = "Novecojis Windows laidiens (vecaks neka vairakumam)" }
        elseif ($r.WinLag) { $gr.Cells["Windows"].Style.BackColor = $colorOrange; $gr.Cells["Windows"].ToolTipText = "Tas pats laidiens, bet nav jaunako labojumu" }
        elseif ($r.WinAhead) { $gr.Cells["Windows"].Style.BackColor = $colorGreen; $gr.Cells["Windows"].ToolTipText = "Jaunaka versija neka vairakumam (preview vai jaunaks laidiens)" }
        if ($r.EsetLag) { $gr.Cells["Eset"].Style.BackColor = $colorOrange }
        if ($r.Flags.Count -gt 0) {
            $flagged++
            if ($r.HasInv) { $gr.Cells["Flags"].Style.BackColor = $colorOrange }
        }
    }

    $script:invSummary.Text = ("Datori: {0}     Ar inventaru: {1}     Ar atzimem: {2}     (dati nolasiti {3})     Dubultklikskis uz datora atver ta atskaiti. Ctrl+klikskis atlasa vairakus datorus komandai." -f $rows.Count, $withInv, $flagged, (Get-Date).ToString("HH:mm:ss"))
}

function Show-InventoryReport {
    param([string]$NasRoot)

    $script:invNasRoot = $NasRoot
    $script:invRows = @()

    $win = New-Object System.Windows.Forms.Form
    $win.AutoScaleMode = [System.Windows.Forms.AutoScaleMode]::None
    $win.Text = "Inventara atskaite - datoru saraksts"
    $win.MinimumSize = New-Object System.Drawing.Size(900, 400)
    Set-InvFormSize -Form $win -DesiredWidth 1340 -DesiredHeight 720

    $summary = New-Object System.Windows.Forms.Label
    $summary.Dock = [System.Windows.Forms.DockStyle]::Top
    $summary.Height = 30
    $summary.TextAlign = [System.Drawing.ContentAlignment]::MiddleLeft
    $summary.Padding = New-Object System.Windows.Forms.Padding(8, 0, 0, 0)
    $script:invSummary = $summary

    $grid = New-InvGridControl -Columns @(
        @("InvNo", "Inv. nr.", 90),
        @("Name", "Dators", 125),
        @("Ip", "IP adrese", 115),
        @("Mac", "MAC adrese", 140),
        @("Group", "Grupa", 120),
        @("Type", "Veids", 90),
        @("Responsible", "Atbildigais", 130),
        @("Windows", "Windows", 160),
        @("Eset", "ESET", 95),
        @("Office", "Office", 200),
        @("Collected", "Pedeja ievaksana", 125),
        @("Flags", "Atzimes", 200)
    ) -Wrap $false
    $grid.MultiSelect = $true
    $script:invGrid = $grid

    # IP adresi kartojam SKAITLISKI (192.168.3.9 pirms 192.168.3.149), nevis ka tekstu
    $grid.Add_SortCompare({
        param($sender, $e)
        if ($e.Column.Name -eq "Ip") {
            $ka = ConvertTo-InvIpSortKey ([string]$e.CellValue1)
            $kb = ConvertTo-InvIpSortKey ([string]$e.CellValue2)
            $e.SortResult = [string]::CompareOrdinal($ka, $kb)
            $e.Handled = $true
        }
    })

    $grid.Add_CellDoubleClick({
        param($sender, $e)
        if ($e.RowIndex -ge 0) {
            $row = $script:invGrid.Rows[$e.RowIndex].Tag
            if ($row) { Show-ComputerReport -Row $row }
        }
    })

    $pnl = New-InvBottomPanel

    $btnRefresh = New-Object System.Windows.Forms.Button
    $btnRefresh.Text = "Atjaunot"
    $btnRefresh.Location = New-Object System.Drawing.Point(10, 9)
    $btnRefresh.Size = New-Object System.Drawing.Size(120, 32)
    $btnRefresh.Add_Click({ Update-InvGrid })
    $pnl.Controls.Add($btnRefresh)

    $btnOpen = New-Object System.Windows.Forms.Button
    $btnOpen.Text = "Atvert datora atskaiti"
    $btnOpen.Location = New-Object System.Drawing.Point(140, 9)
    $btnOpen.Size = New-Object System.Drawing.Size(170, 32)
    $btnOpen.Add_Click({
        $cur = $script:invGrid.CurrentRow
        if ($cur -and $cur.Tag) { Show-ComputerReport -Row $cur.Tag }
    })
    $pnl.Controls.Add($btnOpen)

    $btnExcel = New-Object System.Windows.Forms.Button
    $btnExcel.Text = "Eksports uz Excel (visi)"
    $btnExcel.Location = New-Object System.Drawing.Point(320, 9)
    $btnExcel.Size = New-Object System.Drawing.Size(190, 32)
    $btnExcel.Add_Click({
        if (@($script:invRows).Count -eq 0) { return }
        Invoke-InvExportExcel -Rows @($script:invRows) -DefaultName ("Inventara-saraksts-" + (Get-Date -Format "yyyy-MM-dd") + ".xlsx") -Single $false
    })
    $pnl.Controls.Add($btnExcel)

    $btnWord = New-Object System.Windows.Forms.Button
    $btnWord.Text = "Eksports uz Word (visi)"
    $btnWord.Location = New-Object System.Drawing.Point(520, 9)
    $btnWord.Size = New-Object System.Drawing.Size(190, 32)
    $btnWord.Add_Click({
        if (@($script:invRows).Count -eq 0) { return }
        Invoke-InvExportWord -Rows @($script:invRows) -Title "Datoru inventara atskaite" -DefaultName ("Inventara-atskaite-" + (Get-Date -Format "yyyy-MM-dd") + ".docx")
    })
    $pnl.Controls.Add($btnWord)

    $btnClose = New-Object System.Windows.Forms.Button
    $btnClose.Text = "Aizvert"
    $btnNow = New-Object System.Windows.Forms.Button
    $btnNow.Text = "Atjaunot tagad (iezimetie)"
    $btnNow.Location = New-Object System.Drawing.Point(720, 9)
    $btnNow.Size = New-Object System.Drawing.Size(210, 32)
    $btnNow.Add_Click({
        $sel = @($script:invGrid.SelectedRows | ForEach-Object { $_.Tag })
        [void](Invoke-InvUpdateNow -Rows $sel)
    })
    $pnl.Controls.Add($btnNow)
    Add-InvPowerButtons -Panel $pnl -GetRows { @($script:invGrid.SelectedRows | ForEach-Object { $_.Tag }) }

    $btnClose.Location = New-Object System.Drawing.Point(940, 9)
    $btnClose.Size = New-Object System.Drawing.Size(120, 32)
    $btnClose.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
    $pnl.Controls.Add($btnClose)
    $win.CancelButton = $btnClose

    # vispirms aizpildosais (Fill), tad augseja un apaksejaa josla
    $win.Controls.Add($grid)
    $win.Controls.Add($summary)
    $win.Controls.Add($pnl)

    Update-InvGrid
    [void]$win.ShowDialog()
}
