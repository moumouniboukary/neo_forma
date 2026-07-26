const ACCESS_KEY = "neoforma.accessToken";
const REFRESH_KEY = "neoforma.refreshToken";
const USER_KEY = "neoforma.user";

export type StoredUser = {
  id: string;
  phone: string;
  displayName: string;
  onboardingCompleted: boolean;
  language?: string;
  theme?: "light" | "dark";
  statutCompte?: string;
};

export const storage = {
  getToken(): string | null {
    return localStorage.getItem(ACCESS_KEY);
  },
  getRefreshToken(): string | null {
    return localStorage.getItem(REFRESH_KEY);
  },
  setSession(accessToken: string, user: StoredUser, refreshToken?: string) {
    localStorage.setItem(ACCESS_KEY, accessToken);
    localStorage.setItem(USER_KEY, JSON.stringify(user));
    if (refreshToken) localStorage.setItem(REFRESH_KEY, refreshToken);
  },
  getUser(): StoredUser | null {
    const raw = localStorage.getItem(USER_KEY);
    return raw ? (JSON.parse(raw) as StoredUser) : null;
  },
  clear() {
    localStorage.removeItem(ACCESS_KEY);
    localStorage.removeItem(REFRESH_KEY);
    localStorage.removeItem(USER_KEY);
  },
};
