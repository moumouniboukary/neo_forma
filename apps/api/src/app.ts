import Fastify from "fastify";
import type { FastifyError } from "fastify";
import cors from "@fastify/cors";
import jwt from "@fastify/jwt";
import helmet from "@fastify/helmet";
import rateLimit from "@fastify/rate-limit";
import { config } from "./config.js";
import { prismaPlugin } from "./plugins/prisma.js";
import { registerOpenApi } from "./plugins/openapi.js";
import { captureException } from "./lib/observability.js";
import { recordHttpRequest, renderPrometheus } from "./lib/metrics.js";
import { checkRedis } from "./lib/redis.js";
import "./types.js";
import { identityRoutes } from "./modules/identity/routes.js";
import { profileRoutes } from "./modules/profile/routes.js";
import { consentRoutes } from "./modules/consent/routes.js";
import { privacyRoutes } from "./modules/privacy/routes.js";
import {
  ledgerClientRoutes,
  ledgerOperationRoutes,
} from "./modules/ledger/routes.js";
import { scoringRoutes } from "./modules/scoring/routes.js";
import { creditRoutes } from "./modules/credit/routes.js";
import { syncRoutes } from "./modules/sync/routes.js";
import { dashboardRoutes } from "./modules/dashboard/routes.js";
import { partnersRoutes } from "./modules/partners/routes.js";
import { koboRoutes } from "./modules/kobo/routes.js";
import { mobileMoneyRoutes } from "./modules/mobile-money/routes.js";
import { adminRoutes } from "./modules/admin/routes.js";
import { brandingRoutes } from "./modules/branding/routes.js";
import { stockRoutes } from "./modules/stock/routes.js";
import { tontineRoutes } from "./modules/tontine/routes.js";
import { notificationsRoutes } from "./modules/notifications/routes.js";
import { passportRoutes } from "./modules/passport/routes.js";
import { ussdRoutes } from "./modules/ussd/routes.js";

const INFRA_PATHS = new Set(["/health", "/ready", "/metrics"]);

