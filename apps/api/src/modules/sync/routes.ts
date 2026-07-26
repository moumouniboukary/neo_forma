import type { FastifyPluginAsync, FastifyReply } from "fastify";
import { CreateOperationSchema, SyncPushRequestSchema } from "@neoforma/shared";
import { isLedgerError } from "../ledger/service.js";
import { isSyncError, SyncService } from "./service.js";

function sendError(reply: FastifyReply, err: unknown) {
  if (isSyncError(err) || isLedgerError(err)) {
    return reply.status(err.statusCode).send({
      error: err.code,
      message: err.message,
    });
  }
  throw err;
}

export const syncRoutes: FastifyPluginAsync = async (app) => {
  const sync = new SyncService(app.prisma);

  /**
   * POST /sync/push — mutations offline multi-kind (ops, clients, profil, consents).
   */
  app.post("/push", { preHandler: [app.authenticate] }, async (request, reply) => {
    const parsed = SyncPushRequestSchema.safeParse(request.body);
    if (!parsed.success) {
      return reply.status(400).send({
        error: "validation",
        message: "Payload sync invalide",
        details: parsed.error.flatten(),
      });
    }

    try {
      return await sync.pushMutations(request.user.sub, parsed.data.mutations);
    } catch (err) {
      return sendError(reply, err);
    }
  });

  /**
   * GET /sync/pull?since=&limit=
   * Pull incrémental (updatedAt) avec pagination curseur.
   */
  app.get("/pull", { preHandler: [app.authenticate] }, async (request, reply) => {
    try {
      const query = request.query as { since?: string; limit?: string };
      const since = query.since ? new Date(query.since) : new Date(0);
      if (Number.isNaN(since.getTime())) {
        return reply.status(400).send({
          error: "validation",
          message: "Paramètre since invalide (ISO datetime)",
        });
      }
      const limit = query.limit ? Number(query.limit) : 100;
      return await sync.pull(request.user.sub, { since, limit });
    } catch (err) {
      return sendError(reply, err);
    }
  });

  /** GET /sync/queue — file hors-ligne du travailleur */
  app.get("/queue", { preHandler: [app.authenticate] }, async (request, reply) => {
    try {
      const items = await sync.listQueue(request.user.sub);
      return { items, serverTime: new Date().toISOString() };
    } catch (err) {
      return sendError(reply, err);
    }
  });

  /** POST /sync/enqueue — enregistrer une intention opération sans l'accepter */
  app.post("/enqueue", { preHandler: [app.authenticate] }, async (request, reply) => {
    const body = request.body as {
      clientMutationId?: string;
      payload?: unknown;
      createdAt?: string;
    };
    const payload = CreateOperationSchema.safeParse(body.payload);
    if (!body.clientMutationId || !payload.success || !body.createdAt) {
      return reply.status(400).send({
        error: "validation",
        message: "enqueue invalide (clientMutationId, payload, createdAt)",
      });
    }
    try {
      const row = await sync.enqueue(request.user.sub, {
        clientMutationId: body.clientMutationId,
        payload: payload.data,
        createdAt: body.createdAt,
      });
      return reply.status(201).send(row);
    } catch (err) {
      return sendError(reply, err);
    }
  });
};
