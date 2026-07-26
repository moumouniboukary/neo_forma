#!/bin/sh
set -e

# Applique les migrations Prisma avant de démarrer l'API (idempotent).
echo "[entrypoint] prisma migrate deploy…"
npx prisma migrate deploy

echo "[entrypoint] démarrage API"
exec npx tsx src/main.ts
