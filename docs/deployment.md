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
| `ADMIN_API_KEY` | optionnel | agents admin (`X-Admin-Key`) |
| `USE_JOB_QUEUE` | optionnel | `1` = SMS via worker Redis |
| `ORANGE_MM_*` / `MOOV_MM_*` | optionnel | rails Mobile Money |
| `BRAND_*` / `PARTNER_BRAND_JSON` | optionnel | white-label `GET /branding` |

Sans passerelle SMS, le code OTP est renvoyé dans la réponse (`devCode`) — **mode test uniquement**.

## Option A — Render (le plus simple)

1. Pousser le repo sur GitHub.
2. [render.com](https://render.com) → **New → Blueprint** → sélectionner le repo.
3. Render lit [`render.yaml`](../render.yaml) : crée **Postgres + Key Value** + l'API (`Dockerfile.api`), génère `JWT_SECRET`, injecte `REDIS_URL`.
4. **Always-on :** `neoforma-api` est en `0.5c-512mb` (Starter, ~7 $/mois) pour ne pas s’endormir. `neoforma-db` est en `0.1c-256mb` (Basic-256mb, ~6 $/mois) pour ne pas expirer à 30 jours. Ajouter une carte sur Render avant le sync Blueprint. `neoforma-ml` reste Free.
5. Renseigner dans le dashboard : `CORS_ORIGIN` (ex. `*`), et (optionnel) `TWILIO_*`, `SENTRY_DSN`, `ALERT_WEBHOOK_URL`, `PARTNER_API_KEY`.
6. Les migrations s'appliquent seules au premier boot. Vérifier `https://<service>.onrender.com/ready`.

> **Note :** Render ne supporte pas `dockerTarget` — d’où `Dockerfile.api` dédié (le `Dockerfile` multi-stage reste pour `docker compose`).

Ops (alertes, backups, commissions) : [`docs/ops.md`](ops.md).

## Option B — VPS / serveur Docker

```bash
cp .env.prod.example .env      # renseigner POSTGRES_PASSWORD + JWT_SECRET (≥32)
npm run prod:up                # docker compose -f docker-compose.prod.yml up -d --build
```

- API : `:3001` · Worker (jobs Redis) · PWA legacy : `:8080`
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
# Play Store / distribution : signer en release (pas debug)
#   cp android/key.properties.example android/key.properties
#   keytool -genkey -v -keystore android/upload-keystore.jks ...
flutter build apk --release --dart-define=API_BASE=https://<votre-api>
```

Sans `android/key.properties`, le build release retombe sur la signature **debug** (OK pour tests, pas pour les stores).

E2E device (Maestro) : `npm run mobile:e2e` — voir `apps/mobile/e2e/`.

## NeoScore ML (solvabilité)

Pipeline optionnel : service Python + labels remboursement. Voir [`ml-scoring.md`](ml-scoring.md).

```bash
npm run ml:up
# apps/api/.env → SCORING_ML_URL=http://localhost:8000
```

Sur Render : `render.yaml` crée `neoforma-ml` et injecte automatiquement
`SCORING_ML_URL` (host du service ML) sur `neoforma-api`.

## Santé & métriques

| Endpoint | Rôle |
|----------|------|
| `GET /health` | Liveness (process up) |
| `GET /ready` | Readiness : Postgres obligatoire, Redis si `REDIS_URL` |
| `GET /metrics` | Prometheus (compteurs HTTP, latences, uptime) |

Health check Render : **`/health`** (le process répond). Ne pas utiliser `/ready` comme sonde Render : une base encore endormie renvoyait 503 et faisait tuer l’instance (`Exited with status 1`). `/ready` reste utile pour un diagnostic manuel.

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
