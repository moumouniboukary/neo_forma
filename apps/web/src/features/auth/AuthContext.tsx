import {
  createContext,
  useContext,
  useMemo,
  useState,
  useCallback,
  type ReactNode,
} from "react";
import { api } from "@/shared/lib/api";
import { storage, type StoredUser } from "@/shared/lib/storage";

type OtpPurpose = "login" | "register" | "reset";

type AuthTokensResponse = {
  accessToken: string;
  refreshToken: string;
  expiresIn: number;
  user: StoredUser & { onboardingCompleted?: boolean };
};

type AuthState = {
  user: StoredUser | null;
  token: string | null;
  requestOtp: (
    phone: string,
    purpose?: OtpPurpose
  ) => Promise<{ expiresIn: number; devCode?: string }>;
  verifyOtp: (
    phone: string,
    code: string,
    purpose?: OtpPurpose
  ) => Promise<string>;
  login: (phone: string, pin: string, otpToken: string) => Promise<StoredUser>;
  register: (
    phone: string,
    pin: string,
    otpToken: string,
    opts?: { language?: string; displayName?: string }
  ) => Promise<void>;
  logout: () => Promise<void>;
  refreshMe: () => Promise<void>;
  setUser: (user: StoredUser) => void;
};

const AuthContext = createContext<AuthState | null>(null);

function normalizeUser(user: AuthTokensResponse["user"]): StoredUser {
  return {
    id: user.id,
    phone: user.phone,
    displayName: user.displayName,
    onboardingCompleted: Boolean(user.onboardingCompleted),
    language: user.language,
    statutCompte: user.statutCompte,
  };
}

export function AuthProvider({ children }: { children: ReactNode }) {
  const [token, setToken] = useState(storage.getToken());
  const [user, setUserState] = useState<StoredUser | null>(storage.getUser());

  const setUser = useCallback((u: StoredUser) => {
    setUserState(u);
    const t = storage.getToken();
    const r = storage.getRefreshToken() ?? undefined;
    if (t) storage.setSession(t, u, r);
  }, []);

  const requestOtp = useCallback(
    async (phone: string, purpose: OtpPurpose = "login") => {
      return api.post<{ expiresIn: number; devCode?: string }>(
        "/auth/otp/request",
        { phone, purpose }
      );
    },
    []
  );

  const verifyOtp = useCallback(
    async (phone: string, code: string, purpose: OtpPurpose = "login") => {
      const res = await api.post<{ otpToken: string }>("/auth/otp/verify", {
        phone,
        code,
        purpose,
      });
      return res.otpToken;
    },
    []
  );

  const login = useCallback(
    async (phone: string, pin: string, otpToken: string) => {
      const res = await api.post<AuthTokensResponse>("/auth/login", {
        phone,
        pin,
        otpToken,
      });
      const u = normalizeUser(res.user);
      storage.setSession(res.accessToken, u, res.refreshToken);
      setToken(res.accessToken);
      setUserState(u);
      return u;
    },
    []
  );

  const register = useCallback(
    async (
      phone: string,
      pin: string,
      otpToken: string,
      opts?: { language?: string; displayName?: string }
    ) => {
      const res = await api.post<AuthTokensResponse>("/auth/register", {
        phone,
        pin,
        otpToken,
        language: opts?.language ?? "fr",
        displayName: opts?.displayName?.trim() || "Entrepreneur NeoForma",
      });
      const u = normalizeUser(res.user);
      storage.setSession(res.accessToken, u, res.refreshToken);
      setToken(res.accessToken);
      setUserState(u);
    },
    []
  );

  const logout = useCallback(async () => {
    const refreshToken = storage.getRefreshToken();
    try {
      await api.post("/auth/logout", { refreshToken });
    } catch {
      /* session locale nettoyée même si API indisponible */
    }
    storage.clear();
    setToken(null);
    setUserState(null);
  }, []);

  const refreshMe = useCallback(async () => {
    const me = await api.get<StoredUser>("/me");
    setUser(normalizeUser(me));
  }, [setUser]);

  const value = useMemo(
    () => ({
      user,
      token,
      requestOtp,
      verifyOtp,
      login,
      register,
      logout,
      refreshMe,
      setUser,
    }),
    [
      user,
      token,
      requestOtp,
      verifyOtp,
      login,
      register,
      logout,
      refreshMe,
      setUser,
    ]
  );

  return <AuthContext.Provider value={value}>{children}</AuthContext.Provider>;
}

export function useAuth() {
  const ctx = useContext(AuthContext);
  if (!ctx) throw new Error("useAuth outside AuthProvider");
  return ctx;
}
