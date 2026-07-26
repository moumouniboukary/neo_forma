/**
 * Observabilité — Sentry optionnel + webhook d'alerte ops.
 */
import { createRequire } from "node:module";
import { config } from "../config.js";

type SentryLike = {
  init(opts: Record<string, unknown>): void;
  captureException(err: unknown): void;
  setUser(user: Record<string, unknown> | null): void;
};

let sentry: SentryLike | null = null;
let lastAlertAt = 0;
const ALERT_COOLDOWN_MS = 60_000;

export function initObservability(): void {
  if (!config.sentryDsn) return;
  try {
    const require = createRequire(import.meta.url);
    // eslint-disable-next-line @typescript-eslint/no-require-imports
    const Sentry = require("@sentry/node") as SentryLike;
    Sentry.init({
      dsn: config.sentryDsn,
      environment: config.isProd ? "production" : "development",
      release: config.release,
      tracesSampleRate: config.isProd ? 0.1 : 1.0,
    });
    sentry = Sentry;
    console.info("[observability] Sentry activé");
  } catch (err) {
    console.warn("[observability] Sentry indisponible", err);
    sentry = null;
  }
}

export function captureException(err: unknown, context?: Record<string, unknown>): void {
  if (sentry) {
    try {
      if (context?.userId) {
        sentry.setUser({ id: String(context.userId) });
      }
      sentry.captureException(err);
    } catch {
      /* ignore */
    }
  }
  const message = err instanceof Error ? err.message : String(err);
  void sendAlert(`NeoForma erreur 5xx : ${message}`, context);
}

/**
 * POST JSON générique vers Slack/Discord/n8n (ALERT_WEBHOOK_URL).
 * Rate-limité à 1 alerte / minute.
 */
export async function sendAlert(
  text: string,
  extra?: Record<string, unknown>
): Promise<void> {
  if (!config.alertWebhookUrl) return;
  const now = Date.now();
  if (now - lastAlertAt < ALERT_COOLDOWN_MS) return;
  lastAlertAt = now;
  try {
    await fetch(config.alertWebhookUrl, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        text,
        content: text, // Discord
        ...extra,
        service: "neoforma-api",
        release: config.release,
        time: new Date().toISOString(),
      }),
    });
  } catch (err) {
    console.warn("[alert] webhook échoué", err);
  }
}
