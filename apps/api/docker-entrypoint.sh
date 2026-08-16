#!/bin/sh
set -e

echo "[entrypoint] prisma migrate deploy…"
if ! npx prisma migrate deploy; then
  echo "[entrypoint] migrate a échoué — on débloque agent_dossiers puis on réessaie"
  npx prisma migrate resolve --rolled-back 20260816100000_agent_dossiers || true
  npx prisma migrate deploy
fi

echo "[entrypoint] démarrage API"
exec npx tsx src/main.ts
