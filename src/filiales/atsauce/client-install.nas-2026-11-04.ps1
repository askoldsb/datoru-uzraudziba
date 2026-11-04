<#
============================================================
 client-install.ps1
 Palaizams katra klienta datora (sakotneji - testam - uz admin
 datora ar savu kontu; velak - uz kluso/skoleni/darbinieku
 datoriem ar 'labupdate' kontu caur Scheduled Task).

 Nolasa \\PIUAC_CLOUD\Updates\Config\versions.json (ko raksta
 downloader.ps1) un katrai zinamai programmai:
   1. Noskaidro instaleto versiju (registra parbaude, NEVIS winget,
      jo winget App Execution Alias nestrada non-interaktivas
      sesijas).
   2. Ja NAS versija ir jaunaka - iekopo instalatoru lokali un
      palaiz to ar klusas instalacijas parametriem.
   3. Ja versijas sakrit - izlaiz, iet pie nakamas programmas.

 Prasa: administratora tiesibas (instalesanai).
============================================================
#>

param(
    [string]$NasRoot = "\\192.168.3.31\Updates",
    [string[]]$SkipApps = @(),

    # TeamViewer Script Token (Computers & Contacts: add entries, edit
    # entries) - izmantots, lai automatiski piesaistitu jauno TeamViewer
    # instalaciju kontam uzreiz pec instalesanas/atjauninasanas. Bez ta
    # jauna instalacija paliktu nepiesaistita un "pazustu" no ierices
    # saraksta (tapec, ka veca instalacija tika noemta/aizvietota).
    [string]$TeamViewerApiToken = "<TEAMVIEWER-API-TOKEN - dziva vertiba tikai NAS>"
)

# ---------- KONFIGURACIJA ----------

$ConfigFile   = Join-Path $NasRoot "Config\versions.json"
$ScheduleFile = Join-Path $NasRoot "Config\device-schedule.csv"
$LogDir       = Join-Path $NasRoot "Logs\Clients"
$LocalWork    = "C:\ProgramData\LabUpdates\Work"

# Katrai programmai:
#   Key                - sakrit ar atslegu versions.json (ko raksta downloader.ps1)
#   DisplayNamePattern - -like sablons, pec ka meklet registra Uninstall atslegas
#   InstallType         - "exe" | "msi" | "zip-msi"
#   SilentArgs           - klusas instalacijas parametri
$Apps = @(
    @{ Key = "Firefox";    DisplayNamePattern = "Mozilla Firefox*";      InstallType = "exe";     SilentArgs = @("/S") },
    @{ Key = "Chrome";     DisplayNamePattern = "Google Chrome";         InstallType = "msi";     SilentArgs = @("/quiet", "/norestart") },
    @{ Key = "Zoom";       DisplayNamePattern = "Zoom*";                 InstallType = "msi";     SilentArgs = @("/quiet", "/norestart") },
    # Pilna TeamViewer versija: NEskar datorus, kuros ir TeamViewer HOST (tur tiek atjaunots tikai Host).
    @{ Key = "TeamViewer"; DisplayNamePattern = "TeamViewer*";           ExcludePattern = "TeamViewer Host*"; SkipIfInstalledPattern = "TeamViewer Host*"; InstallType = "zip-msi"; SilentArgs = @("/quiet", "/norestart", "ACCEPT_EULA=1") },
    # TeamViewer HOST: TIKAI atjauninam tur, kur jau instalets (pirmo instalaciju veic administrators ar savu
    # Host moduli no Cache\TeamViewerHost\). Host pats neatjauninas (AutoUpdates=Disabled), tapec so dara sis cikls.
    @{ Key = "TeamViewerHost"; DisplayNamePattern = "TeamViewer Host*"; InstallType = "exe"; SilentArgs = @("/S"); UpdateOnly = $true },
    @{ Key = "VLC";        DisplayNamePattern = "VLC media player*";     InstallType = "msi";     SilentArgs = @("/quiet", "/norestart") },
    # ExcludePattern: "eParaksts Token Signing" (2.3.9) ir cita programma ar augstaku versiju;
    # bez izslegsanas versiju salidzinasana kludaini uzskatitu, ka eParakstitajs 3.0 jau ir aktuals.
    @{ Key = "eParaksts";  DisplayNamePattern = "eParakst*";             ExcludePattern = "*Token Signing*"; InstallType = "msi";     SilentArgs = @("/quiet", "/norestart", "ALLUSERS=1") },
    # PowerShell 7 (pwsh) - TIKAI ATJAUNINAT tur, kur jau instalets (UpdateOnly).
    # Registra nosaukums "PowerShell 7-x64" apzinati precizs, lai nesaktu ar
    # "PowerShell 7-preview-x64". Windows PowerShell 5.1 (powershell.exe),
    # ko lieto saja sistema, ir Windows daala un atjauninas caur Windows Update.
    @{ Key = "PowerShell"; DisplayNamePattern = "PowerShell 7-x64";      InstallType = "msi";     SilentArgs = @("/quiet", "/norestart"); UpdateOnly = $true }
)

# --- apps-managed.csv: papildus programmas no NAS (Enabled=1) ---
# Targets (ja aizpildits) = datoru vardi, kuros programma tiek apstradata (testa aplis); tukss = visi.
$managedCsvPath = Join-Path $NasRoot "Config\apps-managed.csv"
if (Test-Path $managedCsvPath) {
    try {
        foreach ($row in @(Import-Csv -Path $managedCsvPath -Encoding UTF8)) {
            if ([string]$row.Enabled -ne "1") { continue }
            if ([string]::IsNullOrWhiteSpace($row.Key) -or [string]::IsNullOrWhiteSpace($row.DisplayNamePattern)) { continue }
            if ($Apps | Where-Object { $_.Key -eq $row.Key }) { continue }
            if (-not [string]::IsNullOrWhiteSpace($row.Targets)) {
                $tg = @($row.Targets -split '[;,]' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
                if ($tg.Count -gt 0 -and ($tg -notcontains $env:COMPUTERNAME)) { continue }
            }
            $m = @{
                Key                = [string]$row.Key
                DisplayNamePattern = [string]$row.DisplayNamePattern
                InstallType        = $(if ($row.InstallType) { [string]$row.InstallType } else { "auto" })
                SilentArgs         = @(([string]$row.SilentArgs) -split '\s+' | Where-Object { $_ })
            }
            if ($row.ExcludePattern) { $m.ExcludePattern = [string]$row.ExcludePattern }
            if ([string]$row.Mode -ne "Install") { $m.UpdateOnly = $true }
            $Apps += $m
        }
    } catch {
        Write-Host "BRIDINAJUMS: neizdevas nolasit apps-managed.csv ($_)" -ForegroundColor Yellow
    }
}

# TeamViewer piesaistes parametri jabuv nodefinet SEIT (nevis statiski
# masiva augsaa), jo tiem jaizmanto $env:COMPUTERNAME, kas ir pieejams
# tikai skripta izpildes laika. Katrs MSI properties=value pars, kura
# vertiba satur atstarpes, jaiekluaj VIENA masiva elementa (ar pedinam),
# citadi atkartosies tas pats "argumentu sadalisanas" kludas celonis,
# ko jau salabojam agrak citur sajaa skripta.
$teamViewerAssignmentOption = 'ASSIGNMENTOPTIONS="--alias ' + $env:COMPUTERNAME + ' --grant-easy-access"'
$teamViewerApp = $Apps | Where-Object { $_.Key -eq "TeamViewer" } | Select-Object -First 1
if ($teamViewerApp -and -not [string]::IsNullOrWhiteSpace($TeamViewerApiToken)) {
    $teamViewerApp.SilentArgs = $teamViewerApp.SilentArgs + @(
        "APITOKEN=$TeamViewerApiToken",
        $teamViewerAssignmentOption
    )
}

$computerName = $env:COMPUTERNAME
$logFile = Join-Path $LogDir "$computerName-$(Get-Date -Format yyyyMMdd-HHmmss).log"

# ---------- PALIGFUNKCIJAS ----------

function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    $line = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')  [$Level]  $Message"
    Write-Host $line
    try {
        Add-Content -Path $logFile -Value $line -Encoding UTF8
    } catch {
        Write-Host "BRIDINAJUMS: neizdevas rakstit log failu ($_)" -ForegroundColor Yellow
    }
}

function Get-QuotedArg {
    <#
        Start-Process -ArgumentList NEIELIEK automatiski pedinas
        ap masiva elementiem, kas satur atstarpes - tas noved pie
        salauztas komandrindas (piem. msiexec kluda 1639), ja fails
        celš satur atstarpes. Seit manuali pievienojam pedinas,
        NEIZMANTOJOT backtick simbolu (lai izvairitos no iepriekseja
        kopesanas/parsutisanas riska).
    #>
    param([string]$Value)

    if ($Value -match '\s') {
        return '"' + $Value + '"'
    }
    return $Value
}

function Get-MsiLogTail {
    <#
        Pec neveiksmigas msiexec instalacijas - megina atrast
        PASU KLUDAS IEMESLU, nevis tikai loga beigas (kas parasti
        ir vien dzinneja aizversanas process un neko nepasaka).

        MSI verbose logi parasti iezime neveiksmigo darbibu ar
        "Return Value 3" - tur megininam atrast PIRMO saja logaa
        un paradit kontekstu (rindas PIRMS ta), jo tur parasti
        atrodas ta darbiba un ta kluda, kas faktiski izraisija
        instalacijas neveiksmi.

        Ja "Return Value 3" nav atrodams, atgriezhamies pie
        vienkarsas beigu daljas (ka agrak).
    #>
    param([string]$LogPath, [int]$Lines = 15, [int]$ContextBefore = 12)

    if (-not (Test-Path $LogPath)) {
        return "(msi log fails nav atrasts: $LogPath)"
    }
    try {
        $allLines = Get-Content -Path $LogPath -Encoding Unicode -ErrorAction Stop |
            Where-Object { $_.Trim() -ne "" }

        $errorIndex = -1
        for ($i = 0; $i -lt $allLines.Count; $i++) {
            if ($allLines[$i] -match "Return Value 3") {
                $errorIndex = $i
                break
            }
        }

        if ($errorIndex -ge 0) {
            $startIdx = [math]::Max(0, $errorIndex - $ContextBefore)
            $context = $allLines[$startIdx..$errorIndex]
            return "[Atrasts 'Return Value 3' marker, konteksts pirms tam] " + ($context -join " | ")
        }

        $content = $allLines | Select-Object -Last $Lines
        return "[Nav atrasts 'Return Value 3', radu loga beigas] " + ($content -join " | ")
    } catch {
        return "(neizdevas nolasit msi log failu: $_)"
    }
}

