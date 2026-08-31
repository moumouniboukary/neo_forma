# TeriyaScore / DigiCoop — trajectoire scoring hybride

## Objectif long terme

**Scorecard explicable calibré sur la data** + **ML en soutien** (pas un FICO opaque).

| Phase | État | Description |
|-------|------|-------------|
| 1. Expert | **En prod** | Barème à points DigiCoop 300–850 (`expert_scorecard`) |
| 2. Labels | **Socle livré** | Outcomes `rembourse_ok` / `defaut` / `en_cours` sur `agent_dossiers` |
| 3. Calibrage stats | **Socle livré** | Logistique → multiplicateurs de poids (`calibrated_scorecard`) |
| 4. ML assisté | Plus tard | XGBoost / service ML pour proposer recalibrages + AUC hors scorecard |

## API admin (clé `ADMIN_API_KEY`)

| Méthode | Route | Rôle |
|---------|-------|------|
| GET | `/admin/agent-dossiers` | Lister les dossiers |
| PATCH | `/admin/agent-dossiers/:id/outcome` | Labelliser `{ outcome, note? }` |
| GET | `/admin/agent-score/dataset` | Export labels pour stats / ML |
| GET | `/admin/agent-score/calibration` | Calibration active |
| POST | `/admin/agent-score/calibrate` | Recalibrer + activer (min. 20 labels, ≥3 de chaque classe) |

## Code

- `packages/neoscore/src/agent-scorecard.ts` — scorecard + application des poids
- `packages/neoscore/src/calibrate-agent-scorecard.ts` — logistique / AUC / seuils
- `apps/api/src/modules/admin/agent-dossiers.ts` — service labels + calibrage

## Usage terrain

1. Les agents saisissent des dossiers (score expert local).
2. DigiCoop pose les outcomes après décaissement / échéancier.
3. Quand assez de labels : `POST /admin/agent-score/calibrate`.
4. Les prochains calculs peuvent consommer la calibration active (mobile : sync des poids — à brancher côté app).

## Mobile (calibration active)

1. Au login / ouverture « Nouveau dossier » / sync : `GET /score/agent-calibration` (JWT).
2. Cache Hive `agent_score_calibration` → offline garde le dernier calibrage.
3. `computeAgentScorecard(input, calibration: …)` applique les poids.
4. Le dossier figé contient `engine` + `modelVersion` (sync API).

Session locale (« Essayer sans compte ») : reste en `expert_scorecard` (pas d’appel API).

## ML (phase 4)

Réutiliser `SCORING_ML_URL` / `POST /admin/ml/retrain` pour NeoScore entrepreneur.
Pour DigiCoop : exporter `/admin/agent-score/dataset` vers le service ML, entraîner un modèle, puis **proposer** de nouveaux `partWeights` sans remplacer l’explicabilité scorecard.
