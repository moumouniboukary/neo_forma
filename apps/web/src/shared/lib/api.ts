import { storage } from "./storage";

const BASE = (import.meta.env.VITE_API_URL as string | undefined)?.replace(
  /\/$/,
  ""
) || "/api";

export class ApiClientError extends Error {
  constructor(
    message: string,
    public status: number,
    public body?: unknown
  ) {
    super(message);
  }
}

let refreshPromise: Promise<boolean> | null = null;

async function tryRefresh(): Promise<boolean> {
  const refreshToken = storage.getRefreshToken();
  if (!refreshToken) return false;
  try {
    const res = await fetch(`${BASE}/auth/refresh`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ refreshToken }),
    });
    if (!res.ok) return false;
    const data = (await res.json()) as {
      accessToken: string;
      refreshToken: string;
      user: {
        id: string;
        phone: string;
        displayName: string;
        onboardingCompleted?: boolean;
        language?: string;
        statutCompte?: string;
      };
    };
    storage.setSession(
      data.accessToken,
      {
        id: data.user.id,
        phone: data.user.phone,
        displayName: data.user.displayName,
        onboardingCompleted: Boolean(data.user.onboardingCompleted),
        language: data.user.language,
        statutCompte: data.user.statutCompte,
      },
      data.refreshToken
    );
    return true;
  } catch {
    return false;
  }
}

function isNetworkFailure(err: unknown): boolean {
  return (
    err instanceof TypeError ||
    (err instanceof Error &&
      /failed to fetch|networkerror|load failed/i.test(err.message))
  );
}

async function request<T>(
  path: string,
  init: RequestInit = {},
  retried = false
): Promise<T> {
  const headers = new Headers(init.headers);
  headers.set("Content-Type", "application/json");
  const token = storage.getToken();
  if (token) headers.set("Authorization", `Bearer ${token}`);

  let res: Response;
  try {
    res = await fetch(`${BASE}${path}`, { ...init, headers });
  } catch (err) {
    if (isNetworkFailure(err)) {
      throw new ApiClientError("Hors ligne", 0, { offline: true });
    }
    throw err;
  }

  const data = await res.json().catch(() => ({}));

  if (res.status === 401 && !retried && !path.startsWith("/auth/")) {
    refreshPromise ??= tryRefresh().finally(() => {
      refreshPromise = null;
    });
    const ok = await refreshPromise;
    if (ok) return request<T>(path, init, true);
  }

  if (!res.ok) {
    throw new ApiClientError(
      (data as { message?: string }).message ?? res.statusText,
      res.status,
      data
    );
  }
  return data as T;
}

export const api = {
  get: <T>(path: string) => request<T>(path),
  post: <T>(path: string, body?: unknown) =>
    request<T>(path, { method: "POST", body: JSON.stringify(body ?? {}) }),
  patch: <T>(path: string, body?: unknown) =>
    request<T>(path, { method: "PATCH", body: JSON.stringify(body ?? {}) }),
  put: <T>(path: string, body?: unknown) =>
    request<T>(path, { method: "PUT", body: JSON.stringify(body ?? {}) }),
};

export function isOfflineError(err: unknown): boolean {
  if (!(err instanceof ApiClientError)) return false;
  if (err.status === 0) return true;
  const body = err.body;
  return (
    typeof body === "object" &&
    body !== null &&
    "offline" in body &&
    (body as { offline?: boolean }).offline === true
  );
}
