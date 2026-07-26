# NeoForma

Infrastructure numérique d’inclusion financière pour le secteur informel (Burkina Faso).

**Cible produit :** application **mobile Flutter** (`apps/mobile`) + API Node. La PWA React (`apps/web`) reste en legacy.

## Stack

| Couche | Techno |
|--------|--------|
| App mobile | **Flutter / Dart** |
| API | Fastify + Prisma + PostgreSQL + Redis |
| Contrats | Zod (`@neoforma/shared`) |
| Score | `@neoforma/neoscore` |
| Docs API | OpenAPI `/docs` |
| Legacy | React PWA (`apps/web`) |

## Prérequis

- Node.js ≥ 20
- Docker (Postgres + Redis)
- Flutter SDK ≥ 3.22 + Android Studio / device

## 1. API

```bash
docker compose up -d
npm install
cp apps/api/.env.example apps/api/.env   # si besoin
npm run db:deploy
npm run dev:api    # http://localhost:3001  · docs : /docs
```

Postgres : port **5433**. OTP démo : `devCode` (ou SMS via Twilio / `SMS_GATEWAY_URL`).

Ops (alertes, backups, IMF) : [`docs/ops.md`](docs/ops.md) · Déploiement : [`docs/deployment.md`](docs/deployment.md) · **ML solvabilité** : [`docs/ml-scoring.md`](docs/ml-scoring.md)

## 2. App Flutter

```bash
cd apps/mobile
flutter pub get

# Émulateur Android
flutter run --dart-define=API_BASE=http://10.0.2.2:3001

# Téléphone (même Wi‑Fi) — IP du PC
flutter run --dart-define=API_BASE=http://192.168.x.x:3001
```

Détails : [`apps/mobile/README.md`](apps/mobile/README.md)

## PWA legacy (optionnel)

```bash
npm run dev:web    # http://localhost:5173
```

## Production API

```bash
npm run prod:up
```

## Qualité

```bash
npm run typecheck
npm run test
cd apps/mobile && flutter analyze && flutter test
```

CI : `.github/workflows/ci.yml`

## Architecture monorepo

```
apps/mobile       Flutter — client mobile principal
apps/web          PWA React — legacy
apps/api          API métier + OpenAPI
packages/shared   Schémas & contrats
packages/neoscore Moteur NeoScore
docs/             Analyse, domaine, UML, DB, architecture
DAMINA&POESAM_2026/  Livrables concours
```

## Modules API

`identity` · `profile` · `consent` · `ledger` · `sync` · `scoring` · `credit` · `partners`

## Design

- Maquette : `DAMINA&POESAM_2026/NeoForma_Design_Figma.html`
- Figma : `DAMINA&POESAM_2026/NeoForma_App.fig`
