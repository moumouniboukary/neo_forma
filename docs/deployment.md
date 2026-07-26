# Déploiement NeoForma

L'API est packagée en Docker et applique automatiquement les migrations Prisma au démarrage (`docker-entrypoint.sh` → `prisma migrate deploy`).

## Variables d'environnement (API)

| Variable | Requis | Description |
|----------|--------|-------------|
| `DATABASE_URL` | ✅ | URL PostgreSQL |
| `JWT_SECRET` | ✅ (prod) | ≥ 32 caractères, sinon l'API refuse de démarrer |
| `NODE_ENV` | ✅ | `production` |
| `PORT` / `HOST` | – | défaut `3001` / `0.0.0.0` |
| `CORS_ORIGIN` | recommandé | origine(s) autorisée(s), ex. `https://app.neoforma.bf` |
| `REDIS_URL` | recommandé | rate-limit OTP distribué (injecté auto sur Render) |
| `RATE_LIMIT_MAX` / `RATE_LIMIT_WINDOW` | optionnel | rate-limit HTTP global (défaut 300 / 1 min en prod) |
| `TWILIO_ACCOUNT_SID` / `TWILIO_AUTH_TOKEN` / `TWILIO_FROM` | optionnel | SMS réels |
| `SMS_GATEWAY_URL` / `SMS_API_KEY` | optionnel | gateway SMS générique |
| `SENTRY_DSN` | optionnel | suivi des erreurs |
| `ALERT_WEBHOOK_URL` | optionnel | alertes Slack/Discord sur 5xx / not_ready |
| `PARTNER_API_KEY` | optionnel | clé IMF (commissions / décisions) |
| `KOBO_API_KEY` | optionnel | ingestion terrain |

Sans passerelle SMS, le code OTP est renvoyé dans la réponse (`devCode`) — **mode test uniquement**.

## Option A — Render (le plus simple)

1. Pousser le repo sur GitHub.
2. [render.com](https://render.com) → **New → Blueprint** → sélectionner le repo.
3. Render lit [`render.yaml`](../render.yaml) : crée **Postgres + Redis** + l'API Docker, génère `JWT_SECRET`, injecte `REDIS_URL`.
4. Renseigner dans le dashboard : `CORS_ORIGIN`, et (optionnel) `TWILIO_*`, `SENTRY_DSN`, `ALERT_WEBHOOK_URL`, `PARTNER_API_KEY`.
5. Les migrations s'appliquent seules au premier boot. Vérifier `https://<service>.onrender.com/ready`.

Ops (alertes, backups, commissions) : [`docs/ops.md`](ops.md).

## Option B — VPS / serveur Docker

```bash
cp .env.prod.example .env      # renseigner POSTGRES_PASSWORD + JWT_SECRET (≥32)
npm run prod:up                # docker compose -f docker-compose.prod.yml up -d --build
```

- API : `:3001` · PWA legacy : `:8080`
- Migrations appliquées automatiquement au démarrage du conteneur `api`.

## Option C — Fly.io

```bash
fly launch --no-deploy         # génère fly.toml
fly postgres create            # base managée
fly postgres attach <db>       # injecte DATABASE_URL
fly secrets set JWT_SECRET=... CORS_ORIGIN=... TWILIO_ACCOUNT_SID=... TWILIO_AUTH_TOKEN=... TWILIO_FROM=...
fly deploy --dockerfile Dockerfile --build-target api
```

## App mobile

Compiler l'app en pointant sur l'API déployée :

```bash
cd apps/mobile
flutter build apk --release --dart-define=API_BASE=https://<votre-api>
```

## Santé & métriques

| Endpoint | Rôle |
|----------|------|
| `GET /health` | Liveness (process up) |
| `GET /ready` | Readiness : Postgres obligatoire, Redis si `REDIS_URL` |
| `GET /metrics` | Prometheus (compteurs HTTP, latences, uptime) |

Configurer le health check Render/Fly sur `/health` (liveness) ou `/ready` (readiness).

Scraper `/metrics` avec Prometheus / Grafana Cloud. Sentry reste optionnel via `SENTRY_DSN`.

## RGPD

| Endpoint | Rôle |
|----------|------|
| `GET /me/export` | Export JSON portable (droit d'accès) |
| `DELETE /me` | Suppression compte `{ pin, confirm: true }` (droit à l'oubli) |


| Contexte | Commande |
|----------|----------|
| Créer une migration (dev) | `npm run db:migrate` |
| Appliquer en prod / CI | `npm run db:deploy` |
| Vérifier l'état | `npm run db:status` |

Ne plus utiliser `db:push` en production (perte de données possible).
