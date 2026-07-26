import type { FastifyPluginAsync, FastifyReply } from "fastify";
import { z } from "zod";
import { isPrivacyError, PrivacyService } from "./service.js";
import { IdentityService } from "../identity/service.js";
import { isIdentityError } from "../identity/errors.js";

function sendError(reply: FastifyReply, err: unknown) {
  if (isPrivacyError(err) || isIdentityError(err)) {
    return reply.status(err.statusCode).send({
      error: err.code,
      message: err.message,
    });
  }
  throw err;
}

const DeleteAccountSchema = z.object({
  pin: z.string().regex(/^\d{4}$/),
  confirm: z.literal(true),
});

/**
 * RGPD — monté sous /me :
 *   GET  /me/export  — droit d'accès / portabilité
 *   DELETE /me       — droit à l'oubli (PIN + confirm requis)
 */
export const privacyRoutes: FastifyPluginAsync = async (app) => {
  const privacy = new PrivacyService(app.prisma);
  const identity = new IdentityService(app.prisma);

  app.get("/export", { preHandler: [app.authenticate] }, async (request, reply) => {
    try {
      const data = await privacy.exportData(request.user.sub);
      reply.header(
        "Content-Disposition",
        `attachment; filename="neoforma-export-${request.user.sub.slice(0, 8)}.json"`
      );
      return data;
    } catch (err) {
      return sendError(reply, err);
    }
  });

  app.delete("/", { preHandler: [app.authenticate] }, async (request, reply) => {
    const parsed = DeleteAccountSchema.safeParse(request.body);
    if (!parsed.success) {
      return reply.status(400).send({
        error: "validation",
        message: "Confirmation requise : { pin, confirm: true }",
      });
    }
    try {
      // Vérifie le PIN avant suppression irréversible.
      await identity.authenticatePin(request.user.phone, parsed.data.pin, {
        requireActif: false,
      });
      await privacy.deleteAccount(request.user.sub);
      return reply.status(204).send();
    } catch (err) {
      return sendError(reply, err);
    }
  });
};
