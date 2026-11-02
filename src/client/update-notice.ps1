<#
============================================================
 update-notice.ps1
 Parada divus NEATKARIGUS bridinajumus lietotajam PIRMS
 plananotas atjauninasanas, ja CSV faila sim datoram
 ShowNotification=Yes:

   1. GALVENAIS bridinajums - parahdahs vienu reizi dienaa,
      logaa no (UpdateTime - LeadMinutes) lidz UpdateTime.
      Lietotajam JAAPSTIPRINA ar pogu "Sapratu".

   2. ATGADINAJUMS AR TAIMERI - parahdahs vienu reizi dienaa,
      logaa no (UpdateTime - FinalLeadMinutes) lidz UpdateTime.
      NAV pogas - rada precizu atlikuso laiku un aizverjas
      automatiski, kad pienaak laiks. Lietotajam NEKAS nav
      jadara.

 Abiem bridinajumiem ir SAVI atseviski "jau raditi sodien"
 markieri, tapec tie ir pilniigi neatkarigi viens no otra.

 Palaizams bieezi (piem. ik 5-10 min) ar Scheduled Task.

 SIS SKRIPTS NEKO NEINSTALE - tas tikai parada informativus
 logus. Pasu instalesanu un ShutdownAfter logiku veic
 client-install.ps1.
============================================================
#>

param(
    # NasRoot SKRIPTA IEKSIENE VAIRS NETIEK LIETOTS (grafiku nolasa no lokala faila,
    # skat. zemak). Parametrs paliek tikai saderibai: Scheduled Task to joprojam
    # padod, un bez ta skripts izmestu kludu un klusi apstatos.
    [string]$NasRoot = "\\192.168.3.31\Updates",
    [int]$LeadMinutes = 60,
    [int]$FinalLeadMinutes = 5,

    # -Preview: tikai paradit abus logus ar paraugu laikiem (teksta/izkartojuma parbaudei)
    [switch]$Preview
)

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# Sis skripts strada PARASTA lietotaja sesija (tas, kas pie datora strada), un tam
# NAV piekluves NAS. Tapec grafiku (sa datora ierakstu) lokali ieraksta client-install.ps1
# (kas strada ar labupdate kontu un NAS redz), bet sis skripts to tikai NOLASA.
$ConfigFile = "C:\ProgramData\LabUpdates\State\notice-config.json"
$computerName = $env:COMPUTERNAME

# "Jau radits sodien" markierus glabajam LIETOTAJA PASA profila (vienmer rakstamam),
# nevis ProgramData, kur parasts lietotajs ne vienmer var rakstit.
$StateDir = Join-Path $env:LOCALAPPDATA "LabUpdates"
$MainMarkerFile  = Join-Path $StateDir "last-notice-date.txt"
$FinalMarkerFile = Join-Path $StateDir "last-final-notice-date.txt"

function Get-NoticeWindow {
    <#
        Parbauda lokalo konfiguraciju un atgriez, vai esam noradita laika loga
        pirms UpdateTime, un vai konkretais markieris jau
        iestatits sodienai. Nerakata markieri pasha - to dara
        izsaucoshais kods PEC TAM, kad logs faktiski paradits,
        lai gludais kluda (piem. logs netika uzzimets) nenovestu
        pie "izmestas" dienas.
    #>
    param(
        [string]$Path,
        [string]$ComputerName,
        [int]$LeadMinutes,
        [string]$MarkerFile
    )

    $result = [PSCustomObject]@{
        Show             = $false
        TargetDateTime   = $null
        TargetTimeText   = ""
        WindowEndText    = ""
    }

    if (-not (Test-Path $Path)) { return $result }

    # Lokalais fails ar SHIS datora grafika ierakstu (raksta client-install.ps1)
    try {
        $row = Get-Content -Path $Path -Raw -Encoding UTF8 | ConvertFrom-Json
    } catch {
        return $result
    }

    if (-not $row) { return $result }
    if ($row.Listed -ne $true) { return $result }   # dators nav sarakstaa
    if ($row.Enabled -ne "Yes") { return $result }
    if ($row.ThirdPartyApps -ne "Yes" -and $row.WindowsUpdate -ne "Yes") { return $result }
    if ($row.ShowNotification -ne "Yes") { return $result }

    $updateTimeRaw = [string]$row.UpdateTime
    if ([string]::IsNullOrWhiteSpace($updateTimeRaw)) { return $result }

    $timeParts = $updateTimeRaw -split ":"
    if ($timeParts.Count -ne 2) { return $result }
    $hh = 0; $mm = 0
    if (-not ([int]::TryParse($timeParts[0], [ref]$hh) -and [int]::TryParse($timeParts[1], [ref]$mm))) { return $result }

    $todayAbbrev = (Get-Date).DayOfWeek.ToString().Substring(0, 3)
    $allowedDays = $row.UpdateDays
    if ($allowedDays -ne "All") {
        $dayList = $allowedDays -split "," | ForEach-Object { $_.Trim() }
        if ($dayList -notcontains $todayAbbrev) { return $result }
    }

    $now = Get-Date
    $target = Get-Date -Hour $hh -Minute $mm -Second 0

    $diffMinutes = ($target - $now).TotalMinutes

    if ($diffMinutes -lt 0 -or $diffMinutes -gt $LeadMinutes) {
        return $result   # vai nu jau pagajis, vai vel pariak agri sim logam
    }

    # Jau radits sodien (sim konkretajam markierim)?
    $todayStr = $now.ToString("yyyy-MM-dd")
    if (Test-Path $MarkerFile) {
        $markerDate = (Get-Content $MarkerFile -ErrorAction SilentlyContinue | Select-Object -First 1)
        if ($markerDate -eq $todayStr) { return $result }
    }

    $endTarget = $target.AddHours(1)

    $result.Show           = $true
    $result.TargetDateTime = $target
    $result.TargetTimeText = $target.ToString("HH:mm")
    $result.WindowEndText  = $endTarget.ToString("HH:mm")

    return $result
}

