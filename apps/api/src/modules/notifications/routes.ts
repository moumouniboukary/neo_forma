import type { FastifyPluginAsync } from "fastify";

function toNotificationDto(n: {
  id: string;
  type: string;
  titre: string;
  corps: string;
  lu: boolean;
  createdAt: Date;
}) {
  return {
    id: n.id,
    type: n.type,
    titre: n.titre,
    corps: n.corps,
    lu: n.lu,
    createdAt: n.createdAt.toISOString(),
  };
}

/** Notifications in-app — GET /notifications, POST /notifications/:id/read. */
export const notificationsRoutes: FastifyPluginAsync = async (app) => {
  app.get("/", { preHandler: [app.authenticate] }, async (request) => {
    const query = request.query as { unreadOnly?: string; limit?: string };
    const items = await app.prisma.notificationInApp.findMany({
      where: {
        travailleurId: request.user.sub,
        ...(query.unreadOnly === "1" ? { lu: false } : {}),
      },
      orderBy: { createdAt: "desc" },
      take: Math.min(Number(query.limit ?? 50), 200),
    });
    return {
      items: items.map(toNotificationDto),
      unreadCount: await app.prisma.notificationInApp.count({
        where: { travailleurId: request.user.sub, lu: false },
      }),
    };
  });

  app.post(
    "/:id/read",
    { preHandler: [app.authenticate] },
    async (request, reply) => {
      const { id } = request.params as { id: string };
      const notif = await app.prisma.notificationInApp.findFirst({
        where: { id, travailleurId: request.user.sub },
      });
      if (!notif) {
        return reply
          .status(404)
          .send({ error: "not_found", message: "Notification introuvable" });
      }
      const updated = await app.prisma.notificationInApp.update({
        where: { id },
        data: { lu: true },
      });
      return toNotificationDto(updated);
    }
  );

  app.post(
    "/read-all",
    { preHandler: [app.authenticate] },
    async (request) => {
      const res = await app.prisma.notificationInApp.updateMany({
        where: { travailleurId: request.user.sub, lu: false },
        data: { lu: true },
      });
      return { updated: res.count };
    }
  );
};
