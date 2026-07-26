import { FormEvent, useState } from "react";
import { useNavigate } from "react-router-dom";
import { api, ApiClientError, isOfflineError } from "@/shared/lib/api";
import { offlineQueue } from "@/shared/lib/offlineQueue";

type OpType = "vente" | "stock" | "creance" | "depense";

const labels: Record<OpType, string> = {
  vente: "Vente",
  stock: "Stock",
  creance: "Créance",
  depense: "Dépense",
};

export function RecordPage() {
  const nav = useNavigate();
  const [type, setType] = useState<OpType>("vente");
  const [amount, setAmount] = useState("2500");
  const [clientName, setClientName] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [loading, setLoading] = useState(false);
  const [done, setDone] = useState(false);
  const [savedOffline, setSavedOffline] = useState(false);

  async function submit(e: FormEvent) {
    e.preventDefault();
    setLoading(true);
    setError(null);
    const payload = {
      type,
      amountFcfa: Number(amount.replace(/\s/g, "")),
      label:
        type === "vente"
          ? "Vente"
          : type === "stock"
            ? "Stock"
            : type === "depense"
              ? "Dépense"
              : undefined,
      natureStock: type === "stock" ? ("entree" as const) : undefined,
      clientName: type === "creance" ? clientName.trim() || "Client" : undefined,
      dueAt:
        type === "creance"
          ? new Date(Date.now() + 7 * 24 * 3600 * 1000).toISOString()
          : undefined,
      clientMutationId: crypto.randomUUID(),
      createdAt: new Date().toISOString(),
    };

    try {
      await api.post("/operations", payload);
      setSavedOffline(false);
      setDone(true);
    } catch (err) {
      const offline =
        !navigator.onLine ||
        isOfflineError(err) ||
        (err instanceof ApiClientError && err.status >= 500);
      if (offline) {
        offlineQueue.enqueue({
          clientMutationId: payload.clientMutationId!,
          kind: "create_operation",
          payload,
          createdAt: payload.createdAt!,
        });
        setSavedOffline(true);
        setDone(true);
      } else {
        setError(
          err instanceof ApiClientError
            ? err.message
            : "Enregistrement impossible"
        );
      }
    } finally {
      setLoading(false);
    }
  }

  if (done) {
    return (
      <div className="page">
        <div className="score-ring">✓</div>
        <h1 className="h1" style={{ textAlign: "center" }}>
          Enregistré
        </h1>
        <p className="muted" style={{ textAlign: "center" }}>
          {savedOffline
            ? "Sauvé hors ligne — sync au retour réseau"
            : "Synchronisé"}
        </p>
        <button className="btn btn-primary" onClick={() => nav("/app")}>
          Accueil
        </button>
        <button
          className="btn btn-ghost"
          onClick={() => {
            setDone(false);
            setAmount("");
            setError(null);
          }}
        >
          Nouvelle
        </button>
      </div>
    );
  }

  return (
    <div className="page">
      <h1 className="h1">Enregistrer</h1>
      <div className="seg" style={{ marginTop: 16 }}>
        {(["vente", "stock", "creance", "depense"] as const).map((t) => (
          <button
            key={t}
            type="button"
            className={type === t ? "on" : ""}
            onClick={() => setType(t)}
          >
            {labels[t]}
          </button>
        ))}
      </div>
      <form onSubmit={submit}>
        {type === "creance" && (
          <>
            <label className="lbl" style={{ display: "block", marginTop: 16 }}>
              Client
            </label>
            <input
              className="input"
              value={clientName}
              onChange={(e) => setClientName(e.target.value)}
              placeholder="Koné Ibrahim"
            />
          </>
        )}
        <label className="lbl" style={{ display: "block", marginTop: 16 }}>
          Montant (FCFA)
        </label>
        <input
          className="input"
          inputMode="numeric"
          value={amount}
          onChange={(e) => setAmount(e.target.value)}
        />
        {error && <p className="error">{error}</p>}
        <button
          className="btn btn-primary"
          disabled={loading || !Number(amount.replace(/\s/g, ""))}
        >
          {loading ? "…" : `Confirmer · ${labels[type]}`}
        </button>
        <button type="button" className="btn btn-ghost" onClick={() => nav(-1)}>
          Annuler
        </button>
      </form>
    </div>
  );
}
