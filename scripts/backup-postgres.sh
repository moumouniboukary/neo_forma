#!/usr/bin/env bash
# Backup Postgres NeoForma (Docker local ou URL DATABASE_URL).
# Usage:
#   ./scripts/backup-postgres.sh
#   DATABASE_URL=postgresql://... ./scripts/backup-postgres.sh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT_DIR="${BACKUP_DIR:-$ROOT/backups}"
mkdir -p "$OUT_DIR"
STAMP="$(date -u +%Y%m%dT%H%M%SZ)"
FILE="$OUT_DIR/neoforma-$STAMP.sql.gz"

if [[ -n "${DATABASE_URL:-}" ]]; then
  echo "[backup] pg_dump via DATABASE_URL → $FILE"
  pg_dump "$DATABASE_URL" | gzip > "$FILE"
elif docker ps --format '{{.Names}}' | grep -q '^neoforma-postgres$'; then
  echo "[backup] pg_dump via conteneur neoforma-postgres → $FILE"
  docker exec neoforma-postgres pg_dump -U neoforma neoforma | gzip > "$FILE"
else
  echo "Ni DATABASE_URL ni conteneur neoforma-postgres. Abort." >&2
  exit 1
fi

# Conservation : 14 derniers backups
ls -1t "$OUT_DIR"/neoforma-*.sql.gz 2>/dev/null | tail -n +15 | xargs -r rm -f

echo "[backup] OK $(du -h "$FILE" | cut -f1)"
