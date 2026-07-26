import type { FastifyPluginAsync, FastifyReply } from "fastify";
import { isScoringError, ScoringService } from "./service.js";

function sendError(reply: FastifyReply, err: unknown) {
  if (isScoringError(err)) {
    return reply.status(err.statusCode).send({
      error: err.code,
      message: err.message,
    });
  }
  throw err;
}

export const scoringRoutes: FastifyPluginAsync = async (app) => {
  const scoring = new ScoringService(app.prisma);

  /** GET /score — NeoScore courant (cache 1h, sinon recalcul sans offre) */
  app.get("/", { preHandler: [app.authenticate] }, async (request, reply) => {
    try {
      return await scoring.getCurrent(request.user.sub);
    } catch (err) {
      return sendError(reply, err);
    }
  });

  /** POST /score/recalculate — force recalcul (ML si SCORING_ML_URL) */
  app.post(
    "/recalculate",
    { preHandler: [app.authenticate] },
    async (request, reply) => {
      try {
        const { result } = await scoring.recalculate(request.user.sub);
        return result;
      } catch (err) {
        return sendError(reply, err);
      }
    }
  );
};
