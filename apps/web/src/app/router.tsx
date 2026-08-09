import { BrowserRouter, Navigate, Outlet, Route, Routes } from "react-router-dom";
import { useEffect, type ReactNode } from "react";
import { AuthProvider, useAuth } from "@/features/auth/AuthContext";
import { ThemeProvider, useTheme } from "@/shared/theme/ThemeContext";
import { RequireAuth, RequireOnboarding } from "@/app/guards";
import { AppShell } from "@/app/AppShell";
import { SplashPage } from "@/features/onboarding/SplashPage";
import { LoginPage } from "@/features/auth/LoginPage";
import { RegisterPage } from "@/features/auth/RegisterPage";
import { ForgotPasswordPage } from "@/features/auth/ForgotPasswordPage";
import { OnboardingPage } from "@/features/onboarding/OnboardingPage";
import { DashboardPage } from "@/features/dashboard/DashboardPage";
import { RecordPage } from "@/features/operations/RecordPage";
import {
  DepensesPage,
  DettesPage,
  VentesPage,
} from "@/features/operations/ListsPages";
import { ScorePage } from "@/features/score/ScorePage";
import { CreditPage } from "@/features/credit/CreditPage";
import { ProfilePage } from "@/features/profile/ProfilePage";
import { ImfAuthProvider } from "@/features/imf/ImfAuthContext";
import { ImfLoginPage } from "@/features/imf/ImfLoginPage";
import { ImfShell } from "@/features/imf/ImfShell";
import { ImfApplicationsPage } from "@/features/imf/ImfApplicationsPage";
import { ImfReportingPage } from "@/features/imf/ImfReportingPage";
import { ImfCommissionsPage } from "@/features/imf/ImfCommissionsPage";

function ThemeAuthSync({ children }: { children: ReactNode }) {
  const { user } = useAuth();
  const { setTheme } = useTheme();
  useEffect(() => {
    if (user?.theme) setTheme(user.theme);
  }, [user?.theme, setTheme]);
  return children;
}

function ImfRoot() {
  return (
    <ImfAuthProvider>
      <Outlet />
    </ImfAuthProvider>
  );
}

export function AppRouter() {
  return (
    <ThemeProvider>
      <AuthProvider>
        <ThemeAuthSync>
          <BrowserRouter>
            <Routes>
              <Route path="/" element={<SplashPage />} />
              <Route path="/login" element={<LoginPage />} />
              <Route path="/register" element={<RegisterPage />} />
              <Route path="/forgot-password" element={<ForgotPasswordPage />} />

              <Route element={<RequireAuth />}>
                <Route path="/onboarding" element={<OnboardingPage />} />
                <Route element={<RequireOnboarding />}>
                  <Route path="/app" element={<AppShell />}>
                    <Route index element={<DashboardPage />} />
                    <Route path="ventes" element={<VentesPage />} />
                    <Route path="depenses" element={<DepensesPage />} />
                    <Route path="dettes" element={<DettesPage />} />
                    <Route path="enregistrer" element={<RecordPage />} />
                    <Route path="score" element={<ScorePage />} />
                    <Route path="credit" element={<CreditPage />} />
                    <Route path="profil" element={<ProfilePage />} />
                  </Route>
                </Route>
              </Route>

              <Route path="/imf" element={<ImfRoot />}>
                <Route index element={<Navigate to="login" replace />} />
                <Route path="login" element={<ImfLoginPage />} />
                <Route element={<ImfShell />}>
                  <Route path="dossiers" element={<ImfApplicationsPage />} />
                  <Route path="reporting" element={<ImfReportingPage />} />
                  <Route path="commissions" element={<ImfCommissionsPage />} />
                </Route>
              </Route>

              <Route path="*" element={<Navigate to="/" replace />} />
            </Routes>
          </BrowserRouter>
        </ThemeAuthSync>
      </AuthProvider>
    </ThemeProvider>
  );
}
