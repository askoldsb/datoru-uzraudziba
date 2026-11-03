# CLAUDE.md — projekta konteksts

Šis fails tiek nolasīts katras jaunas Claude sarunas sākumā. Tajā glabājas viss, kas vajadzīgs, lai turpinātu darbu, nezaudējot iepriekš paveikto.

## Projekts

**Nosaukums:** Automatizēta datoru uzraudzības sistēma
**Repozitorijs:** askoldsb/datoru-uzraudziba
**Saziņas valoda:** latviešu

## Mērķis

Skolas/biroja (~30+ datori, Dobele u.c.) datoru **automātiska uzturēšana un uzraudzība bez domēna un bez servera**. Skolas IT administrators (Askolds) pārvalda to no viena admin datora (PIUAC-ASKOLDS) ar Synology NAS (`\\PIUAC_CLOUD`, 192.168.3.31) kā centrālo vietu.

Sistēma:
- pēc grafika automātiski atjaunina Windows un trešo pušu programmas (klienti paši velk no NAS — "pull" modelis);
- uzstāda/atjaunina nepieciešamās programmas (Firefox, Chrome, Zoom, VLC, Inkscape, Blender, Adobe CC u.c.) un noņem nevēlamās (CCleaner);
- savāc inventāru un statusu, rāda atskaiti ar krāsām (nokavēti atjauninājumi, dators nav redzēts tīklā);
- veido lietotāju profilu rezerves kopijas uz NAS (restic);
- ļauj jaunus datorus pievienot attālināti ar vienu komandu.

Gala rezultāts: administrators pavada minimālu laiku uz katru datoru; atjauninājumi notiek paši, par problēmām redz atskaitē.

Sīkāk: `docs/prasibas.md`, `docs/arhitektura.md`, `docs/darba-procedura.md`; skripti — `src/`.

## Pieņemtie lēmumi

- 2026-11-02 — Projekta informācija tiek glabāta GitHub repozitorijā `askoldsb/datoru-uzraudziba` (privāts), lai to varētu turpināt jaunās sarunās.
- 2026-11-02 — Projekti nodalīti pēc GitHub īpašnieka: šis projekts zem `askoldsb`, Fotostokeris zem `fotostockworkshop`. Abiem piekļūst caur vienu Claude–GitHub pieslēgumu (lietotājs `askoldsb`).
- 2026-11-02 — Lielus bināros failus neglabāt Git (bezmaksas plāna limits 100 MB uz failu); izmantot Releases vai citu krātuvi.

- 2026-11-02 — Repozitorijā **nedrīkst būt paroles/API tokeni**: restic parole (`backup-manager.ps1`) un TeamViewer API token (`client-install.ps1`) izņemti no kopijas; dzīvās vērtības glabājas NAS/admin PC.
- 2026-11-03 — Arī `labupdate` konta parole izņemta no `setup-client.ps1` (vietturis) un `remote-backup-setup.ps1` (prasa palaišanas laikā); tā palikusi Git vēsturē → ieteicams nomainīt.
- 2026-11-03 — Biroja datori: grafiku kopē no PIUAC-MAIRITA (`Dobele-birojs`, Mon,Wed 04:00, ShutdownAfter Yes); biroja datori tiek iekļauti profilu rezerves kopijās; lietotājs drīkst palikt lokālais administrators.
- Pull modelis: `LabAppUpdate` (ik 15 min, lietotājs `labupdate`) palaiž NAS `Scripts\client-install.ps1`; grafiks `Config\device-schedule.csv`; lietotņu saraksts `Config\apps-managed.csv`.
- Rezerves kopijas neietver portatīvos un klases datorus (izņemot ASUS-Ieva, Dace); dokumenti kopumā netiek kopēti; Outlook datus neaiztikt; ESET Endpoint paliek.
- CCleaner tiek noņemts automātiski katrā ciklā visos datoros (`$RemoveAppNames`).
- Dokobit/Web eID automatizācija izlaista (nav winget).
- Adobe CC klases datoriem uzstādīts caur `apps-managed.csv` (`SilentArgs=--mode=stub`); CC jālieto ar **parastu lietotāju**, ne ar paaugstinātu iebūvēto Administrator (balts logs / "missing or damaged"). Lietotņu instalēšanai Kursantam uz laiku dodam admin tiesības.
- Ierīču uzskaite un uzraudzība (3. līmenis) — apturēta, prioritāte ir jaunu datoru pievienošana.
- Darba stils: atbildes latviski un īsi; komandas pa vienam solim; vienmēr norādīt datoru un tiesības (skat. `docs/prasibas.md`).

