import type { FastifyPluginAsync, FastifyReply } from "fastify";
import {
  OnboardingUpdateSchema,
  UpdateActiviteSchema,
  UpdatePreferencesSchema,
} from "@neoforma/shared";
import { toUserProfile } from "../../lib/mappers.js";
import { ScoringService } from "../scoring/service.js";
import { isProfileError, ProfileService } from "./service.js";

function sendProfileError(reply: FastifyReply, err: unknown) {
  if (isProfileError(err)) {
    return reply.status(err.statusCode).send({
      error: err.code,
      message: err.message,
    });
  }
  throw err;
}

export const profileRoutes: FastifyPluginAsync = async (app) => {
  const profiles = new ProfileService(app.prisma);
  const scoring = new ScoringService(app.prisma);

  /** GET /me — profil agrégé (identité + activité + préférences) */
  app.get("/", { preHandler: [app.authenticate] }, async (request, reply) => {
    try {
      const me = await profiles.getMe(request.user.sub);
      return toUserProfile(me);
    } catch (err) {
      return sendProfileError(reply, err);
    }
  });

  /**
   * PATCH /me — mise à jour onboarding / profil (compat UI legacy).
   * Préférer /activite et /preferences pour des mises à jour ciblées.
   */
  app.patch("/", { preHandler: [app.authenticate] }, async (request, reply) => {
    const parsed = OnboardingUpdateSchema.safeParse(request.body);
    if (!parsed.success) {
      return reply.status(400).send({
        error: "validation",
        message: "Profil invalide",
        details: parsed.error.flatten(),
      });
    }
    try {
      const me = await profiles.applyOnboardingUpdate(request.user.sub, parsed.data);
      return toUserProfile(me);
    } catch (err) {
      return sendProfileError(reply, err);
    }
  });

  /** PATCH /me/activite — ProfilActivite + nom affiché */
  app.patch("/activite", { preHandler: [app.authenticate] }, async (request, reply) => {
    const parsed = UpdateActiviteSchema.safeParse(request.body);
    if (!parsed.success) {
      return reply.status(400).send({
        error: "validation",
        message: "Données d'activité invalides",
        details: parsed.error.flatten(),
      });
    }
    try {
      const me = await profiles.updateActivite(request.user.sub, parsed.data);
      return toUserProfile(me);
    } catch (err) {
      return sendProfileError(reply, err);
    }
  });

  /** PATCH /me/preferences — PreferencesUtilisateur */
  app.patch(
    "/preferences",
    { preHandler: [app.authenticate] },
    async (request, reply) => {
      const parsed = UpdatePreferencesSchema.safeParse(request.body);
      if (!parsed.success) {
        return reply.status(400).send({
          error: "validation",
          message: "Préférences invalides",
          details: parsed.error.flatten(),
        });
      }
      try {
        const me = await profiles.updatePreferences(request.user.sub, parsed.data);
        return toUserProfile(me);
      } catch (err) {
        return sendProfileError(reply, err);
      }
    }
  );

  /** POST /me/onboarding/complete — valide RM-P01, active le compte, calcule NeoScore */
  app.post(
    "/onboarding/complete",
    { preHandler: [app.authenticate] },
    async (request, reply) => {
      try {
        const me = await profiles.completeOnboarding(request.user.sub);
        try {
          await scoring.recalculate(request.user.sub, { persistOffer: false });
        } catch {
          // GET /score recalculera plus tard
        }
        return toUserProfile(me);
      } catch (err) {
        return sendProfileError(reply, err);
      }
    }
  );
};
