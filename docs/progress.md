# Darba žurnāls

Jaunākie ieraksti augšā.

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
- ClickShare instrukcija pabeigta (Claude Docs). Ierīču uzskaite — atskaites punkts, apturēts.

## 2026-11-02 (papildinājums)

- Sarunas informācija apkopota `docs/github-iestatijumi.md`: kontu struktūra, darba kārtība jaunās sarunās, ierobežojumi, "Confirm access" pārbaude, bezmaksas plāna limiti.
- `CLAUDE.md` papildināts ar pieņemtajiem lēmumiem.
- Sistēmas mērķis vēl nav aprakstīts — nākamais solis.

## 2026-11-02

- Izveidots GitHub repozitorijs `askoldsb/datoru-uzraudziba` projekta informācijas glabāšanai.
- Pievienoti sākuma faili: `README.md`, `CLAUDE.md`, `docs/progress.md`.
- Noskaidrots: Claude ir pieslēgts GitHub lietotājam `askoldsb`; Fotostokeris repozitoriji atrodas `fotostockworkshop` kontā un paliek nodalīti.