function Write-NoticeConfig {
    # Ieraksta SHIS datora grafika ierakstu lokala faila, lai update-notice.ps1
    # (kas strada PARASTA lietotaja sesija un NAS NEredz) varetu to nolasit lokali.
    # Si funkcija strada ar labupdate kontu, kam NAS piekluve ir.
    param([string]$ScheduleFile, [string]$ComputerName)

    $configDir = "C:\ProgramData\LabUpdates\State"
    $configFile = Join-Path $configDir "notice-config.json"

    try {
        # Ja grafika faila nevar nolasit (NAS nav pieejams), iepriekseju lokalo
        # versiju atstajam neskartu - labak veca, nekaa tuksa.
        if (-not (Test-Path $ScheduleFile)) { return }

        if (-not (Test-Path $configDir)) { New-Item -ItemType Directory -Path $configDir -Force | Out-Null }

        $row = @(Import-Csv -Path $ScheduleFile -Encoding UTF8) | Where-Object { $_.ComputerName -eq $ComputerName } | Select-Object -First 1

        if ($row) {
            $cfg = [PSCustomObject]@{
                Listed           = $true
                Enabled          = [string]$row.Enabled
                UpdateDays       = [string]$row.UpdateDays
                UpdateTime       = [string]$row.UpdateTime
                ShowNotification = [string]$row.ShowNotification
                ThirdPartyApps   = [string]$row.ThirdPartyApps
                WindowsUpdate    = [string]$row.WindowsUpdate
                WrittenAt        = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
            }
        } else {
            $cfg = [PSCustomObject]@{
                Listed    = $false
                WrittenAt = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
            }
        }

        $cfg | ConvertTo-Json | Set-Content -Path $configFile -Encoding UTF8

        # Skaidri atlaujam LASIT visiem lietotajiem (S-1-5-32-545 = BUILTIN\Users), lai
        # logs strada neatkarigi no tam, ka mantotas ProgramData atlaujas.
        & icacls.exe $configFile /grant "*S-1-5-32-545:(R)" | Out-Null
    } catch {
        Write-Log "Neizdevas ierakstit lokalo notice-config.json: $_" "WARN"
    }
}

