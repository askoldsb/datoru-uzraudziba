# src/filiales — filiāļu (Auce u.c.) skripti

Arhitektūra un lēmumi: `docs/filiales-auce.md`; žurnāls: `docs/filiales-progress.md`.

## Galvenais secinājums (2026-11-04)

NAS dzīvais `client-install.ps1` (kopija bez TeamViewer tokena — `atsauce/client-install.nas-2026-11-04.ps1`) visus ceļus ņem no parametra **`-NasRoot`** (`Config\versions.json`, `device-schedule.csv`, `apps-managed.csv`, `adobe-rum.txt`, `Config\Commands\`, `Logs\Clients|Status|Inventory|MsiLogs`, `Modules\PSWindowsUpdate`, `Scripts\collect-inventory.ps1`, `Cache\`). Arī `setup-client.ps1`, `collect-inventory.ps1`, `update-notice.ps1` pieņem `-NasRoot`, un `setup-client.ps1` to ieraksta plānotā uzdevuma darbībā.

→ Filiālē **klienta skripti netiek dakšoti**: hub datorā `C:\Hub\Updates` atkārto NAS `Updates` struktūru, koplietots kā `\\AUCEUPDATE-PC\Updates`, un klientus uzstāda ar `setup-client.ps1 -NasRoot \\AUCEUPDATE-PC\Updates`.

## Kas filiālei jāpielāgo / jāizveido

| Fails | Kas jādara |
|---|---|
| `downloader.ps1` | `$NasRoot` ir cieti iekodēts (`\\PIUAC_CLOUD\Updates`) → padarīt par parametru (vai filiāles kopija ar `C:\Hub\Updates`); palaist hub datorā naktī. winget bez admin/SYSTEM — pārbaudīt. |
| `client-install.ps1` | TeamViewer token iekodēts skriptā → ieteicams pārnest uz atsevišķu konfigurācijas failu (piem. `Config\teamviewer-token.txt`, tikai `labupdate` lasāms), lai skripts pats ir bez noslēpumiem un to var parakstīt/sinhronizēt. |
| (jauns) hub publicēšanas uzdevums | `Sync\Skripti` → `C:\Hub\Updates\Scripts|Config` **tikai pēc paraksta pārbaudes** (Authenticode, sertifikāts no PIUAC-ASKOLDS). |
| (jauns) hub atskaišu uzdevums | `C:\Hub\Updates\Logs\Status|Inventory` (+ pēc vajadzības `Clients`) → `C:\Hub\Sync\Atskaites\` (Drive augšupielādē). Žurnālu glabāšanas limits (5 GB kvota). |
| (jauns) NAS uzdevums | `Filiales\Auce\Atskaites\Status|Inventory` → `Updates\Logs\Status|Inventory` (panelis bez izmaiņām). |
| `device-schedule.csv` (hub) | Auces datori ar `Group = Auce-…`. |
| `config-panel.ps1` | "Nav redzēts tīklā" filiāles datoriem — pēc pēdējā statusa laika, ne ping (vēlāk). |

## Parakstīta publicēšana (2026-11-05)

Centrs → filiāle iet **tikai** caur parakstītu manifestu:

```
PIUAC-ASKOLDS                         NAS                               Hub (AUCEUPDATE-PC)
C:\Scripts\Filiales\Auce\             Filiales\Auce\Skripti\            C:\Hub\Sync\Skripti\  (Drive, Download only)
  Scripts\ Config\ Modules\ Tools\  →   (tie paši + manifest.psd1)   →    Hub-Sync (SYSTEM, 15 min):
publish-filiale.ps1:                                                      paraksts Valid + thumbprint + Branch +
  SHA256 → manifest.psd1 → paraksts                                       Sequence + visi SHA256 → kopē uz
                                                                          C:\Hub\Updates\{Scripts,Config,Modules}, C:\Hub\Tools
```

| Fails | Kur | Kad |
|---|---|---|
| `new-signing-cert.ps1` | PIUAC-ASKOLDS, parasts PowerShell (Askolda konts) | vienreiz; privātā atslēga neeksportējama, CurrentUser\My |
| `publish-filiale.ps1` | PIUAC-ASKOLDS, parasts PowerShell | katru reizi pēc izmaiņām (`-RefreshFromNas` paņem dzīvos skriptus un PSWindowsUpdate no NAS) |
| `install-hub-sync.ps1` | hub, admin, no `C:\Hub\Sync\Skripti\Tools\` | vienreiz (vai pēc sertifikāta maiņas) ar `-ExpectedThumbprint` no PIUAC-ASKOLDS |
| `hub-sync.ps1` | hub `C:\Hub\Tools`, uzdevums `Hub-Sync` | automātiski; arī pats sevi atjaunina caur parakstītu `Tools\` |

Hub stāvoklis centrā: `Filiales\Auce\Atskaites\Hub\<hub>.json` (`PublishResult`: Published / UpToDate / Pending / Rejected / Error). Žurnāls hub datorā: `C:\Hub\State\hub-sync.log`.

Pārbaudīts (mock, pwsh 7 Linux): pirmā publicēšana, atkārtota (UpToDate), SHA256 neatbilstība (Pending, mērķis neskarts), vecāks Sequence, `..\`, neatļauta augšējā mape, cita filiāle, cits parakstītājs, nederīgs paraksts — visi noraidīti.
