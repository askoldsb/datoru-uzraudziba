# Filiāļu darba žurnāls

Jaunākie ieraksti augšā. Sākuma dokuments: `docs/filiales-auce.md` (lēmumi — sadaļa "Lēmumi"). Skripti: `src/filiales/`.

## 2026-11-09 — Auce: hub uz vietas, PIUAC-IVETA

- **Auces tīkls: 10.13.37.x** (DHCP). **AUCEUPDATE-PC = 10.13.37.15** (DHCP — ja mainās, jāpārbauda vārda atrašana; fiksētu IP saskaņot ar tīkla īpašnieku). Vārds `AUCEUPDATE-PC` no Auces datoriem tiek atrisināts (IPv6 link-local un IPv4).
- `Test-NetConnection AUCEUPDATE-PC -Port 445` no PIUAC-IVETA: **TcpTestSucceeded False** (vārds atrisināts uz 10.13.37.15). Aizdomas: hub tīkla profils Aucē = Public (SMB noteikums tikai Private) — solis A1 (`Set-NetConnectionProfile … Private`) vēl jāapstiprina hub datorā.
- 11:08–11:18: hub kabelis bija pārslēgts citā vietā → saņēma **10.136.124.4** no 10.136.124.1 (pakalpojumu sniedzēja tīkls, DNS 195.122.12.241, sufikss net.3d.lv) — **nepareizs tīkls**. Atpakaļ sākotnējā vietā: **10.13.37.15/24, vārteja 10.13.37.254**, profils "Network 2" → **Private** (Windows profilu glabā katram tīklam atsevišķi). Mācība: hubu slēgt tajā pašā tīklā kā darba datorus; pēc pārslēgšanas pārbaudīt profilu.
- TeamViewer hub datorā: pakalpojums Running/Automatic, 15.83.5; Easy Access piešķirts `auceadmin` sesijā, dators pievienots Askolda TeamViewer kontam — pieslēgšanās strādā arī, kad pieteicies `hubsync`.
- Sagatavoti `src/filiales/win11-upgrade.bat` (Win10→Win11), `win11-versijas-atjaunosana.bat` (vecāks Win11→ISO build, `/product server`), `sagatavot-datoru.bat` (WinRM, Administrator, enerģija, WoL, setup-client no hub). Auces datori pašlaik jauninās uz Win11 26300. PIUAC-IVETA: pirmais mēģinājums (GUI setup.exe) iestrēga "Checking for updates 46 %" → apturēts, atkārtots ar `win11-upgrade.bat` (`/dynamicupdate disable`).
- A6 OK: no **AUCE-PASNIEDZEJ** (Win 11 Pro 26H2) `Test-NetConnection AUCEUPDATE-PC -Port 445` → True (caur IPv6 link-local).
- Paroļu versija `sagatavot-datoru-AUCE.bat` (Administrator flotes parole + Auces labupdate parole iestrādātas; **nav repozitorijā**, glabājas tikai pie Askolda; pēc lietošanas dzēst no datoriem). Repozitorijā paliek `sagatavot-datoru.bat` (prasa paroles).
- **Sagatavoti datori (jāpievieno grafikam + jāpublicē no PIUAC-ASKOLDS):**