function Invoke-InventoryCollection {
    # Palaiz collect-inventory.ps1 ATSEVISKA procesa ar laika limitu, lai tas NEKAD nevaretu
    # traucet atjauninasanu. Parasti meginajums notiek reizi diena (ari tad, ja neizdodas),
    # lai kluda neradi atkartotus meginajumus ik 15 minutes. Ar -Force (cikla beigas, kad
    # kaut kas tika instalets) marker tiek ignorets, lai inventars neradit pirms-cikla stavokli.
    param([string]$NasRoot, [switch]$Force)

    try {
        $marker = "C:\ProgramData\LabUpdates\State\last-inventory-date.txt"
        $today = (Get-Date).ToString("yyyy-MM-dd")
        if ((-not $Force) -and (Test-Path $marker)) {
            $lastDate = Get-Content $marker -ErrorAction SilentlyContinue | Select-Object -First 1
            if ($lastDate -eq $today) { return }
        }

        $collectorPath = Join-Path $NasRoot "Scripts\collect-inventory.ps1"
        if (-not (Test-Path $collectorPath)) {
            Write-Log "Inventara skripts nav atrasts uz NAS ($collectorPath) - izlaizu." "WARN"
            return
        }

        $markerDir = Split-Path $marker -Parent
        if (-not (Test-Path $markerDir)) { New-Item -ItemType Directory -Path $markerDir -Force | Out-Null }
        Set-Content -Path $marker -Value $today -Encoding UTF8

        Write-Log "Inventara ievaksana (collect-inventory.ps1)..."
        $inventoryArgs = @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", (Get-QuotedArg $collectorPath), "-NasRoot", (Get-QuotedArg $NasRoot))
        $proc = Start-Process -FilePath "powershell.exe" -ArgumentList $inventoryArgs -PassThru -WindowStyle Hidden
        if (-not $proc.WaitForExit(180000)) {
            try { $proc.Kill() } catch { }
            Write-Log "Inventara ievaksana parsniedza 180 s limitu un tika apturetaa." "WARN"
            return
        }

        $outFile = Join-Path $NasRoot ("Logs\Inventory\" + $env:COMPUTERNAME + ".json")
        if ((Test-Path $outFile) -and (((Get-Date) - (Get-Item $outFile).LastWriteTime).TotalMinutes -lt 10)) {
            Write-Log "Inventara ievaksana pabeigta."
        } else {
            Write-Log "Inventara ievaksana beidzas, bet jauns fails uz NAS nav atrasts (exit code $($proc.ExitCode))." "WARN"
        }
    } catch {
        Write-Log "Inventara ievaksana neizdevas: $_" "WARN"
    }
}

function Write-StatusReport {
    <#
        Ieraksta SAVU statusu atseviska faila uz NAS
        (Logs\Status\{dators}.json). Katrs klients raksta TIKAI
        savu failu - nekad kopeju failu visiem - lai izvairitos
        no vienlaicigas rakstisanas konfliktiem, ja vairaki
        datori raksta vienlaicigi.
    #>
    param(
        [string]$NasRoot,
        [string]$ComputerName,
        [string]$Result,
        [string]$Details,
        [bool]$AnyAppInstalled,
        [bool]$IsSkip = $false,
        [string]$EsetName = "",
        [string]$EsetVersion = "",
        [string]$WindowsVersion = "",
        [string]$WindowsBuild = "",
        [string]$OfficeProduct = "",
        [string]$OfficeVersion = "",
        [string[]]$Installed = @(),
        [string[]]$Failed = @(),
        [string[]]$WuTitles = @(),
        [bool]$RebootRequired = $false
    )

    # Lauki:
    #   LastCheck            - katras palaisanas reize (ari izlaistas) laiks
    #   LastCycle            - pedeja REALA cikla laiks
    #   LastResult / Details - pedeja REALA cikla rezultats (izlaista parbaude TO NEPARRAKSTA)
    #   LastSuccessfulUpdate - kad pedejo reizi kaut kas tika instalets
    #   LastSkipReason       - pedeja izlaistas parbaudes iemesls

    $statusDir = Join-Path $NasRoot "Logs\Status"
    try {
        if (-not (Test-Path $statusDir)) { New-Item -ItemType Directory -Path $statusDir -Force | Out-Null }

        $statusFile = Join-Path $statusDir "$ComputerName.json"
        $existing = $null
        if (Test-Path $statusFile) {
            try { $existing = Get-Content $statusFile -Raw -Encoding UTF8 | ConvertFrom-Json } catch { $existing = $null }
        }

        $nowText = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")

        $lastSuccessfulUpdate = if ($existing) { $existing.LastSuccessfulUpdate } else { $null }
        $lastResult           = if ($existing) { $existing.LastResult } else { "" }
        $lastDetails          = if ($existing) { $existing.Details } else { "" }
        $lastCycle            = if ($existing) { $existing.LastCycle } else { $null }
        $lastSkipReason       = if ($existing) { $existing.LastSkipReason } else { "" }

        # Agraka versija IZLAISTAS pareizes rezultatu ierakstija ka "Izlaists",
        # pariraksot pedejo reallo ciklu - tadu vecu vertibu neturam.
        if ($lastResult -eq "Izlaists") {
            $lastResult = ""
            $lastDetails = ""
        }

        if ($IsSkip) {
            $lastSkipReason = $Details
        } else {
            $lastResult = $Result
            $lastDetails = $Details
            $lastCycle = $nowText
            $lastSkipReason = ""
            if ($AnyAppInstalled) {
                $lastSuccessfulUpdate = $nowText
            }
        }

        # Pedejo 100 REALO ciklu vesture (izlaistas parbaudes to nemaina; pec kartas "viss aktuals" cikli tiek sakopoti)
        $history = @()
        if ($existing -and $existing.History) { $history = @($existing.History) }
        if (-not $IsSkip) {
            $record = [PSCustomObject]@{
                Time           = $nowText
                Result         = $Result
                Installed      = @($Installed)
                Failed         = @($Failed)
                WindowsUpdates = @($WuTitles)
                RebootRequired = $RebootRequired
            }
            if (($Result -eq "JauAktuals") -and ($history.Count -gt 0) -and ([string]$history[0].Result -eq "JauAktuals")) {
                # nekas nav mainijies kops pedeja cikla - neveidojam jaunu ierakstu, tikai atjaunojam pedejo "viss aktuals"
                $history[0] = $record
            } else {
                $history = @((@($record) + $history) | Select-Object -First 100)
            }
        }

        $status = [PSCustomObject]@{
            ComputerName          = $ComputerName
            LastCheck             = $nowText
            LastCycle             = $lastCycle
            LastResult            = $lastResult
            Details               = $lastDetails
            LastSuccessfulUpdate  = $lastSuccessfulUpdate
            LastSkipReason        = $lastSkipReason
            EsetName              = $EsetName
            EsetVersion           = $EsetVersion
            WindowsVersion        = $WindowsVersion
            WindowsBuild          = $WindowsBuild
            OfficeProduct         = $OfficeProduct
            OfficeVersion         = $OfficeVersion
            History               = $history
        }

        $status | ConvertTo-Json -Depth 6 | Set-Content -Path $statusFile -Encoding UTF8
    } catch {
        Write-Log "Neizdevas rakstit statusa failu uz NAS: $_" "WARN"
    }
}

function Install-WindowsUpdatesFromNas {
    <#
        Instale Windows atjauninajumus, izmantojot PSWindowsUpdate
        moduli, kas NAV instalets no PowerShell Gallery (klientam
        nav droshi palauties uz interneta pieeju tieshi tam), bet
        gan iekopets lokali no NAS (Modules\PSWindowsUpdate), kur
        administrators to ievietojis vienu reizi.

        Atgriez objektu ar: Success (bool), InstalledCount (int),
        RebootRequired (bool), Details (string).
    #>
    param([string]$NasRoot)

    $result = [PSCustomObject]@{
        Success        = $false
        InstalledCount = 0
        RebootRequired = $false
        Details        = ""
        Titles         = @()
    }

    $nasModulePath = Join-Path $NasRoot "Modules\PSWindowsUpdate"
    if (-not (Test-Path $nasModulePath)) {
        $result.Details = "PSWindowsUpdate modulis nav atrasts uz NAS ($nasModulePath). Administratoram vienu reizi jaievieto modulis sajaa vieta."
        Write-Log "Windows Update: $($result.Details)" "WARN"
        return $result
    }

    $localModuleRoot = Join-Path $env:ProgramFiles "WindowsPowerShell\Modules\PSWindowsUpdate"
    try {
        if (-not (Test-Path $localModuleRoot)) {
            Write-Log "Windows Update: kopeju PSWindowsUpdate moduli lokali..."
            New-Item -ItemType Directory -Path $localModuleRoot -Force | Out-Null
            Copy-Item -Path (Join-Path $nasModulePath "*") -Destination $localModuleRoot -Recurse -Force
        }

        Import-Module PSWindowsUpdate -ErrorAction Stop

        Write-Log "Windows Update: parbaudu pieejamos atjauninajumus..."
        $available = Get-WindowsUpdate -ErrorAction Stop

        if (-not $available -or $available.Count -eq 0) {
            $result.Success = $true
            $result.Details = "Nav pieejamu Windows atjauninajumu."
            Write-Log "Windows Update: $($result.Details)"
            return $result
        }

        Write-Log "Windows Update: atrasti $($available.Count) atjauninajumi, instaleju (bez piespiedu restarta)..."
        $installResult = Install-WindowsUpdate -AcceptAll -IgnoreReboot -ErrorAction Stop -Confirm:$false

        # PSWindowsUpdate dazkart atgriez vienu un to pasu atjauninajumu vairakas reizes (uz PIUAC-ASKOLDS
        # tris reizes), tapec skaitam un zinojam katru atjauninajumu tikai VIENREIZ (pec nosaukuma).
        $installedList = @($installResult | Where-Object { $_.Result -eq "Installed" } | Sort-Object Title -Unique)
        $result.Success = $true
        $result.InstalledCount = $installedList.Count
        $result.Titles = @($installedList | ForEach-Object {
            $label = ""
            if ($_.KB) { $label = [string]$_.KB + " " }
            $label = $label + [string]$_.Title
            if ($label.Length -gt 140) { $label = $label.Substring(0, 140) }
            $label.Trim()
        })
        $result.RebootRequired = [bool](Get-WURebootStatus -Silent -ErrorAction SilentlyContinue)
        $result.Details = "Instaleti $($installedList.Count) atjauninajumi. Restarts nepieciesams: $($result.RebootRequired)."
        Write-Log "Windows Update: $($result.Details)"

    } catch {
        $result.Details = "Kluda Windows Update procesa: $_"
        Write-Log "Windows Update: $($result.Details)" "ERROR"
    }

    return $result
}

function Confirm-TeamViewerHealthCheck {
    <#
        VIENREIZEJS (ne katru ciklu atkartots), DROSS catch-up solis
        jau instaletam TeamViewer - salabo TIKAI servisa/autostart
        iestatijumus (Repair-TeamViewerAutostart), NEKO citu.

        PIEZIME: seit agrak bija ari atkartota "TeamViewer.exe assign"
        izsauksana, bet tas izradijas RISKANTS mehanisms - pat ar
        uzgaidisanu un atkartotiem mekinajumiem, tas vairakkart
        neizdevas (exit code 202) un vienu reizi izraisija ierices
        PAZUSANU no konta saraksta. Instalesanas laika piesaiste
        (APITOKEN/ASSIGNMENTOPTIONS, skat. augstak $teamViewerApp
        SilentArgs) ir uzticamaka, jo notiek tikai FRESH instalesanas
        kontext2, nevis ka atseviska, atkartota darbiba. Jau
        esosu/problematisku ierisu piesaiste simbrid jarisina
        MANUALI (skat. statusa dokumentu).
    #>
    $permanentMarker = "C:\ProgramData\LabUpdates\State\teamviewer-healthcheck-done.flag"
    if (Test-Path $permanentMarker) {
        return  # Jau izdarits agrak
    }

    $installed = Get-InstalledVersion -DisplayNamePattern "TeamViewer*"
    if (-not $installed) {
        return  # TeamViewer sim datoram nav instalets - nav ko darit
    }

    Repair-TeamViewerAutostart

    try {
        $markerDir = Split-Path $permanentMarker -Parent
        if (-not (Test-Path $markerDir)) { New-Item -ItemType Directory -Path $markerDir -Force | Out-Null }
        Set-Content -Path $permanentMarker -Value (Get-Date).ToString("yyyy-MM-dd HH:mm:ss") -Encoding UTF8
    } catch {
        Write-Log "Neizdevas izveidot TeamViewer healthcheck markieri: $_" "WARN"
    }
}

function Confirm-TeamViewerAlwaysOnline {
    <#
        TeamViewer (Full un Host): ja registra vertiba Always_Online ir 0, TeamViewer serviss paliek
        OFFLINE (nav ID, nav pieslegsanas) - tas notika pec MSI instalacijas. Katra cikla DROSA parbaude:
        mainam TIKAI tad, ja vertiba eksiste un ir 0; tad iestatam 1 un pareistartejam servisu.
    #>
    try {
        $reg = "HKLM:\SOFTWARE\TeamViewer"
        if (-not (Test-Path $reg)) { return }
        if (-not (Get-InstalledVersion -DisplayNamePattern "TeamViewer*")) { return }
        $cur = (Get-ItemProperty -Path $reg -Name "Always_Online" -ErrorAction SilentlyContinue).Always_Online
        if (($null -ne $cur) -and ([int]$cur -eq 0)) {
            Set-ItemProperty -Path $reg -Name "Always_Online" -Value 1 -ErrorAction Stop
            Write-Log "TeamViewer: Always_Online bija 0 - iestatits uz 1, restartejam servisu."
            $svc = Get-Service -Name "TeamViewer" -ErrorAction SilentlyContinue
            if ($svc) { Restart-Service -Name "TeamViewer" -Force -ErrorAction SilentlyContinue }
        }
    } catch {
        Write-Log "TeamViewer Always_Online parbaude neizdevas: $_" "WARN"
    }
}

function Repair-TeamViewerAutostart {
    <#
        Zinams TeamViewer MSI instalatora trukums: pretstata EXE
        instalatoram, MSI NEnodrosina, ka TeamViewer serviss
        startejas automatiski ar Windows, un netiek iestatita
        Autostart_GUI registra atslega. Bez sis labosanas
        TeamViewer var parstat buut sasniedzams pec datora
        restartesanas vai pat uzreiz pec instalesanas, kamer
        kads to manuali neatver/nepartstarte servisu.
    #>
    try {
        $svc = Get-Service -Name "TeamViewer" -ErrorAction SilentlyContinue
        if (-not $svc) {
            Write-Log "TeamViewer autostart labosana: serviss nav atrasts - izlaizu." "WARN"
            return
        }

        if ($svc.StartType -ne "Automatic") {
            Set-Service -Name "TeamViewer" -StartupType Automatic -ErrorAction Stop
            Write-Log "TeamViewer autostart labosana: serviss iestatits uz 'Automatic'."
        }

        if ($svc.Status -ne "Running") {
            Start-Service -Name "TeamViewer" -ErrorAction Stop
            Write-Log "TeamViewer autostart labosana: serviss palaists."
        }

        $regPaths = @(
            "HKLM:\SOFTWARE\WOW6432Node\TeamViewer\DefaultSettings",
            "HKLM:\SOFTWARE\TeamViewer\DefaultSettings"
        )
        foreach ($regPath in $regPaths) {
            $regRoot = Split-Path $regPath -Parent
            if (Test-Path $regRoot) {
                if (-not (Test-Path $regPath)) {
                    New-Item -Path $regPath -Force | Out-Null
                }
                New-ItemProperty -Path $regPath -Name "Autostart_GUI" -Value 1 -PropertyType DWord -Force | Out-Null
                Write-Log "TeamViewer autostart labosana: Autostart_GUI iestatits ($regPath)."
            }
        }
    } catch {
        Write-Log "TeamViewer autostart labosana: neizdevas - $_" "WARN"
    }
}

function Get-ScheduleDecision {
    <#
        Nolasa device-schedule.csv no NAS un nosaka, vai SHOBRID
        sim konkretajam datoram (pec $env:COMPUTERNAME) atlauts
        veikt trešo pušu programmu atjauninasanu.

        Atgriez objektu ar: Allowed (bool), Reason (string),
        WindowsUpdateRequested (bool, informativi - funkcionalitate
        vel nav realizeta).

        DROSAS NOKLUSEJUMA UZVEDIBAS:
          - Fails nav atrodams NAS                  -> NAV atlauts
          - Dators nav sarakstaa                     -> NAV atlauts
          - Enabled != Yes                           -> NAV atlauts
          - ThirdPartyApps != Yes                    -> NAV atlauts
          - UpdateDays neatbilst sodienas dienai      -> NAV atlauts
          - UpdateTime iestatits, bet sobrid arpus laika loga -> NAV atlauts
          - Sodien jau tika veiksmigi pienemts "atlauts" lemums -> NAV atlauts (atkartota palaisana)
        UpdateTime ir OPCIONALS lauks CSV faila: ja tas ir tukss,
        laika pardaude NETIEK piemerota (noderigi testesanai -
        skriptu var palaist jebkura laika). Ja vertiba ir noradita
        formata "HH:mm" (piem. "12:00"), atlauts logs ir no sis
        minutes lidz +$ToleranceMinutes minutem velak.
        Jebkuras neskaidrotas/kludainas situacijas noklusejums
        vienmer ir "NEDARIT NEKO", nevis "darit, ja saubas" -
        IZNEMUMS ir nederigs/nenolasams UpdateTime formats, kur
        noklusejums ir "neierobezot laiku" (lai typo neapstadinatu
        visu atjauninasanu klusi un nemaniti).
    #>
    param(
        [string]$Path,
        [string]$ComputerName,
        [string]$DailyMarkerFile,
        [int]$ToleranceMinutes = 20,
        [bool]$IgnoreSchedule = $false
    )

    $result = [PSCustomObject]@{
        Allowed                  = $false
        Reason                   = ""
        WindowsUpdateRequested   = $false
        ThirdPartyAppsRequested  = $false
        ShutdownAfterRequested   = $false
        SkipTeamViewer           = $false
    }

    if (-not (Test-Path $Path)) {
        $result.Reason = "Grafika fails nav atrasts ($Path) - noklusejuma drosibas pec NEKO nedaru."
        return $result
    }

    try {
        $rows = Import-Csv -Path $Path -Encoding UTF8
    } catch {
        $result.Reason = "Neizdevas nolasit grafika failu: $_"
        return $result
    }

    $row = $rows | Where-Object { $_.ComputerName -eq $ComputerName } | Select-Object -First 1
    if (-not $row) {
        $result.Reason = "Dators '$ComputerName' nav atrasts $Path - noklusejuma drosibas pec NEKO nedaru. Pievienojiet rindu CSV failam, lai iesletu atjauninasanu sim datoram."
        return $result
    }

    if ($row.Enabled -ne "Yes") {
        $result.Reason = "Enabled='$($row.Enabled)' (nav 'Yes') - atjauninasana atslegta sim datoram CSV faila."
        return $result
    }

    $result.WindowsUpdateRequested = ($row.WindowsUpdate -eq "Yes")
    $result.ShutdownAfterRequested = ($row.ShutdownAfter -eq "Yes")

    # TeamViewer kolonna ir opcionala (vecaki CSV ieraksti to varetu
    # nesaturet) - ja tukss/trukst, NOKLUSEJUMS ir "Yes" (neizlaist),
    # lai saglabatu iepriekseja uzvediba un neparsteigtu administratoru.
    $tvColumnRaw = [string]$row.TeamViewer
    if ([string]::IsNullOrWhiteSpace($tvColumnRaw)) {
        $result.SkipTeamViewer = $false
    } else {
        $result.SkipTeamViewer = ($tvColumnRaw -ne "Yes")
    }

    $result.ThirdPartyAppsRequested = ($row.ThirdPartyApps -eq "Yes")

    if (-not $result.ThirdPartyAppsRequested -and -not $result.WindowsUpdateRequested) {
        $result.Reason = "Ne ThirdPartyApps, ne WindowsUpdate nav iesleegti sim datoram - nav ko darit."
        return $result
    }

    # Administratora komanda UpdateNow: dienu, laika un "jau izpildits sodien" ierobezojumi netiek piemeroti
    # (Enabled un ThirdPartyApps/WindowsUpdate joprojam jaatbilst). Izslegsana pec cikla netiek ieplanota.
    if ($IgnoreSchedule) {
        $result.ShutdownAfterRequested = $false
        $result.Allowed = $true
        $result.Reason = "Atlauts (administratora komanda UpdateNow - grafiks ignorets)."
        return $result
    }

    $todayAbbrev = (Get-Date).DayOfWeek.ToString().Substring(0, 3)  # piem. "Mon", "Tue" - invariants, neatkarigs no sistemas valodas
    $allowedDays = $row.UpdateDays

    if ($allowedDays -eq "All") {
        $result.Allowed = $true
        $result.Reason = "Atlauts (UpdateDays=All)."
        return $result
    }

    $dayList = $allowedDays -split "," | ForEach-Object { $_.Trim() }
    if ($dayList -notcontains $todayAbbrev) {
        $result.Reason = "Sodiena '$todayAbbrev' NAV UpdateDays sarakstaa ($allowedDays) - izlaizu sodien."
        return $result
    }

    # --- Laika loga parbaude (opcionala) ---
    $updateTimeRaw = [string]$row.UpdateTime
    if (-not [string]::IsNullOrWhiteSpace($updateTimeRaw)) {
        $timeParts = $updateTimeRaw -split ":"
        $parsedOk = $false
        if ($timeParts.Count -eq 2) {
            $hh = 0; $mm = 0
            if ([int]::TryParse($timeParts[0], [ref]$hh) -and [int]::TryParse($timeParts[1], [ref]$mm)) {
                if ($hh -ge 0 -and $hh -le 23 -and $mm -ge 0 -and $mm -le 59) {
                    $parsedOk = $true
                }
            }
        }

        if (-not $parsedOk) {
            Write-Log "UpdateTime vertiba '$updateTimeRaw' nav derigs formats (gaidits 'HH:mm') - laika parbaude IZLAISTA, turpinu bez laika ierobezojuma." "WARN"
        } else {
            $targetMinutes = ($hh * 60) + $mm
            $nowMinutes = (Get-Date).Hour * 60 + (Get-Date).Minute
            $diff = $nowMinutes - $targetMinutes

            if ($diff -lt 0 -or $diff -gt $ToleranceMinutes) {
                $result.Reason = "Sobrid arpus UpdateTime loga (mereka $updateTimeRaw, logs +$ToleranceMinutes min) - izlaizu sobrid."
                return $result
            }
        }
    }

    # --- "Jau izpildits sodien" parbaude ---
    $todayStr = (Get-Date).ToString("yyyy-MM-dd")
    if ($DailyMarkerFile -and (Test-Path $DailyMarkerFile)) {
        $markerDate = (Get-Content $DailyMarkerFile -ErrorAction SilentlyContinue | Select-Object -First 1)
        if ($markerDate -eq $todayStr) {
            $result.Reason = "Sodien ($todayStr) atjauninasana jau tika uzsakta iepriekseja palaisanas reize - izlaizu atkartotu palaisanu."
            return $result
        }
    }

    $result.Allowed = $true
    $result.Reason = "Atlauts (diena '$todayAbbrev' sarakstaa: $allowedDays; laiks OK)."

    if ($DailyMarkerFile) {
        try {
            $markerDir = Split-Path $DailyMarkerFile -Parent
            if (-not (Test-Path $markerDir)) { New-Item -ItemType Directory -Path $markerDir -Force | Out-Null }
            Set-Content -Path $DailyMarkerFile -Value $todayStr -Encoding UTF8
        } catch {
            Write-Log "Neizdevas rakstit dienas marku failu: $_" "WARN"
        }
    }

    return $result
}

# ---------- ADMINISTRATORA KOMANDAS (Config\Commands\<DATORS>.json) ----------
# Panelis ieraksta komandas failu; klients to nolasa katra cikla sakuma (ik 15 min), izpilda un
# apstiprina ar Logs\Status\<DATORS>.command.json. Apstradatas komandas Id glabajas lokali
# (State\last-command-id.txt), tapec viena komanda tiek izpildita tikai VIENU reizi.

function Get-PendingCommand {
    param([string]$NasRoot, [string]$ComputerName, [string]$StateFile)
    $path = Join-Path $NasRoot ("Config\Commands\" + $ComputerName + ".json")
    if (-not (Test-Path $path)) { return $null }
    try {
        $c = Get-Content -Path $path -Raw -Encoding UTF8 -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
    } catch {
        Write-Log "Komandas fails nav nolasams ($path): $_" "WARN"
        return $null
    }
    $id = [string]$c.Id
    $cmd = [string]$c.Command
    if ([string]::IsNullOrWhiteSpace($id) -or [string]::IsNullOrWhiteSpace($cmd)) { return $null }

    $last = ""
    if (Test-Path $StateFile) { $last = [string](Get-Content -Path $StateFile -ErrorAction SilentlyContinue | Select-Object -First 1) }
    if ($last.Trim() -eq $id) { return $null }

    $expired = $true
    try {
        $exp = [datetime]::ParseExact([string]$c.ExpiresAt, "yyyy-MM-dd HH:mm:ss", [System.Globalization.CultureInfo]::InvariantCulture)
        $expired = ($exp -lt (Get-Date))
    } catch { $expired = $true }

    return [PSCustomObject]@{
        Id        = $id
        Command   = $cmd
        CreatedBy = [string]$c.CreatedBy
        CreatedAt = [string]$c.CreatedAt
        Expired   = $expired
    }
}

function Set-CommandHandled {
    param([string]$StateFile, [string]$Id)
    try {
        $dir = Split-Path $StateFile -Parent
        if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
        Set-Content -Path $StateFile -Value $Id -Encoding UTF8
    } catch {
        Write-Log "Neizdevas saglabat apstradatas komandas Id: $_" "WARN"
    }
}

function Write-CommandAck {
    param([string]$NasRoot, [string]$ComputerName, $Command, [string]$Status, [string]$Details = "")
    $obj = [ordered]@{
        Id        = $Command.Id
        Command   = $Command.Command
        Status    = $Status
        UpdatedAt = (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
        Details   = $Details
    }
    $path = Join-Path $NasRoot ("Logs\Status\" + $ComputerName + ".command.json")
    try {
        ($obj | ConvertTo-Json) | Set-Content -Path $path -Encoding UTF8
    } catch {
        Write-Log "Neizdevas rakstit komandas apstiprinajumu ($path): $_" "WARN"
    }
}

function Get-OfficeInfo {
    # Nolasa uzstadito Office produktu un versiju (TIKAI lasisana): Click-to-Run (Microsoft 365,
    # Office 2019/2021/2024), MSI Office (2010-2024) un LibreOffice. Tikai ATSPOGULO to, kas
    # uzstadits, bez salidzinasanas. Kluda nekad nedrikst traucet atjauninasanu.
    $result = [PSCustomObject]@{ Product = ""; Version = "" }
    try {
        $c2r = Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Office\ClickToRun\Configuration" -ErrorAction SilentlyContinue
        if ($c2r -and $c2r.VersionToReport) {
            $ids = [string]$c2r.ProductReleaseIds
            $product = "Office (Click-to-Run)"
            if ($ids -match 'O365|Microsoft365') { $product = "Microsoft 365" }
            elseif ($ids -match '2024') { $product = "Office 2024" }
            elseif ($ids -match '2021') { $product = "Office 2021" }
            elseif ($ids -match '2019') { $product = "Office 2019" }
            elseif ($ids -match '2016') { $product = "Office 2016" }
            $result.Product = $product
            $result.Version = [string]$c2r.VersionToReport
            return $result
        }

        $paths = @("HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*", "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*")
        $entries = @(Get-ItemProperty -Path $paths -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName })
        $msi = $entries | Where-Object { $_.DisplayName -match '^Microsoft Office (Professional|Standard|Home|Small Business|Enterprise|Plus|Basic).*(2010|2013|2016|2019|2021|2024)' } | Select-Object -First 1
        if ($msi) {
            $result.Product = [string]$msi.DisplayName
            $result.Version = [string]$msi.DisplayVersion
            return $result
        }
        $lo = $entries | Where-Object { $_.DisplayName -like "LibreOffice*" } | Select-Object -First 1
        if ($lo) {
            $result.Product = "LibreOffice"
            $result.Version = [string]$lo.DisplayVersion
            return $result
        }
    } catch { }
    return $result
}

function Start-OfficeUpdate {
    # Uzdod Microsoft Office Click-to-Run atjauninasanu FONA (Microsoft 365, Office 2019/2021/2024).
    # Katrs produkts atjaunojas SAVA kanala; versijas netiek vienadotas. Atvertas Office programmas
    # netiek aizvertas (forceappshutdown=false): tam atjauninajums uzstadas pec aizversanas.
    # MSI Office (2010-2016) ar so nestradas, to atjaunina Windows Update. Atgriez $true, ja uzdots.
    $exe = $null
    foreach ($base in @($env:CommonProgramFiles, ${env:CommonProgramFiles(x86)})) {
        if ($base) {
            $candidate = Join-Path $base "Microsoft Shared\ClickToRun\OfficeC2RClient.exe"
            if (Test-Path $candidate) { $exe = $candidate; break }
        }
    }
    if (-not $exe) { return $false }

    try {
        $updateArgs = @("/update", "user", "displaylevel=false", "updatepromptuser=false", "forceappshutdown=false")
        Start-Process -FilePath $exe -ArgumentList $updateArgs -WindowStyle Hidden | Out-Null
        Start-Sleep -Seconds 10
        return $true
    } catch {
        Write-Log "Office atjauninasanu neizdevas uzdot: $_" "WARN"
        return $false
    }
}

function Wait-OfficeUpdate {
    # Ja Office atjauninatajs vel darbojas, gaida (lidz $MaxMinutes), lai dators neizslegtos atjauninasanas vidu.
    # Ja procesu nav, neko negaida. Kluda nekad nedrikst traucet ciklu.
    param([int]$MaxMinutes = 15)
    try {
        $watch = @("OfficeC2RClient", "integratedoffice")
        $deadline = (Get-Date).AddMinutes($MaxMinutes)
        $announced = $false
        while ((Get-Date) -lt $deadline) {
            $running = @(Get-Process -Name $watch -ErrorAction SilentlyContinue)
            if ($running.Count -eq 0) { break }
            if (-not $announced) {
                Write-Log ("Office: gaidu atjauninasanas beigas (darbojas: " + (($running | ForEach-Object { $_.ProcessName } | Select-Object -Unique) -join ", ") + ").")
                $announced = $true
            }
            Start-Sleep -Seconds 20
        }
        if ($announced) {
            $still = @(Get-Process -Name $watch -ErrorAction SilentlyContinue)
            if ($still.Count -gt 0) {
                Write-Log ("Office: gaidisanas limits (" + $MaxMinutes + " min) beidzies, atjauninasana turpinas fona.") "WARN"
            } else {
                Write-Log "Office: atjauninatajs pabeidza darbu."
            }
        }
    } catch {
        Write-Log "Office gaidisana neizdevas: $_" "WARN"
    }
}

function Get-WindowsVersionInfo {
    # Nolasa Windows versiju (piem., 25H2) un pilnu build numuru (piem., 26200.9457)
    # no registra (TIKAI lasisana). Kluda nekad nedrikst traucet atjauninasanu.
    $result = [PSCustomObject]@{ Version = ""; Build = "" }
    try {
        $cv = Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion" -ErrorAction Stop
        $display = [string]$cv.DisplayVersion
        if ($display -eq "") { $display = [string]$cv.ReleaseId }
        $build = [string]$cv.CurrentBuildNumber
        if (($build -ne "") -and ($null -ne $cv.UBR)) { $build = $build + "." + [string]$cv.UBR }
        $result.Version = $display.Trim()
        $result.Build = $build.Trim()
    } catch { }
    return $result
}

function Get-EsetProduct {
    # Nolasa instaleto ESET ANTIVIRUSA produktu un versiju no registra (TIKAI
    # lasisana). Meklejam tikai pasu antivirusu, nevis piem. ESET Management
    # Agent, tapec nosaukums jasakas ar zinamu produkta nosaukumu.
    $paths = @(
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*",
        "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*"
    )

    $match = Get-ItemProperty -Path $paths -ErrorAction SilentlyContinue |
        Where-Object { $_.DisplayName -match '^ESET (Endpoint|Server Security|File Security|NOD32|Smart Security|Internet Security|Security)' } |
        Select-Object -First 1

    if ($match) {
        return [PSCustomObject]@{
            Name    = [string]$match.DisplayName
            Version = [string]$match.DisplayVersion
        }
    }
    return $null
}

function Get-InstalledVersion {
    <#
        Mekle instaleto versiju registra Uninstall atslegas
        (32-bit un 64-bit skatpunkts, HKLM un HKCU - dazas
        programmas instalejas per-user).
    #>
    param([string]$DisplayNamePattern, [string]$ExcludePattern = "")

    $paths = @(
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*",
        "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*",
        "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*"
    )

    $found = @(Get-ItemProperty -Path $paths -ErrorAction SilentlyContinue |
        Where-Object { ($_.DisplayName -like $DisplayNamePattern) -and
                       ([string]::IsNullOrEmpty($ExcludePattern) -or ($_.DisplayName -notlike $ExcludePattern)) })

    if ($found.Count -eq 0) { return $null }

    # Ja ir vairaki ieraksti (piem., vienas programmas divas versijas vienlaikus), nem
    # AUGSTAKO versiju, nevis pirmo - citadi rezultats ir atkarigs no registra secibas.
    $best = $null
    $bestVersion = $null
    foreach ($entry in $found) {
        $parsed = $null
        if ([version]::TryParse([string]$entry.DisplayVersion, [ref]$parsed)) {
            if (($null -eq $bestVersion) -or ($parsed -gt $bestVersion)) {
                $best = $entry
                $bestVersion = $parsed
            }
        }
    }
    if ($best) { return $best.DisplayVersion }
    return ($found | Select-Object -First 1).DisplayVersion
}

function Compare-Versions {
    <#
        Atgriez $true, ja $Latest ir jaunaka par $Installed.
        Megina [version] salidzinasanu, ja neizdodas (netipisks
        formats) - atgriez $true, ja stringi atskiras (drosak
        instalet un tt.p, nevis klusi izlaist).
    #>
    param([string]$Installed, [string]$Latest)

    if (-not $Installed) { return $true }
    if ($Installed -eq $Latest) { return $false }

    try {
        $vInst = [version]$Installed
        $vLat  = [version]$Latest
        # Ja instaletajai versijai ir mazak komponentu (piem. 1.55 pret 1.55.0.133), salidzinam tikai
        # kopigas komponentes - citadi katru ciklu tiktu mekleta "jaunaka" versija.
        $nInst = @($Installed -split '\.').Count
        $nLat  = @($Latest -split '\.').Count
        if (($nInst -ge 2) -and ($nInst -lt $nLat)) {
            $vLat = [version](($Latest -split '\.')[0..($nInst - 1)] -join '.')
        }
        return $vLat -gt $vInst
    } catch {
        return $Installed -ne $Latest
    }
}

function Save-FailedMsiLog {
    <#
        Saglaba PILNU msiexec verbose logu uz NAS, ja instalesana
        neizdodas - lai butu iespejams veikt detalizetaku manualu
        izpeti, ja automatiska diagnostika (Get-MsiLogTail) nav
        pietiekama.
    #>
    param([string]$LogPath, [string]$Key)

    if (-not (Test-Path $LogPath)) { return }

    try {
        $destDir = Join-Path $NasRoot "Logs\MsiLogs"
        if (-not (Test-Path $destDir)) { New-Item -ItemType Directory -Path $destDir -Force | Out-Null }

        $timestamp = (Get-Date).ToString("yyyyMMdd-HHmmss")
        $destFile = Join-Path $destDir "$computerName-$Key-$timestamp.log"
        Copy-Item -Path $LogPath -Destination $destFile -Force
        Write-Log "$Key : pilns msi log saglabats -> Logs\MsiLogs\$computerName-$Key-$timestamp.log (manualai izpetei)."
    } catch {
        Write-Log "$Key : neizdevas saglabat pilnu msi log uz NAS: $_" "WARN"
    }
}

function Install-App {
    param(
        [string]$Key,
        [string]$InstallType,
        [string[]]$SilentArgs,
        [string]$SourcePath   # pilns UNC cels uz instalatoru NAS Cache
    )

    $localAppDir = Join-Path $LocalWork $Key
    if (Test-Path $localAppDir) {
        Remove-Item -Path $localAppDir -Recurse -Force -ErrorAction SilentlyContinue
    }
    New-Item -ItemType Directory -Path $localAppDir -Force | Out-Null

    $localFile = Join-Path $localAppDir (Split-Path $SourcePath -Leaf)
    Write-Log "$Key : kopeju instalatoru lokali ($localFile)..."
    Copy-Item -Path $SourcePath -Destination $localFile -Force

    # "auto": .msi -> msi, citi -> exe ar SilentArgs no CSV
    if ($InstallType -eq "auto") { $InstallType = $(if ($localFile -like "*.msi") { "msi" } else { "exe" }) }
    if ($InstallType -eq "msi" -and (-not $SilentArgs -or $SilentArgs.Count -eq 0)) { $SilentArgs = @("/qn", "/norestart") }
    if ($InstallType -eq "exe" -and (-not $SilentArgs -or $SilentArgs.Count -eq 0)) {
        Write-Log "$Key : nav noradits SilentArgs exe instalatoram (apps-managed.csv) - izlaizu." "ERROR"
        return -1
    }

    switch ($InstallType) {

        "exe" {
            Write-Log "$Key : palaizu $localFile $($SilentArgs -join ' ')"
            # exe-nowait: gaidam tikai pasa instalatora procesu (ne apakspocesu koku), max 10 min
            $p = Start-Process -FilePath $localFile -ArgumentList $SilentArgs -PassThru -WindowStyle Hidden
            if (-not $p.WaitForExit(600000)) {
                Write-Log "$Key : instalators darbojas ilgak par 10 min - turpinu talak." "WARN"
                return 0
            }
            return $p.ExitCode
        }

        "msi" {
            $msiLogPath = Join-Path $localAppDir "msiexec.log"
            $msiArgs = @("/i", (Get-QuotedArg $localFile), "/l*v", (Get-QuotedArg $msiLogPath)) + $SilentArgs
            Write-Log "$Key : palaizu msiexec.exe $($msiArgs -join ' ')"
            $p = Start-Process -FilePath "msiexec.exe" -ArgumentList $msiArgs -Wait -PassThru -WindowStyle Hidden
            if ($p.ExitCode -ne 0) {
                Write-Log "$Key : msi log fragments: $(Get-MsiLogTail -LogPath $msiLogPath)" "WARN"
                Save-FailedMsiLog -LogPath $msiLogPath -Key $Key
            }
            return $p.ExitCode
        }

        "zip-msi" {
            Write-Log "$Key : izpakoju $localFile..."
            $extractDir = Join-Path $localAppDir "extracted"
            Expand-Archive -Path $localFile -DestinationPath $extractDir -Force

            $msiCandidates = Get-ChildItem -Path $extractDir -Filter "*.msi" -Recurse
            Write-Log "$Key : arhiva atrasti .msi faili: $(($msiCandidates | ForEach-Object { "$($_.Name) ($($_.Length) bytes)" }) -join ', ')"

            if (-not $msiCandidates) {
                Write-Log "$Key : arhiva nav atrasts neviens .msi fails." "ERROR"
                return -1
            }

            # Izvairamies no maziem 'update*' delta paketem - dodam
            # priekssroku lielakajam ne-update .msi failam (visticamak
            # pilnais instalators). Ja tada nav, izmantojam lielako pieejamo.
            $msi = $msiCandidates | Where-Object { $_.Name -notmatch '^update' } | Sort-Object Length -Descending | Select-Object -First 1
            if (-not $msi) {
                $msi = $msiCandidates | Sort-Object Length -Descending | Select-Object -First 1
            }
            Write-Log "$Key : izmantoju $($msi.Name)"

            # TeamViewer bieza darbojas fona (process/service) un var
            # blokket failus - apturam pirms instalesanas, ja tas strada.
            $procNames = @("TeamViewer", "TeamViewer_Service", "tv_w32", "tv_x64")
            foreach ($pn in $procNames) {
                $proc = Get-Process -Name $pn -ErrorAction SilentlyContinue
                if ($proc) {
                    Write-Log "$Key : apturu darbojosos procesu '$pn'..."
                    $proc | Stop-Process -Force -ErrorAction SilentlyContinue
                }
            }
            $svc = Get-Service -Name "TeamViewer*" -ErrorAction SilentlyContinue
            if ($svc) {
                Write-Log "$Key : apturu servisu '$($svc.Name)'..."
                $svc | Stop-Service -Force -ErrorAction SilentlyContinue
            }
            Start-Sleep -Seconds 2

            # Jauna (MSI) TeamViewer pakotne atsakas instaleties, ja
            # atrasta veca (EXE/NSIS tipa) instalacija - sadala
            # pazimi: atseviska "uninstall.exe" faila esamiba Program
            # Files mape (MSI instalacijas so failu neatstaj, jo tas
            # tiek atinstalets caur msiexec /x, nevis atseviska exe).
            # Ja atrasts - megininam to klusi atinstalet pirms jaunas
            # instalesanas.
            $legacyUninstallers = @(
                "C:\Program Files (x86)\TeamViewer\uninstall.exe",
                "C:\Program Files\TeamViewer\uninstall.exe"
            )
            foreach ($legacyPath in $legacyUninstallers) {
                if (Test-Path $legacyPath) {
                    Write-Log "$Key : atrasta veca (ne-MSI) instalacija ($legacyPath) - megino automatiski atinstalet..."
                    try {
                        $uninstProc = Start-Process -FilePath $legacyPath -ArgumentList @("/S") -Wait -PassThru -WindowStyle Hidden
                        Write-Log "$Key : vecas versijas atinstalesanas exit code: $($uninstProc.ExitCode)"
                        Start-Sleep -Seconds 3
                    } catch {
                        Write-Log "$Key : neizdevas automatiski atinstalet veco versiju: $_" "WARN"
                    }
                }
            }

            $msiLogPath = Join-Path $localAppDir "msiexec.log"
            $msiArgs = @("/i", (Get-QuotedArg $msi.FullName), "/l*v", (Get-QuotedArg $msiLogPath)) + $SilentArgs
            Write-Log "$Key : palaizu msiexec.exe $($msiArgs -join ' ')"
            $p = Start-Process -FilePath "msiexec.exe" -ArgumentList $msiArgs -Wait -PassThru -WindowStyle Hidden
            if ($p.ExitCode -ne 0) {
                Write-Log "$Key : msi log fragments: $(Get-MsiLogTail -LogPath $msiLogPath)" "WARN"
                Save-FailedMsiLog -LogPath $msiLogPath -Key $Key
            }
            return $p.ExitCode
        }

        default {
            Write-Log "$Key : nezinams InstallType '$InstallType'." "ERROR"
            return -1
        }
    }
}

# ---------- SAKUMS ----------

if (-not (Test-Path $NasRoot)) {
    Write-Host "NAS ($NasRoot) nav sasniedzams. Beidzam darbu." -ForegroundColor Red
    exit 1
}

if (-not (Test-Path $LogDir)) {
    New-Item -ItemType Directory -Path $LogDir -Force | Out-Null
}
if (-not (Test-Path $LocalWork)) {
    New-Item -ItemType Directory -Path $LocalWork -Force | Out-Null
}

$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Host "KLUDA: sis skripts japalaiz ka Administrators (instalesanai vajag paaugstinatas tiesibas)." -ForegroundColor Red
    exit 1
}

# Aizsardziba pret DIVIEM cikliem vienlaikus uz viena datora. Ja uzdevumu parregistre,
# kamer cikls vel darbojas, vecais process turpina darbu, bet Task Scheduler to vairs
# neredz un palaiz jaunu - divi cikli tad bloke cits cita instalatorus (MSI kludas 1603/1619).
# Mutex pazud pats, kad process beidzas.
$instanceMutex = $null
try {
    $mutexCreated = $false
    $instanceMutex = New-Object System.Threading.Mutex($true, "Global\LabAppUpdateClientInstall", [ref]$mutexCreated)
    if (-not $mutexCreated) {
        # Iestregusa cikla aizsardziba: ja vecais cikls darbojas ilgak par $MaxCycleHours h, to apturam.
        $MaxCycleHours = 4
        $stale = @(Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" -ErrorAction SilentlyContinue |
            Where-Object { $_.ProcessId -ne $PID -and $_.CommandLine -like "*client-install.ps1*" -and $_.CreationDate -lt (Get-Date).AddHours(-$MaxCycleHours) })
        if ($stale.Count -eq 0) {
            Write-Log "Cits klienta skripta cikls jau darbojas sim datoram - so palaisanu izlaizu."
            exit 0
        }
        foreach ($p in $stale) {
            Write-Log ("Iestregis cikls (PID {0}, sakts {1}) darbojas ilgak par {2} h - apturu." -f $p.ProcessId, $p.CreationDate, $MaxCycleHours) "WARN"
            Get-CimInstance Win32_Process -Filter "ParentProcessId=$($p.ProcessId)" -ErrorAction SilentlyContinue | ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
            Stop-Process -Id $p.ProcessId -Force -ErrorAction SilentlyContinue
        }
        try { [void]$instanceMutex.WaitOne(15000) } catch [System.Threading.AbandonedMutexException] { }
    }
} catch {
    Write-Log "Neizdevas izveidot cikla aizsardzibu (mutex): $_ - turpinu bez tas." "WARN"
}

Write-Log "=== Klienta atjauninasana sakta uz $computerName ==="

# Profilu kopesanas palaisanas uzdevums (ja kopesana uzstadita): SYSTEM uzdevums ik stundu palaiz LabProfileBackup,
# jo ikdienas trigera atkartosana nesakas, ja dators 03:30 gul. Kluda cikla neietekme.
try {
    if ((Get-ScheduledTask -TaskName "LabProfileBackup" -ErrorAction SilentlyContinue) -and (-not (Get-ScheduledTask -TaskName "LabProfileBackup-Kick" -ErrorAction SilentlyContinue))) {
        $bkA = New-ScheduledTaskAction -Execute "schtasks.exe" -Argument '/Run /TN "LabProfileBackup"'
        $bkT = New-ScheduledTaskTrigger -Once -At "2026-10-15 00:15" -RepetitionInterval (New-TimeSpan -Hours 1) -RepetitionDuration (New-TimeSpan -Days 3650)
        $bkP = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest
        $bkS = New-ScheduledTaskSettingsSet -StartWhenAvailable -MultipleInstances IgnoreNew -ExecutionTimeLimit (New-TimeSpan -Minutes 5)
        Register-ScheduledTask -TaskName "LabProfileBackup-Kick" -Action $bkA -Trigger $bkT -Principal $bkP -Settings $bkS -Force | Out-Null
        Write-Log "Uzdevums LabProfileBackup-Kick izveidots (ik stundu palaiz profilu kopesanu)."
    }
} catch {
    Write-Log "LabProfileBackup-Kick: kluda - $_" "WARN"
}

# Palaisanas uzdevums: nodrosina, ka cikls turpinas arii pec datora pamosanas no miega.
# (LabAppUpdate ikdienas trigeris pec pusnakts miega neatkarto ik 15 min.) Kluda cikla neietekme.
try {
    if (-not (Get-ScheduledTask -TaskName "LabAppUpdate-Kick" -ErrorAction SilentlyContinue)) {
        $kAct = New-ScheduledTaskAction -Execute "schtasks.exe" -Argument '/Run /TN "LabAppUpdate"'
        $kTrg = New-ScheduledTaskTrigger -Once -At "2026-10-15 00:00" -RepetitionInterval (New-TimeSpan -Minutes 15) -RepetitionDuration (New-TimeSpan -Days 3650)
        $kPri = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest
        $kSet = New-ScheduledTaskSettingsSet -StartWhenAvailable -MultipleInstances IgnoreNew -ExecutionTimeLimit (New-TimeSpan -Minutes 5)
        Register-ScheduledTask -TaskName "LabAppUpdate-Kick" -Action $kAct -Trigger $kTrg -Principal $kPri -Settings $kSet -Force | Out-Null
        Write-Log "Uzdevums LabAppUpdate-Kick izveidots (atkartosana ik 15 min bez beigam, parlaiz miegu)."
    }
} catch {
    Write-Log "LabAppUpdate-Kick: kluda - $_" "WARN"
}

# ESET versija (tikai lasisana) - nolasam katru reizi, ari izlaistajas, lai
# atskaite vienmer redz aktualo versiju.
$esetInfo = Get-EsetProduct
$esetName = ""
$esetVersion = ""
if ($esetInfo) {
    $esetName = $esetInfo.Name
    $esetVersion = $esetInfo.Version
}

# Windows versija (tikai lasisana) - katru reizi, ari izlaistajas palaisanas,
# lai atskaite vienmer redz aktualo versiju.
$winInfo = Get-WindowsVersionInfo
$windowsVersion = $winInfo.Version
$windowsBuild = $winInfo.Build

# Office produkts un versija (tikai lasisana, tikai atspogulojam) - katru reizi, ari izlaistajas palaisanas.
$officeInfo = Get-OfficeInfo
$officeProduct = $officeInfo.Product
$officeVersion = $officeInfo.Version

# TeamViewer servisa/autostart parbaude (DROSA, nerisina piesaisti) -
# NEATKARIGI no diena/laika grafika, jo tas nav traucejosa darbiba.
Confirm-TeamViewerHealthCheck
Confirm-TeamViewerAlwaysOnline

# Lokala konfiguracija bridinajuma logam (katru reizi, ari izlaistajas, lai tas vienmer ir svaigs)
Write-NoticeConfig -ScheduleFile $ScheduleFile -ComputerName $computerName

# Aparaturas un programmatuas inventars (reizi diena, atseviska procesa ar laika limitu)
Invoke-InventoryCollection -NasRoot $NasRoot

if (-not (Test-Path $ConfigFile)) {
    Write-Log "versions.json nav atrasts ($ConfigFile). Beidzam darbu." "ERROR"
    exit 1
}

try {
    $versions = Get-Content $ConfigFile -Raw -Encoding UTF8 | ConvertFrom-Json
} catch {
    Write-Log "Neizdevas nolasit/parsuot versions.json: $_" "ERROR"
    exit 1
}

$DailyMarkerFile = "C:\ProgramData\LabUpdates\State\last-run-date.txt"
$CommandStateFile = "C:\ProgramData\LabUpdates\State\last-command-id.txt"
$pendingCmd = $null
$ignoreSchedule = $false
try {
    $pendingCmd = Get-PendingCommand -NasRoot $NasRoot -ComputerName $computerName -StateFile $CommandStateFile
} catch {
    Write-Log "Komandu parbaude neizdevas: $_" "WARN"
}
if ($pendingCmd) {
    Set-CommandHandled -StateFile $CommandStateFile -Id $pendingCmd.Id
    if ($pendingCmd.Expired) {
        Write-Log ("Administratora komanda '{0}' ({1}) ir novecojusi - neizpildu." -f $pendingCmd.Command, $pendingCmd.Id) "WARN"
        Write-CommandAck -NasRoot $NasRoot -ComputerName $computerName -Command $pendingCmd -Status "Expired" -Details "Komandas derigums beidzies, pirms dators to panema."
        $pendingCmd = $null
    } elseif ($pendingCmd.Command -eq "UpdateNow") {
        Write-Log ("Administratora komanda UpdateNow ({0}, nosutija {1}) - atjauninu uzreiz, grafiks ignorets." -f $pendingCmd.Id, $pendingCmd.CreatedBy)
        Write-CommandAck -NasRoot $NasRoot -ComputerName $computerName -Command $pendingCmd -Status "Started" -Details "Atjauninasana sakta."
        $ignoreSchedule = $true
    } else {
        Write-Log ("Administratora komanda '{0}' nav atbalstita so klienta versija - izlaizu." -f $pendingCmd.Command) "WARN"
        Write-CommandAck -NasRoot $NasRoot -ComputerName $computerName -Command $pendingCmd -Status "Rejected" -Details "Komanda nav atbalstita."
        $pendingCmd = $null
    }
}
$schedule = Get-ScheduleDecision -Path $ScheduleFile -ComputerName $computerName -DailyMarkerFile $DailyMarkerFile -IgnoreSchedule $ignoreSchedule
Write-Log "Grafika parbaude: $($schedule.Reason)"

if (-not $schedule.Allowed) {
    Write-Log "Atjauninasana sodien NETIEK veikta (skat. iepriekseja rindina iemeslu)."
    Write-StatusReport -NasRoot $NasRoot -ComputerName $computerName -Result "Izlaists" -Details $schedule.Reason -AnyAppInstalled $false -IsSkip $true -EsetName $esetName -EsetVersion $esetVersion -WindowsVersion $windowsVersion -WindowsBuild $windowsBuild -OfficeProduct $officeProduct -OfficeVersion $officeVersion
    if ($pendingCmd) {
        Write-CommandAck -NasRoot $NasRoot -ComputerName $computerName -Command $pendingCmd -Status "Rejected" -Details $schedule.Reason
    }
    Write-Log "=== Klienta atjauninasana pabeigta (izlaista pec grafika) ==="
    exit 0
}

$installedApps = @()
$failedApps = @()
$windowsUpdateSummary = ""
$wuTitles = @()
$wuReboot = $false

# Nevelamo programmu nonemsana (CCleaner). Saraksts - DisplayName precizi.
$RemoveAppNames = @("CCleaner")
try {
    $rmPaths = @("HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*", "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*")
    foreach ($rmName in $RemoveAppNames) {
        $rmEntries = @(Get-ItemProperty -Path $rmPaths -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName -eq $rmName })
        foreach ($rm in $rmEntries) {
            $rmUs = [string]$rm.UninstallString
            $rmExe = ""
            if ($rmUs -match '^"([^"]+)"') { $rmExe = $Matches[1] } else { $rmExe = ($rmUs -split ' ')[0] }
            if ((-not $rmExe) -or (-not (Test-Path $rmExe))) {
                Write-Log "$rmName : atinstaletajs nav atrasts ($rmExe) - izlaists." "WARN"
                continue
            }
            Write-Log "$rmName $($rm.DisplayVersion): atinstalesana (nevelama programma)."
            Get-Process -Name "CCleaner", "CCleaner64", "CCUpdate" -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
            Start-Process -FilePath $rmExe -ArgumentList "/S" -WindowStyle Hidden
            $rmGone = $false
            for ($rmI = 0; $rmI -lt 18; $rmI++) {
                Start-Sleep -Seconds 5
                if (@(Get-ItemProperty -Path $rmPaths -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName -eq $rmName }).Count -eq 0) { $rmGone = $true; break }
            }
            if ($rmGone) {
                Write-Log "$rmName : atinstalets."
                $installedApps += "Atinstalets: $rmName"
            } else {
                Write-Log "$rmName : ieraksts pec 90 s joprojam ir." "WARN"
                $failedApps += "$rmName (atinstalesana nepabeigta)"
            }
        }
    }
} catch {
    Write-Log "Nevelamo programmu nonemsana: kluda - $_" "WARN"
}

