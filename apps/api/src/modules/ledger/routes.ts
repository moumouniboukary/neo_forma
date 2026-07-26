import type { FastifyPluginAsync, FastifyReply } from "fastify";
import {
  CreateClientSchema,
  CreateOperationSchema,
  UpdateClientSchema,
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
      return reply.status(400).send({
        error: "validation",
        message: "Opération invalide",
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

  /** POST /operations/:id/settle — régler une créance (RM-O05) */
  app.post(
    "/:id/settle",
    { preHandler: [app.authenticate] },
    async (request, reply) => {
      const { id } = request.params as { id: string };
      try {
        const op = await ledger.settleCreance(request.user.sub, id);
        return toOperation(op);
      } catch (err) {
        return sendLedgerError(reply, err);
      }
    }
  );
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
