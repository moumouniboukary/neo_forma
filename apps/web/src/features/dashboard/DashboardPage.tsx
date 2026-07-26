import { useEffect, useState } from "react";
import { Link, useNavigate } from "react-router-dom";
import { api } from "@/shared/lib/api";
import { useAuth } from "@/features/auth/AuthContext";
import { useSync } from "@/features/sync/useSync";

type Dashboard = {
  monthSalesFcfa: number;
  openDebtsFcfa: number;
  overdueDebtsCount: number;
  last7DaysSales: Array<{ day: string; totalFcfa: number }>;
  recentOperations: Array<{
    id: string;
    type: string;
    amountFcfa: number;
    label?: string;
    clientName?: string;
    createdAt: string;
    dateOperation?: string;
  }>;
};

function isOutflow(type: string) {
  return type === "creance" || type === "dette" || type === "depense";
}

export function DashboardPage() {
  const { user } = useAuth();
  const nav = useNavigate();
  const { pending, flush, lastError } = useSync();
  const [data, setData] = useState<Dashboard | null>(null);

  useEffect(() => {
    void flush();
    api.get<Dashboard>("/dashboard").then(setData).catch(() => setData(null));
  }, [flush]);

  const maxBar = Math.max(1, ...(data?.last7DaysSales.map((d) => d.totalFcfa) ?? [1]));
  const firstName = (user?.displayName || "Entrepreneur").split(" ")[0];

  return (
    <div className="page">
      <header className="dash-header">
        <div>
          <p className="dash-hello">Bonjour</p>
          <h1 className="dash-name">{firstName}</h1>
        </div>
        <Link to="/app/score" className="dash-score-chip">
          NeoScore
        </Link>
      </header>

      {pending > 0 && (
        <div className="toast" style={{ marginTop: 0, marginBottom: 16 }}>
          {pending} opération(s) en attente de synchronisation
        </div>
      )}
      {lastError && (
        <div
          className="toast"
          style={{
            marginTop: 0,
            marginBottom: 16,
            borderColor: "var(--coral)",
            color: "var(--coral)",
          }}
        >
          Sync · {lastError}
        </div>
      )}

      <section className="dash-hero-metric" aria-label="Ventes du mois">
        <div className="lbl">Ventes ce mois</div>
        <div className="dash-hero-value">
          {(data?.monthSalesFcfa ?? 0).toLocaleString("fr-FR")}
          <span>FCFA</span>
        </div>
      </section>

      <section className="dash-secondary" aria-label="Créances">
        <article>
          <div className="lbl">À récupérer</div>
          <div className="stat-val" style={{ color: "var(--warn)" }}>
            {(data?.openDebtsFcfa ?? 0).toLocaleString("fr-FR")}
          </div>
        </article>
        <article>
          <div className="lbl">En retard</div>
          <div className="stat-val">
            {data?.overdueDebtsCount ?? 0}
          </div>
        </article>
      </section>

      <section className="dash-chart" aria-label="Ventes sur 7 jours">
        <div className="lbl">7 derniers jours</div>
        <div className="dash-bars">
          {(data?.last7DaysSales ?? []).map((d, i) => (
            <div key={`${d.day}-${i}`}>
              <i
                style={{
                  height: `${Math.max(6, (d.totalFcfa / maxBar) * 72)}px`,
                  opacity: d.totalFcfa ? 1 : 0.28,
                }}
              />
              <small>{d.day}</small>
            </div>
          ))}
        </div>
      </section>

      <section className="dash-feed" aria-label="Dernières opérations">
        <div className="lbl" style={{ marginBottom: 4 }}>
          Dernières opérations
        </div>
        {(data?.recentOperations ?? []).slice(0, 5).map((op) => {
          const out = isOutflow(op.type);
          const when = op.dateOperation || op.createdAt;
          return (
            <div key={op.id} className="dash-feed-item">
              <div>
                <div>{op.label || op.clientName || op.type}</div>
                <div className="muted" style={{ fontSize: 12 }}>
                  {new Date(when).toLocaleString("fr-FR", {
                    day: "2-digit",
                    month: "short",
                    hour: "2-digit",
                    minute: "2-digit",
                  })}
                </div>
              </div>
              <div className={`dash-feed-amount ${out ? "out" : "in"}`}>
                {out ? "−" : "+"}
                {op.amountFcfa.toLocaleString("fr-FR")}
              </div>
            </div>
          );
        })}
        {!data?.recentOperations?.length && (
          <p className="muted" style={{ marginTop: 12 }}>
            Aucune opération pour l’instant. Enregistrez votre première vente.
          </p>
        )}
      </section>

      <button
        className="fab"
        type="button"
        aria-label="Nouvelle opération"
        onClick={() => nav("/app/enregistrer")}
      >
        +
      </button>
    </div>
  );
}
