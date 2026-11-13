#!/usr/bin/env bash
# Sauvegarde /etc dans /var/backups et supprime les archives trop anciennes.
# Usage : backup-etc.sh [jours_de_conservation]   (7 par défaut)
set -euo pipefail
umask 077

KEEP_DAYS="${1:-7}"
if ! [[ "${KEEP_DAYS}" =~ ^[0-9]+$ ]]; then
  echo "Usage : $0 [jours_de_conservation]  (nombre entier)" >&2
  exit 2
fi

DEST="/var/backups"
ARCHIVE="${DEST}/etc-$(date +%F).tar.gz"

tar -czf "${ARCHIVE}" -C / etc
find "${DEST}" -maxdepth 1 -type f -name 'etc-*.tar.gz' -mtime "+${KEEP_DAYS}" -delete
logger -t backup-etc "OK : ${ARCHIVE} (conservation : ${KEEP_DAYS} jours)"
