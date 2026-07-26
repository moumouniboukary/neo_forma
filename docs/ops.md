# Exploitation NeoForma (ops)

Guide Flutter-first : API + app mobile. La PWA `apps/web` est **legacy** (non cible produit).

## Alertes

| Mécanisme | Description |
|-----------|-------------|
| `ALERT_WEBHOOK_URL` | L'API POSTe sur ce webhook en cas d'erreur 5xx ou `/ready` = not_ready (cooldown 1 min) |
| `scripts/watch-ready.mjs` | Sonde externe (cron toutes les 5 min) |

```bash
# Local / VPS
API_BASE=https://votre-api.onrender.com \
ALERT_WEBHOOK_URL=https://hooks.slack.com/services/... \
node scripts/watch-ready.mjs
```

Compatible Slack (`text`) et Discord (`content`).

Sentry reste optionnel (`SENTRY_DSN`). Métriques : `GET /metrics` (Prometheus).

## Backups Postgres

```bash
# Linux / macOS (Docker ou DATABASE_URL)
./scripts/backup-postgres.sh

# Windows PowerShell
powershell -File scripts/backup-postgres.ps1
```

Fichiers dans `backups/` (14 dernières copies conservées).

**Render :** activer les backups automatiques Postgres dans le dashboard (plan payant) ou planifier `pg_dump` depuis un cron externe avec `DATABASE_URL`.

**Docker Compose prod :** volume `neoforma_pg` — sauvegarder régulièrement avec le script ci-dessus.

## Redis (Render)

Le blueprint [`render.yaml`](../render.yaml) provisionne un **Redis** managé et injecte `REDIS_URL` dans l'API (rate-limit OTP distribué).

## Partenaires IMF / commissions

| Endpoint | Auth | Rôle |
|----------|------|------|
| `GET /partners/applications` | `X-Partner-Key` | File des demandes |
| `POST /partners/applications/:id/decide` | `X-Partner-Key` | Décision (+ commission si approuvée) |
| `GET /partners/commissions` | `X-Partner-Key` | Facturation |
| `PATCH /partners/commissions/:id` | `X-Partner-Key` | `due` → `facturee` → `payee` |

Clé : `PARTNER_API_KEY` (globale) ou `Imf.apiKey` en base. Taux : `Imf.tauxCommission` (défaut 2 %).

## Mobile Money

Les opérations du cahier acceptent `canal: "especes" | "mobile_money"` (API + app Flutter).

Rails cash-in / cash-out (stubs jusqu’aux credentials opérateurs) :

| Endpoint | Auth | Rôle |
|----------|------|------|
| `GET /mobile-money/providers` | – | Orange / Moov / stub + flag `configured` |
| `POST /mobile-money/transfer` | JWT | Transfert ; `async: true` → file worker |

Env : `ORANGE_MM_URL`, `ORANGE_MM_API_KEY`, `MOOV_MM_URL`, `MOOV_MM_API_KEY`.

## Worker async

Processus séparé `apps/worker` qui consomme Redis `neoforma:jobs` (SMS, alertes, MM).

```bash
npm run dev:worker          # local
# Compose prod : service `worker` (USE_JOB_QUEUE=1 sur l’API)
```

`USE_JOB_QUEUE=1` : l’API enqueue SMS ; sinon envoi synchrone (défaut safe sans worker).

## Admin agents

| Endpoint | Auth | Rôle |
|----------|------|------|
| `GET /admin/stats` | `X-Admin-Key` | Compteurs globaux |
| `GET /admin/travailleurs?phone=` | idem | Recherche |
| `GET /admin/credit-applications` | idem | File crédit |

Clé : `ADMIN_API_KEY`.

## White-label

`GET /branding` → `BRAND_*` ou `PARTNER_BRAND_JSON`. L’app Flutter applique couleurs / nom au démarrage.

## Sync hors ligne

Kinds supportés : `create_operation`, `create_client`, `update_profile`, `update_consents`, **`submit_credit`**.
