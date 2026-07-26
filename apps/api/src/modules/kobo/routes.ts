import type { FastifyPluginAsync, FastifyReply, FastifyRequest } from "fastify";
import { isKoboError, KoboService } from "./service.js";

/**
 * Module kobo — ingestion des collectes terrain KoboCollect / KoboToolbox.
 * Auth par clé partagée (KOBO_API_KEY) : agents terrain / webhook REST Kobo.
 */
function requireKoboKey(request: FastifyRequest, reply: FastifyReply): boolean {
  const expected = process.env.KOBO_API_KEY;
  if (!expected) {
    reply.status(503).send({
      error: "kobo_disabled",
      message: "Ingestion Kobo non configurée (KOBO_API_KEY manquant)",
    });
    return false;
  }
  const header =
    (request.headers["x-kobo-key"] as string | undefined) ??
    (request.headers.authorization?.replace(/^Bearer\s+/i, "") ?? "");
  if (header !== expected) {
    reply.status(401).send({
      error: "unauthorized",
      message: "Clé Kobo invalide",
    });
    return false;
  }
  return true;
}

export const koboRoutes: FastifyPluginAsync = async (app) => {
  const kobo = new KoboService(app.prisma);

  /** POST /kobo/import — 1 soumission, un tableau, ou { results: [...] } (format Kobo). */
  app.post("/import", async (request, reply) => {
    if (!requireKoboKey(request, reply)) return;
    try {
      const result = await kobo.import(request.body);
      return reply.status(200).send(result);
    } catch (err) {
      if (isKoboError(err)) {
        return reply.status(err.statusCode).send({
          error: err.code,
          message: err.message,
        });
      }
      throw err;
    }
  });

  /** GET /kobo/submissions — vérification des dernières collectes. */
  app.get("/submissions", async (request, reply) => {
    if (!requireKoboKey(request, reply)) return;
    const limit = Number((request.query as { limit?: string }).limit ?? 50);
    const items = await kobo.list(limit);
    const stats = await kobo.stats();
    return { stats, items };
  });
};
