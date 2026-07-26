"""
NeoForma NeoScore — service ML optionnel (entraînement / batch).
Le score runtime de l'app passe par packages/neoscore (TypeScript).
"""
from __future__ import annotations

import sys
from pathlib import Path

from fastapi import FastAPI
from pydantic import BaseModel, Field

ROOT = Path(__file__).resolve().parents[2]
MODEL_DIR = ROOT / "DAMINA&POESAM_2026"
if MODEL_DIR.exists():
    sys.path.insert(0, str(MODEL_DIR))

app = FastAPI(title="NeoForma NeoScore ML", version="0.1.0")


class TrainRequest(BaseModel):
    n_samples: int = Field(default=120, ge=20, le=5000)


@app.get("/health")
def health():
    return {"status": "ok", "service": "neoscore-ml"}


@app.post("/train/synthetic")
def train_synthetic(body: TrainRequest):
    """Exécute le pipeline historique (données synthétiques)."""
    try:
        from NeoForma_NeoScore_Model import generer_donnees_synthetiques, pretraiter
    except ImportError:
        return {
            "ok": False,
            "message": "NeoForma_NeoScore_Model.py introuvable dans DAMINA&POESAM_2026/",
        }

    df = generer_donnees_synthetiques(body.n_samples)
    processed, _encodings = pretraiter(df)
    return {
        "ok": True,
        "rows": int(len(processed)),
        "columns": list(processed.columns),
        "note": "Pipeline synthétique exécuté — brancher export modèle pour prod.",
    }
