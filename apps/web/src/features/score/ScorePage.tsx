import { useEffect, useState } from "react";
import { Link } from "react-router-dom";
import { api } from "@/shared/lib/api";
import type { NeoScoreResult } from "@neoforma/shared";

export function ScorePage() {
  const [score, setScore] = useState<NeoScoreResult | null>(null);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    api
      .get<NeoScoreResult>("/score")
      .then(setScore)
      .catch(() => setScore(null))
      .finally(() => setLoading(false));
  }, []);

  if (loading) {
    return (
      <div className="page">
        <h1 className="h1">NeoScore</h1>
        <p className="muted">Chargement…</p>
      </div>
    );
  }

  if (!score) {
    return (
      <div className="page">
        <h1 className="h1">NeoScore</h1>
        <p className="muted">Score indisponible pour le moment.</p>
        <Link to="/app" className="btn btn-outline">
          Retour
        </Link>
      </div>
    );
  }

  return (
    <div className="page">
      <h1 className="h1">NeoScore</h1>
      <div className="card" style={{ textAlign: "center" }}>
        <div className="score-ring">{score.score}</div>
        <div className="muted">Score · sur 100 · seuil {score.threshold}</div>
        <div className="toast" style={{ display: "inline-block" }}>
          {score.eligible ? "✓ Profil éligible" : "Pas encore éligible"} · Segment{" "}
          {score.segment}
        </div>
      </div>
      <div className="card">
        <div className="lbl">Détail</div>
        {(
          [
            ["Régularité", score.criteria.regularite],
            ["Volume", score.criteria.volume],
            ["Dettes", score.criteria.dettes],
            ["Croissance", score.criteria.croissance],
          ] as const
        ).map(([label, pct]) => (
          <div key={label} style={{ marginBottom: 10 }}>
            <div
              style={{
                display: "flex",
                justifyContent: "space-between",
                fontSize: 13,
              }}
            >
              <span>{label}</span>
              <span className="muted">{Math.round(pct)}%</span>
            </div>
            <div
              style={{
                height: 6,
                background: "var(--card2)",
                borderRadius: 3,
                marginTop: 4,
              }}
            >
              <div
                style={{
                  width: `${Math.min(100, pct)}%`,
                  height: "100%",
                  background: "var(--green)",
                  borderRadius: 3,
                }}
              />
            </div>
          </div>
        ))}
      </div>
      {score.history.length > 0 && (
        <div className="card">
          <div className="lbl">Historique</div>
          {score.history.map((h) => (
            <div
              key={`${h.month}-${h.score}`}
              style={{
                display: "flex",
                justifyContent: "space-between",
                padding: "8px 0",
                borderBottom: "1px solid var(--border)",
                fontSize: 14,
              }}
            >
              <span className="muted">{h.month}</span>
              <strong>{h.score}</strong>
            </div>
          ))}
        </div>
      )}
      {score.eligible ? (
        <Link to="/app/credit" className="btn btn-primary">
          Demander un crédit
        </Link>
      ) : (
        <div className="toast">
          Continue d’enregistrer des ventes pour dépasser 50.
        </div>
      )}
      <Link to="/app" className="btn btn-outline">
        Retour
      </Link>
    </div>
  );
}
