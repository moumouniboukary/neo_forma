"""
NeoForma NeoScore ML — service solvabilité (entraînement + inférence).

Endpoints :
  GET  /health
  GET  /model
  POST /score          { features: ScoreFeatures }
  POST /train          { samples?: [...], nSynthetic?: int }
  POST /train/synthetic  (legacy bootstrap)
"""
from __future__ import annotations

import sys
from pathlib import Path
from typing import Any

from fastapi import FastAPI, HTTPException
from pydantic import BaseModel, Field

from pipeline import ELIGIBILITY_THRESHOLD, model

ROOT = Path(__file__).resolve().parents[2]
MODEL_DIR = ROOT / "DAMINA&POESAM_2026"
if MODEL_DIR.exists():
    sys.path.insert(0, str(MODEL_DIR))

app = FastAPI(
    title="NeoForma NeoScore ML",
    version="0.2.0",
    description="Solvabilité : P(remboursement OK) → score 0–100",
)


class FeaturesBody(BaseModel):
    anciennete: float = 3
    caJour: float = 3
    partCredit: float = 1
    impayes: float = 0
    tontine: bool = False
    tontineAns: int = 0
    mobileMoney: float = 1
    telephone: float = 2
    compte: float = 0
    creditHist: float = 0
    opsLast30Days: int = 0
    salesLast30Fcfa: int = 0
    openDebtsFcfa: int = 0
    overdueDebtsCount: int = 0


class ScoreRequest(BaseModel):
    features: FeaturesBody


class TrainSample(BaseModel):
    features: FeaturesBody
    outcome: str | None = Field(
        default=None, description="rembourse_ok | defaut"
    )
    default: int | None = Field(default=None, description="1=défaut, 0=OK")


class TrainRequest(BaseModel):
    samples: list[TrainSample] = Field(default_factory=list)
    nSynthetic: int = Field(default=300, ge=0, le=5000)


class LegacyTrainRequest(BaseModel):
    n_samples: int = Field(default=120, ge=20, le=5000)


@app.on_event("startup")
def bootstrap_model() -> None:
    """Ne bloque pas le démarrage : le 1er /score entraîne si besoin.
    Sinon Render rate le health check (entraînement 400 samples trop long).
    """
    model.load()


@app.get("/health")
def health():
    return {
        "status": "ok",
        "service": "neoscore-ml",
        "modelReady": model.ready,
        "modelVersion": model.meta.get("version"),
        "threshold": ELIGIBILITY_THRESHOLD,
    }


@app.get("/model")
def model_info():
    return {
        "ready": model.ready,
        "meta": model.meta,
    }


@app.post("/score")
def score(body: ScoreRequest):
    try:
        result = model.score(body.features.model_dump())
        return result
    except Exception as exc:  # noqa: BLE001
        raise HTTPException(status_code=500, detail=str(exc)) from exc


@app.post("/train")
def train(body: TrainRequest):
    samples: list[dict[str, Any]] = []
    for s in body.samples:
        samples.append(
            {
                "features": s.features.model_dump(),
                "outcome": s.outcome,
                "default": s.default,
            }
        )
    try:
        meta = model.train(samples=samples or None, n_synthetic=body.nSynthetic)
        return {"ok": True, **meta}
    except ValueError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc
    except Exception as exc:  # noqa: BLE001
        raise HTTPException(status_code=500, detail=str(exc)) from exc


@app.post("/train/synthetic")
def train_synthetic(body: LegacyTrainRequest):
    """Legacy + bootstrap DAMINA script si présent."""
    meta = model.train(samples=None, n_synthetic=body.n_samples)
    note = "Modèle solvabilité entraîné (synthétique)."
    try:
        from NeoForma_NeoScore_Model import generer_donnees_synthetiques, pretraiter

        df = generer_donnees_synthetiques(min(body.n_samples, 200))
        processed, _ = pretraiter(df)
        note += f" Pipeline historique OK ({len(processed)} lignes)."
    except ImportError:
        note += " Script DAMINA absent (non bloquant)."
    return {"ok": True, "note": note, **meta}
