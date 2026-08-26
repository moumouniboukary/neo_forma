/**
 * Enregistrement des jetons push (FCM) pour décisions crédit / relances.
 */
import type { FastifyPluginAsync } from "fastify";
import { z } from "zod";

const RegisterSchema = z.object({
  token: z.string().min(20).max(512),
  platform: z.enum(["android", "ios"]).default("android"),
});

export const devicesRoutes: FastifyPluginAsync = async (app) => {
  app.post(
    "/push-token",
    { preHandler: [app.authenticate] },
    async (request, reply) => {
      const parsed = RegisterSchema.safeParse(request.body);
      if (!parsed.success) {
        return reply.status(400).send({
          error: "validation",
          message: "token / platform invalides",
          details: parsed.error.flatten(),
        });
      }
      const { token, platform } = parsed.data;
      const row = await app.prisma.devicePushToken.upsert({
        where: {
          travailleurId_token: {
            travailleurId: request.user.sub,
            token,
          },
        },
        create: {
          travailleurId: request.user.sub,
          token,
          platform,
        },
        update: { platform, updatedAt: new Date() },
      });
      return { id: row.id, platform: row.platform, ok: true };
    }
  );

  app.delete(
    "/push-token",
    { preHandler: [app.authenticate] },
    async (request, reply) => {
      const parsed = z
        .object({ token: z.string().min(20).max(512) })
        .safeParse(request.body);
      if (!parsed.success) {
        return reply.status(400).send({
          error: "validation",
          message: "token requis",
        });
      }
      await app.prisma.devicePushToken.deleteMany({
        where: {
          travailleurId: request.user.sub,
          token: parsed.data.token,
        },
      });
      return { ok: true };
    }
  );
};
