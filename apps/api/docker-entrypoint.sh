#!/bin/sh
# Ne jamais bloquer le boot : un migrate raté tuait le service (status 1).
echo "[entrypoint] prisma migrate deploy…"
npx prisma migrate deploy || echo "[entrypoint] WARN migrate deploy failed, API starts anyway"

echo "[entrypoint] ensure agent_dossiers…"
npx prisma db execute --file prisma/ensure-agent-dossiers.sql || echo "[entrypoint] WARN ensure table failed"

echo "[entrypoint] démarrage API"
exec npx tsx src/main.ts
