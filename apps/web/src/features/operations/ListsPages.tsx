import { useEffect, useState } from "react";
import { api } from "@/shared/lib/api";

type Op = {
  id: string;
  type: string;
  amountFcfa: number;
  label?: string;
  clientName?: string;
  dueAt?: string;
  statutCreance?: string;
  createdAt: string;
  dateOperation?: string;
};

export function VentesPage() {
  const [ops, setOps] = useState<Op[]>([]);
  useEffect(() => {
    api
      .get<Op[]>("/operations?type=vente")
      .then(setOps)
      .catch(() => setOps([]));
  }, []);
  const total = ops.reduce((s, o) => s + o.amountFcfa, 0);

  return (
    <div className="page">
      <h1 className="h1">Cahier · ventes</h1>
      <section className="dash-hero-metric">
        <div className="lbl">Total listé</div>
        <div className="dash-hero-value" style={{ fontSize: "1.8rem" }}>
          {total.toLocaleString("fr-FR")}
          <span>FCFA</span>
        </div>
      </section>
      {!ops.length && <p className="muted">Aucune vente pour l’instant.</p>}
      {ops.map((op) => (
        <div key={op.id} className="dash-feed-item">
          <div>
            <div>{op.label || "Vente"}</div>
            <div className="muted" style={{ fontSize: 12 }}>
              {new Date(op.dateOperation || op.createdAt).toLocaleString("fr-FR")}
            </div>
          </div>
          <div className="dash-feed-amount in">
            +{op.amountFcfa.toLocaleString("fr-FR")}
          </div>
        </div>
      ))}
    </div>
  );
}

export function DettesPage() {
  const [ops, setOps] = useState<Op[]>([]);
  const [busyId, setBusyId] = useState<string | null>(null);

  async function load() {
    const list = await api
      .get<Op[]>("/operations?type=creance")
      .catch(() => [] as Op[]);
    setOps(
      list.filter(
        (o) =>
          o.statutCreance === "ouverte" ||
          o.statutCreance === "en_retard" ||
          !o.statutCreance
      )
    );
  }

  useEffect(() => {
    void load();
  }, []);

  const total = ops.reduce((s, o) => s + o.amountFcfa, 0);

  async function settle(id: string) {
    setBusyId(id);
    try {
      await api.post(`/operations/${id}/settle`);
      await load();
    } finally {
      setBusyId(null);
    }
  }

  return (
    <div className="page">
      <h1 className="h1">Créances</h1>
      <section className="dash-secondary">
        <article>
          <div className="lbl">À récupérer</div>
          <div className="stat-val" style={{ color: "var(--warn)" }}>
            {total.toLocaleString("fr-FR")}
          </div>
        </article>
        <article>
          <div className="lbl">Ouvertes</div>
          <div className="stat-val">{ops.length}</div>
        </article>
      </section>
      {!ops.length && <p className="muted">Aucune créance ouverte.</p>}
      {ops.map((op) => (
        <div key={op.id} className="dash-feed-item" style={{ alignItems: "center" }}>
          <div>
            <div>{op.clientName || "Client"}</div>
            <div className="muted" style={{ fontSize: 12 }}>
              {op.dueAt
                ? `Échéance ${new Date(op.dueAt).toLocaleDateString("fr-FR")}`
                : "Sans échéance"}
              {op.statutCreance === "en_retard" ? " · en retard" : ""}
            </div>
          </div>
          <div style={{ textAlign: "right" }}>
            <div className="dash-feed-amount out">
              {op.amountFcfa.toLocaleString("fr-FR")}
            </div>
            <button
              type="button"
              className="btn btn-ghost"
              style={{ marginTop: 6, padding: "6px 10px", width: "auto", fontSize: 12 }}
              disabled={busyId === op.id}
              onClick={() => void settle(op.id)}
            >
              {busyId === op.id ? "…" : "Régler"}
            </button>
          </div>
        </div>
      ))}
    </div>
  );
}
