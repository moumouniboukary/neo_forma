import { FormEvent, useEffect, useState } from "react";
import { Link, useNavigate } from "react-router-dom";
import { api, ApiClientError } from "@/shared/lib/api";

type Offer = {
  minFcfa: number;
  maxFcfa: number;
  suggestedFcfa: number;
  durationMonths: number;
  monthlyRatePct: number;
  eligible: boolean;
  score: number;
};

export function CreditPage() {
  const nav = useNavigate();
  const [offer, setOffer] = useState<Offer | null>(null);
  const [amount, setAmount] = useState(150000);
  const [purpose, setPurpose] = useState<
    "stock" | "equipement" | "fonds_roulement" | "autre"
  >("stock");
  const [ref, setRef] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [needConsent, setNeedConsent] = useState(false);
  const [consentSaving, setConsentSaving] = useState(false);

  useEffect(() => {
    api
      .get<Offer>("/credit/offer")
      .then((o) => {
        setOffer(o);
        if (o.suggestedFcfa) setAmount(o.suggestedFcfa);
      })
      .catch(() => setOffer(null));
  }, []);

  async function grantConsent() {
    setConsentSaving(true);
    setError(null);
    try {
      await api.put("/me/consents", { consentCreditPartners: true });
      setNeedConsent(false);
    } catch (err) {
      setError(err instanceof ApiClientError ? err.message : "Consentement impossible");
    } finally {
      setConsentSaving(false);
    }
  }

  async function submit(e: FormEvent) {
    e.preventDefault();
    setError(null);
    setNeedConsent(false);
    try {
      const app = await api.post<{ reference: string }>("/credit/applications", {
        amountFcfa: amount,
        purpose,
        repayment: "mensuel",
      });
      setRef(app.reference);
    } catch (err) {
      if (
        err instanceof ApiClientError &&
        (err.body as { error?: string } | undefined)?.error === "consent_required"
      ) {
        setNeedConsent(true);
        setError(err.message);
      } else {
        setError(err instanceof ApiClientError ? err.message : "Échec demande");
      }
    }
  }

  if (ref) {
    return (
      <div className="page">
        <div className="score-ring">OK</div>
        <h1 className="h1" style={{ textAlign: "center" }}>
          Demande envoyée
        </h1>
        <div className="card">
          <div>
            Réf. <strong>{ref}</strong>
          </div>
          <div className="muted">Statut · En cours · réponse 24–48 h</div>
        </div>
        <button className="btn btn-primary" onClick={() => nav("/app")}>
          Accueil
        </button>
      </div>
    );
  }

  return (
    <div className="page">
      <h1 className="h1">Offre de crédit</h1>
      {!offer?.eligible && (
        <div
          className="toast"
          style={{ borderColor: "var(--coral)", color: "var(--coral)" }}
        >
          Non éligible (score {offer?.score ?? "—"})
        </div>
      )}
      {offer?.eligible && (
        <div className="card">
          <div className="lbl">Montant estimé</div>
          <div className="stat-val">
            {offer.suggestedFcfa.toLocaleString("fr-FR")} FCFA
          </div>
          <div className="muted">
            {offer.minFcfa.toLocaleString("fr-FR")} –{" "}
            {offer.maxFcfa.toLocaleString("fr-FR")} · {offer.durationMonths} mois ·{" "}
            {offer.monthlyRatePct}%/mois
          </div>
        </div>
      )}
      {needConsent && (
        <div className="toast">
          Le partage avec les IMF est requis.{" "}
          <button
            type="button"
            className="btn btn-ghost"
            style={{ width: "auto", display: "inline", padding: "4px 8px" }}
            disabled={consentSaving}
            onClick={() => void grantConsent()}
          >
            {consentSaving ? "…" : "Autoriser maintenant"}
          </button>
          <Link to="/app/profil" style={{ marginLeft: 8 }}>
            Profil
          </Link>
        </div>
      )}
      <form onSubmit={submit}>
        <label className="lbl">Montant demandé</label>
        <input
          className="input"
          type="number"
          value={amount}
          min={offer?.minFcfa ?? 0}
          max={offer?.maxFcfa ?? 0}
          onChange={(e) => setAmount(Number(e.target.value))}
          disabled={!offer?.eligible}
        />
        <label className="lbl" style={{ display: "block", marginTop: 12 }}>
          Usage
        </label>
        <div className="seg">
          {(
            [
              ["stock", "Stock"],
              ["equipement", "Équip."],
              ["fonds_roulement", "FDR"],
              ["autre", "Autre"],
            ] as const
          ).map(([v, l]) => (
            <button
              key={v}
              type="button"
              className={purpose === v ? "on" : ""}
              onClick={() => setPurpose(v)}
            >
              {l}
            </button>
          ))}
        </div>
        {error && <p className="error">{error}</p>}
        <button className="btn btn-primary" disabled={!offer?.eligible}>
          Soumettre
        </button>
        <button type="button" className="btn btn-outline" onClick={() => nav(-1)}>
          Retour
        </button>
      </form>
    </div>
  );
}
