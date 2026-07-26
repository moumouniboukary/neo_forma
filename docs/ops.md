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

## Sync hors ligne

Kinds supportés : `create_operation`, `create_client`, `update_profile`, `update_consents`, **`submit_credit`**.
