# Arhitektūra

Apkopots no sarunām līdz 2026-11-02. Sistēma ir paredzēta skolai/birojam (~30+ datori, Windows 10/11) **bez domēna un bez servera**.

## Pamatprincips: "pull" modelis

Centrālā vieta ir Synology NAS `192.168.3.31` (`\\PIUAC_CLOUD`, koplietojums `Updates`). Klienti paši velk skriptus un instalatorus no NAS; admin dators tikai sagatavo saturu un konfigurāciju.

```
 Admin PC (PIUAC-ASKOLDS)                 NAS \\PIUAC_CLOUD\Updates                 Klienta dators
 ─────────────────────────                ──────────────────────────                ───────────────
 downloader.ps1 (winget) ───────────────▶ Cache\<Key>\ + versions.json
 config-panel.ps1 (GUI) ────────────────▶ Config\*.csv  (grafiks, lietotņu saraksts)
 backup-manager.ps1 (GUI) ──────────────▶ Scripts\*, Tools\lab-backup\
                                           Scripts\client-install.ps1 ◀── LabAppUpdate (ik 15 min)
                                           Logs\Clients, Logs\Status, Logs\Inventory ◀── klients raksta
```

## NAS struktūra (`\\PIUAC_CLOUD\Updates`)

| Mape | Saturs |
|---|---|
| `Scripts\` | `client-install.ps1` (klienta galvenais skripts; NAS versija ir aktuālā, ar visiem ielāpiem) |
| `Config\` | `device-schedule.csv`, `apps-managed.csv`, `apps-ignore.txt` |
| `Cache\<Key>\` | winget lejupielādēti instalatori + `versions.json` |
| `Logs\Clients\<PC>-<laiks>.log` | klienta cikla žurnāli |
| `Logs\Status\<PC>.json` | klienta statuss (atskaitei) |
| `Logs\Inventory\<PC>.json` | programmatūras/aparatūras inventārs (`Software.Programs[]`) |
| `Tools\lab-backup\` | restic rezerves kopēšanas skripti |

## Klienta komponenti

- **`LabAppUpdate`** plānotais uzdevums (lietotājs `labupdate`, ik 15 min) palaiž NAS `Scripts\client-install.ps1`.
- **`LabAppUpdate-Kick`** — palīguzdevums cikla uzsākšanai; analoģiski **`LabProfileBackup`** + `-Kick`.
- Cikls lemj, vai darboties, pēc `Config\device-schedule.csv`:
  `ComputerName, Group, UpdateDays, UpdateTime, ShowNotification, ShutdownAfter, WindowsUpdate, ThirdPartyApps, TeamViewer, Enabled`.
  - `UpdateTime` logs = mērķa laiks ±20 min (tukšs = jebkurā laikā).
  - Vienu reizi dienā: marķieris `C:\ProgramData\LabUpdates\State\last-run-date.txt` (dzēšot to, var piespiest atkārtotu ciklu).
  - `ShutdownAfter=Yes` izslēdz datoru pēc cikla (dienas laikā nelietot!).
- Cikla fāzes: Windows Update → iebūvētās lietotnes (`$Apps` skriptā: Firefox, Chrome, Zoom, TeamViewer, VLC, eParaksts, PowerShell) → pārvaldītās lietotnes no `apps-managed.csv` → inventārs → statuss.
- Nevēlamo programmu noņemšana: `$RemoveAppNames` (pašlaik `CCleaner`), tiek atinstalēts klusi katrā ciklā.

## `Config\apps-managed.csv`

Kolonnas: `Enabled, Key, DisplayName, WingetId, DisplayNamePattern, ExcludePattern, InstallType, SilentArgs, Mode, Architecture, DlInstallerType, Targets`

- `Mode`: `UpdateOnly` (atjaunina tikai, ja jau uzstādīts) vai `Install` (uzstāda visiem mērķa datoriem).
- `Targets`: datoru vārdi, atdalīti ar `;`; tukšs = visi.
- `exe` tipa instalatoriem **obligāti** jānorāda `SilentArgs`, citādi cikls izlaiž instalāciju (kļūda "nav noradits SilentArgs").
- `downloader.ps1` (admin PC, administrators) lejupielādē instalatorus ar winget uz `Cache\<Key>`.

## Admin rīki (`src/admin`)

- **`config-panel.ps1`** — grafiks, statusa atskaite (krāsas: zaļš ≤10 d., oranžs ≤14 d., sarkans vēlāk; piezīme "Dators nav redzēts tīklā…" tikai oranžajām rindām), ierīču saraksts.
- **`apps-managed-editor.ps1`** — `apps-managed.csv` redaktors; poga "Mekleet jaunas programmas" salīdzina visu datoru inventāru ar sarakstu (dzeltens = jauna, zaļš = jau automatizēta; ignorētās → `Config\apps-ignore.txt`).
- **`backup-manager.ps1`** — restic rezerves kopijas (lietotāja profili uz NAS); parole **netiek glabāta repozitorijā**.
- **`inventory-report.ps1`**, **`generate-status-report.ps1`** — atskaites.

## Attālā pievienošana (bez domēna)

- Mērķa datorā: `Enable-PSRemoting -Force -SkipNetworkProfileCheck`; iebūvētajam `Administrator` jābūt aktīvam (`net user Administrator * /active:yes`).
- Admin PC: TrustedHosts jau ietver `192.168.3.*`; `Invoke-Command -ComputerName <IP>` (nevis vārdu — TrustedHosts atbilst tikai IP) ar `Get-Credential Administrator`.
- `remote-setup-client.ps1 -ComputerNames "ip,ip"` uzstāda klientu (prasa Administrator + flotes paroli).

## Adobe Creative Cloud (klases datori)

- Rinda `AdobeCC` `apps-managed.csv`: winget `Adobe.CreativeCloud`, `InstallType=auto`, **`SilentArgs=--mode=stub`**, `Mode=Install`, `Targets` = `DATORKLASE-01..12;DATORKLASE-PASN`.
- Stub instalators prasa internetu; CC pats vēlāk atjaunojas (6.11.0.479).
- **Ielāps `patch-exe-nowait.ps1`** (pielietots): `exe` instalatori vairs negaida visu apakšprocesu koku (`Start-Process -Wait` karājās, jo CC atstāj fona procesus), bet tikai pašu instalatoru ar 10 min limitu.
- **Kļūda "Adobe Creative Cloud … missing or damaged" / balts logs**: rodas, ja CC palaiž ar paaugstinātām tiesībām kā cits lietotājs (iebūvētais `Administrator`, Edge WebView2 neizdodas izveidot datu direktoriju `C:\Users\Administrator\AppData\Local\Adobe\webview2`). Parastam lietotājam CC atveras normāli. Tīkls, WebView2 (155.x) un Adobe saimniekdatori ir pārbaudīti — kārtībā.
- Lai instalētu lietotnes (Lightroom u.c.) caur CC: uz laiku pievienot `Kursants` lokālo administratoru grupai, lietotājs izrakstās/pierakstās, atver CC **parasti** un instalē; pēc tam tiesības noņemt (komandas — `docs/darba-procedura.md`).
- Licencēšana: individuālā licence = 2 ierīces; 13 datoriem vajadzīgs Adobe Admin Console **Shared Device License** vai pakotne (Named User + pakotne).

## Ierīču uzskaite (apturēts)

Skat. `docs/iericu-uzraudziba.md`.