# Office (Click-to-Run): uzdodam atjauninasanu FONA cikla sakuma, lai tas notiek lidztekus Windows
# Update un programmam. To kontrole tas pats CSV lauks ThirdPartyApps (atseviska lauka nav).
$officeUpdateStarted = $false
$officeBefore = $null
if ($schedule.ThirdPartyAppsRequested) {
    $officeBefore = Get-OfficeInfo
    $officeUpdateStarted = Start-OfficeUpdate
    if ($officeUpdateStarted) {
        Write-Log ("Office: atjauninasana uzdota fona (" + $officeBefore.Product + " " + $officeBefore.Version + ").")
    } else {
        Write-Log "Office: Click-to-Run atjauninatajs nav atrasts (vai MSI Office, ko atjaunina Windows Update) - izlaists."
    }
}

if ($schedule.WindowsUpdateRequested) {
    Write-Log "--- Windows Update ---"
    $wuResult = Install-WindowsUpdatesFromNas -NasRoot $NasRoot
    $windowsUpdateSummary = $wuResult.Details
    $wuTitles = @($wuResult.Titles)
    $wuReboot = [bool]$wuResult.RebootRequired
    if ($wuResult.Success -and $wuResult.InstalledCount -gt 0) {
        $installedApps += "WindowsUpdate ($($wuResult.InstalledCount) atjauninajumi)"
    } elseif (-not $wuResult.Success) {
        $failedApps += "WindowsUpdate ($($wuResult.Details))"
    }
}

