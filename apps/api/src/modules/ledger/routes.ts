import type { FastifyPluginAsync, FastifyReply, FastifyRequest } from "fastify";
import {
  CreateClientSchema,
  CreateOperationSchema,
  SettleCreanceSchema,
  UpdateClientSchema,
  UpdateDueDateSchema,
} from "@neoforma/shared";
import { toClient, toOperation } from "../../lib/mappers.js";
import { isLedgerError, LedgerService } from "./service.js";

function sendLedgerError(reply: FastifyReply, err: unknown) {
  if (isLedgerError(err)) {
    return reply.status(err.statusCode).send({
      error: err.code,
      message: err.message,
    });
  }
  throw err;
}

export const ledgerOperationRoutes: FastifyPluginAsync = async (app) => {
  const ledger = new LedgerService(app.prisma);

  app.get("/", { preHandler: [app.authenticate] }, async (request, reply) => {
    try {
      const query = request.query as { type?: string; limit?: string };
      const ops = await ledger.listOperations(request.user.sub, {
        type: query.type,
        limit: query.limit ? Number(query.limit) : undefined,
      });
      return ops.map(toOperation);
    } catch (err) {
      return sendLedgerError(reply, err);
    }
  });

  app.post("/", { preHandler: [app.authenticate] }, async (request, reply) => {
    const parsed = CreateOperationSchema.safeParse(request.body);
    if (!parsed.success) {
      const first = parsed.error.issues[0];
      const where = first?.path?.length
        ? `${first.path.join(".")}: ${first.message}`
        : first?.message;
      return reply.status(400).send({
        error: "validation",
        message: where ? `Opération invalide (${where})` : "Opération invalide",
        details: parsed.error.flatten(),
      });
    }
    try {
      const op = await ledger.createOperation(request.user.sub, parsed.data);
      return reply.status(201).send(toOperation(op));
    } catch (err) {
      return sendLedgerError(reply, err);
    }
  });

  /** DELETE /operations/:id — corriger une erreur (annule l'effet stock si besoin) */
  app.delete(
    "/:id",
    { preHandler: [app.authenticate] },
    async (request, reply) => {
      const { id } = request.params as { id: string };
      try {
        await ledger.deleteOperation(request.user.sub, id);
        return reply.status(204).send();
      } catch (err) {
        return sendLedgerError(reply, err);
      }
    }
  );

  /** POST /operations/:id/settle — régler une créance, total ou partiel (RM-O05) */
  app.post(
    "/:id/settle",
    { preHandler: [app.authenticate] },
    async (request, reply) => {
      const { id } = request.params as { id: string };
      const parsed = SettleCreanceSchema.safeParse(request.body ?? {});
      if (!parsed.success) {
        return reply.status(400).send({
          error: "validation",
          message: "Règlement invalide",
          details: parsed.error.flatten(),
        });
      }
      try {
        const op = await ledger.settleCreance(
          request.user.sub,
          id,
          parsed.data.amountFcfa
        );
        return toOperation(op);
      } catch (err) {
        return sendLedgerError(reply, err);
      }
    }
  );

  /** POST /operations/:id/remind — relancer un client (SMS + notif in-app) */
  app.post(
    "/:id/remind",
    { preHandler: [app.authenticate] },
    async (request, reply) => {
      const { id } = request.params as { id: string };
      try {
        const op = await ledger.remindCreance(request.user.sub, id);
        return toOperation(op);
      } catch (err) {
        return sendLedgerError(reply, err);
      }
    }
  );

  /** PATCH /operations/:id/due-date — changer l'échéance d'une créance */
  const handleUpdateDueDate = async (
    request: FastifyRequest,
    reply: FastifyReply
  ) => {
    const { id } = request.params as { id: string };
    const parsed = UpdateDueDateSchema.safeParse(request.body);
    if (!parsed.success) {
      return reply.status(400).send({
        error: "validation",
        message: "Échéance invalide",
        details: parsed.error.flatten(),
      });
    }
    try {
      const op = await ledger.updateDueDate(
        request.user.sub,
        id,
        parsed.data.dueAt
      );
      return toOperation(op);
    } catch (err) {
      return sendLedgerError(reply, err);
    }
  };
  app.patch("/:id/due-date", { preHandler: [app.authenticate] }, handleUpdateDueDate);
  app.patch("/:id/due", { preHandler: [app.authenticate] }, handleUpdateDueDate);
};

export const ledgerClientRoutes: FastifyPluginAsync = async (app) => {
  const ledger = new LedgerService(app.prisma);

  app.get("/", { preHandler: [app.authenticate] }, async (request, reply) => {
    try {
      const clients = await ledger.listClients(request.user.sub);
      return clients.map(toClient);
    } catch (err) {
      return sendLedgerError(reply, err);
    }
  });

  app.post("/", { preHandler: [app.authenticate] }, async (request, reply) => {
    const parsed = CreateClientSchema.safeParse(request.body);
    if (!parsed.success) {
      return reply.status(400).send({
        error: "validation",
        message: "Client invalide",
        details: parsed.error.flatten(),
      });
    }
    try {
      const client = await ledger.createClient(request.user.sub, parsed.data);
      return reply.status(201).send(toClient(client));
    } catch (err) {
      return sendLedgerError(reply, err);
    }
  });

  app.patch("/:id", { preHandler: [app.authenticate] }, async (request, reply) => {
    const parsed = UpdateClientSchema.safeParse(request.body);
    if (!parsed.success) {
      return reply.status(400).send({
        error: "validation",
        message: "Client invalide",
        details: parsed.error.flatten(),
      });
    }
    const { id } = request.params as { id: string };
    try {
      const client = await ledger.updateClient(request.user.sub, id, parsed.data);
      return toClient(client);
    } catch (err) {
      return sendLedgerError(reply, err);
    }
  });

  app.delete("/:id", { preHandler: [app.authenticate] }, async (request, reply) => {
    const { id } = request.params as { id: string };
    try {
      await ledger.deleteClient(request.user.sub, id);
      return reply.status(204).send();
    } catch (err) {
      return sendLedgerError(reply, err);
    }
  });
};
