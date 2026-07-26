"""
Pipeline ML solvabilité NeoScore (production).

Entrée : features alignées sur ScoreFeatures (API).
Sortie : score 0–100 = P(remboursement OK) * 100, segment, eligible.
"""
from __future__ import annotations

import json
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

import joblib
import numpy as np
from sklearn.linear_model import LogisticRegression
from sklearn.metrics import roc_auc_score
from sklearn.model_selection import StratifiedKFold, cross_val_score
from sklearn.pipeline import Pipeline
from sklearn.preprocessing import StandardScaler

ARTIFACT_DIR = Path(__file__).resolve().parent / "artifacts"
MODEL_PATH = ARTIFACT_DIR / "neoscore_solvency.joblib"
META_PATH = ARTIFACT_DIR / "neoscore_solvency.meta.json"

FEATURE_ORDER = [
    "anciennete",
    "caJour",
    "partCredit",
    "impayes",
    "tontine",
    "tontineAns",
    "mobileMoney",
    "telephone",
    "compte",
    "creditHist",
    "opsLast30Days",
    "salesLast30Fcfa",
    "openDebtsFcfa",
    "overdueDebtsCount",
]

ELIGIBILITY_THRESHOLD = 50


def features_to_vector(features: dict[str, Any]) -> np.ndarray:
    tontine = features.get("tontine", False)
    tontine_num = 1.0 if tontine in (True, 1, "1", "true", "oui") else 0.0
    sales = float(features.get("salesLast30Fcfa", 0) or 0)
    debts = float(features.get("openDebtsFcfa", 0) or 0)
    # Normalisation simple pour stabilité (échelle terrain BF)
    row = [
        float(features.get("anciennete", 3) or 3),
        float(features.get("caJour", 3) or 3),
        float(features.get("partCredit", 1) or 1),
        float(features.get("impayes", 0) or 0),
        tontine_num,
        float(features.get("tontineAns", 0) or 0),
        float(features.get("mobileMoney", 1) or 1),
        float(features.get("telephone", 2) or 2),
        float(features.get("compte", 0) or 0),
        float(features.get("creditHist", 0) or 0),
        float(features.get("opsLast30Days", 0) or 0),
        min(sales / 50_000.0, 10.0),
        min(debts / 20_000.0, 10.0),
        float(features.get("overdueDebtsCount", 0) or 0),
    ]
    return np.asarray(row, dtype=np.float64)


def synthetic_training_rows(n: int = 400) -> tuple[np.ndarray, np.ndarray]:
    """Bootstrap : label défaut corrélé aux impayés / dettes / faible volume."""
    rng = np.random.default_rng(42)
    X_list: list[np.ndarray] = []
    y_list: list[int] = []
    for _ in range(n):
        feats = {
            "anciennete": int(rng.integers(1, 6)),
            "caJour": int(rng.integers(1, 7)),
            "partCredit": int(rng.integers(1, 5)),
            "impayes": int(rng.integers(0, 5)),
            "tontine": bool(rng.random() > 0.35),
            "tontineAns": int(rng.integers(0, 8)),
            "mobileMoney": int(rng.integers(0, 4)),
            "telephone": int(rng.integers(0, 3)),
            "compte": int(rng.integers(0, 3)),
            "creditHist": int(rng.integers(0, 3)),
            "opsLast30Days": int(rng.integers(0, 40)),
            "salesLast30Fcfa": int(rng.integers(0, 400_000)),
            "openDebtsFcfa": int(rng.integers(0, 150_000)),
            "overdueDebtsCount": int(rng.integers(0, 6)),
        }
        risk = (
            feats["impayes"] * 0.35
            + feats["overdueDebtsCount"] * 0.25
            + min(feats["openDebtsFcfa"] / 50_000, 3) * 0.2
            - feats["caJour"] * 0.15
            - (1 if feats["tontine"] else 0) * 0.4
            - feats["opsLast30Days"] * 0.02
            + rng.normal(0, 0.35)
        )
        default = 1 if risk > 0.55 else 0
        X_list.append(features_to_vector(feats))
        y_list.append(default)
    return np.vstack(X_list), np.asarray(y_list, dtype=np.int64)


def assign_segment(score: int, features: dict[str, Any]) -> str:
    ops = int(features.get("opsLast30Days", 0) or 0)
    anciennete = int(features.get("anciennete", 3) or 3)
    impayes = int(features.get("impayes", 0) or 0)
    if score < 40 and ops < 5:
        return "D"
    if score < 55 and anciennete <= 2:
        return "C"
    if score >= 65 and impayes <= 1:
        return "A"
    return "B"


def heuristic_criteria(features: dict[str, Any]) -> dict[str, float]:
    """Critères explicables (mêmes idées que @neoforma/neoscore) pour l'UI."""
    ops = float(features.get("opsLast30Days", 0) or 0)
    tontine = 1.0 if features.get("tontine") else 0.0
    mm = float(features.get("mobileMoney", 0) or 0)
    anciennete = float(features.get("anciennete", 3) or 3)
    ca = float(features.get("caJour", 3) or 3)
    sales = float(features.get("salesLast30Fcfa", 0) or 0)
    tel = float(features.get("telephone", 2) or 2)
    part = float(features.get("partCredit", 1) or 1)
    impayes = float(features.get("impayes", 0) or 0)
    debts = float(features.get("openDebtsFcfa", 0) or 0)
    overdue = float(features.get("overdueDebtsCount", 0) or 0)
    compte = float(features.get("compte", 0) or 0)
    tontine_ans = float(features.get("tontineAns", 0) or 0)
    credit_hist = float(features.get("creditHist", 0) or 0)

    def clamp(n: float) -> float:
        return max(0.0, min(100.0, n))

    regularite = clamp(ops * 4 + tontine * 15 + mm * 8 + anciennete * 6)
    volume = clamp(ca * 12 + min(40.0, sales / 5000.0) + tel * 5 + part * 3)
    dettes = clamp(100 - impayes * 18 - min(35.0, debts / 2000.0) - overdue * 12 + compte * 5)
    croissance = clamp(ops * 3 + anciennete * 8 + tontine * tontine_ans * 3 + credit_hist * 10)
    return {
        "regularite": round(regularite, 1),
        "volume": round(volume, 1),
        "dettes": round(dettes, 1),
        "croissance": round(croissance, 1),
    }


