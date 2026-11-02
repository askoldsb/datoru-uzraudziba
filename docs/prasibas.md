# Prasības un lietotāja ierobežojumi

Apkopots no sarunām līdz 2026-11-02. Lietotājs: Askolds (latviski).

## Funkcionālās prasības

1. **Bez domēna un bez servera**: viss darbojas ar Windows plānotajiem uzdevumiem un Synology NAS koplietojumu.
2. **Automātiski atjauninājumi** ~30+ datoriem: Windows Update + trešo pušu programmas (winget instalatori no NAS kešatmiņas), pēc grafika (dienas, laiks, izslēgšana pēc cikla), ar paziņojumu lietotājam.
3. **Jaunu datoru pievienošana** ar minimālu darbu (attālā iestatīšana no admin PC) — prioritāte.
4. **Atskaite** par datoru statusu ar krāsām (nokavēti atjauninājumi pēc ~10–14 dienām; piezīme, ja dators nav redzēts tīklā).
5. **Programmu automatizācijas palīgs**: skenēt visu datoru programmu sarakstus un piedāvāt, ko pievienot automatizācijai (jauna = dzeltena, jau automatizēta = zaļa, ignorēt = `apps-ignore.txt`).
6. **Nevēlamu programmu noņemšana** visos (arī nākotnes) datoros: CCleaner.
7. **Lietotāju profilu rezerves kopijas uz NAS** (restic) — atlasīti datori.
8. **Adobe Creative Cloud** visos klases datoros; lietotājs katrā datorā ielogojas ar savu Adobe kontu.
9. **Ierīču uzskaite un uzraudzība** (monitori, printeri, ekrāni, ClickShare, tīkla ierīces; ping/HTTP, notikumu žurnāls) — apturēts, skat. `docs/iericu-uzraudziba.md`.

## Ierobežojumi / nolemtais

- **Outlook un tā datus neaiztikt.**
- Dokumenti kopumā netiek rezerves kopēti; rezerves kopijas **neietver portatīvos un klases datorus**, izņemot ASUS-Ieva un Dace.
- **ESET Endpoint paliek.**
- **Paroles netiek rakstītas dokumentos/atbildēs**; arī repozitorijā nedrīkst būt paroles/API tokeni (restic parole un TeamViewer API token izņemti no kopijas — glabāt tikai admin PC un NAS).
- Lietotājam nav piekļuves maršrutētājam.
- Dokobit/Web eID automatizācija izlaista (nav winget).
- Nav automatizēta ClickShare pārvaldība (bāze Access Point režīmā, nav LAN).

## Darba stils (no lietotāja globālā CLAUDE.md)

- Atbildēt **latviski, īsi**.
- Komandas dot **tikai pa vienam solim**, gaidīt rezultātu; nekad divas komandu grupas vienā ziņā.
- **Vienmēr norādīt, uz kura datora** komanda jāpalaiž (admin PC PIUAC-ASKOLDS vai mērķa dators) **un ar kādām tiesībām**.
- Ja vienu un to pašu vajag vairākiem datoriem, dot **vienu komandu visiem**.