if (-not $schedule.ThirdPartyAppsRequested) {
    Write-Log "ThirdPartyApps nav iesleegts sim datoram - treso pusu programmu parbaude izlaista."
}

# Apvienojam manuali noradito -SkipApps ar CSV faila TeamViewer
# kolonnu noteikto izlaisanu - abi avoti strada kopa.
$effectiveSkipApps = @($SkipApps)
if ($schedule.SkipTeamViewer) {
    Write-Log "TeamViewer atjauninasana izslegta sim datoram CSV faila (kolonna 'TeamViewer')."
    $effectiveSkipApps += "TeamViewer"
    $effectiveSkipApps += "TeamViewerHost"
}

if ($schedule.ThirdPartyAppsRequested) {
foreach ($app in $Apps) {
    $key = $app.Key
    Write-Log "--- Parbaudu: $key ---"

    if ($effectiveSkipApps -contains $key) {
        Write-Log "$key : izlaists (CSV iestatijums vai -SkipApps parametrs)." "INFO"
        continue
    }

    if ($app.SkipIfInstalledPattern -and (Get-InstalledVersion -DisplayNamePattern $app.SkipIfInstalledPattern)) {
        Write-Log "$key : sim datoram ir instalets '$($app.SkipIfInstalledPattern)' - sis variants netiek instalets/atjauninats."
        continue
    }

    $entry = $versions.$key
    if (-not $entry) {
        Write-Log "$key : nav ieraksta versions.json (varbut downloader vel nav to lejupieladejis). Izlaizu." "WARN"
        continue
    }

    $latestVersion = $entry.version
    $relativePath = $entry.relativePath
    $sourcePath = Join-Path $NasRoot $relativePath

    if (-not (Test-Path $sourcePath)) {
        Write-Log "$key : avota fails nav atrasts ($sourcePath). Izlaizu." "ERROR"
        continue
    }

    $installedVersion = Get-InstalledVersion -DisplayNamePattern $app.DisplayNamePattern -ExcludePattern ([string]$app.ExcludePattern)
    Write-Log "$key : instaleta versija = '$installedVersion', pieejama versija = '$latestVersion'"

    if ($app.UpdateOnly -and [string]::IsNullOrWhiteSpace($installedVersion)) {
        Write-Log "$key : sim datoram nav instalets (UpdateOnly) - NEinstaleju, izlaizu."
        continue
    }

    $healEparaksts = $false
    if (-not (Compare-Versions -Installed $installedVersion -Latest $latestVersion)) {
        # eParaksts: registrs rada aktualo versiju, bet C:\Program Files exe var but vecs (versija uzstadita tikai
        # lietotaja profila). Tada gadijuma parinstalejam datoram kopigi (ne biezak ka 1 reizi dienaa).
        if ($key -eq "eParaksts") {
            try {
                $eExe = "C:\Program Files\eparakstitajs3\eparakstitajs3.exe"
                $eMarker = "C:\ProgramData\LabUpdates\eparaksts-heal.txt"
                $eStamp = "$latestVersion|" + (Get-Date -Format "yyyyMMdd")
                $eDone = ""
                if (Test-Path $eMarker) { $eDone = [string](Get-Content $eMarker -ErrorAction SilentlyContinue | Select-Object -First 1) }
                if ($eDone -ne $eStamp) {
                    $eFileVer = ""
                    if (Test-Path $eExe) { $eFileVer = [string](Get-Item $eExe).VersionInfo.FileVersion }
                    $eJars = @(Get-ChildItem "C:\Program Files\eparakstitajs3\app" -Recurse -Filter *.jar -File -ErrorAction SilentlyContinue).Count
                    $eOld = ([string]::IsNullOrWhiteSpace($eFileVer) -or ([version]$eFileVer -lt [version]$latestVersion))
                    if ($eOld -or ($eJars -lt 40)) {
                        $healEparaksts = $true
                        Write-Log "eParaksts : registra versija aktuala, bet Program Files exe = '$eFileVer', jar faili = $eJars - veicu tiru parinstalesanu datoram kopigi."
                        # Tira atinstalesana: nepilnigu instalaciju parasta parinstalesana nelabo.
                        Get-Process -Name "eparakstitajs3" -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
                        $eUninst = @("HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*", "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*")
                        foreach ($ePr in @(Get-ItemProperty -Path $eUninst -ErrorAction SilentlyContinue | Where-Object { ($_.DisplayName -like "eParakst*") -and ($_.DisplayName -notlike "*Token Signing*") -and ($_.WindowsInstaller -eq 1) })) {
                            $ePx = Start-Process -FilePath "msiexec.exe" -ArgumentList @("/x", $ePr.PSChildName, "/qn", "/norestart") -PassThru -WindowStyle Hidden
                            [void]$ePx.WaitForExit(180000)
                        }
                        if (Test-Path "C:\Program Files\eparakstitajs3") { Remove-Item "C:\Program Files\eparakstitajs3" -Recurse -Force -ErrorAction SilentlyContinue }
                        if (-not (Test-Path (Split-Path $eMarker))) { New-Item -ItemType Directory -Path (Split-Path $eMarker) -Force | Out-Null }
                        Set-Content -Path $eMarker -Value $eStamp -Encoding ASCII
                    }
                }
            } catch {
                Write-Log "eParaksts : exe parbaude neizdevas - $_" "WARN"
            }
        }
        if (-not $healEparaksts) {
            Write-Log "$key : jau aktuala versija, instalesana nav vajadziga."
            continue
        }
    }

    Write-Log "$key : instalesu jaunu versiju ($installedVersion -> $latestVersion)..."
    $exitCode = Install-App -Key $key -InstallType $app.InstallType -SilentArgs $app.SilentArgs -SourcePath $sourcePath

    # 3010 = Windows Installer: "veiksmigi, bet vajadzigs restarts" (piem.
    # ja atjauninata programma tobrid tika lietota) - NAV kluda.
    # 1638 = jau uzstadita ta pati/jaunaka versija; 1641 = veiksmigi, restarts iniciets
    if ($exitCode -eq 0 -or $exitCode -eq 3010 -or $exitCode -eq 1638 -or $exitCode -eq 1641) {
        if ($exitCode -eq 3010) {
            Write-Log "$key : instalesana veiksmiga (exit code 3010 - izmainas pilniba stasies speka pec restarta)."
        } else {
            Write-Log "$key : instalesana veiksmiga (exit code 0)."
        }
        $installedApps += "$key ($installedVersion -> $latestVersion)"
        if (($key -eq "TeamViewer") -or ($key -eq "TeamViewerHost")) {
            Repair-TeamViewerAutostart
        }
    } else {
        Write-Log "$key : instalesana pabeigta ar exit code $exitCode (parbaudit, vai tas ir kluda)." "WARN"
        $failedApps += "$key (exit $exitCode)"
    }
}
}

