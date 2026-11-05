# Filiāle Auce — sākuma dokuments jaunai sarunai

Sagatavots 2026-11-04. Šis fails ir **atsevišķas sarunas** sākumpunkts: atjaunināšanas un uzraudzības sistēmas paplašināšana uz filiāli Aucē (vēlāk arī citām filiālēm). Lokālās (Dobeles) sistēmas darbs turpinās citā sarunā — šajā sarunā to nemainīt.

## 0. Kā sākt jauno sarunu

1. Izlasīt `CLAUDE.md` (projekta konteksts, darba stils) un **šo failu**.
2. Lūgt Askoldam aprakstīt **viņa izdomāto risinājumu** un salīdzināt to ar 2026-10-08 plānu (5. sadaļa) — kas sakrīt, kas atšķiras, kādi riski.
3. Darbu reģistrēt atsevišķi: `docs/filiales-progress.md` (žurnāls) un šī faila sadaļa "Lēmumi"; filiāļu skripti — `src/filiales/`. `CLAUDE.md` lokālās sistēmas sadaļas šajā sarunā nemainīt (tikai saite uz šo failu).

## 1. Situācija filiālē (zināmais)

- Aucē **16 datori**, gandrīz visi Windows 11, ~2 ar Windows 10 (atbalsts beidzies 2025-10-14).
- Filiāļu tīklus **neadministrējam**; maršrutētājus (arī centrā) **konfigurēt nevar** → nav porta pārsūtīšanas, **nav VPN**.
- Piekļuve datoriem — **TeamViewer**.
- Centra NAS ārpus biroja pieejams tikai ar **QuickConnect** (tas neatbalsta SMB/WebDAV/FTP/NFS skriptiem).
- Office 365 (izglītības licence) gandrīz visiem; OneDrive kopīgai krātuvei neder.
- Askolda prioritātes: (1) atskaites par filiāļu datoriem jāsavāc centra NAS; (2) iespēja pēc vajadzības palaist skriptus; (3) filiāļu datori drīkst visu lejupielādēt tieši no interneta (NAS kešs nav obligāts).
- Nav zināms (jānoskaidro): datoru vārdi/konti filiālē, vai ir kopīgs lokālais Administrator ar vienu paroli, vai filiālē ir kāds "vienmēr ieslēgts" dators/NAS, interneta ātrums, vai izejošais 443 ir atvērts.

## 2. Kā darbojas lokālā sistēma (kas jāatkārto)

Sīkāk: `docs/arhitektura.md`, `docs/darba-procedura.md`, `docs/prasibas.md`.

