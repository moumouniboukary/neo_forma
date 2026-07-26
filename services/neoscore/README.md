# Service ML NeoScore — solvabilité
#
# Le score runtime de l'API peut appeler ce service si SCORING_ML_URL est défini.
# Sinon, l'API utilise l'heuristique TypeScript (`@neoforma/neoscore`).

## Démarrage local

```bash
cd services/neoscore
python -m venv .venv
# Windows
.venv\Scripts\activate
# Linux/macOS
# source .venv/bin/activate
pip install -r requirements.txt
uvicorn main:app --reload --port 8000
```

Health : http://localhost:8000/health

## Endpoints

| Méthode | Chemin | Rôle |
|---------|--------|------|
| GET | `/health` | Liveness + modèle chargé |
| GET | `/model` | Métadonnées (version, AUC, nSamples) |
| POST | `/score` | Inférence `{ "features": { ... } }` |
| POST | `/train` | Ré-entraînement (samples labellisés + synthétique) |
| POST | `/train/synthetic` | Bootstrap synthétique (legacy) |

## Brancher l'API

```bash
# apps/api/.env
SCORING_ML_URL=http://localhost:8000
SCORING_ML_TIMEOUT_MS=2500
```

Puis `POST /score/recalculate` — le champ `engine` devient `"ml"`.

## Labels solvabilité

Les labels viennent des demandes crédit (`outcome` = `rembourse_ok` | `defaut`).
L'admin exporte le dataset et déclenche `/train` (voir `docs/ml-scoring.md`).
