# Darba žurnāls

Jaunākie ieraksti augšā.

## 2026-11-04 (RUM ieviests)

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
