# Skripti

Visi skripti ir PowerShell (`.ps1`), komentāri latviski bez garumzīmēm (ASCII, CRLF — svarīgi Windows PowerShell 5.1).

| Mape | Saturs | Kur darbojas |
|---|---|---|
| `client/` | `client-install.ps1` (klienta cikls), `setup-client.ps1`, `remote-setup-client.ps1`, `enable-remoting-bootstrap.ps1`, inventārs, paziņojumi, rezerves kopēšanas klienta daļa | klientu datoros / no admin PC attālināti |
| `admin/` | `config-panel.ps1`, `backup-manager.ps1`, `apps-managed-editor.ps1`, `downloader.ps1`, atskaites, reģistrācijas uzdevumi, tīkla skenēšana | admin PC `C:\Scripts` |
| `patches/` | vienreizēji ielāpi NAS `client-install.ps1` + labojumi (`fix-*`) | admin PC, administrators |
| `tv-test/` | TeamViewer Host testa komplekts (`00-common` … `08-rollback`) | admin PC |

## Svarīgi

- **Slepenie dati nav repozitorijā.** `client-install.ps1`: `$TeamViewerApiToken = ""`; `backup-manager.ps1`: `$script:ResticPasswordDefault = ''`. Faktiskās vērtības glabājas NAS/admin PC failos; pēc kopēšanas atpakaļ tās jāaizpilda (vai `client-install.ps1` nemainīt — dzīvā versija ir NAS).
- `client-install.ps1` šeit ir vecāka versija (2026-10-12); aktuālā — NAS.
- `config-piemeri/` satur piemēru/vecākas `Config\*.csv` versijas; dzīvā konfigurācija ir NAS `Config\`.
