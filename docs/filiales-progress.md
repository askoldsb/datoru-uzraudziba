# Filiāļu darba žurnāls

Jaunākie ieraksti augšā. Sākuma dokuments: `docs/filiales-auce.md` (lēmumi — sadaļa "Lēmumi"). Skripti: `src/filiales/`.

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

### Aucē uz vietas (kontrolsaraksts)

- Tīkla profils → Private (`Set-NetConnectionProfile -InterfaceAlias Ethernet -NetworkCategory Private`).
- Vai Auces datori atrod `AUCEUPDATE-PC` pēc vārda (`net use`/`Test-Path \\AUCEUPDATE-PC\Updates`); ja nē — fiksēta IP (saskaņot ar tīkla īpašnieku).
- Vai izejošais 443 / QuickConnect strādā (Drive Client "Up to date").
- Hub pieslēgts ar vadu; TeamViewer pieslēgšanās no Dobeles strādā.

### Plānotie soļi

1. ~~Centra NAS: Synology Drive Server, Team Folder `Filiales\Auce\`, DSM konts `auce-sync`.~~ Izdarīts.
2. ~~Portatīvais: datora vārds, aktivizācija, strāvas iestatījumi, ierobežots lietotājs ar auto-pieteikšanos, Drive Client sinhronizācija.~~ Izdarīts (atlicis: ekrāna bloķēšana pēc auto-pieteikšanās, tīkla profils Aucē).
3. Portatīvajā: SMB koplietojums (skripti, konfigurācija, kešs), filiāles `client-install.ps1` versija (`src/filiales/`), grafiks ar `Group = Auce-…`; nakts lejupielādes uzdevums (downloader) instalatoru kešam portatīvajā — ar Dobeli nesinhronizē.
4. NAS plānotais uzdevums: kopēt Auces statusu/inventāru uz `Logs\Status` / `Logs\Inventory`.
5. Tests uz 2 Auces datoriem → visi 16 → citas filiāles.

## 2026-11-04

- Sagatavots `docs/filiales-auce.md` atsevišķai sarunai par filiāli Aucē (situācija, lokālās sistēmas apraksts, kas neder pa internetu, mācības, 2026-10-08 plāna kopsavilkums).