class SolvencyModel:
    def __init__(self) -> None:
        self.pipeline: Pipeline | None = None
        self.meta: dict[str, Any] = {}

    @property
    def ready(self) -> bool:
        return self.pipeline is not None

    def load(self) -> bool:
        if not MODEL_PATH.exists():
            return False
        payload = joblib.load(MODEL_PATH)
        self.pipeline = payload["pipeline"]
        self.meta = payload.get("meta", {})
        if META_PATH.exists():
            self.meta = {**self.meta, **json.loads(META_PATH.read_text(encoding="utf-8"))}
        return True

    def save(self, meta: dict[str, Any]) -> None:
        ARTIFACT_DIR.mkdir(parents=True, exist_ok=True)
        assert self.pipeline is not None
        joblib.dump({"pipeline": self.pipeline, "meta": meta}, MODEL_PATH)
        META_PATH.write_text(json.dumps(meta, indent=2), encoding="utf-8")
        self.meta = meta

    def train(
        self,
        samples: list[dict[str, Any]] | None = None,
        n_synthetic: int = 300,
    ) -> dict[str, Any]:
        Xs: list[np.ndarray] = []
        ys: list[int] = []
        source = "synthetic"

        if samples:
            for s in samples:
                feats = s.get("features") or s
                label = s.get("default")
                if label is None:
                    outcome = str(s.get("outcome", "")).lower()
                    if outcome == "defaut":
                        label = 1
                    elif outcome == "rembourse_ok":
                        label = 0
                    else:
                        continue
                Xs.append(features_to_vector(feats))
                ys.append(int(label))
            if Xs:
                source = "labeled" if n_synthetic <= 0 else "mixed"

        if n_synthetic > 0:
            X_syn, y_syn = synthetic_training_rows(n_synthetic)
            Xs.extend(list(X_syn))
            ys.extend(list(y_syn))
            if source == "labeled":
                source = "mixed"

        if len(Xs) < 20:
            raise ValueError("Au moins 20 échantillons requis pour entraîner")

        X = np.vstack(Xs)
        y = np.asarray(ys, dtype=np.int64)
        if len(np.unique(y)) < 2:
            # Forcer diversité minimale
            X_syn, y_syn = synthetic_training_rows(80)
            X = np.vstack([X, X_syn])
            y = np.concatenate([y, y_syn])
            source = "mixed"

        pipe = Pipeline(
            [
                ("scaler", StandardScaler()),
                (
                    "clf",
                    LogisticRegression(
                        max_iter=2000,
                        class_weight="balanced",
                        random_state=42,
                        C=1.0,
                    ),
                ),
            ]
        )

        auc: float | None = None
        try:
            cv = StratifiedKFold(n_splits=min(5, int(y.sum()) or 2), shuffle=True, random_state=42)
            if len(np.unique(y)) > 1 and min(np.bincount(y)) >= 2:
                scores = cross_val_score(pipe, X, y, cv=cv, scoring="roc_auc")
                auc = float(scores.mean())
        except Exception:
            auc = None

        pipe.fit(X, y)
        self.pipeline = pipe

        # AUC hold-out simple si CV a échoué
        if auc is None:
            try:
                proba = pipe.predict_proba(X)[:, 1]
                auc = float(roc_auc_score(y, proba))
            except Exception:
                auc = None

        version = datetime.now(timezone.utc).strftime("%Y%m%d-%H%M%S")
        meta = {
            "version": version,
            "trainedAt": datetime.now(timezone.utc).isoformat(),
            "nSamples": int(len(y)),
            "nDefaults": int(y.sum()),
            "auc": auc,
            "source": source,
            "featureOrder": FEATURE_ORDER,
            "threshold": ELIGIBILITY_THRESHOLD,
        }
        self.save(meta)
        return meta

    def score(self, features: dict[str, Any]) -> dict[str, Any]:
        if self.pipeline is None and not self.load():
            # Auto-bootstrap léger (Render free / cold start)
            self.train(samples=None, n_synthetic=120)

        assert self.pipeline is not None
        vec = features_to_vector(features).reshape(1, -1)
        # classe 1 = défaut → P(OK) = 1 - P(défaut)
        p_default = float(self.pipeline.predict_proba(vec)[0, 1])
        p_ok = 1.0 - p_default
        score = int(round(max(0.0, min(100.0, p_ok * 100.0))))
        eligible = score >= ELIGIBILITY_THRESHOLD
        segment = assign_segment(score, features)
        return {
            "score": score,
            "segment": segment,
            "eligible": eligible,
            "threshold": ELIGIBILITY_THRESHOLD,
            "criteria": heuristic_criteria(features),
            "engine": "ml",
            "modelVersion": self.meta.get("version"),
            "pDefault": round(p_default, 4),
            "computedAt": datetime.now(timezone.utc).isoformat().replace("+00:00", "Z"),
        }


# Singleton process
model = SolvencyModel()
model.load()