| Datora vārds (`$env:COMPUTERNAME`) | IP | MAC | Piezīmes |
|---|---|---|---|
| AUCE-PASNIEDZEJ (hostname "Auce-pasniedzejs", NetBIOS saīsināts līdz 15) | 10.13.37.186 | 90-1B-0E-D9-37-5E | Win 11 26H2; lietotāji Administrator, labupdate, pasniedzejs, students; sagatavots 2026-11-09 11:59 bez brīdinājumiem → pārdēvēt **AUCE-PASN** |
| DATORKLASE-1 | 10.13.37.122 | 4C-52-62-19-DE-89 | lietotāji Administrator, kursants, labupdate; sagatavots 2026-11-09 12:08 bez brīdinājumiem. → pārdēvēt **AUCE-KLASE-1** |
| DATORKLASE-2 | 10.13.37.137 | 4C-52-62-19-DE-F3 | lietotāji Administrator, kursants, labupdate; sagatavots 2026-11-09 12:14 bez brīdinājumiem → pārdēvēt **AUCE-KLASE-2** |
| DATORKLASE-3 | 10.13.37.125 | 4C-52-62-19-DE-97 | lietotāji Administrator, kursants, labupdate; sagatavots 2026-11-09 12:24 bez brīdinājumiem → pārdēvēt **AUCE-KLASE-3** |
| DATORKLASE-4 | 10.13.37.3 | 4C-52-62-19-DE-F4 | lietotāji Administrator, kursants, labupdate; sagatavots 2026-11-09 12:33 bez brīdinājumiem → pārdēvēt **AUCE-KLASE-4** |
| DATORKLASE-5 | 10.13.37.78 | B4-2E-99-8C-3B-E2 ("Ethernet 2") | lietotāji Administrator, labupdate, students; sagatavots 2026-11-09 12:42 bez brīdinājumiem → pārdēvēt **AUCE-KLASE-5** |
| DATORKLASE-6 | 10.13.37.93 | 4C-52-62-11-DD-1D | lietotāji Administrator, labupdate, students; sagatavots 2026-11-09 12:43 bez brīdinājumiem → pārdēvēt **AUCE-KLASE-6** |
| DATORKLASE-7 | 10.13.37.76 | B4-2E-99-7D-EC-08 ("Ethernet 2") | lietotāji Administrator, labupdate, students; sagatavots 2026-11-09 12:42 bez brīdinājumiem → pārdēvēt **AUCE-KLASE-7** |
| DATORKLASE-8 | 10.13.37.53 | 00-22-4D-AA-DE-6A | lietotāji Administrator, labupdate, students; sagatavots 2026-11-09 12:52 bez brīdinājumiem → pārdēvēt **AUCE-KLASE-8** |
| PIUAC-IVETA (**Auces biroja dators**, grupa `Auce-birojs`) | 10.13.37.123 | 90-1B-0E-D9-37-95 (Intel, EEE Off) | lietotāji Administrator, Iveta, labupdate; Win 11 jaunināts no Win 10 22H2; D: "data" 2 TB; ārējais INTENSO USB (F: "hot_service") atvienots jaunināšanai — pieslēgt atpakaļ; sagatavots 2026-11-09 13:46 bez brīdinājumiem; vārds paliek (vai `AUCE-IVETA`); profilu rezerves kopijas Aucē vēl nav |

