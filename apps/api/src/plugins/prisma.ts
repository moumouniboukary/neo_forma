import fp from "fastify-plugin";
import { PrismaClient } from "@prisma/client";
import type { FastifyPluginAsync } from "fastify";
import { closeRedis } from "../lib/redis.js";

declare module "fastify" {
  interface FastifyInstance {
    prisma: PrismaClient;
  }
}

async function connectWithRetry(
  prisma: PrismaClient,
  attempts = 12,
  delayMs = 3000
): Promise<void> {
  let last: unknown;
  for (let i = 1; i <= attempts; i++) {
    try {
      await prisma.$connect();
      if (i > 1) {
        console.info(`[prisma] connexion OK à l’essai ${i}/${attempts}`);
      }
      return;
    } catch (err) {
      last = err;
      const msg = err instanceof Error ? err.message : String(err);
      console.warn(`[prisma] connexion ${i}/${attempts} échouée: ${msg}`);
      if (i < attempts) {
        await new Promise((r) => setTimeout(r, delayMs));
      }
    }
  }
  throw last;
}

const prismaPluginImpl: FastifyPluginAsync = async (app) => {
  const prisma = new PrismaClient();
  await connectWithRetry(prisma);
  app.decorate("prisma", prisma);
  app.addHook("onClose", async () => {
    await prisma.$disconnect();
    await closeRedis();
  });
};

export const prismaPlugin = fp(prismaPluginImpl);