- **Pull modelis**: katrā datorā plānotais uzdevums `LabAppUpdate` (konts `labupdate`, ik 15 min) palaiž NAS `\\192.168.3.31\Updates\Scripts\client-install.ps1` caur **SMB**.
- Cikls lemj pēc `Config\device-schedule.csv` (`ComputerName, Group, UpdateDays, UpdateTime ±20 min, ShowNotification, ShutdownAfter, WindowsUpdate, ThirdPartyApps, TeamViewer, Enabled`), vienreiz dienā (marķieris `C:\ProgramData\LabUpdates\State\last-run-date.txt`).
- Cikla fāzes: nevēlamo programmu noņemšana (CCleaner) → Windows Update (PSWindowsUpdate modulis no NAS) → iebūvētās lietotnes (Firefox, Chrome, Zoom, TeamViewer, VLC, eParaksts, PowerShell) → `Config\apps-managed.csv` lietotnes (instalatori no NAS `Cache\<Key>\`, ko sagatavo `downloader.ps1` ar winget uz admin PC) → Office Click-to-Run → Adobe RUM (tikai `Config\adobe-rum.txt`) → inventārs → statuss → (ShutdownAfter) izslēgšana.
- **Statuss** `Logs\Status\<PC>.json` (laiki, `LastResult`, `Details`, `LastSuccessfulUpdate`, `LastSkipReason`, ESET/Windows/Office versijas, `History` ar pēdējiem cikliem: `Time, Result, Installed[], Failed[], WindowsUpdates[], RebootRequired`).
- **Inventārs** `Logs\Inventory\<PC>.json` — `src/client/collect-inventory.ps1` (tikai lasīšana; režīms `-Mode Json` atgriež JSON tekstu — der aģentam bez NAS). ~34 KB/dators.
- **Žurnāli** `Logs\Clients\<PC>-<laiks>.log`.
- **Admin rīki** (admin PC PIUAC-ASKOLDS, `C:\Scripts`): `config-panel.ps1` (grafiks, atskaite ar krāsām: zaļš ≤10 d., oranžs ≤14 d., sarkans; "nav redzēts tīklā"), `apps-managed-editor.ps1`, `inventory-report.ps1`, `generate-status-report.ps1`, `backup-manager.ps1`. Atskaite lasa **tās pašas NAS mapes** — ja filiāļu dati nonāk `Logs\Status` / `Logs\Inventory` tajā pašā formātā, panelis strādā bez izmaiņām.
- Klienta uzstādīšana: `enable-remoting-bootstrap.ps1` (WinRM) → `remote-setup-client.ps1` / `setup-client.ps1` (konts `labupdate`, uzdevumi). **Filiālē WinRM no centra nebūs sasniedzams** → uzstādīšana caur TeamViewer ar vienu komandu katrā datorā.

## 3. Kas filiālē NEDER no lokālās sistēmas

- SMB uz NAS pa internetu (ports 445 — drošība, ISP bloķē, lēns).
- WinRM/`Invoke-Command` no admin PC (nav maršruta uz filiāli).
- Wake-on-LAN no NAS (cits tīkls) — filiālē vajadzīgs cits risinājums vai grafiks dienas laikā / `StartWhenAvailable`.
- NAS kešs instalatoriem un PSWindowsUpdate no NAS — jāņem no interneta (PowerShell Gallery / winget / ražotāju saites) ar kontrolsummas pārbaudi.
- Paroles skriptos (`labupdate`, TeamViewer API token) — pa internetu nedrīkst.

## 4. Mācības no lokālās sistēmas (lai neatkārtotu kļūdas)

- `exe` instalatoriem obligāti `SilentArgs`; `Start-Process -Wait` var karāties uz fona procesiem (Adobe) → gaidīt tikai instalatoru ar limitu.
- Versiju salīdzināšana: salīdzināt kopīgās komponentes (1.55 pret 1.55.0.133).
- winget kā SYSTEM/bez lietotāja: App Execution Alias un per-user problēmas; lokāli winget lieto tikai admin PC lejupielādei.
- GUI instalatori caur attālu `Start-Process` nestrādā → vienreizējs plānotais uzdevums kā SYSTEM.
- CSV faili (`device-schedule.csv`) ir ar pēdiņām; rediģējot saglabāt kodējumu (BOM) un CRLF.
- Ielāpi `client-install.ps1`: idempotenti, `.bak-*` kopija, ASCII/CRLF, enkuru meklēšana; NAS dzīvā versija ir aktuālā (repozitorija `src/client/client-install.ps1` ir veca).
- Adobe CC: lietot ar parastu lietotāju; Shared Device pakotnes datoros atjaunināšanai ir RUM.
- Windows 11 uz neatbalstīta CPU: `HKLM\SYSTEM\Setup\MoSetup\AllowUpgradesWithUnsupportedTPMOrCPU=1` + `setup.exe` no ISO (OPENLAB-2, 2026-11-04).
- Atskaitē "nav redzēts tīklā" pašlaik balstās uz LAN — filiālē jābalstās uz pēdējā statusa laiku.

## 5. Iepriekšējais plāns (2026-10-08, `docs/dokumenti/Filialu-risinajuma-planojums-v1.docx`)

Nekas no tā vēl nav uzbūvēts. Kopsavilkums:

- **Arhitektūra**: viss tikai izejoši. Filiāles datora **aģents** (ik ~15 min) caur HTTPS raksta statusu/inventāru **mākoņa krātuvē** (ieteikts **Backblaze B2**, privāts bucket; rezerve Cloudflare R2): `inbox/` (raksta aģenti), `outbox/` (komandas/grafiks, raksta NAS). NAS ar **Cloud Sync** pats ielasa `inbox/` → `Logs\Status`, `Logs\Inventory`, un izsūta `outbox/`. NAS internetam netiek atvērts.
- **Posmi**: (1) tikai atskaites — zems risks; (2) komandas pēc pieprasījuma, fiksēts saraksts, **parakstītas** ar privāto atslēgu — vidējs; (3) atjaunināšana tieši no interneta (Windows Update; programmas pēc iespējām) — vidējs.
- **Drošība**: fiksēts komandu saraksts; komandu paraksts (privātā atslēga tikai admin PC); skriptu kontrolsumma; atslēgas ar prefiksu katrai filiālei; komandu žurnāls un "kill switch".
- **Riski**: filiāles ugunsmūris (443), winget bez lietotāja, PSWindowsUpdate avots, Win 10 datori, B2 izmaksas (dienas limiti), ES reģions, aģenta roku uzstādīšana; alternatīva — gatavi RMM rīki.
- **Atvērtie jautājumi tolaik**: vai Backblaze konts/bucket izveidots; ES reģions; kā nogādāt aģentu (TeamViewer fails vai viena lejupielādes komanda); kur glabāt un dublēt privāto atslēgu; vai datu glabāšana mākonī atbilst iestādes noteikumiem.
- **Plānotie soļi**: B2 konts + bucket → atslēgas ar prefiksu un Cloud Sync uz NAS → aģents 1. posmam → tests uz 2 Auces datoriem → visi 16 → citas filiāles.

## 6. Noteikumi jaunajai sarunai

- Saziņa latviski, īsi; komandas pa vienam solim, gaidīt apstiprinājumu; vienmēr norādīt **datoru un tiesības**.
- Paroles/tokeni/privātās atslēgas **nekad** repozitorijā vai atbildēs.
- Lokālo sistēmu (NAS `Scripts\client-install.ps1`, `Config\*.csv`) mainīt tikai, ja tas apzināti vajadzīgs filiālēm un saskaņots — Dobeles datori no tās atkarīgi.
- Filiāļu dati atskaitē jāatšķir (piemēram, `Group` = `Auce-…`), lai panelī var filtrēt.

## Lēmumi (filiāles)

- 2026-11-04 — **Arhitektūra: vietējais "hub" portatīvais filiālē** (aizstāj 2026-10-08 mākoņa/B2 plānu). Vecs portatīvais Aucē, vienmēr ieslēgts, pilda NAS + admin datora lomu: SMB koplietojums ar skriptiem/konfigurāciju/kešu, filiāles datori to velk kā Dobelē (pull, `LabAppUpdate`); WinRM, WoL un instalatoru kešs strādā filiāles LAN ietvaros. Piekļuve portatīvajam — TeamViewer.
- 2026-11-04 — **Atskaites uz centru: Synology Drive Client caur QuickConnect** (Tailscale atmests: licence nav paredzēta iestādei, tunelis uz Dobeles tīklu ir lielāks risks). Portatīvais sinhronizē tikai atsevišķu Team Folder (piem. `Filiales\Auce\`), nevis `Updates`; NAS plānotais uzdevums kopē statusu/inventāru uz `Logs\Status` / `Logs\Inventory`, lai panelis strādā bez izmaiņām.
- 2026-11-04 — **Instalatoru kešs tikai portatīvajā**: portatīvais katru nakti pats lejupielādē programmu atjauninājumus (kā `downloader.ps1` Dobelē) un glabā lokāli; filiāles datori tos ņem no portatīvā koplietojuma. Ar Dobeles NAS kešs **netiek sinhronizēts** (caur Drive iet tikai atskaites un skripti/grafiks).
- 2026-11-04 — Drošība: atsevišķs DSM konts (piem. `auce-sync`) tikai ar šo mapi — **obligāts**; atskaites tikai Auce → centrs, skripti/grafiks tikai centrs → Auce (atsevišķas mapes vai sinhronizācijas uzdevumi, ne divvirzienu viena mape).
- 2026-11-04 — Drive Client: **divi sinhronizācijas uzdevumi** — `Atskaites` Upload only, `Skripti` Download only (+ NAS ACL Deny). Tests parādīja, ka lokāli izmainīts `Skripti` fails netiek atjaunots → **skriptu integritāte jānodrošina ar Authenticode parakstu** (privātā atslēga tikai PIUAC-ASKOLDS; hub un filiāles datori palaiž tikai parakstītus skriptus) — atvērts, risināt, veidojot `src/filiales/`.
- 2026-11-05 — **Auces programmas:** tikai iebūvētās (`client-install.ps1` saraksts: Firefox, Chrome, Zoom, TeamViewer(+Host atjaunināšana), VLC, eParaksts, PowerShell 7 tikai atjaunināšana) + Windows Update + Office Click-to-Run; **bez `apps-managed.csv`**. Grafikā `WindowsUpdate=Yes`, `ThirdPartyApps=Yes` (Office atjaunināšana piesaistīta ThirdPartyApps). Iebūvētās tiek arī uzstādītas, ja trūkst.
- 2026-11-05 — Klientus uzstāda ar filiāles `setup-client.ps1` (dzīvā versija bez paroles, `-NasRoot \\AUCEUPDATE-PC\Updates` noklusējums, parole tiek prasīta), publicēts hub `Scripts\`. Pirms vešanas uz Auci — **tests Dobelē ar norakstāmu E5540 kā "Auces klientu"**.

**Zināmie riski / prasības:** portatīvais = vienīgais kļūmes punkts (vads, Win 11, bez miega, auto-start pēc strāvas, akumulatora uzlādes limits); Drive Client darbojas lietotāja sesijā → auto-pieteikšanās ierobežotam lietotājam + ekrāna bloķēšana; "nav redzēts tīklā" pēc pēdējā statusa laika; `Group = Auce-…`; filiāles tīkla īpašnieku informēt par vienmēr ieslēgtu ierīci.

**Nākamie soļi (2026-11-05 beigās):** (1) PC000062 tiek norakstīts → programmu uzstādīšanu no hub keša un pilnu cikla statusu pārbaudīt ar **pirmo īsto Auces datoru**; ja cikls apstājas Windows Update laikā — izmeklēt (tīkla draiveris / SMB); (2) tīrīšana: PC000062 izņemt no `C:\Scripts\Filiales\Auce\Config\device-schedule.csv` (+ publicēt) un dzēst `PC000062*.json` no NAS `Updates\Logs\Status|Inventory`, `Filiales\Auce\Atskaites\...` un hub `C:\Hub\Updates\Logs\...`; (3) vest hub uz Auci un izpildīt kontrolsarakstu `docs/filiales-progress.md` ("Aucē uz vietas"); (4) Auces datoru vārdi → grafiks (`Group = Auce-…`) un `setup-client.ps1` katrā (caur TeamViewer); (5) `config-panel.ps1` "nav redzēts tīklā" filiālei pēc statusa laika; (6) TeamViewer token no `client-install.ps1` uz atsevišķu failu (vēlāk).

**Atvērtie jautājumi:** portatīvā modelis/Windows/disks, vai var pieslēgt ar vadu; datoru vārdi un vai ir kopīgs lokālais Administrator; vai Drive Client atbalsta vienvirziena sinhronizāciju (pārbaudīt pēc uzstādīšanas); kur glabāt galveno skriptu kopiju filiālēm.
