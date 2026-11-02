# Darba procedūras un biežākās problēmas

Komandas paredzētas PowerShell. Vienmēr norādīts, uz kura datora un ar kādām tiesībām tās palaist.

## Skriptu izvietošana

Faili no `src/` jākopē uz **`C:\Scripts`** admin PC (PIUAC-ASKOLDS), pēc tam:

```powershell
Get-ChildItem C:\Scripts\*.ps1 | Unblock-File
```

`patch-*.ps1` palaiž **vienu reizi uz admin PC kā administrators**; tie maina NAS `Scripts\client-install.ps1` (rezerves kopija `.bak-*`, idempotenti, ASCII/CRLF, enkuru meklēšana).

> `src/client/client-install.ps1` ir **vecāka kopija** (2026-10-12) ar izņemtu TeamViewer API token. Aktuālā versija ar visiem ielāpiem ir NAS `\\PIUAC_CLOUD\Updates\Scripts\client-install.ps1`; pirms rediģēšanas to nolasīt no NAS.

## Jauna datora pieslēgšana (kopsavilkums)

1. **Mērķa dators, administrators:** `Enable-PSRemoting -Force -SkipNetworkProfileCheck`; ja `Administrator` ir izslēgts: `net user Administrator * /active:yes`.
2. **Admin PC, administrators:** `cd C:\Scripts; .\remote-setup-client.ps1 -ComputerNames "ip,ip"` (prasa Administrator + flotes paroli).
3. Pievienot rindu `Config\device-schedule.csv` (portatīvajiem atsevišķa grupa); vajadzības gadījumā pievienot datoru `Targets` kolonnā `apps-managed.csv` rindām (Inkscape, Blender u.c.).
4. Pirmo ciklu palaist ārpus UpdateTime loga: dzēst `last-run-date.txt`, palaist `LabAppUpdate`.
5. Atstāt lieko `admin` kontu likvidēšanai; turpmāk lietot iebūvēto `Administrator`.

## Cikla piespiedu palaišana

**Mērķa dators, administrators:**

```powershell
Remove-Item C:\ProgramData\LabUpdates\State\last-run-date.txt -ErrorAction SilentlyContinue; Start-ScheduledTask -TaskName LabAppUpdate
```

Ja `UpdateTime` ir aizpildīts, cikls tiks izlaists ārpus loga ±20 min. Pagaidu risinājums: iztukšot `UpdateTime` un `ShutdownAfter=No` šim datoram `device-schedule.csv` (pēc tam **atjaunot**). Žurnāls: `\\PIUAC_CLOUD\Updates\Logs\Clients\<PC>-*.log`.

## Attālā komanda vairākiem datoriem (IP no DNS)

**Admin PC, administrators:**

```powershell
$cred=Get-Credential Administrator; $pcs=1..12|%{"DATORKLASE-{0:D2}" -f $_}; $pcs+="DATORKLASE-PASN"
$ips=$pcs|%{([Net.Dns]::GetHostAddresses($_)|Where-Object{$_.AddressFamily -eq "InterNetwork"}|select -First 1).IPAddressToString}
Invoke-Command -ComputerName $ips -Credential $cred -ScriptBlock { ... }
```

Piezīmes: izmantot IP (TrustedHosts); PowerShell pārbaudēs rakstīt `Where-Object {…}` vai `? DisplayName` ar atstarpi pēc `?` (kļūda `?DisplayName` nav komanda); attālā `Start-Process` ar GUI instalatoriem nedarbojas — izmantot plānoto uzdevumu (`Register-ScheduledTask … -User SYSTEM`).

## Adobe Creative Cloud: Kursanta tiesības uz laiku

Piešķirt (**admin PC, administrators**):

```powershell
… -ScriptBlock { Add-LocalGroupMember -Group Administrators -Member Kursants }
```

Noņemt (to pašu bloku ar `Remove-LocalGroupMember`). Kursantam jāizrakstās un jāpierakstās no jauna. 2026-10-29 noņemts visos klases datoros, izņemot **DATORKLASE-PASN** (pasniedzēja dators bija izslēgts — jāpārbauda un jānoņem, kad ieslēgts; `DATORKLASE-07`: Kursants grupā nebija).

## Zināmās problēmas un risinājumi

| Problēma | Cēlonis / risinājums |
|---|---|
| Cikls izlaists "jau tika uzsākta iepriekšējā palaišanas reize" | marķieris `last-run-date.txt` — dzēst |
| Cikls izlaists "Grafika parbaude … laiks" | `UpdateTime` logs — iztukšot pagaidām |
| "remote-setup" Access denied jaunam portatīvajam | iebūvētais Administrator izslēgts → `net user Administrator * /active:yes` |
| VLC exit 1603 | restartēt datoru un atkārtot ciklu |
| Windows Update fāze karājas > 1 h | restartēt un atkārtot |
| Recuva bezgalīga "atjaunināšana" (1.55 pret 1.55.0.133) | `patch-version-compare.ps1` (salīdzina kopīgās komponentes) |
| Openlab-1 Win11 autologon "User" kļūda | iztīrīt Winlogon `AutoAdminLogon` ierakstus |
| AdobeCC "nav noradits SilentArgs" | `SilentArgs=--mode=stub` (`apps-managed.csv`) |
| Cikls karājas pie Adobe instalatora | `patch-exe-nowait.ps1` |
| TeamViewerHost exit code 2 (DATORKLASE-01) | vēl nav izmeklēts; vērot, vai atkārtojas |
| Mairita (PIUAC-MAIRITA) Kick uzdevums neparādās | parādās pēc datora ieslēgšanas (viņa strādā pirmdienās) |
| ClickShare Wi-Fi pazūd | iespējams aparatūras defekts; instrukcija Claude Docs dokumentā "ClickShare" |
