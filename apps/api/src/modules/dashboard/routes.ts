import type { FastifyPluginAsync } from "fastify";
import { toOperation } from "../../lib/mappers.js";
import { LedgerService } from "../ledger/service.js";

export const dashboardRoutes: FastifyPluginAsync = async (app) => {
  const ledger = new LedgerService(app.prisma);

  app.get("/", { preHandler: [app.authenticate] }, async (request) => {
    const stats = await ledger.getDashboardStats(request.user.sub);
    return {
      ...stats,
      recentOperations: stats.recentOperations.map(toOperation),
    };
  });
};
