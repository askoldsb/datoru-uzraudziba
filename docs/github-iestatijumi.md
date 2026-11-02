# GitHub iestatījumi un darba kārtība

Apkopots no sarunas 2026-11-02.

## Kontu struktūra

- Claude (claude.ai konts `askoldsb@gmail.com`) ir pieslēgts GitHub lietotājam **`askoldsb`**.
- GitHub pieslēgums ir viens visam Claude kontam, nevis atsevišķai sarunai. To maina claude.ai sadaļā **Settings → Connectors → GitHub**.
- Projekti ir nodalīti pēc īpašnieka:
  - `askoldsb/datoru-uzraudziba` — šis projekts (privāts)
  - `fotostockworkshop/Fotostokeris`, `fotostockworkshop/fotostokeris-releases` — Fotostokeris projekti
- Abiem kontiem var piekļūt caur vienu pieslēgumu, pārslēgšanās nav vajadzīga.

## Kā turpināt darbu jaunā sarunā

1. Sāc jaunu sarunu un palūdz Claude pieslēgt repozitoriju `askoldsb/datoru-uzraudziba`.
2. Claude nolasa `CLAUDE.md` un `docs/progress.md` un turpina no vietas, kur palikām.
3. Darba beigās saki **"saglabā progresu"**: Claude atjaunina `CLAUDE.md` un `docs/progress.md` un veic commit + push.

## Ierobežojumi, kas jāzina

- Claude sesija **nevar izveidot jaunu GitHub repozitoriju**, to jāizveido pašam (https://github.com/new). Pēc tam Claude to var pieslēgt un aizpildīt, arī ja tas ir pilnīgi tukšs (README nav obligāts).
- Ja Claude GitHub lietotnei piekļuve atļauta tikai izvēlētiem repozitorijiem, jaunus repozitorijus var pievienot https://github.com/apps/claude → Configure.
- **"Confirm access"** logs GitHub ir drošības pārbaude (sudo mode). Kods netiek sūtīts automātiski, to var apstiprināt ar:
  - GitHub paroli (vienkāršākais),
  - passkey / drošības atslēgu,
  - GitHub Mobile lietotni,
  - authenticator lietotnes kodu,
  - "Send a code via email" — kods nāk uz GitHub konta **galveno** e-pastu (var nebūt `askoldsb@gmail.com`; pārbaudīt arī spam).

## GitHub bezmaksas plāna limiti (aptuveni)

Avots: trešo pušu apskati; precīzi aktuālie limiti — docs.github.com ("Repository limits").

| Kas | Limits |
|---|---|
| Repozitoriju skaits (arī privāti) | neierobežots |
| Repozitorija izmērs | ieteicams < 1 GB, stingri ieteicams < 5 GB |
| Viens fails | brīdinājums > 50 MB, bloķē > 100 MB |
| Git LFS | 1 GB krātuve, 1 GB datplūsma mēnesī |
| Actions artefakti + Packages | 500 MB kopā |
| GitHub Pages | 1 GB vietne, 100 GB datplūsma mēnesī |

Šim projektam (teksta dokumenti, kods) limiti nav problēma. Lielus bināros failus (instalatorus, video, datubāzu dampus, lielus logus) labāk neglabāt Git — izmantot GitHub Releases vai citu krātuvi.
