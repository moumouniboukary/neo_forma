import { Link } from "react-router-dom";
import { useAuth } from "@/features/auth/AuthContext";

export function SplashPage() {
  const { token, user } = useAuth();
  const dest = !token
    ? "/login"
    : user && !user.onboardingCompleted
      ? "/onboarding"
      : "/app";

  return (
    <div className="app-shell">
      <div className="auth-screen page no-nav" style={{ justifyContent: "center" }}>
        <header className="auth-hero">
          <p className="brand-mark">NeoForma</p>
          <p className="tagline">
            Cahier numérique & passeport financier pour le secteur informel.
          </p>
        </header>
        <div className="auth-panel">
          <Link to={dest} className="btn btn-primary">
            {token ? "Continuer" : "Commencer"}
          </Link>
          {!token && (
            <Link to="/register" className="btn btn-ghost">
              Créer un compte
            </Link>
          )}
          <p className="muted" style={{ textAlign: "center", marginTop: 24, fontSize: 13 }}>
            App mobile · ajoutez NeoForma à l’écran d’accueil pour l’utiliser hors navigateur.
          </p>
        </div>
      </div>
    </div>
  );
}