function Set-NoticeMarker {
    param([string]$MarkerFile, [string]$DateStr)
    try {
        $dir = Split-Path $MarkerFile -Parent
        if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
        Set-Content -Path $MarkerFile -Value $DateStr -Encoding UTF8
    } catch {
        # klusa kluda - ne kritiski
    }
}

# ---------- TEKSTI (latviesu garumzimes ar \uXXXX kodiem) ----------
# Fails paliek tikai ASCII, jo UTF-8 fails BEZ BOM PowerShell 5.1 nolasa nepareizi un
# garumzimes sabojajas. [regex]::Unescape \uXXXX kodus parversh par pareizajam rakstzimem.
$TextMainTitle     = [regex]::Unescape('Br\u012bdin\u0101jums par pl\u0101notu sist\u0113mas atjaunin\u0101\u0161anu')
$TextMainTemplate  = [regex]::Unescape('\u0160odien laika posm\u0101 no {0} l\u012bdz {1} tiek pl\u0101nota sist\u0113mas atjaunin\u0101\u0161ana.')
$TextMainLine2     = [regex]::Unescape('L\u016bdzu pirms t\u0101 laika saglab\u0101jiet ies\u0101ktos darbus un aizveriet visas atv\u0113rt\u0101s programmas, jo sist\u0113ma var tikt restart\u0113ta.')
$TextMainLine3     = [regex]::Unescape('L\u016bdzu atst\u0101jiet datoru iesl\u0113gtu.')
$TextCountTitle    = [regex]::Unescape('Atjaunin\u0101\u0161ana dr\u012bz s\u0101ksies')
$TextCountTemplate = [regex]::Unescape('Atjaunin\u0101\u0161ana s\u0101ksies p\u0113c {0} min\u016bt\u0113m.')
$TextCountSave     = [regex]::Unescape('L\u016bdzu pabeidziet saglab\u0101\u0161anu.')
$TextCountNow      = [regex]::Unescape('Atjaunin\u0101\u0161ana s\u0101kas tagad.')

function Set-DarkTitleBar {
    # Padara loga virsraksta joslu TUMSU. Strada Windows 10 (1809+) un Windows 11;
    # Windows 11 ari uzstada precizu krasu un baltu tekstu. Vecakas versijas to nepienem
    # un josla vienkarsi paliek noklusejuma - nekas nesalust, tikai izskats.
    # Add-Type (C# kompilesana) tiek veikts TIKAI ja logs tiesam tiek raditis,
    # nevis katru 5 minusu parbaudi.
    param([IntPtr]$Handle)

    try {
        if (-not ('DwmHelper' -as [type])) {
            Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class DwmHelper {
    [DllImport("dwmapi.dll")]
    public static extern int DwmSetWindowAttribute(IntPtr hwnd, int attr, ref int attrValue, int attrSize);
}
'@
        }

        $dark = 1
        $result = [DwmHelper]::DwmSetWindowAttribute($Handle, 20, [ref]$dark, 4)
        if ($result -ne 0) {
            [void][DwmHelper]::DwmSetWindowAttribute($Handle, 19, [ref]$dark, 4)
        }

        # Windows 11 (build 22000+): precizas krasas. Krasa = R + G*256 + B*65536.
        $captionColor = 31 + (41 * 256) + (55 * 65536)       # RGB(31,41,55) - tumsi pelekzils
        $textColor    = 255 + (255 * 256) + (255 * 65536)    # balts
        [void][DwmHelper]::DwmSetWindowAttribute($Handle, 35, [ref]$captionColor, 4)
        [void][DwmHelper]::DwmSetWindowAttribute($Handle, 36, [ref]$textColor, 4)
    } catch {
        # Tikai izskats - ja neizdodas, logs paliek ar parasto virsraksta josli
    }
}