- **Nosaukumu shēma (2026-11-09):** klases datori `AUCE-KLASE-<n>`, pasniedzēja dators `AUCE-PASN` (`Rename-Computer -NewName … -Restart`; sagatavošana paliek spēkā). Grafikā rakstīt JAUNOS vārdus.
- WoL: `sagatavot-datoru.bat` iestata tikai Windows pusi (draiveris, ierīces modināšana, Fast Startup izslēgts); **BIOS WoL nav mainīts** — sakārtot, kad Aucē veidos WoL sūtītāju (hub uzdevums).
- **WoL tests no hub (2026-11-09 13:12–13:17):** magic packet (UDP 9 uz 10.13.37.255 un 255.255.255.255) no AUCEUPDATE-PC — **DATORKLASE-6 (4C-52-62-…) un pasniedzēja dators (90-1B-0E-…) pamodās uzreiz**; DATORKLASE-5, -7 (Gigabyte, B4-2E-99-…, "Ethernet 2", BIOS ErP=Disabled) un -8 (00-22-4D-…) **nepamodās** → DATORKLASE-5 (Realtek PCIe GbE): Shutdown Wake-On-Lan un Magic Packet jau bija Enabled; **izslēdzot Energy-Efficient Ethernet, Green Ethernet, Power Saving Mode → pamostas no hub** (13:33). Iestrādāts `sagatavot-datoru.bat` (4. solis). AUCE-KLASE-7 (Realtek Gaming GbE) un AUCE-KLASE-8 (**Intel I217-V**: iestatījums "Energy Efficient Ethernet" = Off) pēc labojuma **pamostas no hub** (13:40). Pārbaudīti WoL: 5, 6, 7, 8, pasniedzējs, PIUAC-IVETA (13:53); nav testēti: 1–4 (4C-52-62-…, tāda pati saime kā 6). Atlicis: hub nakts WoL uzdevums (kā Dobeles NAS).
- **Attālā pārvaldība no hub darbojas:** hub WinRM pakalpojums ieslēgts (tikai klients), TrustedHosts `10.13.37.*`; `Invoke-Command -ComputerName <IP> -Credential Administrator` (flotes parole). Windows PowerShell 5.1 `Stop-Computer -ComputerName` lieto DCOM (bloķēts) → lietot `Invoke-Command { Stop-Computer -Force }`.
- Ieteiktā grafika rinda (Aucē WoL vēl nav): `"<DATORS>","Auce","Mon,Tue,Wed,Thu,Fri,Sat,Sun","","No","No","Yes","Yes","Yes","Yes"` → `C:\Scripts\Filiales\Auce\Config\device-schedule.csv` → `publish-filiale.ps1 -Branch Auce`.
- **PIUAC-IVETA** (Auces dators): Win 10 Pro 22H2 aktivizēts, i7-7700 (neatbalstīts → MoSetup `AllowUpgradesWithUnsupportedTPMOrCPU=1`), 16 GB RAM, C: WD SSD 224 GB (122 GB brīvi), D: Toshiba HDD 2 TB "data", GPT/UEFI, TPM 2.0, **Secure Boot izslēgts** (ieslēgt BIOS pēc jaunināšanas), BitLocker Off. Ārējais USB INTENSO (F: "hot_service") atvienots pirms jaunināšanas. Lietotāji: `Administrator` (ieslēgts, parole nomainīta uz flotes paroli), `Iveta` (nav admin). WinRM ieslēgts (`Enable-PSRemoting -SkipNetworkProfileCheck`). Windows 11 jaunināšana no `D:\Downloads\Windows11_Client_x64_en-us_26300_9457.iso` (F:\setup.exe, "Keep personal files and apps") — sākta ~09:20.

## 2026-11-04 — Auce: arhitektūras izvēle, centra NAS, hub portatīvais

- Salīdzināts Askolda risinājums ar 2026-10-08 plānu (B2 mākonis). Izvēle: vietējais hub portatīvais Aucē + Synology Drive Client (QuickConnect) atskaitēm uz centra NAS. Tailscale apsvērts un atmests.

### Izdarīts centra NAS

- Synology Drive Server jau bija uzstādīts.
- Koplietojamā mape `Filiales` (Volume 1, slēpta, atkritne tikai adminiem, kontrolsumma, kvota 5 GB); apakšmapes `Auce\Atskaites`, `Auce\Skripti`.
- DSM konts `auce-sync`: grupa `users`; Read/Write tikai `Filiales`, citur No Access; lietotnes — tikai Synology Drive (pārējās Deny).
- `Filiales\Auce\Skripti`: ACL ieraksts `auce-sync` Deny (visas Write + Change permissions, Take ownership) → tikai lasīšana.
- `Filiales` iespējota kā Team Folder (versijas: 8, 30 dienas).
- Synology Drive caur QuickConnect jau tiek lietots (Askolds apstiprina) — praktiski pārbaudīt ar `auce-sync`.
- Uz NAS ir arī Tailscale — Askolda privātai piekļuvei; Auces portatīvo tajā tailnet **nepievienot**.

### Auces hub portatīvais

