import type { FastifyPluginAsync, FastifyReply } from "fastify";
import { SubmitCreditSchema } from "@neoforma/shared";
import { toCredit } from "../../lib/mappers.js";
import { CreditService, isCreditError } from "./service.js";

function sendError(reply: FastifyReply, err: unknown) {
  if (isCreditError(err)) {
    return reply.status(err.statusCode).send({
      error: err.code,
      message: err.message,
      details: err.details,
    });
  }
  throw err;
}

export const creditRoutes: FastifyPluginAsync = async (app) => {
  const credit = new CreditService(app.prisma);
  await credit.ensurePilotImf();

  app.get("/offer", { preHandler: [app.authenticate] }, async (request, reply) => {
    try {
      return await credit.getOffer(request.user.sub);
    } catch (err) {
      return sendError(reply, err);
    }
  });

  app.post(
    "/applications",
    { preHandler: [app.authenticate] },
    async (request, reply) => {
      const parsed = SubmitCreditSchema.safeParse(request.body);
      if (!parsed.success) {
        return reply.status(400).send({
          error: "validation",
          message: "Demande invalide",
          details: parsed.error.flatten(),
        });
      }
      try {
        const application = await credit.submit(request.user.sub, parsed.data);
        return reply.status(201).send(toCredit(application));
      } catch (err) {
        return sendError(reply, err);
      }
    }
  );

  app.get(
    "/applications",
    { preHandler: [app.authenticate] },
    async (request, reply) => {
      try {
        const apps = await credit.listApplications(request.user.sub);
        return apps.map(toCredit);
      } catch (err) {
        return sendError(reply, err);
      }
    }
  );

  app.get(
    "/applications/:id",
    { preHandler: [app.authenticate] },
    async (request, reply) => {
      const { id } = request.params as { id: string };
      try {
        const appRow = await credit.getApplication(request.user.sub, id);
        return toCredit(appRow);
      } catch (err) {
        return sendError(reply, err);
      }
    }
  );
};