export async function buildApp() {
  const app = Fastify({ logger: true });

  // Dio / fetch envoient souvent Content-Type: application/json sans corps.
  app.removeContentTypeParser("application/json");
  app.addContentTypeParser(
    "application/json",
    { parseAs: "string" },
    (_req, body, done) => {
      try {
        const text = typeof body === "string" ? body.trim() : "";
        done(null, text.length === 0 ? {} : JSON.parse(text));
      } catch (err) {
        done(err as Error, undefined);
      }
    }
  );

  await app.register(helmet, {
    // Swagger UI a besoin d'inline scripts/styles ; on n'impose pas de CSP stricte ici.
    contentSecurityPolicy: false,
  });
  await app.register(cors, { origin: config.corsOrigin, credentials: true });
  await app.register(rateLimit, {
    max: config.rateLimitMax,
    timeWindow: config.rateLimitWindow,
    allowList: (req) => INFRA_PATHS.has(req.url.split("?")[0] ?? ""),
  });
  await app.register(jwt, { secret: config.jwtSecret });
  await app.register(prismaPlugin);
  await registerOpenApi(app);

  // Métriques HTTP (Prometheus) — latence + compteurs.
  app.addHook("onResponse", async (request, reply) => {
    recordHttpRequest({
      method: request.method,
      route: request.routeOptions?.url ?? request.url,
      statusCode: reply.statusCode,
      durationMs: reply.elapsedTime,
    });
  });

  // Gestion d'erreur centralisée : masque les 500 en prod + report Sentry.
  app.setErrorHandler((error: FastifyError, request, reply) => {
    const status = error.statusCode ?? 500;
    if (status >= 500) {
      request.log.error(error);
      captureException(error, { userId: request.user?.sub });
    }
    const isServerError = status >= 500;
    reply.status(status).send({
      error: error.code ?? "error",
      message:
        isServerError && config.isProd
          ? "Erreur interne — réessayez plus tard"
          : error.message,
    });
  });

  app.setNotFoundHandler((request, reply) => {
    reply.status(404).send({
      error: "not_found",
      message: `Route inconnue : ${request.method} ${request.url}`,
    });
  });

  app.decorate("authenticate", async (request, reply) => {
    try {
      await request.jwtVerify();
      const user = request.user;
      if (user.typ && user.typ !== "access") {
        return reply.status(401).send({
          error: "unauthorized",
          message: "Token invalide ou manquant",
        });
      }
      if (user.sid) {
        const session = await app.prisma.session.findUnique({
          where: { id: user.sid },
        });
        if (
          !session ||
          session.statut !== "active" ||
          session.expireA < new Date()
        ) {
          return reply.status(401).send({
            error: "unauthorized",
            message: "Session révoquée ou expirée",
          });
        }
      }
    } catch {
      return reply.status(401).send({
        error: "unauthorized",
        message: "Token invalide ou manquant",
      });
    }
  });

  /** Liveness — process up (k8s / Render probes). */
  app.get(
    "/health",
    {
      schema: {
        tags: ["health"],
        response: {
          200: {
            type: "object",
            properties: {
              status: { type: "string" },
              service: { type: "string" },
              time: { type: "string" },
            },
          },
        },
      },
    },
    async () => ({
      status: "ok",
      service: "neoforma-api",
      time: new Date().toISOString(),
    })
  );

  /**
   * Readiness — Postgres obligatoire ; Redis si configuré.
   * 503 si une dépendance requise est down.
   */
  app.get("/ready", async (_request, reply) => {
    const checks: {
      postgres: "ok" | "down";
      redis: "ok" | "skip" | "down";
    } = { postgres: "down", redis: "skip" };

    try {
      await app.prisma.$queryRaw`SELECT 1`;
      checks.postgres = "ok";
    } catch {
      checks.postgres = "down";
    }

    checks.redis = await checkRedis();

    const ready =
      checks.postgres === "ok" &&
      (checks.redis === "ok" || checks.redis === "skip");

    if (!ready) {
      const { sendAlert } = await import("./lib/observability.js");
      void sendAlert("NeoForma /ready = not_ready", { checks });
    }

    return reply.status(ready ? 200 : 503).send({
      status: ready ? "ready" : "not_ready",
      service: "neoforma-api",
      checks,
      time: new Date().toISOString(),
    });
  });

  /** Prometheus scrape endpoint. */
  app.get("/metrics", async (_request, reply) => {
    reply.header("Content-Type", "text/plain; version=0.0.4; charset=utf-8");
    return renderPrometheus();
  });

  await app.register(identityRoutes, { prefix: "/auth" });
  await app.register(profileRoutes, { prefix: "/me" });
  await app.register(privacyRoutes, { prefix: "/me" });
  await app.register(consentRoutes, { prefix: "/me/consents" });
  await app.register(profileRoutes, { prefix: "/users/me" });

  await app.register(ledgerOperationRoutes, { prefix: "/operations" });
  await app.register(ledgerClientRoutes, { prefix: "/clients" });
  await app.register(dashboardRoutes, { prefix: "/dashboard" });

  await app.register(syncRoutes, { prefix: "/sync" });
  await app.register(scoringRoutes, { prefix: "/score" });
  await app.register(creditRoutes, { prefix: "/credit" });
  await app.register(partnersRoutes, { prefix: "/partners" });
  await app.register(koboRoutes, { prefix: "/kobo" });
  await app.register(mobileMoneyRoutes, { prefix: "/mobile-money" });
  await app.register(adminRoutes, { prefix: "/admin" });
  await app.register(brandingRoutes, { prefix: "/branding" });
  await app.register(stockRoutes, { prefix: "/stock" });
  await app.register(tontineRoutes, { prefix: "/tontine" });
  await app.register(tontineRoutes, { prefix: "/tontines" });
  await app.register(notificationsRoutes, { prefix: "/notifications" });
  await app.register(passportRoutes, { prefix: "/me" });
  await app.register(ussdRoutes, { prefix: "/ussd" });

  return app;
}