- Dell Latitude E5540, Service Tag 6Q9JVY1, i5-4300U (Haswell, neatbalstīts Win 11), SSD Crucial BX500 240 GB, RAM 4 → **8 GB** (2×4 GB DDR3L no norakstāma E5540, dual channel), BIOS A24.
- BIOS: UEFI + Secure Boot (jau bija), TPM Activate (jau bija), Wake on AC, Primary Battery Charge = Primarily AC Use, Wake on LAN = LAN Only, BIOS Admin Password iestatīta (glabājas paroļu pārvaldniekā).
- Tīra Windows 11 Pro instalācija (bija Win 10 Pro 22H2): Rufus 4.15, ISO build 26300 en-US, GPT/UEFI; Rufus opcijas — apiet TPM/CPU/RAM, bez MS konta, lokālais konts `auceadmin`, reģionālie iestatījumi, bez datu vākšanas, BitLocker auto-šifrēšana izslēgta, QoL (bez Copilot/OneDrive/Fast Startup); "Windows CA 2023" bootloaderi un "SILENTLY erase" — nē. Visi Disk 0 nodalījumi dzēsti.
- Datora vārds `AUCEUPDATE-PC`, Windows 11 Pro 10.0.26300, aktivizēts (digitālā licence). Uzstādīts TeamViewer (Easy Access Askolda kontā) un ESET NOD32.
- Rezerves daļas/dators: citi norakstāmie E5540.
- Hub sagatavošana Dobelē: strāvas iestatījumi (nekad neaizmigt AC/DC, vāks = Do nothing AC/DC — LIDACTION bija paslēpts, `powercfg /attributes ... -ATTRIB_HIDE`; hibernācija un Fast Startup izslēgti; ekrāns 5 min). Tīkla profils Public → Private jāiestata **uz vietas Aucē**.
- Lietotājs `hubsync` (Users, ne admin, parole nemainās, paroļu pārvaldniekā); auto-pieteikšanās ar Sysinternals Autologon (parole šifrēta LSA).
- `C:\Hub`: mantošana noņemta, tikai SYSTEM + Administrators (F) + `hubsync:(RX)` (tikai šai mapei, lai Drive Client redz apakšmapes); `C:\Hub\Sync`: `hubsync:(OI)(CI)M`.
- Synology Drive Client (instalēts kā `auceadmin`, konfigurēts `hubsync` sesijā; Windows ugunsmūra ienākošie pieprasījumi — Cancel), QuickConnect + `auce-sync` strādā. Divi uzdevumi: `/Filiales/Auce/Atskaites` → `C:\Hub\Sync\Atskaites` **Upload only** (bez "Keep locally deleted"), `/Filiales/Auce/Skripti` → `C:\Hub\Sync\Skripti` **Download only**; On-demand izslēgts, consistency check ieslēgts.
- Testi OK: augšupielāde (fails no admin sesijas → NAS), lejupielāde (NAS → hub), aizsardzība (lokāla izmaiņa/jauns fails `Skripti` nenonāk NAS). Atklājums: Download only **neatjauno** lokāli izmainītu failu → hub nedrīkst palaist skriptus tieši no `Sync\Skripti` (sk. lēmumus: Authenticode paraksts). Testa faili izdzēsti.

- `C:\Hub\Updates` (Scripts, Config, Config\Commands, Cache, Modules, Logs\Clients|Status|Inventory|MsiLogs) — atkārto NAS `Updates` struktūru (2026-11-05).
- Hub lokālais konts `labupdate` (ne admin; **Auces parole**, atšķirīga no Dobeles; jāsakrīt ar `labupdate` Auces datoros). NTFS: `Updates` RX (tikai mape), `Scripts|Config|Cache|Modules` RX, `Logs` Modify. Koplietojums `Updates`: Administrators Full, labupdate Change (bez Everyone).
- Ugunsmūris: visi iebūvētie "File and Printer Sharing (… SMB-In)" (arī jaunais "Restrictive") izslēgti; savs noteikums **"Hub SMB-In (Private, LocalSubnet)"** TCP 445. Tīkla profils Dobelē uz laiku Private (192.168.3.89).
- Tests no PIUAC-ASKOLDS: `net use \\AUCEUPDATE-PC\Updates /user:AUCEUPDATE-PC\labupdate` OK (vārds atrasts), `Logs` rakstāms, `Scripts` — Access denied (pareizi).
- Klienta skripti filiālē netiek dakšoti — viss caur `-NasRoot \\AUCEUPDATE-PC\Updates` (sk. `src/filiales/README.md`).

