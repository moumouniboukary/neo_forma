import { useEffect, useState } from "react";
import { api, ApiClientError, isOfflineError } from "@/shared/lib/api";
import { localCache, LocalCacheKeys } from "@/shared/lib/localCache";
import { offlineQueue } from "@/shared/lib/offlineQueue";

type Op = {
  id: string;
  type: string;
  amountFcfa: number;
  label?: string;
  clientName?: string;
  categorieDepense?: string;
  quantity?: number;
  articleStockId?: string;
  dueAt?: string;
  statutCreance?: string;
  createdAt: string;
  dateOperation?: string;
  pendingSync?: boolean;
};

function openCreances(list: Op[]) {
  return list.filter(
    (o) =>
      o.type === "creance" &&
      (o.statutCreance === "ouverte" ||
        o.statutCreance === "en_retard" ||
        !o.statutCreance)
  );
}

type LedgerTab = "vente" | "depense";

export function VentesPage({ initialTab = "vente" }: { initialTab?: LedgerTab }) {
  const [tab, setTab] = useState<LedgerTab>(initialTab);
  const [ops, setOps] = useState<Op[]>([]);
  const [fromCache, setFromCache] = useState(false);
  const [noLocal, setNoLocal] = useState(false);
  const [busyId, setBusyId] = useState<string | null>(null);
  const [hint, setHint] = useState<string | null>(null);

  async function load(nextTab: LedgerTab = tab) {
    try {
      const list = await api.get<Op[]>(`/operations?type=${nextTab}`);
      setOps(list);
      setFromCache(false);
      setNoLocal(false);
      const all = localCache.getList(LocalCacheKeys.operations);
      const others = all.filter((o) => o.type !== nextTab);
      localCache.setList(LocalCacheKeys.operations, [
        ...others,
        ...(list as unknown as Record<string, unknown>[]),
      ]);
    } catch {
      const cached = localCache
        .getList(LocalCacheKeys.operations)
        .filter((o) => o.type === nextTab) as unknown as Op[];
      setOps(cached);
      setFromCache(cached.length > 0 || localCache.has(LocalCacheKeys.operations));
      setNoLocal(!localCache.has(LocalCacheKeys.operations));
    }
  }

  useEffect(() => {
    void load(tab);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [tab]);

  const total = ops.reduce((s, o) => s + o.amountFcfa, 0);
  const isExpense = tab === "depense";

  async function removeOp(op: Op) {
    if (!window.confirm("Supprimer cette opération ?")) return;
    setBusyId(op.id);
    setHint(null);

    const removeLocal = () => {
      const all = localCache.getList(LocalCacheKeys.operations);
      localCache.setList(
        LocalCacheKeys.operations,
        all.filter((o) => o.id !== op.id)
      );
      setOps((prev) => prev.filter((o) => o.id !== op.id));
    };

    if (op.pendingSync) {
      removeLocal();
      setBusyId(null);
      return;
    }

    try {
      await api.delete(`/operations/${op.id}`);
      removeLocal();
    } catch (err) {
      const offline =
        !navigator.onLine ||
        isOfflineError(err) ||
        (err instanceof ApiClientError && err.status >= 500);
      if (offline) {
        offlineQueue.enqueue({
          clientMutationId: crypto.randomUUID(),
          kind: "delete_operation",
          payload: { operationId: op.id },
          createdAt: new Date().toISOString(),
        });
        removeLocal();
        setHint("Suppression enregistrée hors ligne — sync au retour réseau");
      } else {
        setHint(
          err instanceof ApiClientError
            ? err.message
            : "Suppression impossible"
        );
      }
    } finally {
      setBusyId(null);
    }
  }

  return (
    <div className="page">
      <h1 className="h1">Cahier</h1>
      <div className="seg" style={{ marginTop: 12, marginBottom: 12 }}>
        <button
          type="button"
          className={!isExpense ? "on" : ""}
          onClick={() => setTab("vente")}
        >
          Ventes
        </button>
        <button
          type="button"
          className={isExpense ? "on" : ""}
          onClick={() => setTab("depense")}
        >
          Dépenses
        </button>
      </div>
      {fromCache && (
        <p className="muted" style={{ marginBottom: 8 }}>
          Hors ligne — données locales
        </p>
      )}
      {hint && <p className="muted">{hint}</p>}
      <section className="dash-hero-metric">
        <div className="lbl">Total listé</div>
        <div
          className="dash-hero-value"
          style={{
            fontSize: "1.8rem",
            color: isExpense ? "var(--warn)" : undefined,
          }}
        >
          {total.toLocaleString("fr-FR")}
          <span>FCFA</span>
        </div>
      </section>
      {!ops.length && (
        <p className="muted">
          {noLocal
            ? "Hors ligne — aucune donnée locale. Vous pouvez déjà enregistrer."
            : isExpense
              ? "Aucune dépense pour l’instant."
              : "Aucune vente pour l’instant."}
        </p>
      )}
      {!ops.length && (
        <a className="btn btn-primary" href="/app/enregistrer" style={{ marginTop: 12 }}>
          {isExpense ? "Enregistrer une dépense" : "Enregistrer une vente"}
        </a>
      )}
      {ops.map((op) => (
        <div key={op.id} className="dash-feed-item" style={{ alignItems: "center" }}>
          <div>
            <div>{op.label || (isExpense ? "Dépense" : "Vente")}</div>
            <div className="muted" style={{ fontSize: 12 }}>
              {op.categorieDepense ? `${op.categorieDepense} · ` : ""}
              {new Date(op.dateOperation || op.createdAt).toLocaleString("fr-FR")}
            </div>
          </div>
          <div style={{ textAlign: "right" }}>
            <div className={`dash-feed-amount ${isExpense ? "out" : "in"}`}>
              {isExpense ? "-" : "+"}
              {op.amountFcfa.toLocaleString("fr-FR")}
            </div>
            <button
              type="button"
              className="btn btn-ghost"
              style={{
                marginTop: 6,
                padding: "6px 10px",
                width: "auto",
                fontSize: 12,
              }}
              disabled={busyId === op.id}
              onClick={() => void removeOp(op)}
            >
              {busyId === op.id ? "…" : "Supprimer"}
            </button>
          </div>
        </div>
      ))}
    </div>
  );
}

export function DepensesPage() {
  return <VentesPage initialTab="depense" />;
}

export function DettesPage() {
  const [ops, setOps] = useState<Op[]>([]);
  const [busyId, setBusyId] = useState<string | null>(null);
  const [fromCache, setFromCache] = useState(false);
  const [noLocal, setNoLocal] = useState(false);
  const [hint, setHint] = useState<string | null>(null);

  async function load() {
    try {
      const list = await api.get<Op[]>("/operations?type=creance");
      const open = openCreances(list);
      setOps(open);
      setFromCache(false);
      setNoLocal(false);
      const all = localCache.getList(LocalCacheKeys.operations);
      const others = all.filter((o) => o.type !== "creance");
      localCache.setList(LocalCacheKeys.operations, [
        ...others,
        ...(list as unknown as Record<string, unknown>[]),
      ]);
    } catch {
      const cached = openCreances(
        localCache.getList(LocalCacheKeys.operations) as unknown as Op[]
      );
      setOps(cached);
      setFromCache(
        cached.length > 0 || localCache.has(LocalCacheKeys.operations)
      );
      setNoLocal(!localCache.has(LocalCacheKeys.operations));
    }
  }

  useEffect(() => {
    void load();
  }, []);

  const total = ops.reduce((s, o) => s + o.amountFcfa, 0);

  async function settle(id: string) {
    setBusyId(id);
    setHint(null);
    const op = ops.find((o) => o.id === id);
    try {
      await api.post(`/operations/${id}/settle`);
      await load();
    } catch (err) {
      const offline =
        !navigator.onLine ||
        isOfflineError(err) ||
        (err instanceof ApiClientError && err.status >= 500);
      if (offline && op) {
        offlineQueue.enqueue({
          clientMutationId: crypto.randomUUID(),
          kind: "settle_creance",
          payload: {
            operationId: id,
            amountFcfa: op.amountFcfa,
          },
          createdAt: new Date().toISOString(),
        });
        setOps((prev) => prev.filter((o) => o.id !== id));
        setHint("Règlement enregistré hors ligne — sync au retour réseau");
      }
    } finally {
      setBusyId(null);
    }
  }

  return (
    <div className="page">
      <h1 className="h1">Créances</h1>
      {fromCache && (
        <p className="muted" style={{ marginBottom: 8 }}>
          Hors ligne — données locales
        </p>
      )}
      {hint && <p className="muted">{hint}</p>}
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
      {!ops.length && (
        <p className="muted">
          {noLocal
            ? "Hors ligne — aucune donnée locale. Vous pouvez déjà enregistrer une créance."
            : "Aucune créance ouverte."}
        </p>
      )}
      {!ops.length && (
        <a className="btn btn-primary" href="/app/enregistrer" style={{ marginTop: 12 }}>
          Enregistrer une créance
        </a>
      )}
      {ops.map((op) => (
        <div
          key={op.id}
          className="dash-feed-item"
          style={{ alignItems: "center" }}
        >
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
              style={{
                marginTop: 6,
                padding: "6px 10px",
                width: "auto",
                fontSize: 12,
              }}
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