function Show-MainNotice {
    param([string]$StartText, [string]$EndText)

    $messageLines = @(
        ($TextMainTemplate -f $StartText, $EndText),
        "",
        $TextMainLine2,
        "",
        $TextMainLine3
    )
    $message = [string]::Join([Environment]::NewLine, $messageLines)

    $form = New-Object System.Windows.Forms.Form
    $form.AutoScaleMode = [System.Windows.Forms.AutoScaleMode]::None
    $form.Text = $TextMainTitle
    # ClientSize (darba laukums), NEVIS Size - citadi virsraksta josla "apedam" vietu
    # un poga paliek pielipusi apakseja malai.
    $form.ClientSize = New-Object System.Drawing.Size(440, 260)
    $form.StartPosition = "CenterScreen"
    $form.FormBorderStyle = "FixedDialog"
    $form.MaximizeBox = $false
    $form.MinimizeBox = $false
    $form.TopMost = $true
    $form.Add_HandleCreated({ param($sender, $e) Set-DarkTitleBar -Handle $sender.Handle })

    $label = New-Object System.Windows.Forms.Label
    $label.Text = $message
    $label.Location = New-Object System.Drawing.Point(20, 20)
    $label.Size = New-Object System.Drawing.Size(400, 170)
    $label.Font = New-Object System.Drawing.Font("Segoe UI", 10)
    $form.Controls.Add($label)

    $okButton = New-Object System.Windows.Forms.Button
    $okButton.Text = "Sapratu"
    $okButton.Size = New-Object System.Drawing.Size(120, 35)
    $okButton.Location = New-Object System.Drawing.Point(160, 205)
    $okButton.DialogResult = [System.Windows.Forms.DialogResult]::OK
    $form.Controls.Add($okButton)
    $form.AcceptButton = $okButton

    [void]$form.ShowDialog()
}

function Show-CountdownNotice {
    <#
        Logs BEZ pogas - rada precizu atlikuso laiku lidz
        $TargetDateTime un aizverjas automatiski, kad tas
        pienak (vai kad lietotajs to pats aizver - abi gadijumi
        ir pienemami, jo nekada apstiprinajuma nav vajadziga).
    #>
    param([datetime]$TargetDateTime)

    $form = New-Object System.Windows.Forms.Form
    $form.AutoScaleMode = [System.Windows.Forms.AutoScaleMode]::None
    $form.Text = $TextCountTitle
    $form.ClientSize = New-Object System.Drawing.Size(380, 140)
    $form.StartPosition = "CenterScreen"
    $form.FormBorderStyle = "FixedDialog"
    $form.MaximizeBox = $false
    $form.MinimizeBox = $false
    $form.ControlBox = $true
    $form.TopMost = $true
    $form.Add_HandleCreated({ param($sender, $e) Set-DarkTitleBar -Handle $sender.Handle })

    $label = New-Object System.Windows.Forms.Label
    $label.Location = New-Object System.Drawing.Point(20, 20)
    $label.Size = New-Object System.Drawing.Size(340, 100)
    $label.Font = New-Object System.Drawing.Font("Segoe UI", 11)
    $form.Controls.Add($label)

    $updateLabel = {
        $remaining = $TargetDateTime - (Get-Date)
        if ($remaining.TotalSeconds -le 0) {
            $label.Text = $TextCountNow
            $form.Close()
            return
        }
        $mm = [int][math]::Floor($remaining.TotalMinutes)
        $ss = $remaining.Seconds
        $timeText = "{0}:{1:D2}" -f $mm, $ss
        $label.Text = ($TextCountTemplate -f $timeText) + [Environment]::NewLine + [Environment]::NewLine + $TextCountSave
    }

    & $updateLabel

    $timer = New-Object System.Windows.Forms.Timer
    $timer.Interval = 1000
    $timer.Add_Tick($updateLabel)
    $timer.Start()

    [void]$form.ShowDialog()
    $timer.Stop()
}

# ---------- PARAUGS (-Preview) ----------
# Tikai PARADA abus logus ar paraugu laikiem tuliit. NELASA konfiguraciju un NEMAINA
# markierus - paredzets tekstu un izkartojuma parbaudei, nevis ikdienas lietosanai.

if ($Preview) {
    $previewStart = (Get-Date).AddMinutes(30)
    Show-MainNotice -StartText $previewStart.ToString("HH:mm") -EndText $previewStart.AddHours(1).ToString("HH:mm")
    Show-CountdownNotice -TargetDateTime (Get-Date).AddSeconds(20)
    exit 0
}

# ---------- GALVENAIS BRIDINAJUMS ----------

$mainDecision = Get-NoticeWindow -Path $ConfigFile -ComputerName $computerName -LeadMinutes $LeadMinutes -MarkerFile $MainMarkerFile
if ($mainDecision.Show) {
    Show-MainNotice -StartText $mainDecision.TargetTimeText -EndText $mainDecision.WindowEndText
    Set-NoticeMarker -MarkerFile $MainMarkerFile -DateStr (Get-Date).ToString("yyyy-MM-dd")
}

# ---------- ATGADINAJUMS AR TAIMERI ----------

$finalDecision = Get-NoticeWindow -Path $ConfigFile -ComputerName $computerName -LeadMinutes $FinalLeadMinutes -MarkerFile $FinalMarkerFile
if ($finalDecision.Show) {
    Show-CountdownNotice -TargetDateTime $finalDecision.TargetDateTime
    Set-NoticeMarker -MarkerFile $FinalMarkerFile -DateStr (Get-Date).ToString("yyyy-MM-dd")
}