Sīkāk par GitHub iestatījumiem, limitiem un darba kārtību: `docs/github-iestatijumi.md`.

## Pašreizējais stāvoklis

**Sistēma ir darbībā** (izveidota un testēta iepriekšējās sarunās; 2026-11-02 apkopota repozitorijā: `src/`, `docs/`, `config-piemeri/`).

Izdarīts pēdējās sesijās (oktobris 2026):
- Atskaites krāsu loģika (10/14 dienas) un piezīme "nav redzēts tīklā"; programmu meklētājs `apps-managed-editor`; CCleaner automātiska noņemšana; versiju salīdzināšanas labojums (Recuva); `exe` instalatoru gaidīšanas labojums.
- Pievienoti datori: PC000159, PC000184, PC000158, PC000161 (portatīvie), OPENLAB-1 (tagad Win 11), OpenLab-2; noņemti liekie `admin` konti; Inkscape/Blender Targets.
- ClickShare pieslēgšanas instrukcija tika sagatavota; lietotājs to saglabājis savā datorā, Claude Docs dokuments izdzēsts (2026-11-02).
- **Adobe Creative Cloud 6.11.0.478.6 uzstādīts visos 13 klases datoros** (DATORKLASE-01..12, -PASN); pārbaudīts, ka parastam lietotājam CC atveras. DATORKLASE-01 grafiks atjaunots (Sun,Wed 04:00, ShutdownAfter Yes).
- Kursantam admin tiesības noņemtas 11 klases datoros (07 nebija; **PASN vēl jāpārbauda**).
- 2026-11-03 — **Pievienots PIUAC-MONTA** (biroja stacionārais, Win 11 Pro, 192.168.3.29 DHCP, PC000179, Monta Mantrova): WinRM, klients, grafiks, `LabProfileBackup`, inventārs; pirmais cikls veiksmīgs (WinRAR 7.23.0, VC++ x86); liekais `admin` konts un profils izdzēsti.

Neapstiprināts / atvērts: skat. "Nākamie soļi".

## Nākamie soļi

1. **DATORKLASE-PASN**: kad ieslēgts, noņemt `Kursants` no lokālajiem administratoriem (komanda `docs/darba-procedura.md`).
2. Izdzēst pagaidu plānoto uzdevumu `AdobeCC-Install` datoros DATORKLASE-02..12 un -PASN.
3. Adobe licences: izlemt Shared Device License vs Named User + pakotne (Admin Console); pārbaudīt lietotņu (Lightroom u.c.) instalēšanu klases datoros.
4. Pārbaudīt CCleaner noņemšanu visos datoros (inventārs/žurnāli); PC000163/165/166/168/180/182/183 bija ar CCleaner.
5. Pārbaudīt OPENLAB-1/2 pirmos plānotos ciklus un PC000158/161 pabeigšanu; Trotec JobControl + lāzergriezēja tests uz OPENLAB-1 (kad darbiniece klāt, pirmdienās).
6. PIUAC-MAIRITA: pārbaudīt Kick uzdevumu un profila kopijas rindu (viņa strādā pirmdienās); ASUS-IEVA Kick izveidots.
7. Izmeklēt TeamViewerHost exit code 2 (DATORKLASE-01), ja atkārtojas.
8. Pārbaudīt jaunās GUI funkcijas (backup-manager, apps-managed-editor, config-panel), kuras vēl nav palaistas praksē; pārliecināties, ka atjaunotais `lab-backup-collect.ps1` ir NAS `Updates\Tools\lab-backup\`.
9. PC000182 atpakaļ uz SSID PIUAC.
10. (Apturēts) Ierīču reģistrs un uzraudzība — `docs/iericu-uzraudziba.md`.
11. Ja repozitorijā rediģē `client-install.ps1`: sākt no NAS dzīvās versijas, nevis `src/client` kopijas.
12. PIUAC-MONTA: pārbaudīt pirmo plānoto ciklu (trešdien 04:00 — vai WoL pamodināja, cikls, izslēgšanās) un pirmo profila kopiju; ja mainās DHCP IP (.29), pievienot jauno TrustedHosts.
13. Nomainīt `labupdate` paroli (bija repozitorija vēsturē) — visos datoros un NAS.

## Darba kārtība ar Claude

- Sarunas sākumā: izlasīt šo failu un `docs/progress.md`.
- Sarunas beigās (vai pēc lietotāja lūguma "saglabā progresu"): atjaunināt sadaļas "Pieņemtie lēmumi", "Pašreizējais stāvoklis", "Nākamie soļi" šajā failā, pievienot ierakstu `docs/progress.md` un veikt commit + push.