# Office: ja atjauninatajs vel darbojas, pagaidam; tad salidzinam versiju un zinojam par izmainam
if ($officeUpdateStarted) {
    Wait-OfficeUpdate -MaxMinutes 15
    $officeAfter = Get-OfficeInfo
    if ($officeAfter.Version -ne "") {
        $officeProduct = $officeAfter.Product
        $officeVersion = $officeAfter.Version
    }
    if (($officeBefore.Version -ne "") -and ($officeAfter.Version -ne "") -and ($officeBefore.Version -ne $officeAfter.Version)) {
        Write-Log ("Office: atjaunots " + $officeBefore.Version + " -> " + $officeAfter.Version)
        $installedApps += ("Office (" + $officeBefore.Version + " -> " + $officeAfter.Version + ")")
    } else {
        Write-Log "Office: versija nav mainijusies (visticamak jau aktuala sava kanala, vai atjauninasana vel turpinas fona)."
    }
}

# Adobe CC lietotnu atjauninasana ar Remote Update Manager (saraksts Config\adobe-rum.txt)
if ($schedule.ThirdPartyAppsRequested) {
    try {
        $rumListFile = Join-Path $NasRoot "Config\adobe-rum.txt"
        $rumTargets = @()
        if (Test-Path $rumListFile) {
            $rumTargets = @(Get-Content $rumListFile | ForEach-Object { $_.Trim() } | Where-Object { $_ -and -not $_.StartsWith("#") })
        }
        if ($rumTargets -contains $computerName) {
            $rumExe = "C:\Program Files (x86)\Common Files\Adobe\OOBE_Enterprise\RemoteUpdateManager\RemoteUpdateManager.exe"
            $RumMaxMinutes = 180
            if (-not (Test-Path $rumExe)) {
                Write-Log "AdobeRUM : RemoteUpdateManager nav atrasts ($rumExe) - izlaists." "WARN"
                $failedApps += "AdobeRUM (RUM nav atrasts)"
            } else {
                $rumState = "C:\ProgramData\LabUpdates\State"
                if (-not (Test-Path $rumState)) { New-Item -ItemType Directory -Path $rumState -Force | Out-Null }
                $rumOut = Join-Path $rumState "rum-last.log"
                $rumErr = Join-Path $rumState "rum-last.err.log"
                Write-Log "AdobeRUM : palaizu RemoteUpdateManager --action=install (limits $RumMaxMinutes min)..."
                $rumProc = Start-Process -FilePath $rumExe -ArgumentList "--action=install" -NoNewWindow -PassThru -RedirectStandardOutput $rumOut -RedirectStandardError $rumErr
                if (-not $rumProc.WaitForExit($RumMaxMinutes * 60 * 1000)) {
                    try { $rumProc.Kill() } catch { }
                    Write-Log "AdobeRUM : parsniegts $RumMaxMinutes min limits - process aptureets." "WARN"
                    $failedApps += "AdobeRUM (laika limits)"
                } else {
                    $rumCode = $rumProc.ExitCode
                    $rumText = ""
                    if (Test-Path $rumOut) { $rumText = [System.IO.File]::ReadAllText($rumOut) }
                    $rumTail = @($rumText -split "`r?`n" | Where-Object { $_.Trim() -and $_ -notmatch '^\*+$' } | Select-Object -Last 30)
                    foreach ($rumLine in $rumTail) { Write-Log ("AdobeRUM > " + $rumLine.Trim()) }
                    if ($rumCode -eq 0) {
                        if ($rumText -match "(?i)successfully installed") {
                            Write-Log "AdobeRUM : atjauninajumi uzstaditi (exit code 0)."
                            $installedApps += "Adobe CC lietotnes (RUM)"
                        } else {
                            Write-Log "AdobeRUM : pabeigts (exit code 0), jaunu atjauninajumu nebija."
                        }
                    } else {
                        Write-Log "AdobeRUM : beidzas ar exit code $rumCode (sk. $rumOut)." "WARN"
                        $failedApps += "AdobeRUM (exit $rumCode)"
                    }
                }
            }
        }
    } catch {
        Write-Log "AdobeRUM : kluda - $_" "WARN"
        $failedApps += "AdobeRUM (kluda)"
    }
}
# Sakopsana - iztiram lokalo darba mapi
Remove-Item -Path $LocalWork -Recurse -Force -ErrorAction SilentlyContinue

