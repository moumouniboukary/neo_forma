import { FormEvent, useState } from "react";
import { Link, useNavigate } from "react-router-dom";
import { useAuth } from "@/features/auth/AuthContext";
import { ApiClientError } from "@/shared/lib/api";

type Step = "phone" | "otp" | "pin";

/** Inscription MFA — alignée Auth API (nécessaire au typecheck avec Login). */
export function RegisterPage() {
  const { requestOtp, verifyOtp, register } = useAuth();
  const nav = useNavigate();
  const [step, setStep] = useState<Step>("phone");
  const [phone, setPhone] = useState("+226 ");
  const [otp, setOtp] = useState("");
  const [otpToken, setOtpToken] = useState<string | null>(null);
  const [devCode, setDevCode] = useState<string | null>(null);
  const [pin, setPin] = useState("");
  const [displayName, setDisplayName] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [loading, setLoading] = useState(false);

  async function sendOtp(e: FormEvent) {
    e.preventDefault();
    setLoading(true);
    setError(null);
    try {
      const res = await requestOtp(phone.trim(), "register");
      if (res.devCode) setDevCode(res.devCode);
      setStep("otp");
    } catch (err) {
      setError(err instanceof ApiClientError ? err.message : "Envoi OTP impossible");
    } finally {
      setLoading(false);
    }
  }

  async function confirmOtp(e: FormEvent) {
    e.preventDefault();
    setLoading(true);
    setError(null);
    try {
      const token = await verifyOtp(phone.trim(), otp, "register");
      setOtpToken(token);
      setStep("pin");
    } catch (err) {
      setError(err instanceof ApiClientError ? err.message : "Code incorrect");
    } finally {
      setLoading(false);
    }
  }

  async function confirmPin(e: FormEvent) {
    e.preventDefault();
    if (!otpToken) return;
    if (displayName.trim().length < 2) {
      setError("Indiquez votre prénom ou nom (2 caractères minimum)");
      return;
    }
    setLoading(true);
    setError(null);
    try {
      await register(phone.trim(), pin, otpToken, {
        displayName: displayName.trim(),
      });
      nav("/onboarding");
    } catch (err) {
      setError(err instanceof ApiClientError ? err.message : "Inscription impossible");
    } finally {
      setLoading(false);
    }
  }

  return (
    <div className="app-shell">
      <div className="auth-screen page no-nav">
        <header className="auth-hero">
          <p className="brand-mark">NeoForma</p>
          <p className="tagline">Créer votre cahier numérique en quelques minutes.</p>
        </header>
        <div className="auth-panel">
          {step === "phone" && (
            <form onSubmit={sendOtp}>
              <h2 className="auth-title">Nouveau compte</h2>
              <label className="lbl" htmlFor="reg-phone">Téléphone</label>
              <input
                id="reg-phone"
                className="input"
                value={phone}
                onChange={(e) => setPhone(e.target.value)}
                placeholder="+226 70 00 00 00"
              />
              {error && <p className="error">{error}</p>}
              <button className="btn btn-primary" disabled={loading}>
                {loading ? "Envoi…" : "Recevoir le code"}
              </button>
            </form>
          )}
          {step === "otp" && (
            <form onSubmit={confirmOtp}>
              <h2 className="auth-title">Code SMS</h2>
              <input
                className="input"
                inputMode="numeric"
                maxLength={4}
                value={otp}
                onChange={(e) => setOtp(e.target.value.replace(/\D/g, "").slice(0, 4))}
              />
              {devCode && <p className="dev-hint">Dev · code {devCode}</p>}
              {error && <p className="error">{error}</p>}
              <button className="btn btn-primary" disabled={loading || otp.length !== 4}>
                Continuer
              </button>
            </form>
          )}
          {step === "pin" && (
            <form onSubmit={confirmPin}>
              <h2 className="auth-title">Votre identité</h2>
              <label className="lbl" htmlFor="reg-name">Prénom / nom</label>
              <input
                id="reg-name"
                className="input"
                value={displayName}
                onChange={(e) => setDisplayName(e.target.value)}
                placeholder="Ex. Awa Ouédraogo"
                autoComplete="name"
              />
              <label className="lbl" htmlFor="reg-pin">Code PIN</label>
              <input
                id="reg-pin"
                className="input"
                type="password"
                inputMode="numeric"
                maxLength={4}
                value={pin}
                onChange={(e) => setPin(e.target.value.replace(/\D/g, "").slice(0, 4))}
              />
              {error && <p className="error">{error}</p>}
              <button
                className="btn btn-primary"
                disabled={loading || pin.length !== 4 || displayName.trim().length < 2}
              >
                Créer mon compte
              </button>
            </form>
          )}
          <Link to="/login" className="btn btn-ghost">
            J’ai déjà un compte
          </Link>
        </div>
      </div>
    </div>
  );
}
