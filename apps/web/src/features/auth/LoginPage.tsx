import { FormEvent, useState } from "react";
import { Link, useNavigate } from "react-router-dom";
import { useAuth } from "@/features/auth/AuthContext";
import { ApiClientError } from "@/shared/lib/api";

type Step = "phone" | "otp" | "pin";

export function LoginPage() {
  const { requestOtp, verifyOtp, login } = useAuth();
  const nav = useNavigate();

  const [step, setStep] = useState<Step>("phone");
  const [phone, setPhone] = useState("+226 ");
  const [otp, setOtp] = useState("");
  const [otpToken, setOtpToken] = useState<string | null>(null);
  const [devCode, setDevCode] = useState<string | null>(null);
  const [pin, setPin] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [loading, setLoading] = useState(false);

  async function sendOtp(e: FormEvent) {
    e.preventDefault();
    setLoading(true);
    setError(null);
    setDevCode(null);
    try {
      const res = await requestOtp(phone.trim(), "login");
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
      const token = await verifyOtp(phone.trim(), otp, "login");
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
    setLoading(true);
    setError(null);
    try {
      const u = await login(phone.trim(), pin, otpToken);
      nav(u.onboardingCompleted ? "/app" : "/onboarding");
    } catch (err) {
      setError(err instanceof ApiClientError ? err.message : "Connexion impossible");
    } finally {
      setLoading(false);
    }
  }

  const stepIndex = step === "phone" ? 0 : step === "otp" ? 1 : 2;

  return (
    <div className="app-shell">
      <div className="auth-screen page no-nav">
        <header className="auth-hero">
          <p className="brand-mark">NeoForma</p>
          <p className="tagline">
            Votre activité, visible. Votre solvabilité, accessible.
          </p>
        </header>

        <div className="auth-panel">
          <div className="auth-steps" aria-hidden>
            <span className={stepIndex >= 0 ? "on" : ""} />
            <span className={stepIndex >= 1 ? "on" : ""} />
            <span className={stepIndex >= 2 ? "on" : ""} />
          </div>

          {step === "phone" && (
            <form onSubmit={sendOtp}>
              <h2 className="auth-title">Connexion</h2>
              <p className="muted" style={{ marginBottom: 18 }}>
                Entrez votre numéro burkinabè pour recevoir un code SMS.
              </p>
              <label className="lbl" htmlFor="phone">
                Téléphone
              </label>
              <input
                id="phone"
                className="input"
                inputMode="tel"
                autoComplete="tel"
                placeholder="+226 70 00 00 00"
                value={phone}
                onChange={(e) => setPhone(e.target.value)}
                required
              />
              {error && <p className="error">{error}</p>}
              <button className="btn btn-primary" disabled={loading || phone.trim().length < 8}>
                {loading ? "Envoi…" : "Recevoir le code"}
              </button>
            </form>
          )}

          {step === "otp" && (
            <form onSubmit={confirmOtp}>
              <h2 className="auth-title">Code SMS</h2>
              <p className="muted" style={{ marginBottom: 18 }}>
                Saisissez le code à 4 chiffres envoyé au {phone.trim()}.
              </p>
              <label className="lbl" htmlFor="otp">
                OTP
              </label>
              <input
                id="otp"
                className="input"
                inputMode="numeric"
                autoComplete="one-time-code"
                maxLength={4}
                placeholder="••••"
                value={otp}
                onChange={(e) => setOtp(e.target.value.replace(/\D/g, "").slice(0, 4))}
                required
              />
              {devCode && (
                <p className="dev-hint">Dev · code {devCode}</p>
              )}
              {error && <p className="error">{error}</p>}
              <button className="btn btn-primary" disabled={loading || otp.length !== 4}>
                {loading ? "Vérification…" : "Continuer"}
              </button>
              <button
                type="button"
                className="btn btn-ghost"
                disabled={loading}
                onClick={() => {
                  void (async () => {
                    setLoading(true);
                    setError(null);
                    try {
                      const res = await requestOtp(phone.trim(), "login");
                      if (res.devCode) setDevCode(res.devCode);
                      setOtp("");
                    } catch (err) {
                      setError(
                        err instanceof ApiClientError
                          ? err.message
                          : "Renvoi impossible"
                      );
                    } finally {
                      setLoading(false);
                    }
                  })();
                }}
              >
                Renvoyer le code
              </button>
              <button
                type="button"
                className="btn btn-ghost"
                onClick={() => {
                  setStep("phone");
                  setOtp("");
                  setError(null);
                }}
              >
                Changer de numéro
              </button>
            </form>
          )}

          {step === "pin" && (
            <form onSubmit={confirmPin}>
              <h2 className="auth-title">Votre PIN</h2>
              <p className="muted" style={{ marginBottom: 18 }}>
                Deuxième facteur — code secret à 4 chiffres.
              </p>
              <label className="lbl" htmlFor="pin">
                PIN
              </label>
              <input
                id="pin"
                className="input"
                type="password"
                inputMode="numeric"
                autoComplete="current-password"
                maxLength={4}
                placeholder="••••"
                value={pin}
                onChange={(e) => setPin(e.target.value.replace(/\D/g, "").slice(0, 4))}
                required
              />
              {error && <p className="error">{error}</p>}
              <button className="btn btn-primary" disabled={loading || pin.length !== 4}>
                {loading ? "Connexion…" : "Se connecter"}
              </button>
              <Link to="/login" className="btn btn-ghost" onClick={() => setStep("phone")}>
                Recommencer
              </Link>
            </form>
          )}

          <p className="muted" style={{ textAlign: "center", marginTop: 28 }}>
            <Link to="/forgot-password" style={{ color: "var(--text-mute)" }}>
              PIN oublié ?
            </Link>
            <br />
            <span style={{ display: "inline-block", marginTop: 12 }}>
              Pas encore de compte ?{" "}
              <Link to="/register" style={{ color: "var(--brand-soft)", fontWeight: 650 }}>
                Créer un compte
              </Link>
            </span>
          </p>
        </div>
      </div>
    </div>
  );
}
