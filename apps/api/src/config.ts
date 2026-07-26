const isProd = process.env.NODE_ENV === "production";

/** En dev : true = téléphone sur le LAN (PWA). En prod : origine explicite. */
function resolveCorsOrigin(): boolean | string | string[] {
  const raw = process.env.CORS_ORIGIN;
  if (!raw || raw === "*") return isProd ? "http://localhost:5173" : true;
  if (raw.includes(",")) return raw.split(",").map((s) => s.trim());
  return raw;
}

const DEV_JWT_SECRET = "neoforma-dev-secret";

/** En prod : secret obligatoire (≥ 32 car.). En dev : fallback toléré. */
function resolveJwtSecret(): string {
  const secret = process.env.JWT_SECRET;
  if (isProd) {
    if (!secret || secret === DEV_JWT_SECRET || secret.length < 32) {
      throw new Error(
        "JWT_SECRET manquant ou trop faible en production (≥ 32 caractères requis)."
      );
    }
  }
  return secret ?? DEV_JWT_SECRET;
}

export const config = {
  port: Number(process.env.PORT ?? 3001),
  host: process.env.HOST ?? "0.0.0.0",
  jwtSecret: resolveJwtSecret(),
  corsOrigin: resolveCorsOrigin(),
  databaseUrl:
    process.env.DATABASE_URL ??
    "postgresql://neoforma:neoforma@localhost:5433/neoforma?schema=public",
  isProd,
  /** Fenêtre / plafond du rate-limit HTTP global. */
  rateLimitMax: Number(process.env.RATE_LIMIT_MAX ?? (isProd ? 300 : 1000)),
  rateLimitWindow: process.env.RATE_LIMIT_WINDOW ?? "1 minute",
  sentryDsn: process.env.SENTRY_DSN ?? "",
  release: process.env.APP_RELEASE ?? "neoforma-api@0.1.0",
  /** Webhook Slack/Discord/generic pour alertes ops (5xx, readiness). */
  alertWebhookUrl: process.env.ALERT_WEBHOOK_URL ?? "",
};
