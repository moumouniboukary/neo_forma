import { useState } from "react";
import { useNavigate } from "react-router-dom";
import { api } from "@/shared/lib/api";
import { useAuth } from "@/features/auth/AuthContext";

const metiers = ["commerce", "artisanat", "mecanique", "restauration"] as const;

export function OnboardingPage() {
  const nav = useNavigate();
  const { setUser, user, refreshMe } = useAuth();
  const [step, setStep] = useState(0);
  const [displayName, setDisplayName] = useState("");
  const [metier, setMetier] = useState<(typeof metiers)[number]>("commerce");
  const [anciennete, setAnciennete] = useState("3_5");
  const [caJour, setCaJour] = useState("15_30k");
  const [tontine, setTontine] = useState(true);
  const [mobileMoney, setMobileMoney] = useState("regulier");
  const [shareImf, setShareImf] = useState(true);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  async function finish() {
    setLoading(true);
    setError(null);
    try {
      await api.patch("/me", {
        displayName: displayName.trim() || "Entrepreneur NeoForma",
        metier,
        anciennete,
        caJour,
        tontine,
        mobileMoney,
        city: "Ouagadougou",
        consentAnonymized: true,
        consentCreditPartners: shareImf,
        consentMarketing: false,
      });

      await api.put("/me/consents", {
        consentAnonymized: true,
        consentCreditPartners: shareImf,
        consentMarketing: false,
      });

      const updated = await api.post<{
        id: string;
        phone: string;
        displayName: string;
        onboardingCompleted: boolean;
      }>("/me/onboarding/complete");

      setUser({
        id: updated.id,
        phone: user?.phone ?? updated.phone,
        displayName: updated.displayName,
        onboardingCompleted: true,
      });
      await refreshMe().catch(() => undefined);
      nav("/app");
    } catch (err) {
      setError(
        err instanceof Error ? err.message : "Impossible de terminer l'onboarding"
      );
    } finally {
      setLoading(false);
    }
  }

  return (
    <div className="app-shell">
      <div className="page no-nav">
        <p className="brand-mark" style={{ fontSize: "1.4rem", marginBottom: 8 }}>
          NeoForma
        </p>
        <h1 className="h1">Ton activité</h1>
        <p className="muted">Étape {step + 1} / 3 — alimente ton NeoScore</p>

        {step === 0 && (
          <div style={{ marginTop: 20 }}>
            <label className="lbl">Prénom / nom</label>
            <input
              className="input"
              value={displayName}
              onChange={(e) => setDisplayName(e.target.value)}
              placeholder="Aminata K."
            />
            <label className="lbl" style={{ display: "block", marginTop: 16 }}>
              Métier
            </label>
            <div className="seg">
              {metiers.map((m) => (
                <button
                  key={m}
                  type="button"
                  className={metier === m ? "on" : ""}
                  onClick={() => setMetier(m)}
                >
                  {m}
                </button>
              ))}
            </div>
            <label className="lbl" style={{ display: "block", marginTop: 16 }}>
              Ancienneté
            </label>
            <div className="seg">
              {(
                [
                  ["m1", "<1 an"],
                  ["3_5", "3–5"],
                  ["p10", ">10"],
                ] as const
              ).map(([v, l]) => (
                <button
                  key={v}
                  type="button"
                  className={anciennete === v ? "on" : ""}
                  onClick={() => setAnciennete(v)}
                >
                  {l}
                </button>
              ))}
            </div>
            <label className="lbl" style={{ display: "block", marginTop: 16 }}>
              CA journalier
            </label>
            <div className="seg">
              {(
                [
                  ["m5k", "<5k"],
                  ["15_30k", "15–30k"],
                  ["p100k", ">100k"],
                ] as const
              ).map(([v, l]) => (
                <button
                  key={v}
                  type="button"
                  className={caJour === v ? "on" : ""}
                  onClick={() => setCaJour(v)}
                >
                  {l}
                </button>
              ))}
            </div>
            <button className="btn btn-primary" onClick={() => setStep(1)}>
              Suivant
            </button>
          </div>
        )}

        {step === 1 && (
          <div style={{ marginTop: 20 }}>
            <label className="lbl">Tontine</label>
            <div className="seg">
              <button
                type="button"
                className={tontine ? "on" : ""}
                onClick={() => setTontine(true)}
              >
                Oui
              </button>
              <button
                type="button"
                className={!tontine ? "on" : ""}
                onClick={() => setTontine(false)}
              >
                Non
              </button>
            </div>
            <label className="lbl" style={{ display: "block", marginTop: 16 }}>
              Mobile Money
            </label>
            <div className="seg">
              {(
                [
                  ["jamais", "Jamais"],
                  ["occasionnel", "Parfois"],
                  ["regulier", "Souvent"],
                ] as const
              ).map(([v, l]) => (
                <button
                  key={v}
                  type="button"
                  className={mobileMoney === v ? "on" : ""}
                  onClick={() => setMobileMoney(v)}
                >
                  {l}
                </button>
              ))}
            </div>
            <button className="btn btn-ghost" onClick={() => setStep(0)}>
              Retour
            </button>
            <button className="btn btn-primary" onClick={() => setStep(2)}>
              Suivant
            </button>
          </div>
        )}

        {step === 2 && (
          <div style={{ marginTop: 20 }}>
            <p className="muted">
              Tes données construisent ton NeoScore. Tu contrôles le partage avec les
              partenaires de crédit.
            </p>
            <label className="lbl" style={{ marginTop: 16 }}>
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
                Plus tard
              </button>
            </div>
            <div className="toast">📍 Ouagadougou · consentements versionnés</div>
            {error && <p className="error">{error}</p>}
            <button className="btn btn-ghost" onClick={() => setStep(1)}>
              Retour
            </button>
            <button
              className="btn btn-primary"
              disabled={loading || !displayName.trim()}
              onClick={() => void finish()}
            >
              {loading ? "Activation…" : "Activer mon NeoScore"}
            </button>
          </div>
        )}
      </div>
    </div>
  );
}
