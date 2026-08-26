import type { Prisma, PrismaClient } from "@prisma/client";
import { enqueueOrRun } from "./jobs.js";
import { isFcmConfigured, sendFcmToToken } from "./fcm.js";

export type NotifyInput = {
  travailleurId: string;
  type: string;
  titre: string;
  corps: string;
  meta?: Prisma.InputJsonValue;
};

async function pushToDevices(
  prisma: PrismaClient,
  travailleurId: string,
  titre: string,
  corps: string,
  type: string
): Promise<void> {
  if (!isFcmConfigured()) return;
  const tokens = await prisma.devicePushToken.findMany({
    where: { travailleurId },
    select: { token: true },
  });
  for (const row of tokens) {
    await enqueueOrRun(
      "fcm_push",
      { token: row.token, title: titre, body: corps, type },
      async () => {
        const result = await sendFcmToToken(row.token, {
          title: titre,
          body: corps,
          data: { type },
        });
        if (!result.ok) {
          console.warn(`[fcm] ${result.error}`);
        }
      }
    );
  }
}

export async function createNotification(
  prisma: PrismaClient,
  input: NotifyInput
) {
  const row = await prisma.notificationInApp.create({
    data: {
      travailleurId: input.travailleurId,
      type: input.type,
      titre: input.titre,
      corps: input.corps,
      meta: input.meta ?? undefined,
    },
  });
  void pushToDevices(
    prisma,
    input.travailleurId,
    input.titre,
    input.corps,
    input.type
  ).catch((err) => console.warn("[fcm] dispatch", err));
  return row;
}

/** Crée une notif par créance en retard (idempotent ~1 / jour / créance). */
export async function notifyOverdueCreances(prisma: PrismaClient): Promise<number> {
  const overdue = await prisma.operation.findMany({
    where: {
      type: "creance",
      statutCreance: "en_retard",
    },
    include: { client: true },
    take: 200,
  });
  let n = 0;
  const dayStart = new Date();
  dayStart.setHours(0, 0, 0, 0);
  for (const op of overdue) {
    const existing = await prisma.notificationInApp.findFirst({
      where: {
        travailleurId: op.travailleurId,
        type: "creance_retard",
        createdAt: { gte: dayStart },
        meta: { path: ["operationId"], equals: op.id },
      },
    });
    if (existing) continue;
    const reste = op.montantFcfa - (op.montantRegleFcfa ?? 0);
    await createNotification(prisma, {
      travailleurId: op.travailleurId,
      type: "creance_retard",
      titre: "Créance en retard",
      corps: `${op.client?.nom ?? "Client"} — ${reste} FCFA à encaisser`,
      meta: { operationId: op.id },
    });
    n += 1;
  }
  return n;
}