- Parakstīšanas sertifikāts (PIUAC-ASKOLDS, CurrentUser\My, neeksportējama atslēga): `CN=PIUAC filiales skripti`, **thumbprint `20E20E2C5D7A6663CE36D110AE07E23895B523B1`**, derīgs līdz 2031-11-05; `.cer` → `C:\Scripts\Filiales\Auce\Tools\`. Publicēšanas avots `C:\Scripts\Filiales\Auce\` (Config: tikai `device-schedule.csv` virsraksts; `apps-managed.csv` — vēl jāizlemj Aucei). `-WhatIf` OK (14 faili); labots: `.tmp` u.c. Drive neatsinhronizējamie faili tiek izlaisti.

- **Parakstītā publicēšana darbojas** (2026-11-05): 1. publicēšana Sequence 20261105112527 (13 faili) → hub `install-hub-sync.ps1` (thumbprint sakrita, `.cer` → LocalMachine\Root, paraksts Valid, uzdevums `Hub-Sync` SYSTEM ik 15 min + startējot, LastTaskResult 0) → "Published - publiceti 13 faili". Statuss `Filiales\Auce\Atskaites\Hub\AUCEUPDATE-PC.json` nonāk NAS.
- Kļūda un labojums: PS 5.1 `Get-Content` → JSON ar PSPath u.c. (statuss 445 KB) → `[string]`. Labotais `hub-sync.ps1` piegādāts **caur pašu publicēšanu** (Sequence 20261105113521) — hub pats atjaunināja savu rīku; statuss 408 B.
- NAS `Filiales\Auce\Skripti\New Text Document.txt` — lieks (nav manifestā, hub ignorē), var dzēst.

- `Hub-Downloader` (konts `auceadmin`, katru nakti 02:30, `C:\Hub\Tools\downloader.ps1` → `C:\Hub\Updates`), publicēts caur `Tools\` (Sequence 20261105124155, 15 faili). Pirmā palaišana: visām programmām "Neizdevas noteikt jaunako versiju" — **winget avots nebija inicializēts `auceadmin` kontam**; `winget source update` paaugstinātā logā no `hubsync` sesijas (runas cits lietotājs) neizdodas (0 %, "Failed when searching source"), **īstā `auceadmin` sesijā** — 100 %, Firefox 159.0 atrasts. Mācība: winget pirmoreiz jāpalaiž interaktīvi tā konta sesijā, ar kuru darbojas uzdevums.
- `hubsync` parole aizmirsta → nomainīta (`Set-LocalUser`) un Autologon atjaunots (2026-11-05 13:01).

- Hub-Downloader 2. palaišana OK (13:14–13:22): Firefox 159.0, Chrome 157.0.8103.39, Zoom 7.2.51704, TeamViewer 15.83.5, TeamViewerHost 15.83.5, VLC 3.0.24, eParaksts 1.11.0, PowerShell 7.6.9.0 → `C:\Hub\Updates\Cache`, `versions.json`.
- NAS uzdevums **`Filiales-Auce-atskaites`** (Task Scheduler, root, ik 15 min 00:00–23:45, skripta teksts uzdevumā — `src/filiales/nas-filiales-atskaites.sh`): kopē `Filiales/Auce/Atskaites/{Status,Inventory}/<PC>.json` → `Updates/Logs/...` **tikai** datoriem no `Skripti/Config/device-schedule.csv`; žurnāls `Filiales/Auce/nas-atskaites.log` (tikai, ja kopēts vai kļūda). DSM kolonna "Run" rāda fragmentu no komentāriem — tas ir normāli.

- Filiāles `setup-client.ps1` publicēts (Sequence 20261105134800, 16 faili). **Testa klients PC000062** (Win 10 Pro, Dobeles tīklā, iepriekš nebija sistēmā): `Test-NetConnection AUCEUPDATE-PC -Port 445` OK (vārds atrisināts uz IPv6 link-local — tieša vārdu atrašana, labs signāls Aucei); `net use … /user:labupdate` + `setup-client.ps1` no `\\AUCEUPDATE-PC\Updates\Scripts` → GATAVS. Grafikā `PC000062,Auce-test,Mon..Sun,"",No,No,Yes,Yes,Yes,Yes` (Sequence 20261105135918; `UpdateDays=All` nelieto — apiet "reizi dienā").
- Pirmais cikls 14:00: grafiks atļauj, inventārs savākts, PSWindowsUpdate no hub `Modules`, Office nav (C2R nav atrasts), Windows Update sākts. **Inventāra ķēde pārbaudīta līdz galam:** hub `Logs\Inventory` → Hub-Sync → `Sync\Atskaites` → Drive → NAS `Filiales\Auce\Atskaites` → `Filiales-Auce-atskaites` → `Updates\Logs\Inventory\PC000062.json` (27 KB).

- PC000062 1. cikls (14:00): Windows Update atrada 11, uzstādīti 10 (līdz 14:20: .NET 8/10, MSRT, draiveri, pēdējais — **Intel tīkla kartes draiveris**), KB5126256 (Win10 ESU sagatavošana) `InProgress`, gaida restartu. Pēc 14:04 žurnālā vairs nav ierakstu, process beidzās bez avārijas notikuma un bez restarta (boot 13:46) — **aizdomas:** tīkla draivera maiņa pārtrauca SMB savienojumu ar hub (žurnāls/kešs). Cēlonis nav pierādīts. "Reizi dienā" marķieris aizliedza atkārtojumu šodien (15:15 — pareizi izlaists).
- **Statusa ķēde arī pārbaudīta:** izlaistās palaišanas (15:15) statuss `PC000062.json` bija nonācis NAS `Updates\Logs\Status`. **Nav pārbaudīts:** programmu uzstādīšana no hub keša — ar pirmo īsto Auces datoru (PC000062 norakstīts, izslēgts).
- Tīrīšana (15:28–15:30): PC000062 izņemts no Auces grafika (Sequence 20261105152819, grafiks atkal tikai virsraksts); dzēsti PC000062 faili hub `Logs\Clients|Inventory|Status` (no PIUAC-ASKOLDS ar Auces `labupdate`) un NAS `Updates\Logs\Status|Inventory`; `Filiales\Auce\Atskaites` iztīrās automātiski (Hub-Sync /MIR + Drive).

### Aucē uz vietas (kontrolsaraksts)

- Tīkla profils → Private (`Set-NetConnectionProfile -InterfaceAlias Ethernet -NetworkCategory Private`).
- Vai Auces datori atrod `AUCEUPDATE-PC` pēc vārda (`net use`/`Test-Path \\AUCEUPDATE-PC\Updates`); ja nē — fiksēta IP (saskaņot ar tīkla īpašnieku).
- Vai izejošais 443 / QuickConnect strādā (Drive Client "Up to date").
- Hub pieslēgts ar vadu; TeamViewer pieslēgšanās no Dobeles strādā.

### Plānotie soļi

1. ~~Centra NAS: Synology Drive Server, Team Folder `Filiales\Auce\`, DSM konts `auce-sync`.~~ Izdarīts.
2. ~~Portatīvais: datora vārds, aktivizācija, strāvas iestatījumi, ierobežots lietotājs ar auto-pieteikšanos, Drive Client sinhronizācija.~~ Izdarīts (atlicis: ekrāna bloķēšana pēc auto-pieteikšanās, tīkla profils Aucē).
3. Portatīvajā: ~~SMB koplietojums, parakstīta skriptu publicēšana, atskaites uz Drive~~ izdarīts; ~~nakts lejupielāde~~ izdarīts (`Hub-Downloader`); **atlicis:** Auces `apps-managed.csv` izvēle, grafiks ar `Group = Auce-…`.
4. ~~NAS plānotais uzdevums: kopēt Auces statusu/inventāru uz `Logs\Status` / `Logs\Inventory`.~~ Izdarīts (`Filiales-Auce-atskaites`).
5. Tests uz 2 Auces datoriem → visi 16 → citas filiāles.

## 2026-11-04

- Sagatavots `docs/filiales-auce.md` atsevišķai sarunai par filiāli Aucē (situācija, lokālās sistēmas apraksts, kas neder pa internetu, mācības, 2026-10-08 plāna kopsavilkums).
