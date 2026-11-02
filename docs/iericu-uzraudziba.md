# Atskaites punkts: ierīču uzskaite un uzraudzība (2026-10-22)

Statuss: **apturēts**, prioritāte ir jaunu datoru pievienošana. Turpināt vēlāk.

## Mērķis
Uzskaitīt ne-datoru iekārtas (monitori, printeri, ekrāni, info kioski, ClickShare, tīkla iekārtas) un zināt "kas, kur, kad noticis". Izvēlētais līmenis: **3. līmenis**, t.i. automātiska uzraudzība + reģistrs + notikumu žurnāls.

## Plāns
1. `Config\devices.csv` uz NAS: ID, veids, modelis, sērijas nr., telpa, IP/MAC, piegādātājs, garantija līdz, uzraudzība (jā/nē, ping/HTTP), piezīmes.
2. Uzraudzība uz NAS: DSM Task Scheduler, ik pēc 5 min ping/HTTP katrai ierīcei ar uzraudzību, raksta `Logs\Devices\status.json` un `events.csv` (nokrita/atgriezās ar laiku). Neobligāts e-pasta brīdinājums, ja ierīce nav sasniedzama > 30 min.
3. Logs config panelī "Ierīces": zaļš/sarkans, "pēdējo reizi redzēts", vēsture, manuāla notikuma pievienošana (remonts, firmware u.c.). Nosaukumus un telpas aizpilda lietotājs pats.

## Kas jau zināms (skenēšana 2026-10-22, apakštīkls 192.168.3.x)
- Skenēšanas rezultāts: `C:\Scripts\devices-scan.csv` uz admin PC (IP, atvērtie porti, lapas virsraksts).
- MikroTik / RouterOS: .1 (vārteja), .3, .4, .6, .7, .8, .10.
- .2: tīmekļa lapa 80/443, iespējams slēdzis.
- Printeri (pēc portiem/MAC): .113 (Ricoh), .54 (9100), .251 (9100), .48 un .49 (Brother).
- Iespējami IP telefoni ("Loading Web Application"): .25, .75, .130, .131, .132.
- NAS: .31.
- Sākuma uzraudzības saraksts (~12 ierīces): MikroTik ierīces, 3 printeri, NAS. Pārējās var pievienot reģistram bez uzraudzības.

## Zināmie ierobežojumi
- **ClickShare bāze** (C 3010S) ir Access Point režīmā, LAN kabelis nav pievienots, tāpēc tā nav sasniedzama no tīkla. Uzraudzībai jāpievieno kabelis un jānosaka tās IP (piekļuves maršrutētājam nav).
- Monitori un ekrāni parasti nav tīklā, tos var tikai uzskaitīt reģistrā.
- Ierīču datu pamatā ir tikai MAC/ports/virsraksts, nosaukumi un telpas jāaizpilda pašam.

## Nākamie soļi, kad atgriežamies
1. Apstiprināt sākuma uzraudzības sarakstu (IP + nosaukumi).
2. Es izveidoju `devices.csv`, NAS uzraudzības skriptu (bash) un logu "Ierīces".
3. Lietotājs NAS DSM izveido plānoto uzdevumu (instrukcijas sniegs Claude).

## Saistītie atvērtie jautājumi (cita tēma)
- ClickShare Wi-Fi pazušana: instrukcija dokumentā https://claude.ai/artifact/UJQ9ziNyMRwgzciQixSyMF
- CCleaner noņemšana: ielāps uzlikts, pārbaude pirmdien 26.10 plkst. 12:05 (atgādinājums).
- PIUAC-MAIRITA Kick pārbaude: pirmdien 26.10 plkst. 12:00 (atgādinājums).

## Papildinājums: otrā skenēšana (ar DNS vārdiem), 2026-10-22 11:28
- .16 "Dataserver": porti 445 + 3389 (serveris), iekļaut uzraudzībā.
- .1 "router"; .10 "emacibas.piuac.lv" (RouterOS).
- .29 PIUAC-Monta, .43 PIUAC-Dace, .66 PIUAC-INITA, .31 PIUAC_CLOUD (NAS).
- Printeri: .72 un .113 (Ricoh, RNP...; 80/443/9100/515/631), .54 (80/443/9100/515), .57, .58, .251 (9100).
- Atšķirības starp skenējumiem: printeri miega režīmā dažkārt neatbild uz portiem (.57, .58, .72), tāpēc uzraudzībā jāpārbauda 9100 ports, ne tikai ping. Lapu virsraksti ne vienmēr atgriežas (.113, .25).
- .57 un .127 ARP tabulā ir viena MAC adrese (00-03-76-07-38-e2): pārbaudīt (viens printeris ar divām adresēm vai dublikāts).
- ARP saraksts mainās starp skenējumiem (.194/.195 un .188/.193), tāpēc reģistru veido pēc apstiprinātā saraksta, nevis automātiski.
