# NeoScore ML — solvabilité (pipeline prod)

## Architecture

```
App / API  ──►  ScoringService
                  │
                  ├─ SCORING_ML_URL défini + /score OK  → engine: "ml"
                  └─ sinon / timeout / erreur           → engine: "heuristic"
                                                              (@neoforma/neoscore)

Labels  ◄──  DemandeCredit.outcome (rembourse_ok | defaut)
             + featuresSnapshot figé à la soumission

Admin   ──►  GET /admin/ml/dataset
             POST /admin/ml/retrain  ──►  service ML POST /train
             GET /admin/ml/runs
```

Le modèle prédit **P(défaut)** puis expose `score = (1 − P) × 100` (seuil d’éligibilité 50).

## Activer (local)

### 1. Service ML

```bash
cd services/neoscore
python -m venv .venv
.venv\Scripts\activate          # Windows
pip install -r requirements.txt
uvicorn main:app --reload --port 8000
```

Vérifier : http://localhost:8000/health → `modelReady: true`

### 2. API

Dans `apps/api/.env` :

```bash
SCORING_ML_URL=http://localhost:8000
SCORING_ML_TIMEOUT_MS=2500
ADMIN_API_KEY=dev-admin-key-change-me
```

Redémarrer l’API, puis :

```bash
# depuis l’app ou curl authentifié
POST /score/recalculate
# → { "engine": "ml", "modelVersion": "...", "score": ... }
```

## Collecte des labels (solvabilité réelle)

1. IMF décaissement : `POST /partners/applications/:id/decide` `{ "statut": "decaissee" }`  
   → `outcome=en_cours`, dates décaissement / échéance.
2. Clôture :
   - Partenaire : `POST /partners/applications/:id/outcome` `{ "outcome": "rembourse_ok" | "defaut" }`
   - Admin : `POST /admin/credit-applications/:id/outcome` (header `X-Admin-Key`)

À la soumission, `featuresSnapshot` est déjà figé pour l’entraînement.

## Ré-entraînement

```bash
# Inspecter le dataset
curl -H "X-Admin-Key: $ADMIN_API_KEY" https://API/admin/ml/dataset

# Ré-entraîner (labels réels + 200 synthétiques par défaut)
curl -X POST -H "X-Admin-Key: $ADMIN_API_KEY" -H "Content-Type: application/json" \
  -d '{"nSynthetic":200}' https://API/admin/ml/retrain
```

Sans labels réels, le modèle bootstrappe sur données synthétiques (proxy risque).  
Dès que des `rembourse_ok` / `defaut` existent, le mix `mixed` améliore la pertinence.

## Déployer le ML (Render)

1. **New → Web Service** → repo `neo_forma`
2. Runtime Docker, Dockerfile : `services/neoscore/Dockerfile`, context : `services/neoscore`
3. Health check : `/health`
4. Plan free OK pour un pilote
5. Sur `neoforma-api`, env `SCORING_ML_URL=https://<ml-service>.onrender.com`
6. Redéployer l’API

> Plan free : le service ML s’endort aussi (~30–60 s au réveil). Timeout API configurable via `SCORING_ML_TIMEOUT_MS` (fallback heuristique si trop lent).

## Monitoring

| Endpoint | Rôle |
|----------|------|
| `GET /admin/stats` → `ml` | enabled, health, labeledOutcomes |
| `GET /admin/ml/runs` | historique AUC / nSamples |
| `GET <ML>/model` | métadonnées artefact actif |

## Migration DB

```bash
npm run db:deploy
# migration 20260726170000_ml_solvency
```
