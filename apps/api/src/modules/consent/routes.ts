import type { FastifyPluginAsync, FastifyReply } from "fastify";
import {
  ConsentTypeSchema,
  CURRENT_PRIVACY_POLICY_VERSION,
  UpdateConsentSchema,
  UpdateConsentsBatchSchema,
} from "@neoforma/shared";
import {
  ConsentService,
  isConsentError,
  toConsentDto,
} from "./service.js";

function sendConsentError(reply: FastifyReply, err: unknown) {
  if (isConsentError(err)) {
    return reply.status(err.statusCode).send({
      error: err.code,
      message: err.message,
    });
  }
  throw err;
}

export const consentRoutes: FastifyPluginAsync = async (app) => {
  const consents = new ConsentService(app.prisma);

  /** GET /me/consents — liste des consentements versionnés */
  app.get("/", { preHandler: [app.authenticate] }, async (request, reply) => {
    try {
      const items = await consents.list(request.user.sub);
      return {
        items: items.map(toConsentDto),
        policyVersion: CURRENT_PRIVACY_POLICY_VERSION,
      };
    } catch (err) {
      return sendConsentError(reply, err);
    }
  });

  /** PUT /me/consents — mise à jour groupée (clés legacy onboarding) */
  app.put("/", { preHandler: [app.authenticate] }, async (request, reply) => {
    const parsed = UpdateConsentsBatchSchema.safeParse(request.body);
    if (!parsed.success) {
      return reply.status(400).send({
        error: "validation",
        message: "Consentements invalides",
        details: parsed.error.flatten(),
      });
    }
    try {
      const items = await consents.applyLegacyBatch(request.user.sub, parsed.data);
      return {
        items: items.map(toConsentDto),
        policyVersion: CURRENT_PRIVACY_POLICY_VERSION,
      };
    } catch (err) {
      return sendConsentError(reply, err);
    }
  });

  /** PUT /me/consents/:type — accorder / refuser un type */
  app.put("/:type", { preHandler: [app.authenticate] }, async (request, reply) => {
    const typeParsed = ConsentTypeSchema.safeParse(
      (request.params as { type?: string }).type
    );
    if (!typeParsed.success) {
      return reply.status(400).send({
        error: "validation",
        message: "Type de consentement invalide",
      });
    }
    const body = UpdateConsentSchema.safeParse(request.body);
    if (!body.success) {
      return reply.status(400).send({
        error: "validation",
        message: "Données de consentement invalides",
        details: body.error.flatten(),
      });
    }
    try {
      const row = await consents.setConsent(
        request.user.sub,
        typeParsed.data,
        body.data
      );
      return toConsentDto(row);
    } catch (err) {
      return sendConsentError(reply, err);
    }
  });

  /** POST /me/consents/:type/revoke — RM-C03 */
  app.post(
    "/:type/revoke",
    { preHandler: [app.authenticate] },
    async (request, reply) => {
      const typeParsed = ConsentTypeSchema.safeParse(
        (request.params as { type?: string }).type
      );
      if (!typeParsed.success) {
        return reply.status(400).send({
          error: "validation",
          message: "Type de consentement invalide",
        });
      }
      try {
        const row = await consents.revoke(request.user.sub, typeParsed.data);
        return toConsentDto(row);
      } catch (err) {
        return sendConsentError(reply, err);
      }
    }
  );
};
