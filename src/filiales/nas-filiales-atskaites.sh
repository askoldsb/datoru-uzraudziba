#!/bin/bash
# ============================================================
# nas-filiales-atskaites.sh
# Centra NAS (Synology DSM): Control Panel > Task Scheduler >
# Create > Scheduled Task > User-defined script, lietotajs root,
# ik 15 min. Skripta TEKSTU ielimet uzdevuma laukaa (NEVIS faila
# uz koplietojuma - root palaists fails, ko var rakstit kads cits
# konts, butu drosibas caurums).
#
# Kope filiales atskaites (no hub caur Synology Drive) uz Dobeles
# paneli: Filiales/<BR>/Atskaites/{Status,Inventory}/<PC>.json ->
# Updates/Logs/{Status,Inventory}/<PC>.json
#
# Drosiba: kope TIKAI datorus, kas ir filiales grafikaa
# Filiales/<BR>/Skripti/Config/device-schedule.csv (to raksta tikai
# admins caur parakstitu publicesanu; auce-sync tur rakstit nevar),
# lai filiale nevaretu parrakstit Dobeles datoru statusu.
# ============================================================

BR="Auce"
VOL="/volume1"
SRC="$VOL/Filiales/$BR/Atskaites"
CSV="$VOL/Filiales/$BR/Skripti/Config/device-schedule.csv"
DST="$VOL/Updates/Logs"
LOG="$VOL/Filiales/$BR/nas-atskaites.log"

log() { [ -L "$LOG" ] && rm -f "$LOG"; echo "$(date '+%Y-%m-%d %H:%M:%S')  $*" >> "$LOG"; }

if [ ! -d "$SRC" ] || [ ! -d "$DST/Status" ] || [ ! -d "$DST/Inventory" ] || [ ! -f "$CSV" ]; then
    log "KLUDA: nav $SRC, $DST/Status|Inventory vai $CSV"
    exit 1
fi

# Datoru vardi no grafika (1. kolonna, bez virsraksta, bez pedinam/BOM/CR);
# atlautas tikai drosas rakstzimes (nav celu, atstarpju u.c.).
names=$(tail -n +2 "$CSV" | tr -d '\r' | cut -d, -f1 | tr -d '"' | grep -E '^[A-Za-z0-9._-]{1,63}$')

copied=0
for n in $names; do
    for rel in "Status/$n.json" "Status/$n.command.json" "Inventory/$n.json"; do
        f="$SRC/$rel"
        d="$DST/$rel"
        [ -f "$f" ] || continue
        [ -L "$f" ] && continue
        if [ ! -f "$d" ] || [ "$f" -nt "$d" ]; then
            rm -f "$d.tmp-filiale"
            cp -f "$f" "$d.tmp-filiale" && mv -f "$d.tmp-filiale" "$d" && touch -r "$f" "$d" && copied=$((copied + 1))
        fi
    done
done

[ "$copied" -gt 0 ] && log "nokopeti $copied faili ($BR)"

# Zurnalu neturam bezgaligi
if [ -f "$LOG" ] && [ "$(wc -c < "$LOG")" -gt 1048576 ]; then
    mv -f "$LOG" "$LOG.old"
fi
exit 0