$anyInstalled = ($installedApps.Count -gt 0)
if ($failedApps.Count -gt 0) {
    $statusResult = "Dalejs"
} elseif ($anyInstalled) {
    $statusResult = "Atjauninats"
} else {
    $statusResult = "JauAktuals"
}
$detailParts = @()
if ($installedApps.Count -gt 0) {
    $detailParts += ("Instaleti: " + ($installedApps -join '; ') + ".")
} else {
    $detailParts += "Viss aktuals, nekas nebija jainstale."
}
if ($failedApps.Count -gt 0) {
    $detailParts += ("KLUDAS: " + ($failedApps -join '; ') + ".")
} else {
    $detailParts += "Kludu nav."
}
$statusDetails = $detailParts -join " "
Write-StatusReport -NasRoot $NasRoot -ComputerName $computerName -Result $statusResult -Details $statusDetails -AnyAppInstalled $anyInstalled -EsetName $esetName -EsetVersion $esetVersion -WindowsVersion $windowsVersion -WindowsBuild $windowsBuild -OfficeProduct $officeProduct -OfficeVersion $officeVersion -Installed $installedApps -Failed $failedApps -WuTitles $wuTitles -RebootRequired $wuReboot

# Ja cikla laika kaut kas tika instalets, inventaru ievacam VELREIZ (cikla beigas), lai atskaite
# nerada pirms-cikla stavokli. Tas pats atseviskais process ar laika limitu; kluda cikla neietekme.
if ($anyInstalled) {
    Invoke-InventoryCollection -NasRoot $NasRoot -Force
}

