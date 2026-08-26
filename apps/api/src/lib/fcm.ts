/**
 * Firebase Cloud Messaging — envoi push via Legacy HTTP API.
 * Requiert FCM_SERVER_KEY (Firebase Console → Cloud Messaging).
 */
export type FcmPayload = {
  title: string;
  body: string;
  data?: Record<string, string>;
};

export function isFcmConfigured(): boolean {
  return Boolean(process.env.FCM_SERVER_KEY?.trim());
}

export async function sendFcmToToken(
  token: string,
  payload: FcmPayload
): Promise<{ ok: boolean; error?: string }> {
  const key = process.env.FCM_SERVER_KEY?.trim();
  if (!key) return { ok: false, error: "FCM_SERVER_KEY manquant" };

  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), 8_000);
  try {
    const res = await fetch("https://fcm.googleapis.com/fcm/send", {
      method: "POST",
      signal: controller.signal,
      headers: {
        Authorization: `key=${key}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        to: token,
        priority: "high",
        notification: {
          title: payload.title,
          body: payload.body,
          sound: "default",
        },
        data: payload.data ?? {},
      }),
    });
    if (!res.ok) {
      const text = await res.text().catch(() => "");
      return { ok: false, error: `FCM HTTP ${res.status}: ${text.slice(0, 200)}` };
    }
    const body = (await res.json()) as { success?: number; failure?: number };
    if ((body.failure ?? 0) > 0 && (body.success ?? 0) === 0) {
      return { ok: false, error: "FCM delivery failed" };
    }
    return { ok: true };
  } catch (err) {
    return {
      ok: false,
      error: err instanceof Error ? err.message : "FCM network error",
    };
  } finally {
    clearTimeout(timer);
  }
}
