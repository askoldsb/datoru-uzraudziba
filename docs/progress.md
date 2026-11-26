# Darba žurnāls

Jaunākie ieraksti augšā.

## 2026-11-26 (jauns portatīvais DELL-MONTA + atjaunināšana ārpus biroja)

- DELL-MONTA — Montas portatīvais (otrs dators blakus PIUAC-MONTA), Wi-Fi 192.168.3.139, programmas jau bija uzstādītas.
- Iebūvētais administrators (SID -500) bija **pārdēvēts par `admin`** (`net user Administrator` → "user name could not be found") → `Rename-LocalUser admin Administrator` + flotes parole. Pārbaude: `Get-LocalUser | ? { $_.SID -like '*-500' }`.
- `Enable-PSRemoting` → `remote-setup-client.ps1 -ComputerNames "192.168.3.139"` — veiksmīgi (TrustedHosts papildināts). `C:\Scripts\setup-client.ps1` (satur `labupdate` paroli) pēc tam izdzēsts.
- `device-schedule.csv`: rinda pēc PC000159 parauga — grupa `portatīvie`, All, bez laika, ShowNotification Yes, ShutdownAfter No, **TeamViewer No** (lietotāja lēmums).
- Pirmie cikli: Firefox 151 → 160.0.1, Zoom 7.2.51704 (uzstādīts mašīnas līmenī — pārbaudīt dublikātu lietotāja profilā), WinRAR 6.21 → 7.23, VC++ x64/x86. VLC 1603 (MSI 2318) — pēc restarta OK.
- **Windows Update kļūda** "Value does not fall within the expected range" (PSWindowsUpdate, tikai fona uzdevumā; interaktīvi meklēšana strādāja, 14 atjauninājumi). Cēlonis: dators atnests **bez barošanas bloka**, Dell BIOS (System Firmware 1.33.0) atjauninājums iestrēdzis (ierīces problēmas kods 14). Ar barošanu Windows Update uzstādīja visu → 11:43 cikls: 10 atjauninājumi, 12:00 — vairs nav. Kļūda pazuda.
- Jauns `src/client/portativais-offline.ps1` (uzstādīts DELL-MONTA, `C:\Program Files\LabUpdates\`): `LabOfflineUpdate` (SYSTEM, ik 2 h + startā; ārpus biroja tīkla, ar internetu, ne "metered" — reizi ~20 h `winget upgrade` jau uzstādītām programmām, bez TeamViewer; žurnāls `C:\ProgramData\LabUpdates\Offline\Logs`) un `LabOfflineReport` (`labupdate`, ik 30 min; birojā nosūta žurnālus uz `Logs\Clients\<PC>-offline-*.log`). Biroja tīkla noteikšana — TCP 445 uz 192.168.3.31. **Ārpus biroja vēl nav pārbaudīts.**

## 2026-11-25 (OpenLab-Display — pēc Dell rūpnīcas atiestatīšanas no jauna)

- Pēc nakts Win11 atjauninājuma dators 01:01 atjaunoja **Dell rūpnīcas attēlu** (visi dati C: zaudēti, Windows.old nav); OOBE cilpa ar `start ms-cxh:localonly` (build 26300.9974). Apiets: Shift+F10 → `net user` + `net localgroup Administrators` + `reg add …\Setup\OOBE /v UnattendCreatedUser /d 1` + `…\OOBE /v BypassNRO /d 1` → restarts. Cēlonis nav noskaidrots (Event Viewer ap 00:30–01:05, BIOS *Auto OS Recovery Threshold*).
- Kopīgs lektoru dators pie skārienekrāna: `src/client/openlab-uzstadisana.ps1` (Administrator ieslēgšana, LV reģionālie iestatījumi ar EN saskarni, winget programmas + ESET Endpoint ar `ACTIVATION_DATA=key:` — atslēga repozitorijā NAV; `-Pabeigt`: OpenLab ne-admin, bez paroles, nevar mainīt, AutoAdminLogon) un `src/client/openlab-konti.ps1` (NoConnectedUser=3, BlockAADWorkplaceJoin, OneDrive tikai piuac.lv tenant, Office SignInOptions=2, Edge/Chrome bez profila pieteikšanās, dati dzēsti aizverot, meklētājs Google, programmu spraudņi ExtensionInstallForcelist, Chrome AllowedDomainsForApps=piuac.lv).
- Mācība: svaigā Dell attēlā winget nebija reģistrēts (0x80073CF9) — Store → Get updates (App Installer).
- Mācība: `ForceEphemeralProfiles` lika Chrome katrā startā prasīt meklētāju un spraudņus → aizstāts ar `ClearBrowsingDataOnExitList` + noklusējuma meklētāju politiku.
- Sistēmā: NetBIOS vārds nemainījās (`OpenLab-display-pc` jau bija saīsināts līdz `OPENLAB-DISPLAY`), rinda grafikā derēja. `remote-setup-client.ps1` → veiksmīgi; Inkscape/Blender `Targets` papildināti ar OPENLAB-DISPLAY; pirmais cikls 13:54: 4 Windows atjauninājumi, VC++; Office 16.0.20625 atrasts. `C:\Scripts\setup-client.ps1` izdzēsts.
- PIUAC-MAIRITA (2026-11-24): BrightAuthor "Directory C:\Users\Mairita\Documents cannot be written to" — Documents pārcelts uz `E:\OneDrive - Dobeles PIUAC\Dokumenti`; mērķis nomainīts. Ekrāni ir tīklā → publicēt caur Publish → Local Network.

## 2026-11-04 (OPENLAB-2 → Windows 11)

- Pārbaude: profili uz C: (`ProfilesDirectory`=C:\Users), lietotājam pārvietotas tikai Documents/Desktop/Downloads uz D:; `D:\AppData` tukša paliekas mape. UEFI+GPT, TPM gatavs, Secure Boot izslēgts, CPU i7-7700 neatbalstīts.
- `MoSetup\AllowUpgradesWithUnsupportedTPMOrCPU=1` + `setup.exe` no `D:\Downloads\Windows11_Client_x64_en-us_26300_9457.iso`, Keep files and apps, brīdinājums Accept. Ilga ~25 min.
- Rezultāts: Windows 11 Pro 26300; `LabAppUpdate` LastTaskResult 0; D: mapes un RUM vietā.

## 2026-11-04 (RUM ieviests)

- OPENLAB-1 pēc RUM: visas lietotnes jaunākajā 2025 versijā; CC Desktop "Update available" = 2026 versijas — lēmums atlikts (konsultācija ar kolēģi).
- PIUAC-MONTA pirmais plānotais cikls 04:00 veiksmīgs (Adobe Reader 26.003.22075, izslēgšanās 04:19); `LabProfileBackup` rezultāts 0. WoL nav pārbaudīts (dators jau bija ieslēgts).

- Testa uzdevumi pabeigti: OPENLAB-1 23/23, OPENLAB-2 16/16 atjauninājumi uzstādīti (Return Code 0; noslēgumā "Following Updates were successfully installed"). Lejupielāde aizņēma vairākas stundas.
- `patch-adobe-rum.ps1` uzlikts uz admin PC → NAS `client-install.ps1` (rezerves kopija .bak-*); `Config\adobe-rum.txt` = OPENLAB-1, OPENLAB-2.
- `AdobeRUM-Test` un `rum-test.log` dzēsti abos datoros. OPENLAB grafiks Mon,Wed 04:00 → pirmais RUM nakts cikls 2026-11-09.

## 2026-11-03 (Adobe CC atjaunināšana OPENLAB-1/2 ar RUM)

- OPENLAB-1/2: Admin Console Shared Device pakotne, RUM jau uzstādīts (`OOBE_Enterprise\RemoteUpdateManager`). `--action=list`: OPENLAB-1 23 atjauninājumi, OPENLAB-2 16 (pēc manuālas daļējas atjaunināšanas).
- Tests: vienreizējs SYSTEM uzdevums `AdobeRUM-Test` (`--action=install`, izvade `C:\ProgramData\LabUpdates\rum-test.log`) — darbojas bez lietotāja; lejupielāde lēna.
- Uzrakstīts `src/patches/patch-adobe-rum.ps1` (pārbaudīts uz dzīvās `client-install.ps1` kopijas, idempotents); vēl NAV pielietots.

## 2026-11-03 (jauns biroja dators PIUAC-MONTA)

- WinRM + Administrator aktivizēts klātienē; IP 192.168.3.29 (DHCP, statisko nelikām); Windows 11 Pro.
- `remote-setup-client.ps1` — veiksmīgi; `device-schedule.csv` rinda pēc PIUAC-MAIRITA parauga (Dobele-birojs, Mon,Wed 04:00, ShutdownAfter Yes). Piezīme: CSV vērtības ir pēdiņās — raw meklēšanai `'"PIUAC-…",*'`.
- Pirmais cikls ar pagaidu grafiku (All, bez laika, ShutdownAfter No) — veiksmīgs; grafiks atjaunots.
- `remote-backup-setup.ps1` — `LabProfileBackup` Ready; `inventory-manual.csv`: PC000179, Monta Mantrova.
- `admin` konts (pēdējoreiz 21.11.2024, bez datiem) un profils izdzēsti; Monta paliek lokālais administrators.
- NAS WoL uzdevumam pievienots PIUAC-MONTA (4C:52:62:AD:03:B3); WoL tīkla kartē ieslēgts. MAC saraksts → `docs/arhitektura.md`.
- Repozitorijā izņemta `labupdate` parole (`setup-client.ps1`, `remote-backup-setup.ps1`).

## 2026-11-02 (projekta apkopojums repozitorijā)

Apkopota visa iepriekšējo sarunu informācija:
- `CLAUDE.md`: aizpildīts "Mērķis", papildināti "Pieņemtie lēmumi", "Pašreizējais stāvoklis", "Nākamie soļi".
- Jauni dokumenti: `docs/prasibas.md`, `docs/arhitektura.md`, `docs/darba-procedura.md`, `docs/iericu-uzraudziba.md` (atskaites punkts), `docs/dokumenti/` (statusa apraksts v7, uzstādīšanas instrukcija v4, filiāļu risinājuma plānojums v1).
- Skripti `src/` (client, admin, patches, tv-test) un konfigurācijas piemēri `config-piemeri/`. **Paroles un API tokeni izņemti** (restic parole, TeamViewer API token).

## 2026-10-26 … 2026-10-29 (Adobe Creative Cloud klases datoriem)

- Pilots uz DATORKLASE-01: cikls izlaida AdobeCC, jo trūka `SilentArgs` → iestatīts `--mode=stub`; instalators uzstādījās, bet cikls karājās (`Start-Process -Wait` gaidīja Adobe fona procesus) → `patch-exe-nowait.ps1` (gaida tikai instalatoru, 10 min limits).
- Reģistra nosaukums "Adobe Creative Cloud" sakrīt ar `DisplayNamePattern`; DATORKLASE-01 grafiks atjaunots.
- `Targets` paplašināts uz visiem 13 klases datoriem; tūlītēja uzstādīšana attālināti (Invoke-Command + vienreizējs SYSTEM plānotais uzdevums `AdobeCC-Install`) — visi 12 saņēma versiju 6.11.0.478.6.
- Balts CC logs / "missing or damaged": izpētīts (WebView2, tīkls, žurnāli) — cēlonis ir CC palaišana ar paaugstinātām tiesībām kā citam lietotājam; parastam lietotājam darbojas.
- Lietotņu uzstādīšanai Kursantam uz laiku pievienotas, pēc tam noņemtas admin tiesības (11/12 datoros; PASN gaida).

## 2026-10-22 … 2026-10-28 (jaunu datoru pievienošana un uzlabojumi)

- Atskaite: krāsas pēc 10/14 dienām; piezīme "nav redzēts tīklā" tikai oranžajām rindām.
- `apps-managed-editor`: poga jaunu programmu meklēšanai (153 → 45 kandidāti).
- CCleaner automātiska noņemšana (`patch-remove-ccleaner.ps1`); versiju salīdzināšanas labojums (`patch-version-compare.ps1`).
- Pievienoti PC000159, PC000184, PC000158, PC000161, OPENLAB-1 (→ Win 11), OpenLab-2; Inkscape/Blender Targets; WoL skripts papildināts.
- ClickShare instrukcija pabeigta (vēlāk saglabāta lietotāja datorā, Claude Docs dokuments izdzēsts 2026-11-02). Ierīču uzskaite — atskaites punkts, apturēts.

## 2026-11-02 (papildinājums)

- Sarunas informācija apkopota `docs/github-iestatijumi.md`: kontu struktūra, darba kārtība jaunās sarunās, ierobežojumi, "Confirm access" pārbaude, bezmaksas plāna limiti.
- `CLAUDE.md` papildināts ar pieņemtajiem lēmumiem.
- Sistēmas mērķis vēl nav aprakstīts — nākamais solis.

## 2026-11-02

- Izveidots GitHub repozitorijs `askoldsb/datoru-uzraudziba` projekta informācijas glabāšanai.
- Pievienoti sākuma faili: `README.md`, `CLAUDE.md`, `docs/progress.md`.
- Noskaidrots: Claude ir pieslēgts GitHub lietotājam `askoldsb`; Fotostokeris repozitoriji atrodas `fotostockworkshop` kontā un paliek nodalīti.
