import { FormEvent, useEffect, useState } from "react";
import { Link, useNavigate } from "react-router-dom";
import { api, ApiClientError } from "@/shared/lib/api";
import { useAuth } from "@/features/auth/AuthContext";
import { offlineQueue } from "@/shared/lib/offlineQueue";

type ConsentsList = {
  items: Array<{ type: string; accorde: boolean }>;
  policyVersion: string;
};

export function ProfilePage() {
  const { user, logout, refreshMe, setUser } = useAuth();
  const nav = useNavigate();
  const [displayName, setDisplayName] = useState(user?.displayName ?? "");
  const [shareImf, setShareImf] = useState(false);
  const [saving, setSaving] = useState(false);
  const [message, setMessage] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    setDisplayName(user?.displayName ?? "");
  }, [user?.displayName]);

  useEffect(() => {
    api
      .get<ConsentsList>("/me/consents")
      .then((res) => {
        const imf = res.items.find((i) => i.type === "partage_imf");
        setShareImf(Boolean(imf?.accorde));
      })
      .catch(() => undefined);
  }, []);

  async function saveProfile(e: FormEvent) {
    e.preventDefault();
    setSaving(true);
    setError(null);
    setMessage(null);
    try {
      const me = await api.patch<{
        id: string;
        phone: string;
        displayName: string;
        onboardingCompleted: boolean;
      }>("/me", { displayName: displayName.trim() });
      setUser({
        id: me.id,
        phone: me.phone,
        displayName: me.displayName,
        onboardingCompleted: me.onboardingCompleted,
      });
      await api.put("/me/consents", {
        consentCreditPartners: shareImf,
      });
      await refreshMe().catch(() => undefined);
      setMessage("Profil enregistré");
    } catch (err) {
      setError(err instanceof ApiClientError ? err.message : "Échec");
    } finally {
      setSaving(false);
    }
  }

  return (
    <div className="page">
      <h1 className="h1">Profil</h1>
      <div className="card" style={{ textAlign: "center" }}>
        <div
          style={{
            width: 64,
            height: 64,
            borderRadius: "50%",
            background: "var(--green)",
            display: "grid",
            placeItems: "center",
            margin: "0 auto 12px",
            fontWeight: 700,
          }}
        >
          {(user?.displayName || "N").slice(0, 2).toUpperCase()}
        </div>
        <div className="muted">{user?.phone}</div>
      </div>

      <form onSubmit={saveProfile} className="card">
        <label className="lbl">Nom affiché</label>
        <input
          className="input"
          value={displayName}
          onChange={(e) => setDisplayName(e.target.value)}
        />
        <label className="lbl" style={{ display: "block", marginTop: 16 }}>
          Partage IMF
        </label>
        <div className="seg">
          <button
            type="button"
            className={shareImf ? "on" : ""}
            onClick={() => setShareImf(true)}
          >
            Autoriser
          </button>
          <button
            type="button"
            className={!shareImf ? "on" : ""}
            onClick={() => setShareImf(false)}
          >
            Refuser
          </button>
        </div>
        {message && <p className="muted">{message}</p>}
        {error && <p className="error">{error}</p>}
        <button className="btn btn-primary" disabled={saving}>
          {saving ? "…" : "Enregistrer"}
        </button>
      </form>

      <div className="card">
        <Link to="/app/score" style={{ display: "block", padding: "10px 0" }}>
          NeoScore ›
        </Link>
        <Link
          to="/app/credit"
          style={{
            display: "block",
            padding: "10px 0",
            borderTop: "1px solid var(--border)",
          }}
        >
          Crédit ›
        </Link>
        <div
          style={{ padding: "10px 0", borderTop: "1px solid var(--border)" }}
          className="muted"
        >
          File offline · {offlineQueue.count()}
        </div>
      </div>

      <button
        className="btn btn-outline"
        style={{ color: "var(--coral)", borderColor: "rgba(216,90,48,.5)" }}
        onClick={() => {
          void logout().finally(() => nav("/login"));
        }}
      >
        Se déconnecter
      </button>
    </div>
  );
}