# Windows 11 taskbar ikonas (Config\taskbar-pins.csv). Kluda cikla neietekme.
try {
    $pinScript = Join-Path $NasRoot "Scripts\ensure-taskbar-pins.ps1"
    if (Test-Path $pinScript) { & $pinScript -NasRoot $NasRoot }
} catch {
    Write-Log "Taskbar pins: kluda - $_" "WARN"
}
Write-Log "=== Klienta atjauninasana pabeigta ==="

if ($pendingCmd) {
    Write-CommandAck -NasRoot $NasRoot -ComputerName $computerName -Command $pendingCmd -Status "Done" -Details ("Rezultats: " + $statusResult + ". " + $statusDetails)
}

if ($schedule.ShutdownAfterRequested) {
    Write-Log "ShutdownAfter=Yes sim datoram - ieplanoju izslegsanu pec 5 minutem (lai dotu laiku, ja kads tomer dara darbu)."
    try {
        # Komentars satur atstarpes, tapec tas JAIEKLAUJ PEDINAS pasiem
        # (Start-Process masiva elementus pats NEcite). Citadi shutdown.exe
        # sanem atseviskus vardus ka nezinamus parametrus un datoru NEIZSLEDZ.
        $shutdownComment = Get-QuotedArg -Value "Planota atjauninasana pabeigta, dators izslegsies automatiski."
        $shutdownArgs = @("/s", "/t", "300", "/c", $shutdownComment)
        $shutdownProc = Start-Process -FilePath "shutdown.exe" -ArgumentList $shutdownArgs -Wait -PassThru -WindowStyle Hidden

        if ($shutdownProc.ExitCode -eq 0) {
            Write-Log "Izslegsana ieplanota (exit code 0): dators izslegsies pec 5 minutem."
        } else {
            Write-Log "shutdown.exe atgrieza exit code $($shutdownProc.ExitCode) - izslegsana, iespejams, NAV ieplanota." "WARN"
        }
    } catch {
        Write-Log "Neizdevas ieplanot izslegsanu: $_" "ERROR"
    }
}
