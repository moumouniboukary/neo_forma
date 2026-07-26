# NeoForma

Infrastructure numérique d’inclusion financière pour le secteur informel (Burkina Faso).

**Cible produit :** application **mobile Flutter** (`apps/mobile`) branchée sur l’API Node. La PWA React (`apps/web`) reste disponible en legacy / démo navigateur.

## Stack

| Couche | Techno |
|--------|--------|
| App mobile | **Flutter / Dart** (`apps/mobile`) |
| API | Fastify + Prisma + PostgreSQL + Redis |
| Contrats | Zod (`@neoforma/shared`) |
| Score | `@neoforma/neoscore` |
| Docs API | OpenAPI `/docs` |
| Legacy web | React PWA (`apps/web`) |

## Prérequis

- Node.js ≥ 20
- Docker (Postgres + Redis)
- Flutter SDK ≥ 3.22 + Android Studio (ou device)

## API (toujours requise)

```bash
docker compose up -d
npm install
cp apps/api/.env.example apps/api/.env   # si besoin
npm run db:push
npm run dev:api    # http://localhost:3001  · docs : /docs
```

## App Flutter

```bash
cd apps/mobile
flutter pub get

# Émulateur Android (API sur la machine hôte)
flutter run --dart-define=API_BASE=http://10.0.2.2:3001

# Téléphone physique (même Wi‑Fi) — remplacer par l’IP du PC
flutter run --dart-define=API_BASE=http://192.168.x.x:3001
```

OTP démo : le code `devCode` s’affiche à l’écran (pas de SMS réel en local).

## PWA legacy (optionnel)

```bash
npm run dev:web    # http://localhost:5173
```

## Production API

```bash
npm run prod:up
# PWA : http://localhost:8080  · API : http://localhost:3001/docs
```

## Qualité

```bash
npm run typecheck
npm run test
cd apps/mobile && flutter analyze && flutter test
```

## Architecture monorepo

```
apps/mobile       Flutter (client mobile principal)
apps/web          PWA React (legacy)
apps/api          API métier + OpenAPI
packages/shared   Schémas & contrats
packages/neoscore Moteur NeoScore
docs/             Analyse, domaine, UML, DB, architecture
DAMINA&POESAM_2026/  Livrables concours
```

## Modules API

`identity` · `profile` · `consent` · `ledger` · `sync` · `scoring` · `credit` · `partners`
