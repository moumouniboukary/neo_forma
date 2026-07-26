import { FormEvent, useState } from "react";
import { Link } from "react-router-dom";
import { api, ApiClientError } from "@/shared/lib/api";
import { useAuth } from "@/features/auth/AuthContext";

type Step = "phone" | "otp" | "pin";

export function ForgotPasswordPage() {
  const { verifyOtp } = useAuth();
  const [step, setStep] = useState<Step>("phone");
  const [phone, setPhone] = useState("+226 ");
  const [otp, setOtp] = useState("");
  const [otpToken, setOtpToken] = useState<string | null>(null);
  const [devCode, setDevCode] = useState<string | null>(null);
  const [newPin, setNewPin] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [done, setDone] = useState(false);
  const [loading, setLoading] = useState(false);
  const [info, setInfo] = useState<string | null>(null);

  async function sendOtp(e: FormEvent) {
    e.preventDefault();
    setLoading(true);
    setError(null);
    setInfo(null);
    setDevCode(null);
    try {
      const res = await api.post<{
        ok: boolean;
        expiresIn: number;
        message?: string;
        devCode?: string;
      }>("/auth/forgot-password", { phone: phone.trim() });
      if (res.devCode) setDevCode(res.devCode);
      setInfo(res.message ?? "Si le compte existe, un code a été envoyé.");
      setStep("otp");
    } catch (err) {
      setError(err instanceof ApiClientError ? err.message : "Envoi impossible");
    } finally {
      setLoading(false);
    }
  }

  async function confirmOtp(e: FormEvent) {
    e.preventDefault();
    setLoading(true);
    setError(null);
    try {
      const token = await verifyOtp(phone.trim(), otp, "reset");
      setOtpToken(token);
      setStep("pin");
    } catch (err) {
      setError(err instanceof ApiClientError ? err.message : "Code incorrect");
    } finally {
      setLoading(false);
    }
  }

  async function resetPin(e: FormEvent) {
    e.preventDefault();
    if (!otpToken) return;
    setLoading(true);
    setError(null);
    try {
      await api.post("/auth/reset-password", {
        phone: phone.trim(),
        otpToken,
        newPin,
      });
      setDone(true);
    } catch (err) {
      setError(
        err instanceof ApiClientError ? err.message : "Réinitialisation impossible"
      );
    } finally {
      setLoading(false);
    }
  }

  return (
    <div className="app-shell">
      <div className="auth-screen page no-nav">
        <header className="auth-hero">
          <p className="brand-mark">NeoForma</p>
          <p className="tagline">Réinitialiser votre PIN secret.</p>
        </header>
        <div className="auth-panel">
          {done ? (
            <>
              <h2 className="auth-title">PIN mis à jour</h2>
              <p className="muted">Reconnectez-vous avec votre nouveau code.</p>
              <Link to="/login" className="btn btn-primary">
                Se connecter
              </Link>
            </>
          ) : step === "phone" ? (
            <form onSubmit={sendOtp}>
              <h2 className="auth-title">PIN oublié</h2>
              <label className="lbl">Téléphone</label>
              <input
                className="input"
                value={phone}
                onChange={(e) => setPhone(e.target.value)}
              />
              {error && <p className="error">{error}</p>}
              <button className="btn btn-primary" disabled={loading}>
                Recevoir un code
              </button>
            </form>
          ) : step === "otp" ? (
            <form onSubmit={confirmOtp}>
              <h2 className="auth-title">Code SMS</h2>
              {info && <p className="muted">{info}</p>}
              <input
                className="input"
                inputMode="numeric"
                maxLength={4}
                value={otp}
                onChange={(e) =>
                  setOtp(e.target.value.replace(/\D/g, "").slice(0, 4))
                }
              />
              {devCode && <p className="dev-hint">Dev · code {devCode}</p>}
              {error && <p className="error">{error}</p>}
              <button
                className="btn btn-primary"
                disabled={loading || otp.length !== 4}
              >
                Continuer
              </button>
            </form>
          ) : (
            <form onSubmit={resetPin}>
              <h2 className="auth-title">Nouveau PIN</h2>
              <input
                className="input"
                type="password"
                inputMode="numeric"
                maxLength={4}
                value={newPin}
                onChange={(e) =>
                  setNewPin(e.target.value.replace(/\D/g, "").slice(0, 4))
                }
              />
              {error && <p className="error">{error}</p>}
              <button
                className="btn btn-primary"
                disabled={loading || newPin.length !== 4}
              >
                Enregistrer
              </button>
            </form>
          )}
          <Link to="/login" className="btn btn-ghost">
            Retour connexion
          </Link>
        </div>
      </div>
    </div>
  );
}
