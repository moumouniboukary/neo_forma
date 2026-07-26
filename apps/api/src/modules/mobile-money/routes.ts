import type { FastifyPluginAsync } from "fastify";
import { z } from "zod";
import {
  createMobileMoneyGateway,
  isMmConfigured,
  type MmProvider,
} from "../../lib/mobile-money.js";
import { enqueueJob } from "../../lib/jobs.js";

const TransferSchema = z.object({
  provider: z.enum(["orange", "moov", "stub"]).default("stub"),
  phone: z.string().min(8).max(20),
  amountFcfa: z.number().int().positive(),
  direction: z.enum(["cash_in", "cash_out"]).default("cash_in"),
  reference: z.string().max(64).optional(),
  async: z.boolean().optional(),
});

/**
 * Mobile Money — cash-in / cash-out via Orange ou Moov.
 * POST /mobile-money/transfer
 */
export const mobileMoneyRoutes: FastifyPluginAsync = async (app) => {
  app.get("/providers", async () => ({
    providers: [
      {
        id: "orange",
        configured: isMmConfigured("orange"),
        label: "Orange Money",
      },
      {
        id: "moov",
        configured: isMmConfigured("moov"),
        label: "Moov Money",
      },
      { id: "stub", configured: true, label: "Mode test" },
    ],
  }));

  app.post(
    "/transfer",
    { preHandler: [app.authenticate] },
    async (request, reply) => {
      const parsed = TransferSchema.safeParse(request.body);
      if (!parsed.success) {
        return reply.status(400).send({
          error: "validation",
          message: "Transfert Mobile Money invalide",
          details: parsed.error.flatten(),
        });
      }
      const input = parsed.data;
      const provider = input.provider as MmProvider;
      const reference =
        input.reference ??
        `NF-MM-${request.user.sub.slice(0, 8)}-${Date.now()}`;

      if (input.async) {
        const { queued } = await enqueueJob("mm_transfer", {
          ...input,
          reference,
          travailleurId: request.user.sub,
        });
        if (queued) {
          return {
            status: "queued",
            reference,
            provider,
          };
        }
      }

      const gw = createMobileMoneyGateway(provider);
      const result = await gw.transfer({
        provider,
        phone: input.phone,
        amountFcfa: input.amountFcfa,
        reference,
        direction: input.direction,
      });
      if (result.status === "failed") {
        return reply.status(502).send({
          error: "mm_failed",
          message: result.message ?? "Échec Mobile Money",
          result,
        });
      }
      return result;
    }
  );
};
