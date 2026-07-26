import {
  createContext,
  useCallback,
  useContext,
  useEffect,
  useMemo,
  useState,
  type ReactNode,
} from "react";
import { api } from "@/shared/lib/api";

export type ThemeMode = "light" | "dark";

const STORAGE_KEY = "nf-theme";

type ThemeContextValue = {
  theme: ThemeMode;
  setTheme: (theme: ThemeMode) => void;
  persistTheme: (theme: ThemeMode) => Promise<void>;
};

const ThemeContext = createContext<ThemeContextValue | null>(null);

function normalizeTheme(value: unknown): ThemeMode {
  return value === "light" ? "light" : "dark";
}

function readStoredTheme(): ThemeMode {
  try {
    return normalizeTheme(localStorage.getItem(STORAGE_KEY));
  } catch {
    return "dark";
  }
}

function applyDomTheme(theme: ThemeMode) {
  document.documentElement.dataset.theme = theme;
  const meta = document.querySelector('meta[name="theme-color"]');
  if (meta) {
    meta.setAttribute("content", theme === "light" ? "#E8F3ED" : "#0A1F18");
  }
}

export function ThemeProvider({ children }: { children: ReactNode }) {
  const [theme, setThemeState] = useState<ThemeMode>(() => {
    const initial = readStoredTheme();
    applyDomTheme(initial);
    return initial;
  });

  useEffect(() => {
    applyDomTheme(theme);
    try {
      localStorage.setItem(STORAGE_KEY, theme);
    } catch {
      // ignore
    }
  }, [theme]);

  const setTheme = useCallback((next: ThemeMode) => {
    setThemeState(normalizeTheme(next));
  }, []);

  const persistTheme = useCallback(async (next: ThemeMode) => {
    const value = normalizeTheme(next);
    setThemeState(value);
    try {
      await api.patch("/me/preferences", { theme: value });
    } catch {
      // Préférence locale conservée hors ligne
    }
  }, []);

  const value = useMemo(
    () => ({ theme, setTheme, persistTheme }),
    [theme, setTheme, persistTheme]
  );

  return (
    <ThemeContext.Provider value={value}>{children}</ThemeContext.Provider>
  );
}

export function useTheme() {
  const ctx = useContext(ThemeContext);
  if (!ctx) throw new Error("useTheme must be used within ThemeProvider");
  return ctx;
}
